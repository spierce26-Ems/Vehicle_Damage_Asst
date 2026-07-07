// CaseListViewModel.swift
// Vehicle Damage Investigation Assistant
// Drives the dashboard / case list screen. Loads all persisted cases,
// supports search, filtering, deletion, and "new case" creation.

import Foundation
import Combine

// MARK: - Case List View Model

@MainActor
final class CaseListViewModel: ObservableObject {

    // MARK: Published

    @Published private(set) var cases: [ForensicCase] = []
    @Published var searchText: String = ""
    @Published var statusFilter: CaseStatus? = nil
    @Published private(set) var isLoading: Bool = false
    @Published var lastError: String?

    // MARK: Dependencies

    private let storage: StorageService
    private var cancellables: Set<AnyCancellable> = []

    /// NOTE(AI Developer): `storage` defaults to `nil` rather than
    /// `= .shared` directly in the parameter list -- see the identical
    /// note in CaptureViewModel.init for why (Swift 6 strict concurrency:
    /// default-argument expressions are evaluated in a non-isolated
    /// context, but `StorageService.shared` is `@MainActor`-isolated).
    init(storage: StorageService? = nil) {
        self.storage = storage ?? .shared
        bind()
    }

    // MARK: Public API

    func load() async {
        isLoading = true
        await storage.loadAllCases()
        isLoading = false
    }

    /// Filtered + searched cases for display.
    var filteredCases: [ForensicCase] {
        cases.filter { c in
            // Status filter
            if let s = statusFilter, c.status != s { return false }
            // Search
            guard searchText.isEmpty == false else { return true }
            let q = searchText.lowercased()
            return c.caseNumber.lowercased().contains(q)
                || c.caseName.lowercased().contains(q)
                || c.notes.lowercased().contains(q)
                || c.victimVehicle.displayName.lowercased().contains(q)
                || (c.suspectVehicle?.displayName.lowercased().contains(q) ?? false)
                || (c.location?.displayAddress.lowercased().contains(q) ?? false)
        }
    }

    /// Create a new draft case and return its ID for navigation.
    ///
    /// NOTE(AI Developer): Expanded per Sean's decision (2026-07) to accept
    /// a case name, full incident details (type/date/address), and the
    /// victim vehicle's make/model/etc. up front instead of only `notes`.
    /// `caseNumber` is always auto-assigned here via `nextCaseNumber()` —
    /// there is intentionally no way for the "New Case" form to set it
    /// manually, so every case is guaranteed a serial number.
    func createNewCase(
        caseName: String = "",
        caseType: CaseType = .hitAndRun,
        incidentDate: Date? = nil,
        location: IncidentLocation? = nil,
        victimVehicle: Vehicle = Vehicle(role: .victim),
        notes: String = ""
    ) async -> ForensicCase {
        let newCase = ForensicCase(
            caseNumber: nextCaseNumber(),
            caseName: caseName,
            caseType: caseType,
            status: .inProgress,
            dateCreated: Date(),
            incidentDate: incidentDate,
            location: (location?.isEmpty ?? true) ? nil : location,
            notes: notes,
            victimVehicle: victimVehicle
        )
        await storage.save(newCase)
        return newCase
    }

    /// Persist edits made via `EditCaseSheet` from the Dashboard. Records
    /// a `.caseEdited` audit entry before saving so the chain-of-custody
    /// log reflects every post-creation change, not just creation itself.
    func updateCase(_ updated: ForensicCase) async {
        var updated = updated
        updated.recordAudit(.caseEdited)
        await storage.save(updated)
    }

    /// Permanently remove a case from disk.
    func deleteCase(_ id: UUID) {
        storage.delete(caseID: id)
    }

    func openCounts() -> Int {
        cases.filter { $0.status == .inProgress }.count
    }

    // MARK: Helpers

    /// NOTE(AI Developer): Previously `cases.count + 1`, which reissues a
    /// duplicate serial number after any case is deleted (e.g. delete the
    /// only case, "count" goes back to 0, next case gets the same number
    /// as the deleted one). Now scans existing case numbers for the
    /// current year's highest sequence and increments past it, so numbers
    /// stay unique/increasing regardless of deletions. Falls back to `1`
    /// for the first case of a new year.
    private func nextCaseNumber() -> String {
        let year = Calendar.current.component(.year, from: Date())
        let prefix = "VD-\(year)-"
        let highestExisting = cases
            .map(\.caseNumber)
            .filter { $0.hasPrefix(prefix) }
            .compactMap { Int($0.dropFirst(prefix.count)) }
            .max() ?? 0
        return String(format: "%@%05d", prefix, highestExisting + 1)
    }

    private func bind() {
        storage.$cases
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.cases = $0 }
            .store(in: &cancellables)
        storage.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] err in self?.lastError = err?.errorDescription }
            .store(in: &cancellables)
    }
}
