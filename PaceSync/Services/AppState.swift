// AppState.swift
// Transient UI state — loading, errors, parsing progress, WorkoutKit schedule statuses.
// Persistence is handled by PlanStore.

import Combine
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

    func importFile(from url: URL) async {
        isLoading = true
        errorMessage = nil
        startProgress(phase: "Extracting text…")

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let importer = try makeImporter(for: url)
            let text     = try importer.extractText(from: url)
            guard text.count > 30 else {
                throw ImportError.emptyContent
            }
            let title = url.deletingPathExtension().lastPathComponent
            advanceProgress(to: 0.25, phase: "Sending to Claude…")
            let plan = try await parser.parseTrainingPlan(from: text, title: title) { [weak self] progress, phase in
                self?.advanceProgress(to: 0.25 + progress * 0.70, phase: phase)
            }
            completeProgress()
            try? await Task.sleep(nanoseconds: 350_000_000)
            planStore.save(plan, title: title, sourceURL: url, extractedText: text)
            scheduleStatuses = [:]
        } catch {
            cancelProgress()
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Import from pasted text

    func importText(_ rawText: String, title: String = "Training Plan") async {
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
            planStore.saveText(plan, title: title, rawText: rawText)
            scheduleStatuses = [:]
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

        do {
            advanceProgress(to: 0.20, phase: "Sending to Claude…")
            let plan = try await parser.parseTrainingPlan(from: text, title: title) { [weak self] progress, phase in
                self?.advanceProgress(to: 0.20 + progress * 0.75, phase: phase)
            }
            completeProgress()
            try? await Task.sleep(nanoseconds: 350_000_000)
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
