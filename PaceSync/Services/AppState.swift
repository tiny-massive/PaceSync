// AppState.swift
// Transient UI state — loading, errors, parsing progress, WorkoutKit schedule statuses.
// Persistence is handled by PlanStore.

import Combine
import HealthKit
import SwiftUI

@MainActor
class AppState: ObservableObject {

    @Published var isLoading      = false
    @Published var errorMessage: String?
    @Published var scheduleStatuses: [UUID: ScheduleStatus] = [:]
    @Published var scheduledDates: [UUID: Date] = [:]

    /// 0.0 → 1.0 progress during parsing; reset to 0 when idle.
    @Published var parsingProgress: Double = 0
    /// Human-readable phase label shown under the progress bar.
    @Published var parsingPhase: String = ""

    let planStore = PlanStore.shared
    private let parser = ClaudeParserService()

    private var cancellables    = Set<AnyCancellable>()
    private var progressTask: Task<Void, Never>?

    init() {
        // Forward PlanStore's objectWillChange through AppState so any view
        // that observes AppState (via @EnvironmentObject) re-renders when the
        // plan changes — including on clear() and updatePlanOnly().
        planStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Import from file

    func importFile(from url: URL, raceDate: Date? = nil) async {
        isLoading = true
        errorMessage = nil
        startProgress(phase: "Extracting text…")

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let title = url.deletingPathExtension().lastPathComponent
            let text: String
            if url.pathExtension.lowercased() == "pdf" {
                // Stage A: transcribe the real PDF to clean Markdown (Claude reads the
                // rendered layout, so table columns don't scramble), then parse the Markdown.
                let pdfData = try Data(contentsOf: url)
                advanceProgress(to: 0.10, phase: "Reading your plan…")
                text = try await parser.transcribePDFToMarkdown(pdfData) { [weak self] p, phase in
                    self?.advanceProgress(to: 0.10 + p * 0.25, phase: phase)
                }
            } else {
                let importer = try makeImporter(for: url)
                text = try importer.extractText(from: url)
            }
            guard text.count > 30 else {
                throw ImportError.emptyContent
            }
            advanceProgress(to: 0.35, phase: "Parsing workouts…")
            let plan = try await parser.parseTrainingPlan(from: text, title: title) { [weak self] progress, phase in
                self?.advanceProgress(to: 0.35 + progress * 0.60, phase: phase)
            }
            completeProgress()
            try? await Task.sleep(nanoseconds: 350_000_000)
            planStore.save(plan, title: title, sourceURL: url, extractedText: text, raceDate: raceDate)
            scheduleStatuses = [:]
            scheduledDates = [:]
        } catch {
            cancelProgress()
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Import from pasted text

    func importText(_ rawText: String, title: String = "Training Plan", raceDate: Date? = nil) async {
        isLoading = true
        errorMessage = nil
        startProgress(phase: "Reading plan…")

        do {
            advanceProgress(to: 0.20, phase: "Sending to Claude…")
            let plan = try await parser.parseTrainingPlan(from: rawText, title: title) { [weak self] progress, phase in
                self?.advanceProgress(to: 0.20 + progress * 0.75, phase: phase)
            }
            completeProgress()
            try? await Task.sleep(nanoseconds: 350_000_000)
            planStore.saveText(plan, title: title, rawText: rawText, raceDate: raceDate)
            scheduleStatuses = [:]
            scheduledDates = [:]
        } catch {
            cancelProgress()
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Re-parse (hits Claude again using the stored source, preserves race date)

    func reparse() async {
        guard let title = planStore.current?.title else { return }
        guard let text = planStore.sourceText() else {
            errorMessage = "Original source file not found — import the plan again to re-parse."
            return
        }
        isLoading = true
        errorMessage = nil
        startProgress(phase: "Loading source…")

        let existingRaceDate = planStore.current?.raceDate
        let pid = planStore.activePlanID   // guard against the user switching plans mid-parse

        do {
            advanceProgress(to: 0.20, phase: "Sending to Claude…")
            let plan = try await parser.parseTrainingPlan(from: text, title: title) { [weak self] progress, phase in
                self?.advanceProgress(to: 0.20 + progress * 0.75, phase: phase)
            }
            completeProgress()
            try? await Task.sleep(nanoseconds: 350_000_000)
            // If the active plan changed while Claude was working, drop the result rather
            // than overwrite the now-active plan with this one's re-parse.
            guard planStore.activePlanID == pid else { cancelProgress(); isLoading = false; return }
            // Use updatePlanOnly so we don't try to re-copy the source file over itself
            planStore.updatePlanOnly(plan, title: title, raceDate: existingRaceDate)
            scheduleStatuses = [:]
        } catch {
            cancelProgress()
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Schedule

    func scheduleWorkout(_ day: WorkoutDay, on date: Date) async {
        scheduleStatuses[day.id] = .scheduling

        do {
            try await WorkoutKitService.shared.schedule(day, on: date)
            let confirmed = await WorkoutKitService.shared.isScheduled(day)
            if confirmed {
                scheduleStatuses[day.id] = .scheduled
                scheduledDates[day.id] = date
                planStore.setScheduledDate(dayID: day.id, date)   // persist so it survives relaunch
            } else {
                scheduleStatuses[day.id] = .failed("Sync could not be verified — check your Watch.")
            }
        } catch {
            scheduleStatuses[day.id] = .failed(error.localizedDescription)
        }
    }

    func resetScheduleStatus(for day: WorkoutDay) {
        scheduleStatuses[day.id] = .unscheduled
    }

    // MARK: - Completion auto-match (HealthKit)

    /// Match completed HealthKit runs to planned workouts by date and mark them done.
    /// Manual completions always win — never overwritten.
    func autoMatchCompletions() async {
        guard let plan = planStore.current, let start = plan.planStartDate else { return }
        let pid = planStore.activePlanID   // guard against a plan switch across the awaits below
        guard await HealthKitService.shared.requestReadAuthorization() else { return }

        let runs = await HealthKitService.shared.completedRuns(since: start)
        guard !runs.isEmpty else { return }
        guard planStore.activePlanID == pid else { return }   // stale — user switched plans

        let cal = Calendar.current
        func miles(_ w: HKWorkout) -> Double { w.totalDistance?.doubleValue(for: .mile()) ?? 0 }

        for (weekIndex, days) in plan.plan.weeks.enumerated() {
            for day in days where !day.isRestDay && !day.isCompleted {
                guard let plannedDate = plan.date(forWeekIndex: weekIndex, day: day) else { continue }
                let sameDay = runs.filter { cal.isDate($0.startDate, inSameDayAs: plannedDate) }
                // Longest run that day, and require it to cover at least half the planned
                // distance (when known) — so a short jog can't tick off a long run.
                guard let match = sameDay.max(by: { miles($0) < miles($1) }) else { continue }
                let plannedMiles = day.segments.compactMap { $0.distanceMiles }.reduce(0, +)
                if plannedMiles > 0 && miles(match) < plannedMiles * 0.5 { continue }
                planStore.setCompletion(dayID: day.id,
                                        WorkoutCompletion(isDone: true,
                                                          completedDate: match.startDate,
                                                          source: .auto,
                                                          healthKitWorkoutID: match.uuid))
            }
        }
    }

    // MARK: - Calendar sync (EventKit → the phone Calendar)

    /// Upsert every non-rest workout into the dedicated PaceSync calendar (moves events on re-date).
    func syncCalendar() async {
        // Request access first, then read the plan — so a plan captured before the await
        // can't go stale if the user switches plans during the permission prompt.
        guard await EventKitService.shared.requestAccess() else {
            errorMessage = "Calendar access was denied. You can enable it in Settings ▸ PaceSync."
            return
        }
        guard let plan = planStore.current else { return }
        let pid = planStore.activePlanID
        for (weekIndex, days) in plan.plan.weeks.enumerated() {
            for day in days where !day.isRestDay {
                guard let date = plan.date(forWeekIndex: weekIndex, day: day) else { continue }
                if let id = EventKitService.shared.upsert(title: day.title, notes: day.notes,
                                                          date: date, existingID: day.calendarEventID) {
                    guard planStore.activePlanID == pid else { return }
                    planStore.setCalendarEventID(dayID: day.id, id)
                }
            }
        }
    }

    /// Remove all of this plan's events from the phone Calendar.
    func clearCalendar() {
        guard let plan = planStore.current else { return }
        for day in plan.plan.allDays where day.calendarEventID != nil {
            EventKitService.shared.remove(day.calendarEventID!)
            planStore.setCalendarEventID(dayID: day.id, nil)
        }
    }

    /// Switch the active plan and drop transient per-day status so nothing bleeds across plans.
    func activatePlan(_ id: UUID) {
        planStore.activate(id)
        scheduleStatuses = [:]
        scheduledDates = [:]
    }

    /// Remove a saved plan and clean up its calendar events (no orphans left behind).
    func removePlan(_ id: UUID) {
        if let p = planStore.plans.first(where: { $0.id == id }) {
            for day in p.plan.allDays where day.calendarEventID != nil {
                EventKitService.shared.remove(day.calendarEventID!)
            }
        }
        let wasActive = planStore.activePlanID == id
        planStore.removePlan(id)
        // removePlan may auto-activate the next plan; clear transient status so it can't
        // inherit the removed plan's badges (day ids aren't unique across plans).
        if wasActive {
            scheduleStatuses = [:]
            scheduledDates = [:]
        }
    }

    // MARK: - Parsing progress helpers

    private func startProgress(phase: String) {
        parsingPhase = phase
        withAnimation(.easeOut(duration: 0.3)) { parsingProgress = 0.05 }

        progressTask?.cancel()
        progressTask = Task { @MainActor [weak self] in
            // Slowly crawl to 0.88 over ~35 seconds to give Claude enough runway
            let steps: [(UInt64, Double, String)] = [
                (4_000_000_000,  0.35, "Analysing workouts…"),
                (9_000_000_000,  0.58, "Structuring schedule…"),
                (16_000_000_000, 0.75, "Building week blocks…"),
                (25_000_000_000, 0.88, "Almost there…"),
            ]
            for (delay, target, phase) in steps {
                try? await Task.sleep(nanoseconds: delay)
                guard let self, !Task.isCancelled else { return }
                self.parsingPhase = phase
                withAnimation(.easeOut(duration: 0.6)) { self.parsingProgress = target }
            }
        }
    }

    private func advanceProgress(to target: Double, phase: String) {
        parsingPhase = phase
        withAnimation(.easeOut(duration: 0.4)) { parsingProgress = max(parsingProgress, target) }
    }

    private func completeProgress() {
        progressTask?.cancel()
        progressTask = nil
        withAnimation(.easeOut(duration: 0.25)) { parsingProgress = 1.0 }
        parsingPhase = "Done!"
    }

    private func cancelProgress() {
        progressTask?.cancel()
        progressTask = nil
        parsingProgress = 0
        parsingPhase = ""
    }
}
