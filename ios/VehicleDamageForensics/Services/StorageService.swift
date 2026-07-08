// StorageService.swift
// Vehicle Damage Investigation Assistant
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
        // NOTE(AI Developer), fixed 2026-07 per Sean's report ("running
        // correlation analysis" stuck for several minutes): `.prettyPrinted`
        // + `.sortedKeys` together are a well-documented ~5x+ slowdown for
        // `JSONEncoder` (see Swift Forums: "JSONSerialization writing is
        // slow with .sortedKeys option?"). That's a bad trade-off for a
        // case file whose bulk is base64-encoded photo `Data` -- content
        // nobody reads by eye anyway, where formatting only adds
        // whitespace/sort overhead on top of an already-large payload.
        // Combined with the `maxPhotoDimensions` cap added in
        // `CameraService.configureSession()` (was allowing up to 48MP
        // photos), this was the real source of the multi-minute hang: the
        // encode was actually happening on `runAnalysis()`'s post-analysis
        // `storage.save(forensicCase)` call, not the (fast, already
        // reviewed) analysis math itself.
        self.encoder.outputFormatting = []
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        ensureDirectoryExists()
    }

    // MARK: Public API

    /// Loads all cases from disk into memory. Safe to call on app launch.
    ///
    /// NOTE(AI Developer), fixed 2026-07 alongside `save(_:)` above (same
    /// root-cause investigation as Sean's "stuck for several minutes"
    /// report): this ran the decode of every case file -- each one
    /// potentially containing tens of MB of base64 photo data -- directly
    /// on the `@MainActor` at app launch, with no background hop. Same
    /// fix: do the file listing + decode work in a detached background
    /// task, only touch `@Published` state back on the main actor.
    func loadAllCases() async {
        let fileManager = self.fileManager
        let decoder = self.decoder
        let casesDirectory = self.casesDirectory
        let result: Result<[ForensicCase], Error> = await Task.detached(priority: .userInitiated) {
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
                return .success(decoded)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let decoded):
            self.cases = decoded
        case .failure(let error):
            self.lastError = .read(error.localizedDescription)
            self.cases = []
        }
    }

    /// Saves a case to disk. Replaces any existing file with the same id.
    ///
    /// NOTE(AI Developer), fixed 2026-07 per Sean's report ("running
    /// correlation analysis" stuck for several minutes): the encode +
    /// disk-write used to run directly on the `@MainActor` (this class is
    /// `@MainActor`, and this method had no internal `Task.detached`/
    /// background hop), which froze the UI -- including whatever spinner
    /// was on screen -- for the entire duration. That duration could reach
    /// multiple minutes because every photo's `imageData` is embedded as
    /// base64 inside this one case JSON document (10-shot protocol x 2
    /// vehicles), and before this fix `CameraService` allowed capturing at
    /// up to 48MP per photo with a `.prettyPrinted + .sortedKeys` encoder
    /// (both also fixed, see `CameraService.configureSession()` and this
    /// class's `init`). This was the actual root cause of the reported
    /// hang -- NOT the analysis math in `MatchScoreCalculator`/
    /// `ForensicEngine/*`, which was read in full and confirmed fast
    /// (bounded loops, no network, no heavy ML) before finding this.
    ///
    /// Encoding is still real CPU + I/O work even after capping photo
    /// resolution, so it's moved to a background `Task.detached` here;
    /// only the final `@MainActor` state update (`cases`/`lastError`) hops
    /// back to the main actor. `ForensicCase`, `JSONEncoder`, and `URL` are
    /// all safe to hand across this boundary (`ForensicCase` is a
    /// value-type `Codable` struct with no reference types inside it;
    /// `JSONEncoder` instances are safe to use from a single call site at
    /// a time, which is the case here).
    @discardableResult
    func save(_ forensicCase: ForensicCase) async -> Bool {
        let url = casesDirectory.appendingPathComponent("\(forensicCase.id.uuidString).json")
        let encoder = self.encoder
        let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
            do {
                let data = try encoder.encode(forensicCase)
                // NOTE(AI Developer): `.completeFileProtection` added per
                // Sean's security-audit decision (2026-07). Without it,
                // iOS defaults new files to
                // NSFileProtectionCompleteUntilFirstUserAuthentication --
                // unlocked/readable any time after the device's first
                // unlock since reboot, even while the device is
                // subsequently locked. Given this file holds embedded
                // photos, GPS coordinates, and victim/suspect PII for what
                // may be an active police case,
                // `.completeFileProtection` (inaccessible whenever the
                // device is locked, not just before first unlock) is the
                // stronger, more appropriate default here.
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success:
            // Update in-memory cache
            if let idx = cases.firstIndex(where: { $0.id == forensicCase.id }) {
                cases[idx] = forensicCase
            } else {
                cases.insert(forensicCase, at: 0)
            }
            return true
        case .failure(let error):
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
