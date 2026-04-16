// PlanParseCache.swift
// Disk-based cache for Claude-parsed week JSON, keyed by SHA256 of the input text.
// Stored in iOS Caches directory — automatically cleared by the OS if storage is tight.

import CryptoKit
import Foundation

final class PlanParseCache {

    static let shared = PlanParseCache()

    private let cacheDir: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = base.appendingPathComponent("PlanParseCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Read / Write

    /// Returns the cached JSON string for the given input text, or nil on a cache miss.
    func cachedJSON(for text: String) -> String? {
        try? String(contentsOf: cacheURL(for: text), encoding: .utf8)
    }

    /// Persists a Claude response JSON string keyed by the input text.
    func store(json: String, for text: String) {
        try? json.write(to: cacheURL(for: text), atomically: true, encoding: .utf8)
    }

    // MARK: - Maintenance

    /// Removes every cached entry.
    func clearAll() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        print("🗑️ [PlanParseCache] Cache cleared")
    }

    /// Total bytes used by the cache (for display in Settings).
    var cacheSizeBytes: Int64 {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return urls.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return sum + Int64(size)
        }
    }

    /// Human-readable cache size string (e.g. "48 KB").
    var cacheSizeString: String {
        let bytes = cacheSizeBytes
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    // MARK: - Private

    private func cacheURL(for text: String) -> URL {
        let digest = SHA256.hash(data: Data(text.utf8))
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent("\(hex).json")
    }
}
