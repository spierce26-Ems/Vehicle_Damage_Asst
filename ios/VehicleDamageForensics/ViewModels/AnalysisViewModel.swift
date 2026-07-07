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

    /// NOTE(AI Developer): `storage` defaults to `nil` rather than
    /// `= .shared` directly in the parameter list -- see the identical
    /// note in CaptureViewModel.init for why (Swift 6 strict concurrency:
    /// default-argument expressions are evaluated in a non-isolated
    /// context, but `StorageService.shared` is `@MainActor`-isolated).
    init(forensicCase: ForensicCase, storage: StorageService? = nil) {
        self.forensicCase = forensicCase
        self.storage = storage ?? .shared
        self.matchResult = forensicCase.matchResult
        self.reportURL = forensicCase.reportURL
    }

    // MARK: Public API

    /// Run the full forensic analysis pipeline.
    func runAnalysis() async {
        isRunning = true
        lastError = nil
        let result = await calculator.evaluate(case: forensicCase)
        forensicCase.matchResult = result
        forensicCase.status = .analyzed  // matches Models/Case.swift CaseStatus
        // NOTE(AI Developer): Chain-of-custody entry per Sean's decision to
        // add the audit log (2026-07).
        forensicCase.recordAudit(.analysisRun, detail: String(format: "Composite score: %.1f", result.compositeScore))
        matchResult = result
        await storage.save(forensicCase)
        isRunning = false
    }

    /// Generate a PDF report after analysis is complete.
    func generateReport() {
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
}
