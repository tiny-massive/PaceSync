// WorkoutFileImporter.swift
// Protocol and factory for file format abstraction.

import Foundation
import UniformTypeIdentifiers

protocol WorkoutFileImporter {
    func extractText(from url: URL) throws -> String
}

enum ImportError: LocalizedError {
    case unsupportedFormat(String)
    case fileUnreadable
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): return "'\(ext)' files are not supported yet."
        case .fileUnreadable:             return "Could not read the file."
        case .emptyContent:               return "The file appears to be empty."
        }
    }
}

func makeImporter(for url: URL) throws -> WorkoutFileImporter {
    // Primary check: file extension (fast, works for the common case)
    switch url.pathExtension.lowercased() {
    case "pdf":        return PDFImporter()
    case "txt", "md":  return PlainTextImporter()
    default: break
    }
    // Fallback: UTType conformance check via resource values.
    // Handles iCloud Drive placeholders, share-sheet URLs, and files
    // whose extension doesn't match the extension check above.
    let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey])
    if let type = resourceValues?.contentType {
        if type.conforms(to: .pdf)       { return PDFImporter() }
        if type.conforms(to: .plainText) { return PlainTextImporter() }
        if type.conforms(to: .text)      { return PlainTextImporter() }
    }
    let ext = url.pathExtension.isEmpty ? "unknown" : url.pathExtension
    throw ImportError.unsupportedFormat(ext)
}
