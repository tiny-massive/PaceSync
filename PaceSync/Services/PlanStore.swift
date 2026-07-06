// PlanStore.swift
// Plan LIBRARY persistence — many saved plans, one active at a time. `current` is a
// computed view of the active plan, so existing call sites keep working unchanged.

import Combine
import Foundation

@MainActor
class PlanStore: ObservableObject {

    static let shared = PlanStore()

    /// Every saved plan.
    @Published var plans: [SavedPlan] = []
    /// The active plan's id (nil = none active).
    @Published var activePlanID: UUID?

    /// The active plan. Reads/writes the entry in `plans`, so all existing code is unchanged.
    var current: SavedPlan? {
        get { plans.first { $0.id == activePlanID } }
        set {
            guard let nv = newValue else { activePlanID = nil; persist(); return }
            if let i = plans.firstIndex(where: { $0.id == nv.id }) { plans[i] = nv }
            else { plans.append(nv) }
            activePlanID = nv.id
            persist()
        }
    }

    private let storeURL: URL     // plans.json (library)
    private let legacyURL: URL    // savedplan.json (pre-library, migrated on first launch)
    private let sourcesDir: URL
    private let activeKey = "pacesync.activePlanID"
    private let backupKey = "pacesync.plansBackup"   // durable second copy (survives a file loss)

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storeURL   = docs.appendingPathComponent("plans.json")
        legacyURL  = docs.appendingPathComponent("savedplan.json")
        sourcesDir = docs.appendingPathComponent("Plans", isDirectory: true)
        try? FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        load()
        #if targetEnvironment(simulator)
        if plans.isEmpty { seedSampleForSimulator() }
        #endif
    }

    // MARK: - Save (new plan → added to the library and activated)

    func save(_ plan: TrainingPlan, title: String, sourceURL: URL, extractedText: String? = nil, raceDate: Date? = nil) {
        let id = UUID()
        let ext  = sourceURL.pathExtension.isEmpty ? "txt" : sourceURL.pathExtension
        let dest = sourcesDir.appendingPathComponent("source-\(id.uuidString).\(ext)")
        if sourceURL.standardizedFileURL != dest.standardizedFileURL {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: sourceURL, to: dest)
        }
        add(SavedPlan(id: id, title: title, raceDate: raceDate, plan: plan, dateAdded: Date(),
                      sourceFileName: dest.lastPathComponent, cachedSourceText: extractedText))
    }

    func saveText(_ plan: TrainingPlan, title: String, rawText: String, raceDate: Date? = nil) {
        let id = UUID()
        let dest = sourcesDir.appendingPathComponent("source-\(id.uuidString).txt")
        try? rawText.write(to: dest, atomically: true, encoding: .utf8)
        add(SavedPlan(id: id, title: title, raceDate: raceDate, plan: plan, dateAdded: Date(),
                      sourceFileName: dest.lastPathComponent, cachedSourceText: rawText))
    }

    private func add(_ plan: SavedPlan) {
        plans.append(plan)
        activePlanID = plan.id
        persist()
    }

    // MARK: - Library

    func activate(_ id: UUID) {
        guard plans.contains(where: { $0.id == id }) else { return }
        activePlanID = id
        persist()
    }

    func deactivate() {
        activePlanID = nil
        persist()
    }

    func removePlan(_ id: UUID) {
        if let p = plans.first(where: { $0.id == id }), let name = p.sourceFileName {
            try? FileManager.default.removeItem(at: sourcesDir.appendingPathComponent(name))
        }
        plans.removeAll { $0.id == id }
        if activePlanID == id { activePlanID = plans.first?.id }
        persist()
    }

    /// "Remove plan" on the active plan.
    func clear() { if let id = activePlanID { removePlan(id) } }

    // MARK: - Update the active plan in-place (reparse — does NOT touch the source file)

    func updatePlanOnly(_ plan: TrainingPlan, title: String, raceDate: Date?) {
        guard let old = current else { return }
        var newPlan = plan
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
        current = SavedPlan(id: old.id, title: title, raceDate: raceDate, plan: newPlan,
                            dateAdded: old.dateAdded, sourceFileName: old.sourceFileName,
                            cachedSourceText: old.cachedSourceText)
    }

    // MARK: - Mutations (operate on the active plan)

    func setRaceDate(_ date: Date?) {
        guard var c = current else { return }
        c.raceDate = date
        for wi in c.plan.weeks.indices {
            for di in c.plan.weeks[wi].indices {
                c.plan.weeks[wi][di].scheduledDate = nil
                if c.plan.weeks[wi][di].completion?.source == .auto {
                    c.plan.weeks[wi][di].completion = nil
                }
            }
        }
        current = c
    }

    func rename(_ newTitle: String) {
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard var c = current else { return }
        c.title = newTitle
        current = c
    }

    func updateDay(_ updatedDay: WorkoutDay) {
        mutateDay(updatedDay.id) { d in
            let keptCompletion = d.completion
            let keptCalendarID = d.calendarEventID
            d = updatedDay
            d.scheduledDate = nil               // Watch copy is stale (can't move) → re-push
            d.calendarEventID = keptCalendarID  // calendar event updates in place on next sync
            d.completion = keptCompletion       // completion reflects the run actually happening
        }
    }

    /// Mutate a single day in the active plan by id and persist.
    func mutateDay(_ dayID: UUID, _ transform: (inout WorkoutDay) -> Void) {
        guard var saved = current else { return }
        for wi in saved.plan.weeks.indices {
            if let di = saved.plan.weeks[wi].firstIndex(where: { $0.id == dayID }) {
                transform(&saved.plan.weeks[wi][di])
                current = saved
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

    /// Clear the calendarEventID on many days across possibly-many plans in ONE shot — a single
    /// in-memory pass, one @Published mutation, and one persist() — instead of one of each per
    /// event (which caused a re-render + full-array JSON encode storm on the main thread when a
    /// user with several synced plans turned calendar sync off).
    func clearCalendarEventIDs(_ days: [(planID: UUID, dayID: UUID)]) {
        guard !days.isEmpty else { return }
        var byPlan: [UUID: Set<UUID>] = [:]
        for d in days { byPlan[d.planID, default: []].insert(d.dayID) }

        var updated = plans     // mutate a local copy so @Published fires just once at the end
        var changed = false
        for pi in updated.indices {
            guard let dayIDs = byPlan[updated[pi].id] else { continue }
            for wi in updated[pi].plan.weeks.indices {
                for di in updated[pi].plan.weeks[wi].indices {
                    if dayIDs.contains(updated[pi].plan.weeks[wi][di].id),
                       updated[pi].plan.weeks[wi][di].calendarEventID != nil {
                        updated[pi].plan.weeks[wi][di].calendarEventID = nil
                        changed = true
                    }
                }
            }
        }
        guard changed else { return }
        plans = updated   // one @Published change → one re-render
        persist()         // one JSON encode + one disk write
    }

    // MARK: - Source file access (active plan)

    func sourceFileURL() -> URL? {
        guard let name = current?.sourceFileName else { return nil }
        return sourcesDir.appendingPathComponent(name)
    }

    func sourceText() -> String? {
        if let cached = current?.cachedSourceText { return cached }
        guard let url = sourceFileURL() else { return nil }
        if url.pathExtension.lowercased() == "pdf" {
            return try? PDFImporter().extractText(from: url)
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Persistence

    private func persist() {
        let data = try? JSONEncoder().encode(plans)
        if let data { try? data.write(to: storeURL, options: .atomic) }
        UserDefaults.standard.set(activePlanID?.uuidString, forKey: activeKey)
        guard let data, !plans.isEmpty else { return }
        // Second copy in Library/Preferences — survives a lost Documents file (same container).
        UserDefaults.standard.set(data, forKey: backupKey)
        // Third copy in iCloud key-value store — survives a full reinstall/container wipe and
        // syncs across devices. No-ops without the iCloud capability. 1MB store cap, so skip an
        // oversized library rather than fail silently.
        if data.count < 900_000 {
            let kv = NSUbiquitousKeyValueStore.default
            kv.set(data, forKey: backupKey)
            kv.synchronize()
        }
    }

    // MARK: - Backup / restore (manual export + import)

    /// Encode the whole library as a user-exportable backup file.
    func exportData() -> Data? { try? JSONEncoder().encode(plans) }

    /// Restore from a backup file's contents (accepts a [SavedPlan] array or a single SavedPlan).
    /// Merges by id, activates one if none active. Returns how many plans were restored.
    @discardableResult
    func importBackup(_ data: Data) -> Int {
        let decoder = JSONDecoder()
        var incoming: [SavedPlan] = []
        if let arr = try? decoder.decode([SavedPlan].self, from: data) { incoming = arr }
        else if let one = try? decoder.decode(SavedPlan.self, from: data) { incoming = [one] }
        guard !incoming.isEmpty else { return 0 }
        for p in incoming {
            if let i = plans.firstIndex(where: { $0.id == p.id }) { plans[i] = p } else { plans.append(p) }
        }
        if activePlanID == nil || !plans.contains(where: { $0.id == activePlanID }) {
            activePlanID = plans.first?.id
        }
        persist()
        return incoming.count
    }

    private func load() {
        let fm = FileManager.default

        // --- Diagnostics: what's actually on disk? (read-only) ---
        func size(_ url: URL) -> Int? { (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int }
        if let s = size(storeURL) { print("📦 [PlanStore] plans.json EXISTS — \(s) bytes") }
        else { print("📦 [PlanStore] plans.json MISSING") }
        if let s = size(legacyURL) { print("📦 [PlanStore] savedplan.json EXISTS — \(s) bytes") }
        else { print("📦 [PlanStore] savedplan.json MISSING") }
        let docs = storeURL.deletingLastPathComponent()
        print("📦 [PlanStore] Documents: \((try? fm.contentsOfDirectory(atPath: docs.path)) ?? [])")
        print("📦 [PlanStore] Plans/: \((try? fm.contentsOfDirectory(atPath: sourcesDir.path)) ?? [])")
        print("📦 [PlanStore] UserDefaults backup present: \(UserDefaults.standard.data(forKey: backupKey) != nil)")

        var libraryDecoded = false
        var migratedFromLegacy = false

        // 1) The library file. Log the exact decode error if it fails.
        if let data = try? Data(contentsOf: storeURL) {
            do {
                plans = try JSONDecoder().decode([SavedPlan].self, from: data)
                libraryDecoded = true
                print("📦 [PlanStore] decoded plans.json → \(plans.count): \(plans.map { $0.title })")
            } catch { print("📦 [PlanStore] ⚠️ plans.json DECODE FAILED — \(error)") }
        }

        // Only reach for fallbacks when the library file is ABSENT or CORRUPT — not when it
        // legitimately decoded to an empty library (that's a valid "removed all plans" state).
        if !libraryDecoded {
            if let data = try? Data(contentsOf: legacyURL),
               let legacy = try? JSONDecoder().decode(SavedPlan.self, from: data) {
                plans = [legacy]
                migratedFromLegacy = true
                print("📦 [PlanStore] recovered savedplan.json → \(plans.map { $0.title })")
            }
            if plans.isEmpty, let data = UserDefaults.standard.data(forKey: backupKey),
               let restored = try? JSONDecoder().decode([SavedPlan].self, from: data), !restored.isEmpty {
                plans = restored
                print("📦 [PlanStore] ♻️ recovered \(plans.count) plan(s) from UserDefaults backup: \(plans.map { $0.title })")
            }
            // Last resort: iCloud key-value store — survives a full reinstall/wipe of the container.
            if plans.isEmpty {
                let kv = NSUbiquitousKeyValueStore.default
                kv.synchronize()
                if let data = kv.data(forKey: backupKey),
                   let restored = try? JSONDecoder().decode([SavedPlan].self, from: data), !restored.isEmpty {
                    plans = restored
                    print("📦 [PlanStore] ♻️ recovered \(plans.count) plan(s) from iCloud backup: \(plans.map { $0.title })")
                }
            }
        }

        if let s = UserDefaults.standard.string(forKey: activeKey),
           let id = UUID(uuidString: s), plans.contains(where: { $0.id == id }) {
            activePlanID = id
        } else {
            activePlanID = plans.first?.id
        }
        // Only WRITE when we actually have plans — a failed decode must NOT clobber the on-disk
        // file, so data stays recoverable. Refresh the backup and drop legacy only after a write.
        if !plans.isEmpty {
            var wrote = false
            if let encoded = try? JSONEncoder().encode(plans) {
                wrote = (try? encoded.write(to: storeURL, options: .atomic)) != nil
                UserDefaults.standard.set(encoded, forKey: backupKey)
            }
            UserDefaults.standard.set(activePlanID?.uuidString, forKey: activeKey)
            if migratedFromLegacy && wrote { try? fm.removeItem(at: legacyURL) }
        } else {
            print("📦 [PlanStore] loaded 0 plans — NOT writing (preserving any on-disk file)")
        }
    }

    #if targetEnvironment(simulator)
    /// Simulator-only sample plans so screenshots aren't an empty shell. Never runs on device.
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
                d(w, .monday,    "Easy run",  "8–12 miles easy plus 6 × 20 sec hill strides", [s(.easy)]),
                d(w, .tuesday,   "Rest", nil, []),
                d(w, .wednesday, "Intervals", "4×1km at 5K effort, 90s jog recovery. 1.5km warm-up + cool-down.", [s(.warmup, mi: 0.9), s(.interval, m: 1000, reps: 4, effort: .fiveK), s(.cooldown, mi: 0.9)]),
                d(w, .thursday,  "Tempo run", "\(3 + w) miles at threshold — comfortably hard.", [s(.warmup, mi: 1), s(.tempo, mi: Double(3 + w), effort: .threshold), s(.cooldown, mi: 1)]),
                d(w, .friday,    "Rest", nil, []),
                d(w, .saturday,  "Easy run",  "12–16 miles easy/mod", [s(.easy)]),
                w == 4
                    ? d(w, .sunday, "Race day", "Half marathon — enjoy it.", [s(.easy, mi: 13.1)], race: true)
                    : d(w, .sunday, "Long run", "Long run \(8 + w * 2) miles, steady effort.", [s(.easy, mi: Double(8 + w * 2))])
            ])
        }
        weeks[0][0].completion = WorkoutCompletion(isDone: true, source: .auto)
        weeks[0][2].completion = WorkoutCompletion(isDone: true, source: .manual)
        weeks[0][3].scheduledDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())
        weeks[0][5].calendarEventID = "sim-demo-event"
        // Current-week (week 2) progress so the week strip shows a ticked-off day.
        weeks[1][0].completion = WorkoutCompletion(isDone: true, source: .manual)
        let active = TrainingPlan(id: UUID(), title: "Half Marathon Plan", weeks: weeks)
        let race = Calendar.current.date(byAdding: .day, value: 18, to: Date()) ?? Date()
        let activeID = UUID()
        plans = [
            SavedPlan(id: activeID, title: "Half Marathon Plan", raceDate: race, plan: active,
                      dateAdded: Date(), sourceFileName: nil, cachedSourceText: nil),
            SavedPlan(id: UUID(), title: "10K Sharpener", raceDate: nil,
                      plan: TrainingPlan(id: UUID(), title: "10K Sharpener",
                                         weeks: Array(weeks.prefix(2))),
                      dateAdded: Date(), sourceFileName: nil, cachedSourceText: nil)
        ]
        activePlanID = activeID
        persist()
    }
    #endif
}
