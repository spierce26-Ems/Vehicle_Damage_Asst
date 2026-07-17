// MatchResult.swift
// Vehicle Damage Investigation Assistant
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

    /// NOTE(AI Developer), added 2026-07 as part of the Scar-Direction
    /// Consistency feature. Per Sean's explicit decision, this runs as a
    /// SECOND, INDEPENDENT check alongside the existing Impact Geometry
    /// factor -- NOT a replacement, and NOT blended into `compositeScore`/
    /// `factors` (that would require rebalancing the 7 factor weights,
    /// which sum to exactly 1.0 -- see `ForensicFactor.weight` -- and would
    /// undercut Sean's framing of "a case can show both, and you can see
    /// if they agree or conflict"). Kept as its own field entirely outside
    /// the weighted-factor system for that reason. `nil` only for
    /// `MatchResult`s produced before this feature existed (backward
    /// compat) or the no-suspect-vehicle early-return case in
    /// `MatchScoreCalculator.evaluate()`.
    var scarDirectionCheck: ScarDirectionCheck?

    /// NOTE(AI Developer), added 2026-07 implementing Sean's explicit hard
    /// exclusion rule ("a formula like if height doesn't match AND scars
    /// don't align then remove"). `nil` means no exclusion is being
    /// recommended by this rule. Non-nil is a human-readable explanation
    /// of why BOTH conditions (Height Alignment mismatch AND
    /// Scar-Direction Consistency conflict) were met -- see
    /// `MatchScoreCalculator.evaluate()`'s exclusion-rule computation for
    /// the exact thresholds. Deliberately a separate flag rather than
    /// forcing `compositeScore` to 0 or hiding the rest of the
    /// breakdown -- an investigator should still be able to see every
    /// factor's evidence even when this rule fires; this is a strong
    /// negative signal layered on top, not a data-hiding mechanism.
    var suspectExclusionReason: String?

    // MARK: Init

    init(
        analysisID: UUID = UUID(),
        compositeScore: Double,
        scoreRangeLabel: String,
        confidence: ConfidenceLevel,
        factors: [FactorScore] = [],
        recommendations: [String] = [],
        analysisDate: Date = Date(),
        processingTimeSeconds: Double = 0,
        scarDirectionCheck: ScarDirectionCheck? = nil,
        suspectExclusionReason: String? = nil
    ) {
        self.analysisID = analysisID
        self.compositeScore = compositeScore
        self.scoreRangeLabel = scoreRangeLabel
        self.confidence = confidence
        self.factors = factors
        self.recommendations = recommendations
        self.analysisDate = analysisDate
        self.processingTimeSeconds = processingTimeSeconds
        self.scarDirectionCheck = scarDirectionCheck
        self.suspectExclusionReason = suspectExclusionReason
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
        // NOTE(AI Developer): decodeIfPresent so any MatchResult JSON
        // persisted before the Scar-Direction Consistency feature existed
        // still loads correctly (both fields simply come back nil, which
        // is exactly the "not part of this old analysis" backward-compat
        // behavior we want -- never treated as a negative result).
        scarDirectionCheck = try c.decodeIfPresent(ScarDirectionCheck.self, forKey: .scarDirectionCheck)
        suspectExclusionReason = try c.decodeIfPresent(String.self, forKey: .suspectExclusionReason)
    }

    private enum CodingKeys: String, CodingKey {
        case analysisID, compositeScore, scoreRangeLabel, confidence, factors,
             recommendations, analysisDate, processingTimeSeconds,
             scarDirectionCheck, suspectExclusionReason
        case legacyProbabilityRange = "probabilityRange"
    }

    /// NOTE(AI Developer): Xcode 26.6 build caught this (real compiler
    /// error, not a static guess): defining a custom `init(from:)` makes
    /// Swift require a matching hand-written `encode(to:)` too --
    /// auto-synthesis of `Encodable` only kicks in when every
    /// `CodingKeys` case maps to a real stored property, and
    /// `legacyProbabilityRange` doesn't (it exists solely to *read* the
    /// old `probabilityRange` key during decode; we deliberately never
    /// want to write it back out). Hand-written encode below intentionally
    /// omits `legacyProbabilityRange` -- every MatchResult we persist from
    /// now on is written under the current `scoreRangeLabel` key only.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(analysisID, forKey: .analysisID)
        try c.encode(compositeScore, forKey: .compositeScore)
        try c.encode(scoreRangeLabel, forKey: .scoreRangeLabel)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(factors, forKey: .factors)
        try c.encode(recommendations, forKey: .recommendations)
        try c.encode(analysisDate, forKey: .analysisDate)
        try c.encode(processingTimeSeconds, forKey: .processingTimeSeconds)
        try c.encodeIfPresent(scarDirectionCheck, forKey: .scarDirectionCheck)
        try c.encodeIfPresent(suspectExclusionReason, forKey: .suspectExclusionReason)
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

// MARK: - Scar Direction Check

/// NOTE(AI Developer), added 2026-07 for the Scar-Direction Consistency
/// feature. This is Sean's SECOND, INDEPENDENT check on top of the
/// existing Impact Geometry factor -- it exists specifically to close a
/// blind spot in Impact Geometry's self-reported/compass direction-of-
/// travel input, which cannot distinguish a vehicle reversing into a
/// parking space from pulling forward out of one (both produce identical
/// damage locations but opposite, both-"valid" directions of travel,
/// which breaks Impact Geometry's sum-to-180° reciprocity check in
/// exactly the most common hit-and-run scenario: parking lots).
///
/// The math driving this check reuses the EXACT SAME reciprocity formula
/// as Impact Geometry (`bearing = (noseHeading + relativeAngle) % 360`,
/// then check victim+suspect bearings sum to ~180°) -- see
/// `Vehicle.scarTravelBearingDegrees` -- confirming Sean's explicit
/// question that scar direction "should line up perfectly with height
/// and basically be the inverse for both vehicles." The only difference
/// is the INPUT: instead of trusting the self-reported compass heading
/// as-is, it corrects that heading using the physically-observed scar
/// taper direction (which end of the scrape has denser transferred
/// paint -- see `ColorAnalysis.detectScarTaper`), which cannot be fooled
/// by a reversing-vs-forward ambiguity the way a self-report can.
///
/// Per Sean's decision, a missing/inconclusive scar on either vehicle
/// must NEVER be treated as a negative result -- it simply makes this
/// check `.notDeterminable`, leaving the other factors (including the
/// original Impact Geometry factor) to decide on their own.
struct ScarDirectionCheck: Codable, Equatable {
    enum Status: String, Codable {
        /// One or both vehicles lack a recorded scar direction (or lack
        /// the impact-profile data the reciprocity math also needs).
        /// Never scored as a negative -- just absent.
        case notDeterminable = "not_determinable"
        /// Scar-corrected bearings reciprocate to ~180° within tolerance
        /// -- i.e. consistent with the two vehicles having actually
        /// collided at the marked locations, given the true (scar-
        /// verified, not self-reported) directions of travel.
        case consistent = "consistent"
        /// Scar-corrected bearings do NOT reciprocate -- a red flag,
        /// especially in combination with a Height Alignment mismatch
        /// (see `MatchResult.suspectExclusionReason`).
        case inconsistent = "inconsistent"
    }

    var status: Status

    /// Scar-corrected absolute compass bearing of the impact point for
    /// each vehicle (see `Vehicle.scarTravelBearingDegrees`). `nil` when
    /// that vehicle's check is not determinable.
    var victimScarBearingDegrees: Double? = nil
    var suspectScarBearingDegrees: Double? = nil

    /// Degrees of deviation from the ideal 180° reciprocity sum. `nil`
    /// when `status == .notDeterminable`. Mirrors
    /// `MatchScoreCalculator.scoreImpactGeometry`'s `delta` calculation,
    /// just fed scar-corrected bearings instead of self-reported ones.
    var reciprocityDeltaDegrees: Double? = nil

    /// 0-100 display score for UI parity with `FactorScore.rawScore`
    /// (same `max(0, 100 - delta*5)` formula as Impact Geometry) --
    /// **display-only**, deliberately NEVER folded into
    /// `MatchResult.compositeScore` or any `ForensicFactor` weight.
    var rawScore: Double? = nil

    /// Whether this scar-based conclusion agrees with the existing,
    /// self-report-driven Impact Geometry factor's conclusion. `nil` if
    /// either check is not determinable. `false` is exactly the
    /// situation this feature was built to catch: the self-reported
    /// heading LOOKED reciprocal, but the physical scar evidence reveals
    /// it wasn't (or vice versa).
    var agreesWithImpactGeometry: Bool? = nil

    /// Per-vehicle plain-language motion description derived from
    /// `Vehicle.scarSlideDirection`, e.g. "Consistent with this vehicle
    /// moving forward (nose-first) at the moment of contact." /
    /// "...reversing (rear-first)...". `nil` when that vehicle's scar
    /// direction was not recorded.
    var victimMotionDescription: String? = nil
    var suspectMotionDescription: String? = nil

    /// Combined, human-readable "scenario" sentence answering Sean's
    /// explicit request to "run a scenario, recreation, or match the
    /// scars with a high level of probability/confidence one way or
    /// another" -- e.g. "Scar evidence is most consistent with the
    /// suspect vehicle REVERSING out of a parking space, striking the
    /// victim vehicle's [zone] with its [zone]." `nil` when
    /// `status == .notDeterminable`.
    var scenarioNarrative: String? = nil

    /// Analyst/algorithm notes, always populated (including when
    /// `.notDeterminable`, to say why).
    var notes: String = ""

    var isDeterminable: Bool { status != .notDeterminable }

    /// Convenience factory for the "not enough data" case, so call sites
    /// don't have to repeat the all-nil boilerplate.
    static func notDeterminable(notes: String) -> ScarDirectionCheck {
        ScarDirectionCheck(status: .notDeterminable, notes: notes)
    }
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
        case .impactGeometry: return "Impact location + direction-of-travel reciprocity"
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
