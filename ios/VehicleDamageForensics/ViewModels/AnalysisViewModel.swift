// AnalysisViewModel.swift
// Vehicle Damage Investigation Assistant
// Runs the multi-factor matching engine against a case and exposes
// the results to the UI. Also drives PDF report generation.

import Foundation
import Combine

// MARK: - Analysis View Model

@MainActor
final class AnalysisViewModel: ObservableObject {

    // MARK: Published

    @Published var forensicCase: ForensicCase
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var matchResult: MatchResult?
    @Published var reportURL: URL?
    @Published var lastError: String?

    // MARK: Dependencies

    private let calculator = MatchScoreCalculator()
    private let pdfGenerator = PDFReportGenerator()
    private let storage: StorageService
    /// NOTE(AI Developer), added 2026-07 per Sean's monetization decision.
    /// See `PurchaseManager` for full architecture rationale.
    private let purchases: PurchaseManager

    /// NOTE(AI Developer): `storage` defaults to `nil` rather than
    /// `= .shared` directly in the parameter list -- see the identical
    /// note in CaptureViewModel.init for why (Swift 6 strict concurrency:
    /// default-argument expressions are evaluated in a non-isolated
    /// context, but `StorageService.shared` is `@MainActor`-isolated).
    init(forensicCase: ForensicCase, storage: StorageService? = nil, purchases: PurchaseManager? = nil) {
        self.forensicCase = forensicCase
        self.storage = storage ?? .shared
        self.purchases = purchases ?? .shared
        self.matchResult = forensicCase.matchResult
        self.reportURL = forensicCase.reportURL
    }

    // MARK: Public API

    /// Run the full forensic analysis pipeline.
    ///
    /// NOTE(AI Developer), 2026-07: after 3 confirmed real fixes (imported-
    /// photo resize cap, AVFoundation session-lifecycle crash,
    /// `CameraService.capturedPhotos` memory leak) the "Running correlation
    /// analysis" hang STILL recurred for Sean on a fresh pull. New
    /// hypothesis under investigation: `calculator` (`MatchScoreCalculator`)
    /// is a plain, non-actor-isolated `struct`, and `DeformationMatcher
    /// .analyze(...)` inside it (called via `async let`) is itself a
    /// *synchronous* function containing real, blocking work
    /// (`VNImageRequestHandler.perform` contour detection). Under Swift's
    /// concurrency model, a nonisolated async function that never hits an
    /// actor-isolated suspension point of its own can simply continue
    /// running on whatever executor was already active when it was
    /// awaited — which, called directly from this `@MainActor` method, is
    /// the MainActor. That would mean Vision's contour detection runs
    /// inline on the UI thread and blocks it for its full duration,
    /// independent of all three bugs already fixed.
    ///
    /// `Task.detached` here removes the ambiguity entirely by forcing this
    /// work onto the background cooperative thread pool, mirroring the
    /// same pattern already used (and confirmed working) in
    /// `StorageService.save(_:)`/`loadAllCases()`. `calculator` and
    /// `forensicCase` are both plain value types with no reference-type
    /// storage, so capturing them by value across the isolation boundary
    /// is safe (same reasoning already documented on `StorageService
    /// .save(_:)`).
    ///
    /// Also added timestamped `print()` instrumentation bracketing each
    /// stage so that if this recurs again, Sean's Xcode console output
    /// will show exactly which stage (analysis vs. save) — and, inside
    /// `MatchScoreCalculator.evaluate`, exactly which factor — is actually
    /// consuming the "few minutes." Cheap to remove once the real cause is
    /// nailed down; deliberately left visible for now rather than guessing
    /// again without data.
    func runAnalysis() async {
        isRunning = true
        lastError = nil
        let overallStart = Date()
        print("[AnalysisViewModel] runAnalysis() started")

        let result = await Task.detached(priority: .userInitiated) { [calculator, forensicCase] in
            await calculator.evaluate(case: forensicCase)
        }.value

        print("[AnalysisViewModel] calculator.evaluate finished after \(String(format: "%.2f", Date().timeIntervalSince(overallStart)))s")

        forensicCase.matchResult = result
        forensicCase.status = .analyzed  // matches Models/Case.swift CaseStatus
        // NOTE(AI Developer): Chain-of-custody entry per Sean's decision to
        // add the audit log (2026-07).
        forensicCase.recordAudit(.analysisRun, detail: String(format: "Composite score: %.1f", result.compositeScore))
        matchResult = result

        let saveStart = Date()
        await storage.save(forensicCase)
        print("[AnalysisViewModel] storage.save finished after \(String(format: "%.2f", Date().timeIntervalSince(saveStart)))s — total runAnalysis() time \(String(format: "%.2f", Date().timeIntervalSince(overallStart)))s")

        isRunning = false
    }

    /// True once this specific case's full report has been unlocked,
    /// either via a purchased case credit or an active Pro subscription
    /// held at the time it was unlocked. See `ForensicCase.isUnlocked`
    /// for why this is stored per-case rather than derived live from
    /// subscription status.
    var isUnlocked: Bool {
        forensicCase.isUnlocked || purchases.hasUnlimitedAccess
    }

    /// Attempts to unlock this case by spending one purchased case
    /// credit. Returns `false` (and spends nothing) if the user has no
    /// credits available -- the caller should present `PaywallView` in
    /// that case so the user can purchase one. Does nothing (returns
    /// `true` immediately) if the case is already unlocked, or if the
    /// user holds an active Pro subscription (no credit needed).
    @discardableResult
    func unlockWithCreditIfAvailable() async -> Bool {
        if isUnlocked { return true }
        guard purchases.consumeCreditForUnlock() else { return false }
        markUnlocked(via: "case credit")
        return true
    }

    /// Marks this case unlocked after a successful `PaywallView` purchase
    /// (subscription or consumable) confirms access. Distinct from
    /// `unlockWithCreditIfAvailable()` because `PaywallView` itself already
    /// drove the purchase/credit-consumption through `PurchaseManager`; by
    /// the time its `onUnlocked` callback fires, access already exists --
    /// this just needs to record that fact against *this* case and persist
    /// it. Idempotent: calling it on an already-unlocked case is a no-op
    /// beyond re-saving (harmless).
    func markUnlockedFromPaywall() {
        markUnlocked(via: purchases.hasUnlimitedAccess ? "Pro subscription" : "case credit")
    }

    private func markUnlocked(via method: String) {
        guard !forensicCase.isUnlocked else { return }
        forensicCase.isUnlocked = true
        forensicCase.recordAudit(.caseUnlocked, detail: "Unlocked via \(method)")
        Task { await storage.save(forensicCase) }
    }

    /// Generate a PDF report after analysis is complete.
    func generateReport() {
        guard isUnlocked else {
            lastError = "Unlock this case's full report before generating a PDF."
            return
        }
        guard forensicCase.matchResult != nil else {
            lastError = "Run analysis before generating a report."
            return
        }
        do {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let url = try pdfGenerator.generate(for: forensicCase, into: docs)
            forensicCase.reportURL = url
            forensicCase.status = .reported
            // NOTE(AI Developer): Chain-of-custody entry per Sean's decision
            // to add the audit log (2026-07).
            forensicCase.recordAudit(.reportGenerated, detail: url.lastPathComponent)
            reportURL = url
            Task { await storage.save(forensicCase) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Apply case-level edits made via `EditCaseSheet` from the Results
    /// screen. NOTE(AI Developer): Added per Sean's decision (2026-07) so
    /// a case can still be corrected/updated (name, address, suspect
    /// vehicle info, etc.) after analysis/reporting — e.g. a witness calls
    /// back with a suspect plate number after the report was already
    /// generated. Does not re-run analysis or invalidate the existing
    /// `matchResult`/`reportURL`; those are separate, explicit actions.
    func applyEdits(_ updated: ForensicCase) async {
        var updated = updated
        updated.recordAudit(.caseEdited)
        forensicCase = updated
        await storage.save(forensicCase)
    }

    // MARK: Computed presentation data

    /// NOTE(AI Developer): Renamed from `verdictText`/`verdictString` per
    /// Sean's decision to keep v1 scoped as an investigative documentation
    /// tool rather than a forensic identification system.
    var correlationLabel: String {
        forensicCase.matchResult?.correlationLabel ?? "Pending Analysis"
    }

    var compositeScore: Double {
        forensicCase.matchResult?.compositeScore ?? 0
    }

    var scoreRangeLabel: String {
        forensicCase.matchResult?.scoreRangeLabel ?? "n/a"
    }

    var topFactors: [FactorScore] {
        guard let factors = forensicCase.matchResult?.factors else { return [] }
        return factors.sorted { $0.weightedScore > $1.weightedScore }
    }

    var recommendations: [String] {
        forensicCase.matchResult?.recommendations ?? []
    }

    /// Standard disclaimer to render alongside every result — see
    /// `MatchResult.disclaimerText` for the full rationale.
    var disclaimerText: String { MatchResult.disclaimerText }

    /// Human-readable list of every shot slot that was explicitly skipped
    /// during capture, across both vehicles.
    ///
    /// NOTE(AI Developer), added 2026-07 per Sean's explicit wording for
    /// how a skipped shot should be surfaced ("Shot X was skipped: not
    /// available") -- rendered by `MatchResultsView.skippedShotsSection`
    /// so the gap in evidence is visible on the results screen, not just
    /// buried in the audit log.
    var skippedShotsSummary: [String] {
        let protocolShots = PhotoType.requiredCaptureProtocol
        func describe(_ vehicle: Vehicle, roleLabel: String) -> [String] {
            vehicle.skippedShotIndices.sorted().compactMap { index in
                guard index < protocolShots.count else { return nil }
                let type = protocolShots[index]
                return "\(roleLabel) — Shot \(index + 1) (\(type.displayName)) was skipped: not available"
            }
        }
        var lines = describe(forensicCase.victimVehicle, roleLabel: "Victim")
        if let suspect = forensicCase.suspectVehicle {
            lines += describe(suspect, roleLabel: "Suspect")
        }
        return lines
    }
}
