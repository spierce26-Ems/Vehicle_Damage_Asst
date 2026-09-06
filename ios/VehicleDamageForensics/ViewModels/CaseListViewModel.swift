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
        notes: String = "",
        examiner: ExaminerIdentity? = nil
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
            victimVehicle: victimVehicle,
            // Task #11: passed into the initializer rather than assigned
            // afterwards, so the `.created` audit entry that
            // `ForensicCase.init` appends is itself attributed. Setting
            // it after construction would leave the very first entry in
            // every case's chain of custody unattributed.
            examiner: examiner
        )
        await storage.save(newCase)
        return newCase
    }

    /// NOTE(AI Developer), added 2026-09 for item #5 of Sean's 5-item
    /// plan ("Duplicate Case for Another Suspect"), Option B per the
    /// Tech Lead's decision.
    ///
    /// Clones `source`'s victim-vehicle evidence and incident details
    /// into a brand-new case with a freshly assigned serial number,
    /// ready for a different suspect vehicle. See
    /// `ForensicCase.duplicatedForNewSuspect` for exactly what is
    /// carried over and (more importantly) what is cleared.
    ///
    /// Also records a `.caseDuplicated` entry on the SOURCE case and
    /// re-saves it, so the link is discoverable from both ends -- a
    /// reader of the original case can see its victim evidence was
    /// reused, not just a reader of the clone. Without this the reuse is
    /// only visible from whichever case you happen to open second.
    ///
    /// `nextCaseNumber()` reads `cases`, which is `@MainActor` state
    /// bound from `StorageService`; this method is therefore
    /// MainActor-isolated like the rest of this class, and the serial is
    /// generated before any `await` so two rapid duplications can't race
    /// to the same number.
    func duplicateCase(_ source: ForensicCase, caseName: String) async -> ForensicCase {
        let assignedNumber = nextCaseNumber()
        let trimmedName = caseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let clone = source.duplicatedForNewSuspect(
            caseNumber: assignedNumber,
            caseName: trimmedName
        )
        await storage.save(clone)

        // Back-link on the source case. Done after the clone is safely
        // persisted, and its failure is deliberately non-fatal: if this
        // second save fails the clone still exists and still carries its
        // own `sourceCaseID` + audit entry, so the link is never lost
        // entirely -- only its convenience direction.
        var updatedSource = source
        updatedSource.recordAudit(
            .caseDuplicated,
            detail: "This case's victim vehicle evidence was duplicated into new case \(clone.displayTitle) (\(assignedNumber)) to compare against a different suspect vehicle."
        )
        await storage.save(updatedSource)

        return clone
    }

    /// A sensible prefilled name for a duplicate, so the case list
    /// doesn't fill up with identically-named rows.
    ///
    /// NOTE(AI Developer): counts existing cases already duplicated from
    /// the same source to produce "… — Suspect 2", "… — Suspect 3", and
    /// so on. The source case itself is implicitly "Suspect 1", which is
    /// why the count starts at 2. Uses the source's `displayTitle` as
    /// the base so an unnamed case falls back to its serial number
    /// rather than producing a name that starts with " — Suspect 2".
    func suggestedDuplicateName(for source: ForensicCase) -> String {
        let base = source.caseName.isEmpty ? source.displayTitle : source.caseName
        // Strip any existing "— Suspect N" so duplicating a duplicate
        // doesn't compound into "X — Suspect 2 — Suspect 3".
        let root: String
        if let range = base.range(of: " — Suspect ", options: .backwards),
           Int(base[range.upperBound...].trimmingCharacters(in: .whitespaces)) != nil {
            root = String(base[base.startIndex..<range.lowerBound])
        } else {
            root = base
        }
        let rootID = source.sourceCaseID ?? source.id
        let siblings = cases.filter { $0.id == rootID || $0.sourceCaseID == rootID }.count
        return "\(root) — Suspect \(max(siblings + 1, 2))"
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
