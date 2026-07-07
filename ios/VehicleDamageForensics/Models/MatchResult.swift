// MatchResult.swift
// Vehicle Damage Forensic Matcher
// Match result model — composite score + per-factor breakdown

import Foundation

// MARK: - Match Result

/// The final output of forensic analysis: overall score and 7 sub-factor scores
struct MatchResult: Codable, Equatable {
    let analysisID: UUID
    var compositeScore: Double          // 0-100 weighted average
    var probabilityRange: String        // e.g. "87-93%"
    var confidence: ConfidenceLevel
    var factors: [FactorScore]
    var recommendations: [String]
    var analysisDate: Date
    var processingTimeSeconds: Double

    // MARK: Init

    init(
        analysisID: UUID = UUID(),
        compositeScore: Double,
        probabilityRange: String,
        confidence: ConfidenceLevel,
        factors: [FactorScore] = [],
        recommendations: [String] = [],
        analysisDate: Date = Date(),
        processingTimeSeconds: Double = 0
    ) {
        self.analysisID = analysisID
        self.compositeScore = compositeScore
        self.probabilityRange = probabilityRange
        self.confidence = confidence
        self.factors = factors
        self.recommendations = recommendations
        self.analysisDate = analysisDate
        self.processingTimeSeconds = processingTimeSeconds
    }

    // MARK: Computed

    /// Verdict string suitable for PDF report headers
    var verdictString: String {
        switch compositeScore {
        case 90...: return "HIGHLY PROBABLE MATCH"
        case 75..<90: return "PROBABLE MATCH"
        case 60..<75: return "POSSIBLE MATCH"
        case 40..<60: return "INCONCLUSIVE"
        default: return "UNLIKELY MATCH"
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
}

// MARK: - Confidence Level

enum ConfidenceLevel: String, Codable, CaseIterable, Comparable {
    case insufficient = "insufficient"
    case low = "low"
    case medium = "medium"
    case high = "high"
    case veryHigh = "very_high"

    var displayName: String {
        switch self {
        case .insufficient: return "Insufficient Data"
        case .low: return "Low Confidence"
        case .medium: return "Moderate Confidence"
        case .high: return "High Confidence"
        case .veryHigh: return "Very High Confidence"
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
