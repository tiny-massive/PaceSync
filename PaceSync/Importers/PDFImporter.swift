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
                text += page.string ?? ""
                text += "\n"
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw ImportError.emptyContent }
        return trimmed
    }
}
