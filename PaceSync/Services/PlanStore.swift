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
    }

    // MARK: - Save (new plan from file)

    func save(_ plan: TrainingPlan, title: String, sourceURL: URL, extractedText: String? = nil) {
        let ext  = sourceURL.pathExtension.isEmpty ? "txt" : sourceURL.pathExtension
        let dest = sourcesDir.appendingPathComponent("source.\(ext)")
        // Only copy if source and destination are different paths
        if sourceURL.standardizedFileURL != dest.standardizedFileURL {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: sourceURL, to: dest)
        }
        current = SavedPlan(id: UUID(), title: title, raceDate: nil,
                            plan: plan, dateAdded: Date(),
                            sourceFileName: dest.lastPathComponent,
                            cachedSourceText: extractedText)
        persist()
    }

    func saveText(_ plan: TrainingPlan, title: String, rawText: String) {
        let dest = sourcesDir.appendingPathComponent("source.txt")
        try? rawText.write(to: dest, atomically: true, encoding: .utf8)
        current = SavedPlan(id: UUID(), title: title, raceDate: nil,
                            plan: plan, dateAdded: Date(),
                            sourceFileName: "source.txt",
                            cachedSourceText: rawText)
        persist()
    }

    // MARK: - Update plan in-place (used by reparse — does NOT touch source file)

    func updatePlanOnly(_ plan: TrainingPlan, title: String, raceDate: Date?) {
        current = SavedPlan(
            id: current?.id ?? UUID(),
            title: title,
            raceDate: raceDate,
            plan: plan,
            dateAdded: current?.dateAdded ?? Date(),
            sourceFileName: current?.sourceFileName,
            cachedSourceText: current?.cachedSourceText
        )
        persist()
    }

    // MARK: - Mutations

    func setRaceDate(_ date: Date?) {
        current?.raceDate = date
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
                saved.plan.weeks[wi][di] = updatedDay
                break
            }
        }
        current = saved
        persist()
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
        guard let data  = try? Data(contentsOf: storeURL),
              let saved = try? JSONDecoder().decode(SavedPlan.self, from: data) else { return }
        current = saved
    }
}
