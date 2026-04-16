// PlainTextImporter.swift
// Reads plain text and markdown files.

import Foundation

struct PlainTextImporter: WorkoutFileImporter {
    func extractText(from url: URL) throws -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw ImportError.fileUnreadable
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw ImportError.emptyContent }
        return trimmed
    }
}
