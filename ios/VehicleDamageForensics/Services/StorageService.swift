// StorageService.swift
// Vehicle Damage Forensic Matcher
// File-based case persistence using Codable + FileManager.
// Cases are stored as individual JSON documents in the app's
// Documents/Cases directory so they can be exported, shared, or
// archived for chain-of-custody purposes.

import Foundation
import Combine

// MARK: - Storage Service

@MainActor
final class StorageService: ObservableObject {

    // MARK: Singleton

    static let shared = StorageService()

    // MARK: Published

    @Published private(set) var cases: [ForensicCase] = []
    @Published private(set) var lastError: StorageError?

    // MARK: Private

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let casesDirectory: URL

    // MARK: Init

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.casesDirectory = docs.appendingPathComponent("Cases", isDirectory: true)

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        ensureDirectoryExists()
    }

    // MARK: Public API

    /// Loads all cases from disk into memory. Safe to call on app launch.
    func loadAllCases() async {
        do {
            let urls = try fileManager.contentsOfDirectory(
                at: casesDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            let decoded: [ForensicCase] = urls
                .filter { $0.pathExtension == "json" }
                .compactMap { url in
                    try? decoder.decode(ForensicCase.self, from: Data(contentsOf: url))
                }
                .sorted { $0.dateCreated > $1.dateCreated }
            self.cases = decoded
        } catch {
            self.lastError = .read(error.localizedDescription)
            self.cases = []
        }
    }

    /// Saves a case to disk. Replaces any existing file with the same id.
    @discardableResult
    func save(_ forensicCase: ForensicCase) async -> Bool {
        let url = casesDirectory.appendingPathComponent("\(forensicCase.id.uuidString).json")
        do {
            let data = try encoder.encode(forensicCase)
            try data.write(to: url, options: [.atomic])
            // Update in-memory cache
            if let idx = cases.firstIndex(where: { $0.id == forensicCase.id }) {
                cases[idx] = forensicCase
            } else {
                cases.insert(forensicCase, at: 0)
            }
            return true
        } catch {
            self.lastError = .write(error.localizedDescription)
            return false
        }
    }

    /// Deletes a case from disk and the in-memory cache.
    @discardableResult
    func delete(caseID: UUID) -> Bool {
        let url = casesDirectory.appendingPathComponent("\(caseID.uuidString).json")
        do {
            try fileManager.removeItem(at: url)
            cases.removeAll { $0.id == caseID }
            return true
        } catch {
            self.lastError = .delete(error.localizedDescription)
            return false
        }
    }

    /// Exports a case as JSON Data for sharing.
    func exportData(for forensicCase: ForensicCase) throws -> Data {
        try encoder.encode(forensicCase)
    }

    /// Returns the file URL for a case so a UIActivityViewController can share it.
    func fileURL(for caseID: UUID) -> URL {
        casesDirectory.appendingPathComponent("\(caseID.uuidString).json")
    }

    // MARK: Helpers

    private func ensureDirectoryExists() {
        guard !fileManager.fileExists(atPath: casesDirectory.path) else { return }
        do {
            try fileManager.createDirectory(at: casesDirectory, withIntermediateDirectories: true)
        } catch {
            self.lastError = .write("Could not create cases directory: \(error.localizedDescription)")
        }
    }
}

// MARK: - Errors

enum StorageError: LocalizedError, Equatable {
    case read(String)
    case write(String)
    case delete(String)

    var errorDescription: String? {
        switch self {
        case .read(let m):   return "Could not load cases: \(m)"
        case .write(let m):  return "Could not save case: \(m)"
        case .delete(let m): return "Could not delete case: \(m)"
        }
    }
}
