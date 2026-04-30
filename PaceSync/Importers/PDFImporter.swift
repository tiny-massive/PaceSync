// PDFImporter.swift
// Extracts plain text from PDF files using PDFKit.

import Foundation
import PDFKit

struct PDFImporter: WorkoutFileImporter {
    func extractText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw ImportError.fileUnreadable
        }
        var text = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i) {
                if i > 0 { text += "\n\n=== PAGE BREAK ===\n\n" }
                text += page.string ?? ""
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw ImportError.emptyContent }
        print("📄 [PDFImporter] Extracted \(trimmed.count) chars, \(document.pageCount) page(s)")
        print("📄 [PDFImporter] First 500 chars:\n\(String(trimmed.prefix(500)))")
        return trimmed
    }
}
