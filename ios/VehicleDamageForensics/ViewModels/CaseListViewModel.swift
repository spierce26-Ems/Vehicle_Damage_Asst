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
                || c.notes.lowercased().contains(q)
                || c.victimVehicle.displayName.lowercased().contains(q)
                || (c.suspectVehicle?.displayName.lowercased().contains(q) ?? false)
        }
    }

    /// Create a new draft case and return its ID for navigation.
    func createNewCase(notes: String = "") async -> ForensicCase {
        let newCase = ForensicCase(
            caseNumber: nextCaseNumber(),
            caseType: .hitAndRun,
            status: .inProgress,
            dateCreated: Date(),
            notes: notes,
            victimVehicle: Vehicle(role: .victim)
        )
        await storage.save(newCase)
        return newCase
    }

    /// Permanently remove a case from disk.
    func deleteCase(_ id: UUID) {
        storage.delete(caseID: id)
    }

    func openCounts() -> Int {
        cases.filter { $0.status == .inProgress }.count
    }

    // MARK: Helpers

    private func nextCaseNumber() -> String {
        let year = Calendar.current.component(.year, from: Date())
        let count = cases.count + 1
        return String(format: "VD-%d-%05d", year, count)
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
