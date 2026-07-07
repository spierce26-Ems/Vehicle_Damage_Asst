// MatchScoreCalculator.swift
// Vehicle Damage Forensic Matcher
// The multi-factor scoring engine. Consumes a fully-populated case
// (victim + suspect vehicle data, photos, LiDAR scans) and produces
// a final `MatchResult` with per-factor breakdown, weighted composite
// score, confidence level, and recommendations.

import Foundation
import UIKit

// MARK: - Match Score Calculator

struct MatchScoreCalculator {

    private let paintAnalyzer = PaintTransferAnalyzer()
    private let heightAnalyzer = HeightAlignmentAnalyzer()
    private let deformationMatcher = DeformationMatcher()

    // MARK: Entry point

    /// Run all 7 factor analyses and combine into a final result.
    func evaluate(case forensicCase: ForensicCase) async -> MatchResult {
        let started = Date()
        guard let suspect = forensicCase.suspectVehicle else {
            return MatchResult(
                compositeScore: 0,
                probabilityRange: "0%",
                confidence: .insufficient,
                recommendations: ["No suspect vehicle data captured."]
            )
        }
        let victim = forensicCase.victimVehicle
        let vZone = victim.primaryDamageZone
        let sZone = suspect.primaryDamageZone

        // Run analyses concurrently where appropriate
        async let paintScore = paintAnalyzer.analyze(
            victim: vZone,
            suspect: sZone,
            victimVehicleColor: victim.colorRGB,
            suspectVehicleColor: suspect.colorRGB)

        async let heightScore = heightAnalyzer.analyze(
            victim: vZone,
            suspect: sZone,
            victimBumperHeight: victim.bumperHeightInches,
            suspectBumperHeight: suspect.bumperHeightInches)

        async let deformScore = deformationMatcher.analyze(
            victimDamageImage: bestDamageImage(in: victim),
            suspectDamageImage: bestDamageImage(in: suspect))

        // Heuristic factors — placeholders that downstream services can replace
        let geometryScore = scoreImpactGeometry(victim: vZone, suspect: sZone)
        let dimensionScore = scoreDamageDimensions(victim: vZone, suspect: sZone)
        let materialScore = scoreMaterialTransfer(victim: vZone, suspect: sZone)
        let temporalScore = scoreTemporalConsistency(case: forensicCase)

        let factors: [FactorScore] = await [
            paintScore,
            heightScore,
            geometryScore,
            deformScore,
            dimensionScore,
            materialScore,
            temporalScore
        ]

        let weighted = factors.reduce(0.0) { acc, fs in
            acc + (fs.rawScore * fs.weight * fs.dataQuality.penaltyMultiplier)
        }
        let composite = max(0, min(100, weighted))

        let usableFactorCount = factors.filter { $0.dataQuality != .unavailable }.count
        let confidence = ConfidenceLevel.from(score: composite, factorCount: usableFactorCount)
        let probability = probabilityRangeString(for: composite, confidence: confidence)

        let elapsed = Date().timeIntervalSince(started)
        return MatchResult(
            compositeScore: composite,
            probabilityRange: probability,
            confidence: confidence,
            factors: factors,
            recommendations: buildRecommendations(factors: factors, composite: composite),
            processingTimeSeconds: elapsed
        )
    }

    // MARK: Heuristic factor implementations

    private func scoreImpactGeometry(victim: DamageZone?, suspect: DamageZone?) -> FactorScore {
        guard let v = victim, let s = suspect,
              let vAng = v.impactAngleDegrees, let sAng = s.impactAngleDegrees else {
            return FactorScore(factor: .impactGeometry, rawScore: 0, dataQuality: .unavailable,
                               notes: "Impact angles not captured (LiDAR required)")
        }
        // Reciprocal angles should sum to ~180°.
        let delta = abs(180 - (vAng + sAng))
        let raw = max(0, 100 - delta * 5)
        return FactorScore(factor: .impactGeometry, rawScore: raw, dataQuality: .full,
                           notes: String(format: "Reciprocity Δ=%.1f° → %.0f", delta, raw))
    }

    private func scoreDamageDimensions(victim: DamageZone?, suspect: DamageZone?) -> FactorScore {
        guard let v = victim, let s = suspect else {
            return FactorScore(factor: .damageDimensions, rawScore: 0, dataQuality: .unavailable,
                               notes: "Damage zones not measured")
        }
        let widthDiff = abs(v.widthMM - s.widthMM)
        let heightDiff = abs(v.heightMM - s.heightMM)
        // 50mm tolerance on each axis is generous but defensible.
        let wScore = max(0, 100 - widthDiff)
        let hScore = max(0, 100 - heightDiff)
        let raw = (wScore + hScore) / 2
        return FactorScore(factor: .damageDimensions, rawScore: raw, dataQuality: .full,
                           notes: String(format: "Δw=%.0fmm, Δh=%.0fmm", widthDiff, heightDiff))
    }

    private func scoreMaterialTransfer(victim: DamageZone?, suspect: DamageZone?) -> FactorScore {
        guard let v = victim?.paintAnalysis, let s = suspect?.paintAnalysis else {
            return FactorScore(factor: .materialTransfer, rawScore: 0, dataQuality: .unavailable,
                               notes: "No paint analysis")
        }
        var raw: Double = 0
        if v.hasRubberTransfer || s.hasRubberTransfer { raw += 50 }
        if v.hasPlasticFragment || s.hasPlasticFragment { raw += 50 }
        return FactorScore(factor: .materialTransfer, rawScore: raw, dataQuality: .full,
                           notes: "Rubber:\(v.hasRubberTransfer || s.hasRubberTransfer) Plastic:\(v.hasPlasticFragment || s.hasPlasticFragment)")
    }

    private func scoreTemporalConsistency(case forensicCase: ForensicCase) -> FactorScore {
        guard let inc = forensicCase.incidentDate else {
            return FactorScore(factor: .temporalConsistency, rawScore: 60, dataQuality: .partial,
                               notes: "Incident date unspecified — neutral score applied")
        }
        let allPhotos = forensicCase.victimVehicle.photos
            + (forensicCase.suspectVehicle?.photos ?? [])
        guard let earliest = allPhotos.map(\.captureDate).min() else {
            return FactorScore(factor: .temporalConsistency, rawScore: 0, dataQuality: .unavailable,
                               notes: "No photos to compare to incident date")
        }
        let hours = abs(earliest.timeIntervalSince(inc)) / 3600
        // Within 24h → 100, decay to 0 at 30 days.
        let raw = max(0, 100 - (hours / (24 * 30)) * 100)
        return FactorScore(factor: .temporalConsistency, rawScore: raw, dataQuality: .full,
                           notes: String(format: "%.1fh between incident and first photo", hours))
    }

    // MARK: Helpers

    private func bestDamageImage(in vehicle: Vehicle) -> UIImage? {
        let candidates = vehicle.photos
            .filter { $0.photoType == .closeupDamage || $0.photoType == .paintTransfer }
            .sorted { $0.qualityScore > $1.qualityScore }
        guard let data = candidates.first?.imageData else { return nil }
        return UIImage(data: data)
    }

    private func probabilityRangeString(for score: Double, confidence: ConfidenceLevel) -> String {
        let band: Double
        switch confidence {
        case .veryHigh: band = 3
        case .high:     band = 5
        case .medium:   band = 8
        case .low:      band = 12
        case .insufficient: band = 20
        }
        let lower = max(0, Int(score - band))
        let upper = min(100, Int(score + band))
        return "\(lower)-\(upper)%"
    }

    private func buildRecommendations(factors: [FactorScore], composite: Double) -> [String] {
        var recs: [String] = []
        if composite >= 90 {
            recs.append("Sufficient evidence for criminal referral.")
        } else if composite >= 75 {
            recs.append("Pursue civil claim; corroborate with witness statements.")
        } else if composite >= 60 {
            recs.append("Evidence is suggestive; collect additional photos & LiDAR data.")
        } else {
            recs.append("Insufficient match for legal proceedings without additional evidence.")
        }
        for f in factors where f.dataQuality == .unavailable {
            recs.append("Capture \(f.factor.displayName.lowercased()) data to improve confidence.")
        }
        return recs
    }
}
