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
        let geometryScore = scoreImpactGeometry(victim: victim, suspect: suspect)
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

        // NOTE(AI Developer), 2026-07, per Sean's explicit direction
        // ("please do both option A and B") after the "is the analysis
        // truly comparing the images" investigation: this used to divide
        // by the full fixed 7-factor weighting (`ForensicFactor.weight`,
        // summing to 1.0) regardless of which factors actually had usable
        // data -- so any factor stuck at `dataQuality: .unavailable`
        // (penaltyMultiplier 0.0) simply vanished from the numerator
        // *without* its weight being removed from the denominator. Before
        // this fix, and before Option A (the new impact-location/
        // direction-of-travel feature) gave `impactGeometry` real data,
        // that meant paintTransfer/heightAlignment/damageDimensions/
        // materialTransfer (0.60 combined weight) were *always*
        // unavailable in every real run, capping the maximum possible
        // composite score at ~40/100 even for a flawless match on every
        // factor that *did* have data.
        //
        // Fixed by renormalizing: only factors with `dataQuality !=
        // .unavailable` contribute to the weight total, and each
        // contributing factor's *effective* weight is rescaled so the
        // usable factors' weights still sum to 1.0 among themselves. A
        // perfect score on 100% of the factors that actually have data
        // now reads as 100, not an artificially depressed number that
        // conflates "no evidence for this factor" with "this factor
        // scored zero." `usableFactorCount == 0` (e.g. a fresh case with
        // no data at all) falls back to composite 0 rather than dividing
        // by zero.
        let usableFactors = factors.filter { $0.dataQuality != .unavailable }
        let usableWeightTotal = usableFactors.reduce(0.0) { $0 + $1.weight }
        let composite: Double
        if usableWeightTotal > 0 {
            let weightedSum = usableFactors.reduce(0.0) { acc, fs in
                acc + (fs.rawScore * fs.weight * fs.dataQuality.penaltyMultiplier)
            }
            composite = max(0, min(100, weightedSum / usableWeightTotal))
        } else {
            composite = 0
        }

        let usableFactorCount = usableFactors.count
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

    /// NOTE(AI Developer), rewritten 2026-07 per Sean's request ("should
    /// we identify the location of the damage on each vehicle and always
    /// identify the direction of traveling at impact... to help
    /// correlating data"). This factor used to require
    /// `DamageZone.impactAngleDegrees` on both vehicles -- a field
    /// confirmed via exhaustive grep to never be populated anywhere in
    /// the app (no capture step, no manual-entry UI), which made this
    /// entire 15%-weighted factor permanently `.unavailable` in every
    /// real analysis run. Now derives the same reciprocity check from
    /// `Vehicle.impactBearingDegrees` (tap-to-mark damage location +
    /// direction-of-travel compass heading, combined -- see that
    /// property's doc comment for the geometry derivation), which is
    /// populated by the new REQUIRED `ImpactMarkerView` capture step for
    /// every case going forward.
    ///
    /// Reciprocal absolute bearings should sum to ~180° regardless of
    /// collision type (head-on, rear-end, T-bone, sideswipe) as long as
    /// both vehicles' bearings are derived the same way -- see the worked
    /// examples in `Vehicle.impactBearingDegrees`'s doc comment.
    private func scoreImpactGeometry(victim: Vehicle, suspect: Vehicle) -> FactorScore {
        guard let vBearing = victim.impactBearingDegrees,
              let sBearing = suspect.impactBearingDegrees else {
            return FactorScore(factor: .impactGeometry, rawScore: 0, dataQuality: .unavailable,
                               notes: "Impact location/direction of travel not recorded for one or both vehicles")
        }
        // Reciprocal bearings should sum to ~180° (mod 360).
        let rawSum = (vBearing + sBearing).truncatingRemainder(dividingBy: 360)
        let delta = min(abs(180 - rawSum), abs(180 - rawSum + 360), abs(180 - rawSum - 360))
        let raw = max(0, 100 - delta * 5)
        return FactorScore(factor: .impactGeometry, rawScore: raw, dataQuality: .full,
                           notes: String(format: "Bearings %.0f° / %.0f°, reciprocity Δ=%.1f° → %.0f",
                                         vBearing, sBearing, delta, raw))
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
