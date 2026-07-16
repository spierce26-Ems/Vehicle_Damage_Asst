// MatchScoreCalculator.swift
// Vehicle Damage Investigation Assistant
// The multi-factor scoring engine. Consumes a fully-populated case
// (victim + suspect vehicle data, photos, LiDAR scans) and produces
// a final `MatchResult` with per-factor breakdown, weighted composite
// score, confidence level, and recommendations.

import Foundation
import UIKit
import ImageIO

// MARK: - Match Score Calculator

struct MatchScoreCalculator {

    private let paintAnalyzer = PaintTransferAnalyzer()
    private let heightAnalyzer = HeightAlignmentAnalyzer()
    private let deformationMatcher = DeformationMatcher()

    // MARK: Entry point

    /// Run all 7 factor analyses and combine into a final result.
    ///
    /// NOTE(AI Developer), 2026-07: added timestamped `print()`
    /// instrumentation around the concurrent `async let` factors while
    /// investigating a recurred "Running correlation analysis" hang (see
    /// the matching note on `AnalysisViewModel.runAnalysis()` for the full
    /// hypothesis — the real suspect here is `deformScore`, since
    /// `DeformationMatcher.analyze(...)` is a synchronous function doing
    /// real Vision-framework work). Cheap, temporary, safe to remove once
    /// Sean's console output confirms/refutes which factor is actually
    /// slow.
    func evaluate(case forensicCase: ForensicCase) async -> MatchResult {
        let started = Date()
        func log(_ msg: String) {
            print("[MatchScoreCalculator] +\(String(format: "%.2f", Date().timeIntervalSince(started)))s \(msg)")
        }
        log("evaluate() started")
        guard let suspect = forensicCase.suspectVehicle else {
            return MatchResult(
                compositeScore: 0,
                scoreRangeLabel: "n/a",
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

        log("bestDamageImage lookups + async let dispatch done, awaiting deformScore next")
        async let deformScore = deformationMatcher.analyze(
            victimDamageImage: bestDamageImage(in: victim),
            suspectDamageImage: bestDamageImage(in: suspect))

        // Heuristic factors — placeholders that downstream services can replace
        let geometryScore = scoreImpactGeometry(victim: vZone, suspect: sZone)
        let dimensionScore = scoreDamageDimensions(victim: vZone, suspect: sZone)
        let materialScore = scoreMaterialTransfer(victim: vZone, suspect: sZone)
        let temporalScore = scoreTemporalConsistency(case: forensicCase)
        log("synchronous heuristic factors done, awaiting concurrent factors")

        let resolvedDeformScore = await deformScore
        log("deformScore (Vision contour matching) resolved")
        let resolvedPaintScore = await paintScore
        log("paintScore resolved")
        let resolvedHeightScore = await heightScore
        log("heightScore resolved")

        let factors: [FactorScore] = [
            resolvedPaintScore,
            resolvedHeightScore,
            geometryScore,
            resolvedDeformScore,
            dimensionScore,
            materialScore,
            temporalScore
        ]
        log("all factors resolved")

        let weighted = factors.reduce(0.0) { acc, fs in
            acc + (fs.rawScore * fs.weight * fs.dataQuality.penaltyMultiplier)
        }
        let composite = max(0, min(100, weighted))

        let usableFactorCount = factors.filter { $0.dataQuality != .unavailable }.count
        let confidence = ConfidenceLevel.from(score: composite, factorCount: usableFactorCount)
        let scoreRange = scoreRangeLabelString(for: composite, confidence: confidence)

        let elapsed = Date().timeIntervalSince(started)
        return MatchResult(
            compositeScore: composite,
            scoreRangeLabel: scoreRange,
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

    /// NOTE(AI Developer), 2026-07, added alongside the `Task.detached`
    /// fix in `AnalysisViewModel.runAnalysis()` while continuing to
    /// investigate memory pressure Sean reported ("terminated by the
    /// operating system because it is using too much memory") during
    /// analysis specifically: this used to be
    /// `UIImage(data: candidates.first?.imageData)`, which fully decodes
    /// the photo's original ~12MP JPEG into an uncompressed in-memory
    /// bitmap (12MP RGBA ≈ 48MB) — for BOTH victim and suspect, i.e.
    /// ~96MB just to hand off to `DeformationMatcher`, which then
    /// immediately re-downsamples to 1024px internally via
    /// `VNDetectContoursRequest.maximumImageDimension` anyway. That
    /// intermediate full-size decode was pure waste sitting right at the
    /// peak of the app's memory footprint (right after all 20 photos'
    /// `imageData` are already loaded into `forensicCase` for this
    /// analysis run).
    ///
    /// Now uses `CGImageSourceCreateThumbnailAtIndex` with
    /// `kCGImageSourceCreateThumbnailFromImageAlways` + a
    /// `kCGImageSourceThumbnailMaxPixelSize` cap: this decodes directly
    /// to the target size during JPEG decompression itself (a real
    /// ImageIO capability, not decode-then-resize), so the full-size
    /// bitmap is never materialized at all. Capped at 1024px to match
    /// `DeformationMatcher`'s own `maximumImageDimension` exactly — no
    /// detail is lost since Vision was already going to downsample to
    /// that size regardless.
    private func bestDamageImage(in vehicle: Vehicle) -> CGImage? {
        let candidates = vehicle.photos
            .filter { $0.photoType == .closeupDamage || $0.photoType == .paintTransfer }
            .sorted { $0.qualityScore > $1.qualityScore }
        guard let data = candidates.first?.imageData,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// NOTE(AI Developer): Renamed from `probabilityRangeString` per Sean's
    /// decision — this produces a *score band* (e.g. "84-92", out of 100),
    /// not a statistical probability. The old "%" suffix implied a
    /// calibrated likelihood-of-truth figure that this heuristic scoring
    /// engine cannot support without a validated error-rate study. Dropped
    /// the "%" and widened the label so it reads as a range on the 0-100
    /// composite score scale instead.
    private func scoreRangeLabelString(for score: Double, confidence: ConfidenceLevel) -> String {
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
        return "\(lower)-\(upper)"
    }

    /// NOTE(AI Developer): Rewrote all recommendation strings per Sean's
    /// decision to scope v1 as an investigative documentation/leads tool.
    /// The original text ("Sufficient evidence for criminal referral.",
    /// "Pursue civil claim...") had the app making legal-action judgment
    /// calls it has no basis or business making — that determination
    /// belongs to investigators, insurers, or attorneys reviewing the case,
    /// never to an unvalidated on-device heuristic. Replaced with
    /// investigative next-steps language only; nothing here should ever
    /// read as legal advice or a certification of evidentiary sufficiency.
    private func buildRecommendations(factors: [FactorScore], composite: Double) -> [String] {
        var recs: [String] = []
        if composite >= 90 {
            recs.append("Correlation is strong enough to warrant investigator follow-up. This is not a substitute for accredited forensic laboratory analysis.")
        } else if composite >= 75 {
            recs.append("Correlation is moderate-to-strong. Consider forwarding this documentation to an insurance investigator or accident reconstructionist for further review.")
        } else if composite >= 60 {
            recs.append("Correlation is suggestive but not strong. Collect additional photos and LiDAR data to improve the analysis.")
        } else {
            recs.append("Correlation is weak or inconclusive based on the data captured. Additional evidence is needed before drawing any conclusions.")
        }
        for f in factors where f.dataQuality == .unavailable {
            recs.append("Capture \(f.factor.displayName.lowercased()) data to strengthen this analysis.")
        }
        return recs
    }
}
