// PlanStore.swift
// Single-plan persistence — JSON sidecar + source file storage.

import Combine
import Foundation

@MainActor
class PlanStore: ObservableObject {

    static let shared = PlanStore()

    @Published var current: SavedPlan?

    private let storeURL: URL
    private let sourcesDir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storeURL   = docs.appendingPathComponent("savedplan.json")
        sourcesDir = docs.appendingPathComponent("Plans", isDirectory: true)
        try? FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        load()
        #if targetEnvironment(simulator)
        if current == nil { seedSampleForSimulator() }
        #endif
    }

    // MARK: - Save (new plan from file)

    func save(_ plan: TrainingPlan, title: String, sourceURL: URL, extractedText: String? = nil, raceDate: Date? = nil) {
        let ext  = sourceURL.pathExtension.isEmpty ? "txt" : sourceURL.pathExtension
        let dest = sourcesDir.appendingPathComponent("source.\(ext)")
        // Only copy if source and destination are different paths
        if sourceURL.standardizedFileURL != dest.standardizedFileURL {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: sourceURL, to: dest)
        }
        current = SavedPlan(id: UUID(), title: title, raceDate: raceDate,
                            plan: plan, dateAdded: Date(),
                            sourceFileName: dest.lastPathComponent,
                            cachedSourceText: extractedText)
        persist()
    }

    func saveText(_ plan: TrainingPlan, title: String, rawText: String, raceDate: Date? = nil) {
        let dest = sourcesDir.appendingPathComponent("source.txt")
        try? rawText.write(to: dest, atomically: true, encoding: .utf8)
        current = SavedPlan(id: UUID(), title: title, raceDate: raceDate,
                            plan: plan, dateAdded: Date(),
                            sourceFileName: "source.txt",
                            cachedSourceText: rawText)
        persist()
    }

    // MARK: - Update plan in-place (used by reparse — does NOT touch source file)

    func updatePlanOnly(_ plan: TrainingPlan, title: String, raceDate: Date?) {
        // Carry per-day state (completion / Watch schedule / calendar link) forward across a
        // re-import, matched by stable day id, so re-parsing never wipes it.
        var newPlan = plan
        if let old = current {
            let byID = Dictionary(old.plan.allDays.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for wi in newPlan.weeks.indices {
                for di in newPlan.weeks[wi].indices {
                    if let prev = byID[newPlan.weeks[wi][di].id] {
                        newPlan.weeks[wi][di].completion      = prev.completion
                        newPlan.weeks[wi][di].scheduledDate   = prev.scheduledDate
                        newPlan.weeks[wi][di].calendarEventID = prev.calendarEventID
                    }
                }
            }
        }
        current = SavedPlan(
            id: current?.id ?? UUID(),
            title: title,
            raceDate: raceDate,
            plan: newPlan,
            dateAdded: current?.dateAdded ?? Date(),
            sourceFileName: current?.sourceFileName,
            cachedSourceText: current?.cachedSourceText
        )
        persist()
    }

    // MARK: - Mutations

    func setRaceDate(_ date: Date?) {
        guard var c = current else { return }
        c.raceDate = date
        // Every workout date derives from the race date, so shifting it lands any existing
        // Watch/Calendar sync on the wrong day — mark them for re-sync.
        for wi in c.plan.weeks.indices {
            for di in c.plan.weeks[wi].indices {
                c.plan.weeks[wi][di].scheduledDate = nil
                c.plan.weeks[wi][di].calendarEventID = nil
                // Auto-completions were pinned to the old dates — drop them so they re-match;
                // manual completions stand.
                if c.plan.weeks[wi][di].completion?.source == .auto {
                    c.plan.weeks[wi][di].completion = nil
                }
            }
        }
        current = c
        persist()
    }

    func rename(_ newTitle: String) {
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        current?.title = newTitle
        persist()
    }

    func updateDay(_ updatedDay: WorkoutDay) {
        guard var saved = current else { return }
        for wi in saved.plan.weeks.indices {
            if let di = saved.plan.weeks[wi].firstIndex(where: { $0.id == updatedDay.id }) {
                var d = updatedDay
                // Content changed, so any Watch/Calendar copy is now stale — clear the links
                // (shows "not synced", ready to re-push). Completion reflects whether the run
                // happened, so keep it.
                d.scheduledDate = nil
                d.calendarEventID = nil
                d.completion = saved.plan.weeks[wi][di].completion
                saved.plan.weeks[wi][di] = d
                break
            }
        }
        current = saved
        persist()
    }

    /// Mutate a single day in place by id and persist. Basis for completion / schedule / calendar writes.
    func mutateDay(_ dayID: UUID, _ transform: (inout WorkoutDay) -> Void) {
        guard var saved = current else { return }
        for wi in saved.plan.weeks.indices {
            if let di = saved.plan.weeks[wi].firstIndex(where: { $0.id == dayID }) {
                transform(&saved.plan.weeks[wi][di])
                current = saved
                persist()
                return
            }
        }
    }

    func setCompletion(dayID: UUID, _ completion: WorkoutCompletion?) {
        mutateDay(dayID) { $0.completion = completion }
    }
    func setScheduledDate(dayID: UUID, _ date: Date?) {
        mutateDay(dayID) { $0.scheduledDate = date }
    }
    func setCalendarEventID(dayID: UUID, _ id: String?) {
        mutateDay(dayID) { $0.calendarEventID = id }
    }

    func clear() {
        // Remove source files
        if let name = current?.sourceFileName {
            try? FileManager.default.removeItem(at: sourcesDir.appendingPathComponent(name))
        }
        // Explicitly notify before AND after to ensure SwiftUI observers update immediately
        objectWillChange.send()
        current = nil
        try? FileManager.default.removeItem(at: storeURL)
    }

    // MARK: - Source file access

    func sourceFileURL() -> URL? {
        guard let name = current?.sourceFileName else { return nil }
        return sourcesDir.appendingPathComponent(name)
    }

    func sourceText() -> String? {
        // Prefer in-memory cache (always available, no file dependency)
        if let cached = current?.cachedSourceText { return cached }
        // Fall back to reading from disk
        guard let url = sourceFileURL() else { return nil }
        if url.pathExtension.lowercased() == "pdf" {
            return try? PDFImporter().extractText(from: url)
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Persistence

    private func persist() {
        guard let current else { return }
        try? JSONEncoder().encode(current).write(to: storeURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        do {
            current = try JSONDecoder().decode(SavedPlan.self, from: data)
        } catch {
            // Don't silently lose the user's only plan on a decode failure — keep the
            // file on disk so a future migration can recover it, and surface the error.
            print("⚠️ [PlanStore] Could not decode saved plan: \(error)")
        }
    }

    #if targetEnvironment(simulator)
    /// Simulator-only sample plan so screenshots aren't an empty shell. Never runs on device.
    private func seedSampleForSimulator() {
        func s(_ type: SegmentType, mi: Double? = nil, m: Double? = nil, reps: Int? = nil, effort: EffortLevel? = nil) -> WorkoutSegment {
            WorkoutSegment(id: UUID(), type: type, durationSeconds: nil, distanceMiles: mi,
                           distanceMeters: m, reps: reps, restDurationSeconds: nil, effort: effort, setIndex: nil)
        }
        func d(_ w: Int, _ dow: DayOfWeek, _ title: String, _ notes: String?, _ segs: [WorkoutSegment], race: Bool = false) -> WorkoutDay {
            WorkoutDay(id: ClaudeParserService.stableDayID(week: w, dayOfWeek: dow), week: w,
                       dayOfWeek: dow, title: title, notes: notes, segments: segs, isRaceDay: race)
        }
        var weeks: [[WorkoutDay]] = []
        for w in 1...4 {
            weeks.append([
                d(w, .monday,    "Easy run",  "Easy \(3 + w) miles at conversational pace.", [s(.easy, mi: Double(3 + w))]),
                d(w, .tuesday,   "Rest", nil, []),
                d(w, .wednesday, "Intervals", "4×1km at 5K effort, 90s jog recovery. 1.5km warm-up + cool-down.", [s(.warmup, mi: 0.9), s(.interval, m: 1000, reps: 4, effort: .fiveK), s(.cooldown, mi: 0.9)]),
                d(w, .thursday,  "Tempo run", "\(3 + w) miles at threshold — comfortably hard.", [s(.warmup, mi: 1), s(.tempo, mi: Double(3 + w), effort: .threshold), s(.cooldown, mi: 1)]),
                d(w, .friday,    "Rest", nil, []),
                d(w, .saturday,  "Easy run",  "Easy 4 miles.", [s(.easy, mi: 4)]),
                w == 4
                    ? d(w, .sunday, "Race day", "Half marathon — enjoy it.", [s(.easy, mi: 13.1)], race: true)
                    : d(w, .sunday, "Long run", "Long run \(8 + w * 2) miles, steady effort.", [s(.easy, mi: Double(8 + w * 2))])
            ])
        }
        weeks[0][0].completion = WorkoutCompletion(isDone: true, source: .auto)
        weeks[0][2].completion = WorkoutCompletion(isDone: true, source: .manual)
        weeks[0][3].scheduledDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())
        let plan = TrainingPlan(id: UUID(), title: "Half Marathon Plan", weeks: weeks)
        let race = Calendar.current.date(byAdding: .day, value: 18, to: Date()) ?? Date()
        current = SavedPlan(id: UUID(), title: "Half Marathon Plan", raceDate: race,
                            plan: plan, dateAdded: Date(), sourceFileName: nil, cachedSourceText: nil)
        persist()
    }
    #endif
}
