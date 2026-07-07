// MatchResult.swift
// Vehicle Damage Forensic Matcher
// Match result model — composite score + per-factor breakdown

import Foundation

// MARK: - Match Result

/// The final output of correlation analysis: overall score and 7 sub-factor scores.
/// NOTE(AI Developer): Per Sean's explicit v1 scope decision (2026-07), this
/// app is "best-in-class investigative documentation + leads tool" — NOT a
/// certified forensic identification system. All user-facing language in
/// this file and its consumers (PDFReportGenerator, MatchResultsView) was
/// rewritten to reflect that: we report a *correlation strength score*
/// between two vehicles' damage evidence, not a forensic "match" verdict or
/// a calibrated statistical probability. See `MatchResult.disclaimerText`
/// for the standard disclaimer that must accompany every rendered result
/// (PDF cover page + results screen, per Sean's decision).
struct MatchResult: Codable, Equatable {
    let analysisID: UUID
    var compositeScore: Double          // 0-100 weighted average
    var scoreRangeLabel: String         // e.g. "87-93" (out of 100) — a score band, NOT a statistical probability
    var confidence: ConfidenceLevel
    var factors: [FactorScore]
    var recommendations: [String]
    var analysisDate: Date
    var processingTimeSeconds: Double

    // MARK: Init

    init(
        analysisID: UUID = UUID(),
        compositeScore: Double,
        scoreRangeLabel: String,
        confidence: ConfidenceLevel,
        factors: [FactorScore] = [],
        recommendations: [String] = [],
        analysisDate: Date = Date(),
        processingTimeSeconds: Double = 0
    ) {
        self.analysisID = analysisID
        self.compositeScore = compositeScore
        self.scoreRangeLabel = scoreRangeLabel
        self.confidence = confidence
        self.factors = factors
        self.recommendations = recommendations
        self.analysisDate = analysisDate
        self.processingTimeSeconds = processingTimeSeconds
    }

    // MARK: Codable (backward-compatible with the old `probabilityRange` key)

    /// NOTE(AI Developer): Custom decode so any case JSON already persisted
    /// under the old field name `probabilityRange` still loads correctly
    /// after this rename, instead of throwing `keyNotFound`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        analysisID = try c.decode(UUID.self, forKey: .analysisID)
        compositeScore = try c.decode(Double.self, forKey: .compositeScore)
        if let renamed = try c.decodeIfPresent(String.self, forKey: .scoreRangeLabel) {
            scoreRangeLabel = renamed
        } else {
            scoreRangeLabel = try c.decodeIfPresent(String.self, forKey: .legacyProbabilityRange) ?? "n/a"
        }
        confidence = try c.decode(ConfidenceLevel.self, forKey: .confidence)
        factors = try c.decodeIfPresent([FactorScore].self, forKey: .factors) ?? []
        recommendations = try c.decodeIfPresent([String].self, forKey: .recommendations) ?? []
        analysisDate = try c.decode(Date.self, forKey: .analysisDate)
        processingTimeSeconds = try c.decodeIfPresent(Double.self, forKey: .processingTimeSeconds) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case analysisID, compositeScore, scoreRangeLabel, confidence, factors,
             recommendations, analysisDate, processingTimeSeconds
        case legacyProbabilityRange = "probabilityRange"
    }

    // MARK: Computed

    /// Correlation-strength label suitable for report headers.
    /// NOTE(AI Developer): Renamed from `verdictString` /
    /// "...MATCH"-style wording per Sean's decision — "MATCH" implies a
    /// forensic identification conclusion (akin to a fingerprint/ballistics
    /// hit), which this tool does not and cannot provide without a
    /// validated, peer-reviewed error rate behind it. "Correlation" framing
    /// is accurate to what the algorithm actually measures: similarity
    /// across weighted photographic/sensor factors.
    var correlationLabel: String {
        switch compositeScore {
        case 90...: return "STRONG CORRELATION"
        case 75..<90: return "MODERATE-STRONG CORRELATION"
        case 60..<75: return "MODERATE CORRELATION"
        case 40..<60: return "INCONCLUSIVE"
        default: return "NO SIGNIFICANT CORRELATION"
        }
    }

    /// Score as 0-1 fraction
    var normalizedScore: Double { compositeScore / 100.0 }

    /// Factor score by type for quick lookup
    func score(for factor: ForensicFactor) -> FactorScore? {
        factors.first { $0.factor == factor }
    }

    var paintScore: Double? { score(for: .paintTransfer)?.rawScore }
    var heightScore: Double? { score(for: .heightAlignment)?.rawScore }

    static func == (lhs: MatchResult, rhs: MatchResult) -> Bool {
        lhs.analysisID == rhs.analysisID
    }

    // MARK: Disclaimer

    /// NOTE(AI Developer): Added per Sean's explicit decision (2026-07) to
    /// keep v1 scoped as "investigative documentation + leads tool" rather
    /// than implying forensic-grade / ballistics-level certainty. This text
    /// must be shown (a) on the PDF cover page in a visually distinct
    /// callout, and (b) on `MatchResultsView` before/alongside the score —
    /// see `PDFReportGenerator.drawCoverPage` and `MatchResultsView.verdictCard`.
    /// Do not shorten or soften this wording without Sean's sign-off; it
    /// exists specifically to avoid overstating what an unvalidated
    /// heuristic scoring algorithm can support.
    static let disclaimerText = """
    This report documents a photographic and sensor-based correlation \
    analysis between two vehicles. It is an investigative aid intended to \
    support further review by investigators, insurers, or forensic \
    professionals — it is NOT a certified forensic identification and has \
    not been validated against a known-match / known-non-match dataset with \
    a peer-reviewed error rate. This report should not be represented as \
    conclusive proof of vehicle involvement in any legal proceeding.
    """
}

// MARK: - Confidence Level

/// NOTE(AI Developer): Kept the Swift type/case names as-is (internal
/// symbols, never shown to users) but changed every user-facing
/// `displayName` string per Sean's decision — "Confidence" implies a
/// validated statistical certainty this algorithm does not have (no
/// known/peer-reviewed error rate). Relabeled as "Correlation Strength" to
/// describe what it actually is: how much of the required data was present
/// and how strongly the weighted factors agreed, not a probability of
/// truth.
enum ConfidenceLevel: String, Codable, CaseIterable, Comparable {
    case insufficient = "insufficient"
    case low = "low"
    case medium = "medium"
    case high = "high"
    case veryHigh = "very_high"

    var displayName: String {
        switch self {
        case .insufficient: return "Insufficient Data"
        case .low: return "Low Correlation Strength"
        case .medium: return "Moderate Correlation Strength"
        case .high: return "High Correlation Strength"
        case .veryHigh: return "Very High Correlation Strength"
        }
    }

    var systemImageName: String {
        switch self {
        case .insufficient: return "exclamationmark.triangle"
        case .low: return "1.circle"
        case .medium: return "2.circle"
        case .high: return "3.circle"
        case .veryHigh: return "checkmark.seal.fill"
        }
    }

    private var sortOrder: Int {
        switch self {
        case .insufficient: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .veryHigh: return 4
        }
    }

    static func < (lhs: ConfidenceLevel, rhs: ConfidenceLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    /// Derive confidence level from composite score
    static func from(score: Double, factorCount: Int) -> ConfidenceLevel {
        guard factorCount >= 3 else { return .insufficient }
        switch score {
        case 90...: return .veryHigh
        case 75..<90: return .high
        case 60..<75: return .medium
        case 40..<60: return .low
        default: return .insufficient
        }
    }
}

// MARK: - Forensic Factor

/// The 7 independent forensic markers used in scoring
enum ForensicFactor: String, Codable, CaseIterable {
    case paintTransfer = "paint_transfer"
    case heightAlignment = "height_alignment"
    case impactGeometry = "impact_geometry"
    case deformationPattern = "deformation_pattern"
    case damageDimensions = "damage_dimensions"
    case materialTransfer = "material_transfer"
    case temporalConsistency = "temporal_consistency"

    /// Relative weight as described in the architecture (must sum to 1.0)
    var weight: Double {
        switch self {
        case .paintTransfer: return 0.30
        case .heightAlignment: return 0.20
        case .impactGeometry: return 0.15
        case .deformationPattern: return 0.15
        case .damageDimensions: return 0.10
        case .materialTransfer: return 0.05
        case .temporalConsistency: return 0.05
        }
    }

    var displayName: String {
        switch self {
        case .paintTransfer: return "Paint Transfer"
        case .heightAlignment: return "Height Alignment"
        case .impactGeometry: return "Impact Geometry"
        case .deformationPattern: return "Deformation Pattern"
        case .damageDimensions: return "Damage Dimensions"
        case .materialTransfer: return "Material Transfer"
        case .temporalConsistency: return "Temporal Consistency"
        }
    }

    var description: String {
        switch self {
        case .paintTransfer: return "CIE ΔE color match + layer analysis"
        case .heightAlignment: return "Bumper-to-ground height comparison"
        case .impactGeometry: return "LiDAR-derived impact angle reciprocity"
        case .deformationPattern: return "3D contour shape signature matching"
        case .damageDimensions: return "Physical size of damage zones"
        case .materialTransfer: return "Rubber, plastic, glass transfer"
        case .temporalConsistency: return "Damage age and timeline verification"
        }
    }
}

// MARK: - Factor Score

/// Individual score for one of the 7 forensic factors
struct FactorScore: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var factor: ForensicFactor
    var rawScore: Double           // 0-100 before weighting
    var weightedScore: Double      // rawScore × weight
    var weight: Double             // copy of factor.weight at calculation time
    var dataQuality: DataQuality   // how much data was available
    var notes: String              // analyst or algorithm notes

    init(
        factor: ForensicFactor,
        rawScore: Double,
        dataQuality: DataQuality = .full,
        notes: String = ""
    ) {
        self.factor = factor
        self.rawScore = max(0, min(100, rawScore))
        self.weight = factor.weight
        self.weightedScore = self.rawScore * factor.weight
        self.dataQuality = dataQuality
        self.notes = notes
    }

    /// Display string e.g. "87.2 / 100"
    var scoreDisplay: String { String(format: "%.1f / 100", rawScore) }
    var weightedDisplay: String { String(format: "%.1f", weightedScore) }
}

// MARK: - Data Quality

enum DataQuality: String, Codable {
    case full       // all required data present
    case partial    // some data missing but calculable
    case estimated  // inferred, lower confidence
    case unavailable // could not be calculated

    var penaltyMultiplier: Double {
        switch self {
        case .full: return 1.0
        case .partial: return 0.85
        case .estimated: return 0.70
        case .unavailable: return 0.0
        }
    }

    var displayName: String {
        switch self {
        case .full: return "Full Data"
        case .partial: return "Partial"
        case .estimated: return "Estimated"
        case .unavailable: return "N/A"
        }
    }
}
