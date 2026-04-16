// WorkoutFileImporter.swift
// Protocol and factory for file format abstraction.

import Foundation

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
    switch url.pathExtension.lowercased() {
    case "pdf":       return PDFImporter()
    case "txt", "md": return PlainTextImporter()
    default:
        throw ImportError.unsupportedFormat(url.pathExtension)
    }
}
