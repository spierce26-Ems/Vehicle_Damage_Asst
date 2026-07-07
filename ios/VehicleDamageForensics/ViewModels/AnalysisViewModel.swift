// AnalysisViewModel.swift
// Vehicle Damage Forensic Matcher
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

    init(forensicCase: ForensicCase, storage: StorageService = .shared) {
        self.forensicCase = forensicCase
        self.storage = storage
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
            reportURL = url
            Task { await storage.save(forensicCase) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Computed presentation data

    var verdictText: String {
        forensicCase.matchResult?.verdictString ?? "Pending Analysis"
    }

    var compositeScore: Double {
        forensicCase.matchResult?.compositeScore ?? 0
    }

    var topFactors: [FactorScore] {
        guard let factors = forensicCase.matchResult?.factors else { return [] }
        return factors.sorted { $0.weightedScore > $1.weightedScore }
    }

    var recommendations: [String] {
        forensicCase.matchResult?.recommendations ?? []
    }
}
