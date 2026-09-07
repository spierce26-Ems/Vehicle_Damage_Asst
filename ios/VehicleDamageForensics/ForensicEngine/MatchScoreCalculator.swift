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
    /// hypothesis — the real suspect here is `deformResult`, since
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
                recommendations: ["No suspect vehicle data captured."],
                algorithmVersion: .current
            )
        }
        let victim = forensicCase.victimVehicle
        let vZone = victim.primaryDamageZone
        let sZone = suspect.primaryDamageZone

        // Run analyses concurrently where appropriate
        //
        // NOTE(AI Developer), updated 2026-07 as part of the paint-color
        // reference-normalization fix: dropped the `victimVehicleColor`/
        // `suspectVehicleColor` arguments (`Vehicle.colorRGB`, which
        // nothing in the app ever populated) now that
        // `PaintTransferAnalyzer.analyze()` compares each vehicle's own
        // same-photo-sampled `PaintAnalysis` against the other's instead
        // of a "nominal vehicle color" — see that method's updated doc
        // comment for the full rationale.
        async let paintScore = paintAnalyzer.analyze(
            victim: vZone,
            suspect: sZone)

        // NOTE(AI Developer), added 2026-07 per Sean's request ("wire LiDAR
        // data into the Height Alignment factor... we need the use of
        // Lidar as an extra tool"). `effectiveBumperHeightInches` prefers
        // `lidarMeasuredHeightInches` (a real measurement taken from the
        // LiDAR-reconstructed mesh via LiDARScanView's tap-to-measure step)
        // and falls back to the manually-entered `bumperHeightInches`
        // (which nothing in the app populates today, but is kept as a
        // fallback for a possible future manual-entry UI). Previously this
        // read raw `bumperHeightInches` directly, which was always nil —
        // Height Alignment (20% weight) was permanently `.unavailable` in
        // every real run.
        async let heightScore = heightAnalyzer.analyze(
            victim: vZone,
            suspect: sZone,
            victimBumperHeight: victim.effectiveBumperHeightInches,
            suspectBumperHeight: suspect.effectiveBumperHeightInches)

        // NOTE(AI Developer), updated 2026-07 for the contour-overlay
        // feature: now looks up `(photoID, image)` pairs via
        // `bestDamagePhotoAndImage` instead of the plain-`CGImage`
        // `bestDamageImage`, so the resulting overlay (below) can record
        // which exact photo it was traced on.
        let victimDamage = bestDamagePhotoAndImage(in: victim)
        let suspectDamage = bestDamagePhotoAndImage(in: suspect)
        log("bestDamageImage lookups + async let dispatch done, awaiting deformResult next")
        async let deformResult = deformationMatcher.analyze(
            victimDamageImage: victimDamage?.image,
            suspectDamageImage: suspectDamage?.image)

        // Heuristic factors — placeholders that downstream services can replace
        let geometryScore = scoreImpactGeometry(victim: victim, suspect: suspect)
        let dimensionScore = scoreDamageDimensions(victim: vZone, suspect: sZone)
        let materialScore = scoreMaterialTransfer(victim: vZone, suspect: sZone)
        let temporalScore = scoreTemporalConsistency(case: forensicCase)

        // NOTE(AI Developer), added 2026-07 for the Scar-Direction
        // Consistency feature -- Sean's explicit "second, independent
        // check" alongside Impact Geometry (see
        // `ScarDirectionCheck`'s doc comment and `scoreScarDirectionConsistency`
        // below for the full design). Deliberately computed here but
        // NEVER added to the `factors` array below -- it must not
        // participate in the weighted composite score.
        let scarCheck = scoreScarDirectionConsistency(victim: victim, suspect: suspect)
        // NOTE(AI Developer), added 2026-07 for the fingerprint-style
        // Scar Matching feature -- a THIRD, INDEPENDENT scar-based
        // signal (see `MatchResult.scarFingerprintMatch`'s doc comment).
        // Purely a read of already-extracted `ScarMinutia` (computed at
        // capture time by `CaptureViewModel.recordScarDirection` --
        // never re-runs Vision/pixel sampling here), so this is cheap
        // enough to compute synchronously alongside the other heuristic
        // factors above.
        let scarFingerprintMatch = ScarFingerprintMatcher.match(
            victim: victim.scarPhoto?.scarMinutiae ?? [],
            suspect: suspect.scarPhoto?.scarMinutiae ?? []
        )
        // NOTE(AI Developer), added 2026-07 for the tool-mark/striation
        // matching feature (Sean: "we are basically looking for tooling
        // marks on each vehicle from the other") -- a FOURTH,
        // INDEPENDENT scar-based signal alongside `scarCheck`/
        // `scarFingerprintMatch` above (see `MatchResult
        // .toolMarkComparison`'s doc comment). Same "purely a read of
        // already-extracted data, never re-runs pixel sampling here"
        // property as `scarFingerprintMatch` -- `toolMarkStriationProfile`
        // was computed once at capture time by `CaptureViewModel
        // .recordScarDirection`, so this comparison is cheap enough to
        // run synchronously right alongside it.
        let toolMarkComparison = ToolMarkMatcher.compare(
            victim: victim.scarPhoto?.toolMarkStriationProfile ?? .empty(),
            suspect: suspect.scarPhoto?.toolMarkStriationProfile ?? .empty()
        )
        log("synchronous heuristic factors done, awaiting concurrent factors")

        let resolvedDeform = await deformResult
        log("deformResult (Vision contour matching) resolved")
        let resolvedPaintScore = await paintScore
        log("paintScore resolved")
        let resolvedHeightScore = await heightScore
        log("heightScore resolved")

        let factors: [FactorScore] = [
            resolvedPaintScore,
            resolvedHeightScore,
            geometryScore,
            resolvedDeform.factorScore,
            dimensionScore,
            materialScore,
            temporalScore
        ]
        log("all factors resolved")

        // NOTE(AI Developer), added 2026-07 for the "show analysed
        // results in the PDF" feature (Sean: "we need to show that we
        // did something with the images in the report, not just show
        // the pictures uploaded"). The Vision-detected damage contour
        // boundary was already computed above as a side effect of the
        // Deformation Pattern factor's `VNDetectContoursRequest` call --
        // this just persists it (paired with the exact source photo ID
        // it was traced on) so `PDFReportGenerator` can draw it later
        // WITHOUT ever re-running Vision at PDF-render time (see
        // `AnalysisViewModel.generateReport()`, which calls the PDF
        // generator synchronously -- re-running Vision there would risk
        // exactly the kind of main-thread hang/OOM this file's other
        // NOTEs already describe). `flatMap` ensures we only build an
        // overlay when BOTH a source photo AND extracted contour points
        // exist for that vehicle.
        let victimOverlay: ContourOverlay? = victimDamage.flatMap { damage in
            resolvedDeform.victimContourNormalizedPoints.map {
                ContourOverlay(normalizedPoints: $0, sourcePhotoID: damage.photoID)
            }
        }
        let suspectOverlay: ContourOverlay? = suspectDamage.flatMap { damage in
            resolvedDeform.suspectContourNormalizedPoints.map {
                ContourOverlay(normalizedPoints: $0, sourcePhotoID: damage.photoID)
            }
        }

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

        // NOTE(AI Developer), added 2026-07 implementing Sean's explicit
        // hard exclusion rule ("if height doesn't match AND scars don't
        // align then remove [the suspect vehicle]"). BOTH conditions
        // must independently fire:
        //   1. Height Alignment mismatch -- reuses the exact same
        //      `MeasurementHelpers.heightsAlign` boolean check
        //      `HeightAlignmentAnalyzer` itself uses (2.0" default
        //      tolerance), applied to whichever height inputs are
        //      actually available (a LiDAR-measured bumper height is
        //      preferred as the better estimate of WHERE the damage is,
        //      so it's checked first; falls back to zone center height
        //      only if bumper height wasn't captured for either
        //      vehicle). Preference is not precision, and the two come
        //      apart here: the raycast pair locates the damage point
        //      better than a tape reading of a nominal bumper line and
        //      is the WORSE basis for a binary threshold crossing,
        //      because its difference carries sigma ~1.7" (see
        //      `Vehicle.HeightSource`). That is why the standalone
        //      rule-out below consults `ruleOutCapable` instead of just
        //      using this value, and why anyone "simplifying" the
        //      ordering reintroduces the false-exclusion path -- it
        //      would look like cleanup. If NEITHER height
        //      input is available for this pair, the height condition
        //      cannot be evaluated at all, so the exclusion rule does
        //      not fire (a missing measurement must never be treated as
        //      a "mismatch" -- same non-punitive principle as
        //      `DataQuality.unavailable` elsewhere in this engine).
        //   2. Scar-Direction Consistency conflict -- `scarCheck.status
        //      == .inconsistent` (which itself already requires BOTH
        //      vehicles to have a determinable scar direction -- see
        //      `scoreScarDirectionConsistency` below).
        // Deliberately does NOT zero `composite` or hide `factors` --
        // see `MatchResult.suspectExclusionReason`'s doc comment for why.
        let suspectExclusionReason = evaluateExclusionRule(
            victim: victim,
            suspect: suspect,
            scarCheck: scarCheck
        )

        let elapsed = Date().timeIntervalSince(started)
        return MatchResult(
            compositeScore: composite,
            scoreRangeLabel: scoreRange,
            confidence: confidence,
            factors: factors,
            recommendations: buildRecommendations(factors: factors, composite: composite, exclusionReason: suspectExclusionReason),
            processingTimeSeconds: elapsed,
            scarDirectionCheck: scarCheck,
            suspectExclusionReason: suspectExclusionReason,
            victimContourOverlay: victimOverlay,
            suspectContourOverlay: suspectOverlay,
            scarFingerprintMatch: scarFingerprintMatch,
            toolMarkComparison: toolMarkComparison,
            // NOTE(AI Developer), added 2026-09: stamped here, at the
            // one place a MatchResult is actually produced, so no
            // analysis path can emit an unstamped result.
            algorithmVersion: .current
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

    /// NOTE(AI Developer), added 2026-07 for the Scar-Direction
    /// Consistency feature -- Sean's SECOND, INDEPENDENT check alongside
    /// `scoreImpactGeometry` above (never blended into it or into
    /// `factors`/`compositeScore` -- see `ScarDirectionCheck`'s doc
    /// comment for the full rationale). Mirrors
    /// `scoreImpactGeometry`'s sum-to-180° reciprocity math exactly,
    /// substituting `Vehicle.scarTravelBearingDegrees` (scar-taper-
    /// corrected) for `Vehicle.impactBearingDegrees` (self-reported) --
    /// confirming Sean's explicit question that this "should be a
    /// perfect match... basically be the inverse for both vehicles."
    ///
    /// Per Sean's explicit no-scar-fallback decision, returns
    /// `.notDeterminable` (never a negative result) whenever either
    /// vehicle lacks a resolvable `scarTravelBearingDegrees` -- i.e. no
    /// scar line was marked, the taper sample was inconclusive, or the
    /// underlying impact-profile inputs that formula also needs are
    /// missing.
    ///
    /// Also builds the plain-language `scenarioNarrative` Sean explicitly
    /// requested ("run a scenario, recreation, or match the scars with a
    /// high level of probability/confidence one way or another") --
    /// naming which specific maneuver (forward vs. reversing) each
    /// vehicle's scar evidence points to, not just a raw score.
    private func scoreScarDirectionConsistency(victim: Vehicle, suspect: Vehicle) -> ScarDirectionCheck {
        func motionDescription(for vehicle: Vehicle) -> String? {
            guard let slide = vehicle.scarSlideDirection else { return nil }
            switch slide {
            case .towardFront:
                return "Scar evidence is consistent with this vehicle moving FORWARD (nose-first) at the moment of contact."
            case .towardRear:
                return "Scar evidence is consistent with this vehicle REVERSING (rear-first) at the moment of contact."
            }
        }
        let victimMotion = motionDescription(for: victim)
        let suspectMotion = motionDescription(for: suspect)

        guard let vBearing = victim.scarTravelBearingDegrees,
              let sBearing = suspect.scarTravelBearingDegrees else {
            return ScarDirectionCheck(
                status: .notDeterminable,
                victimMotionDescription: victimMotion,
                suspectMotionDescription: suspectMotion,
                notes: "Scar-direction taper not marked/conclusive for one or both vehicles — Impact Geometry and the other 6 factors are unaffected."
            )
        }

        let rawSum = (vBearing + sBearing).truncatingRemainder(dividingBy: 360)
        let delta = min(abs(180 - rawSum), abs(180 - rawSum + 360), abs(180 - rawSum - 360))
        let raw = max(0, 100 - delta * 5)
        // Same reciprocity tolerance Sean's hard exclusion rule checks
        // against below (`scarMismatchThresholdDegrees`).
        let status: ScarDirectionCheck.Status = delta <= Self.scarMismatchThresholdDegrees ? .consistent : .inconsistent

        // Cross-check against Impact Geometry's OWN (self-report-driven)
        // reciprocity delta -- recomputed directly from
        // `impactBearingDegrees` here (same tiny calculation
        // `scoreImpactGeometry` does) rather than threading that
        // function's result through as a parameter, so this function's
        // signature stays focused on just the two vehicles like every
        // other `score*` function in this file. `nil` (no comparison
        // possible) if Impact Geometry itself isn't determinable.
        var agrees: Bool? = nil
        if let vGeoBearing = victim.impactBearingDegrees, let sGeoBearing = suspect.impactBearingDegrees {
            let geoRawSum = (vGeoBearing + sGeoBearing).truncatingRemainder(dividingBy: 360)
            let geoDelta = min(abs(180 - geoRawSum), abs(180 - geoRawSum + 360), abs(180 - geoRawSum - 360))
            let geometryConsistent = geoDelta <= Self.scarMismatchThresholdDegrees
            agrees = (status == .consistent) == geometryConsistent
        }

        let scenario = scarScenarioNarrative(
            victim: victim, suspect: suspect,
            status: status, delta: delta
        )

        return ScarDirectionCheck(
            status: status,
            victimScarBearingDegrees: vBearing,
            suspectScarBearingDegrees: sBearing,
            reciprocityDeltaDegrees: delta,
            rawScore: raw,
            agreesWithImpactGeometry: agrees,
            victimMotionDescription: victimMotion,
            suspectMotionDescription: suspectMotion,
            scenarioNarrative: scenario,
            notes: String(format: "Scar-corrected bearings %.0f° / %.0f°, reciprocity Δ=%.1f° → %.0f",
                          vBearing, sBearing, delta, raw)
        )
    }

    /// Degrees of reciprocity deviation tolerated before Scar-Direction
    /// Consistency is called `.inconsistent` -- kept as its own named
    /// constant (rather than a magic number inline) since Sean's hard
    /// exclusion rule (`evaluateExclusionRule`) checks against this same
    /// threshold. 15° is intentionally looser than a "perfect match"
    /// would require (0°) to allow for real-world tap-placement and
    /// compass-heading imprecision, while still catching a genuinely
    /// contradictory (e.g. 90°+ off) reciprocity failure.
    private static let scarMismatchThresholdDegrees: Double = 15

    /// NOTE(AI Developer), added 2026-07 implementing Sean's explicit
    /// hard exclusion rule ("if height doesn't match AND scars don't
    /// align then remove [the suspect vehicle]"). Fires only when BOTH
    /// conditions hold:
    ///   1. A real height mismatch — checked via
    ///      `MeasurementHelpers.heightsAlign`, preferring
    ///      `Vehicle.effectiveBumperHeightInches` (LiDAR-measured when
    ///      available) and falling back to `DamageZone.centerHeightInches`
    ///      only when bumper height wasn't captured for either vehicle.
    ///      If NEITHER input is available, the height condition cannot
    ///      be evaluated, and the rule does not fire (a missing
    ///      measurement is never treated as a mismatch).
    ///   2. `scarCheck.status == .inconsistent` (already requires both
    ///      vehicles to have a determinable scar direction).
    /// Returns `nil` (no exclusion recommended) otherwise.
    private func evaluateExclusionRule(
        victim: Vehicle,
        suspect: Vehicle,
        scarCheck: ScarDirectionCheck
    ) -> String? {
        // Resolve the best available height pair once, for both rules
        // below. Preference order and the never-treat-missing-as-mismatch
        // principle are unchanged from the original implementation.
        // NOTE(AI Developer), 2026-09-06 (task #14): now carries the
        // measurement's provenance alongside the value, because the
        // standalone rule-out below is only defensible on a source
        // precise enough to support it. `ruleOutCapable` is false for a
        // LiDAR-derived pair (difference sigma ~1.7"), true for a manual
        // measurement (well under 1"). See `Vehicle.HeightSource`.
        let heights: (v: Double, s: Double, note: String, ruleOutCapable: Bool)?
        if let vh = victim.effectiveHeight, let sh = suspect.effectiveHeight {
            heights = (vh.inches, sh.inches,
                       String(format: "bumper heights %.1f\" vs %.1f\"", vh.inches, sh.inches),
                       // Both sides must support a rule-out; the weaker
                       // measurement governs, since a comparison is only
                       // as good as its worse input.
                       vh.source.canSupportStandaloneRuleOut && sh.source.canSupportStandaloneRuleOut)
        } else if let vz = victim.primaryDamageZone, let sz = suspect.primaryDamageZone,
                  vz.hasZoneHeightData, sz.hasZoneHeightData {
            // Damage-zone heights are manually recorded zone geometry,
            // not raycasts, so they carry manual-measurement precision.
            heights = (vz.centerHeightInches, sz.centerHeightInches,
                       String(format: "damage-zone heights %.1f\" vs %.1f\"", vz.centerHeightInches, sz.centerHeightInches),
                       true)
        } else {
            heights = nil
        }

        // NOTE(AI Developer), added 2026-09 (task #10a). RULE 1 --
        // standalone physical rule-out. A height difference above
        // `MeasurementHelpers.heightRuleOutInches` (6", per
        // ALGORITHM_EXPLAINER §2) means these two damage points cannot
        // have contacted each other, whatever every other factor says.
        //
        // This does NOT require a scar conflict, and that is the point of
        // the change. Previously the ONLY path to an exclusion was
        // "height mismatch AND scar conflict", so a physically
        // impossible height difference on a case with no usable scar
        // evidence -- or with scars that happened to agree -- produced no
        // exclusion at all, just a low subscore averaged into a
        // composite that could still read "MODERATE CORRELATION". A
        // geometric impossibility is not a weak signal to be outvoted by
        // paint colour; it stands on its own.
        //
        // Note this fires on the 2-inch-tolerance `heightsAlign`
        // mismatch's much stricter cousin: a 3-inch difference is a poor
        // score but a plausible collision, while a 7-inch difference is
        // not a collision at all.
        // NOTE(AI Developer), 2026-09-06 (task #14): gated on
        // `ruleOutCapable`. Before this gate, a LiDAR-measured pair
        // could trigger a standalone exclusion at a measurement
        // uncertainty of roughly +/-3.3" (95%), so a genuinely 5-inch
        // mismatch -- a plausible collision -- was excluded about 28% of
        // the time. A false exclusion exonerates a vehicle that could
        // have caused the damage, which is the mirror image of the
        // 39/100 defect the rule-out was introduced to fix, and no less
        // serious for pointing the other way.
        if let heights, heights.ruleOutCapable, MeasurementHelpers.heightsRuleOut(heights.v, heights.s) {
            let diff = abs(heights.v - heights.s)
            // NOTE(AI Developer), 2026-09-07 (task #12): the trailing
            // "the full factor breakdown is still shown for reference"
            // clause was removed from this string, and from the other
            // two this function returns, when the free tier began
            // rendering `suspectExclusionReason` above the paywall. The
            // clause narrated the layout the string used to sit in --
            // below an always-visible breakdown -- and the breakdown is
            // now gated while this sentence is not, so it asserted
            // something false to exactly the reader who cannot see it.
            // A string that narrates its own placement cannot be
            // relocated: the move falsifies it while the diff shows no
            // change to the string. The pointer to what IS gated lives
            // in the banner, where it can be conditioned on
            // `isUnlocked`. The graded consequence sentence below stays
            // -- it is this path's finding, not a claim about layout.
            // NOTE(AI Developer), 2026-09-06: this string deliberately
            // does NOT cite "ALGORITHM_EXPLAINER §2", though an earlier
            // draft did. Per PROCESS.md §4.0, a document the app names
            // in report-bound text is pulled inside the copy lock in
            // its entirety -- a citation is a promise the whole
            // destination is as defensible as the passage cited, and a
            // reader who follows it does not stop where we wanted them
            // to. The threshold's provenance belongs in this comment and
            // in the Analysis Provenance page, both of which are
            // reviewable; it does not belong in a sentence an
            // investigator reads, where it adds no information they can
            // act on and commits us to every other line of the
            // destination.
            return String(format:
                "Height Alignment rule-out: %@ differ by %.1f\", more than the %.0f\" maximum at which "
                + "two damage points can physically have contacted each other. "
                + "On height evidence alone this suspect vehicle should be ruled out, independently of every "
                + "other factor below.",
                heights.note, diff, MeasurementHelpers.heightRuleOutInches)
        }

        // NOTE(AI Developer), added 2026-09-06 (task #14). When the
        // measured difference WOULD have ruled out but the measurement
        // is not precise enough to support it, say so explicitly.
        //
        // Silence here would be the exact failure this project has now
        // hit from several directions: an absent verdict asserting the
        // clean case. An investigator who sees no exclusion assumes the
        // heights were compatible, when in fact they differed by more
        // than the physical limit and the app declined to act on a
        // measurement it could not stand behind. Those are opposite
        // findings and must not render identically.
        //
        // Deliberately worded as inconclusive rather than as an
        // exclusion: with a difference sigma of roughly 1.7", a measured
        // 7" difference genuinely does not distinguish "impossible
        // collision" from "plausible collision, measured imprecisely".
        if let heights, heights.ruleOutCapable == false,
           MeasurementHelpers.heightsRuleOut(heights.v, heights.s) {
            let diff = abs(heights.v - heights.s)
            return String(format:
                "Height Alignment inconclusive: %@ differ by %.1f\", which exceeds the %.0f\" physical limit "
                + "— but this height came from a LiDAR scan measurement, whose uncertainty is too large to "
                + "support ruling a vehicle out on its own. A difference this size may be a genuine "
                + "impossibility or a measurement artefact, and these photographs cannot tell them apart. "
                + "Re-measure both heights with a tape measure to resolve it; a manual measurement is precise "
                + "enough to support an exclusion.",
                heights.note, diff, MeasurementHelpers.heightRuleOutInches)
        }

        // RULE 2 -- Sean's original combined rule: a height mismatch that
        // is NOT severe enough to rule out on its own, plus a
        // scar-direction conflict. Unchanged in behaviour; it now runs
        // only for the sub-rule-out band, since anything above the
        // rule-out threshold already returned above.
        guard scarCheck.status == .inconsistent else { return nil }
        guard let heights, MeasurementHelpers.heightsAlign(heights.v, heights.s) == false else { return nil }

        let deltaText = scarCheck.reciprocityDeltaDegrees.map { String(format: "%.0f°", $0) } ?? "n/a"
        // NOTE(AI Developer), reworded 2026-09-06. This previously read
        // "both conditions of Sean's hard exclusion rule are met" -- a
        // named individual presented, in report-bound text, as the
        // authority for excluding a suspect. Whose rule it is carries no
        // information an investigator can act on, and attributing an
        // exclusion to a person rather than to the evidence invites
        // exactly the question the app should not be raising. The rule
        // itself is what belongs in the sentence; the attribution stays
        // in the doc comment on `evaluateExclusionRule`, where it
        // records design intent for maintainers.
        return "Height Alignment mismatch (\(heights.note)) AND Scar-Direction Consistency conflict (reciprocity Δ=\(deltaText)) — both conditions of the combined exclusion rule are met. Consider ruling out this suspect vehicle pending further review."
    }

    /// Builds the `scenarioNarrative` sentence Sean explicitly requested:
    /// names which specific maneuver (forward vs. reversing) each
    /// vehicle's scar evidence points to, and whether that combination
    /// is or is not consistent with the marked impact locations.
    private func scarScenarioNarrative(
        victim: Vehicle, suspect: Vehicle,
        status: ScarDirectionCheck.Status, delta: Double
    ) -> String {
        func maneuver(_ vehicle: Vehicle) -> String {
            switch vehicle.scarSlideDirection {
            case .towardFront: return "moving forward"
            case .towardRear: return "reversing"
            case .none: return "direction unknown"
            }
        }
        let victimManeuver = maneuver(victim)
        let suspectManeuver = maneuver(suspect)
        switch status {
        case .consistent:
            return "Scar evidence on both vehicles is most consistent with the victim vehicle \(victimManeuver) and the suspect vehicle \(suspectManeuver) at the moment of contact (reciprocity Δ=\(String(format: "%.0f°", delta)))."
        case .inconsistent:
            return "Scar evidence suggests the victim vehicle was \(victimManeuver) and the suspect vehicle was \(suspectManeuver), but these directions do NOT reciprocate with the marked impact locations (reciprocity Δ=\(String(format: "%.0f°", delta))) — this combination is not physically consistent and warrants closer review."
        case .notDeterminable:
            return "Not enough scar evidence to reconstruct a scenario."
        }
    }

    /// NOTE(AI Developer), fixed 2026-07 as an immediate follow-up to the
    /// Paint Transfer factor fix shipped moments earlier in the same
    /// session (Sean: "are there any other features that actually lead to
    /// a dead end right now"). That fix made `CaptureViewModel
    /// .applyPaintAnalysis` the first code anywhere in the app to ever
    /// construct a real (non-nil) `DamageZone`. Before it, `victim`/
    /// `suspect` here were always `nil` and this guard always fired
    /// correctly. Now that a zone can exist (created only to carry
    /// `paintAnalysis`), `widthMM`/`heightMM` on it are still always `0.0`
    /// -- nothing in the app has ever populated real dimension data --
    /// so without the added `hasDimensionData` check below, this would
    /// diff `0` against `0` and report a false PERFECT match (`rawScore:
    /// 100, dataQuality: .full`) instead of the correct `.unavailable`,
    /// fabricating evidence for a measurement that was never taken. See
    /// `DamageZone.hasDimensionData`'s doc comment for the full root cause.
    private func scoreDamageDimensions(victim: DamageZone?, suspect: DamageZone?) -> FactorScore {
        guard let v = victim, let s = suspect,
              v.hasDimensionData, s.hasDimensionData else {
            return FactorScore(factor: .damageDimensions, rawScore: 0, dataQuality: .unavailable,
                               notes: "Damage zones not measured")
        }
        // NOTE(AI Developer), rewritten 2026-09 (task #10b). The previous
        // implementation was:
        //
        //     let wScore = max(0, 100 - widthDiff)   // 1mm = 1 point
        //     let hScore = max(0, 100 - heightDiff)
        //
        // with a comment claiming "50mm tolerance on each axis" that the
        // code did not implement -- at 1mm per point the effective
        // tolerance was 100mm to reach zero, and the comment was simply
        // wrong. It is deleted rather than corrected, because the whole
        // absolute-difference approach is being replaced.
        //
        // The real defect is that absolute millimetres are SCALE-BLIND,
        // and blind in both directions at once:
        //
        //   victim/suspect      absolute form   ratio form
        //   300 vs 400mm wide        0            67    <- nearly-similar damage scored as total mismatch
        //   1200 vs 1250mm          65            96    <- a 4% difference on a long gouge scored as poor
        //   40 vs 60mm              85            67    <- a 50%-larger chip scored as a good match
        //
        // A 50mm discrepancy means something completely different on a
        // 40mm chip than on a 1200mm gouge, and the old form treated them
        // identically. The last row is the dangerous one: it inflates a
        // factor score for two marks that are plainly not the same mark.
        //
        // Replaced with the smaller/larger ratio form used by
        // `_analyze_dimensions` in `ios/reference/forensic_analyzer.py`.
        // Python is not automatically authoritative here (it is an
        // earlier, simpler design and elsewhere it is the weaker
        // implementation), but on this specific factor it is right: a
        // ratio is scale-relative, which is the property this comparison
        // needs, and it lands in 0-100 with no invented constants.
        //
        // `hasDimensionData` already guarantees both values are > 0, so
        // the division cannot be by zero; the `max(_, 0.0001)` is belt
        // and braces against a future caller relaxing that guard.
        func ratioScore(_ a: Double, _ b: Double) -> Double {
            let smaller = min(a, b), larger = max(a, b)
            return (smaller / max(larger, 0.0001)) * 100
        }
        let wScore = ratioScore(v.widthMM, s.widthMM)
        let hScore = ratioScore(v.heightMM, s.heightMM)
        let raw = (wScore + hScore) / 2
        return FactorScore(factor: .damageDimensions, rawScore: raw, dataQuality: .full,
                           notes: String(format: "width %.0f vs %.0fmm (%.0f%%), height %.0f vs %.0fmm (%.0f%%)",
                                         v.widthMM, s.widthMM, wScore,
                                         v.heightMM, s.heightMM, hScore))
    }

    /// NOTE(AI Developer), fixed 2026-07 alongside `scoreDamageDimensions`
    /// above -- same audit, same regression class. `hasRubberTransfer`/
    /// `hasPlasticFragment` have zero real detectors anywhere in the app;
    /// `CaptureViewModel.buildPaintAnalysis` hardcodes both to `false`
    /// (there is no rubber/plastic-fragment detection step in the capture
    /// flow today). Before the Paint Transfer fix, `paintAnalysis` was
    /// always `nil` and this guard always correctly reported
    /// `.unavailable`. Now that it's real/non-nil, without the added
    /// `materialTransferExamined` check below this would read the two
    /// hardcoded `false`s as a confident, examined "no transfer detected"
    /// (`dataQuality: .full`, rawScore 0) instead of the honest "not
    /// examined at all." See `PaintAnalysis.materialTransferExamined`'s
    /// doc comment for the full root cause.
    private func scoreMaterialTransfer(victim: DamageZone?, suspect: DamageZone?) -> FactorScore {
        guard let v = victim?.paintAnalysis, let s = suspect?.paintAnalysis,
              v.materialTransferExamined || s.materialTransferExamined else {
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
    /// NOTE(AI Developer), access widened from `private` to internal
    /// (default) 2026-07 so `PDFReportGenerator`/`AnalysisEvidenceRenderer`
    /// can reuse this EXACT same ImageIO-thumbnail-decode helper for the
    /// new "Analysis Evidence" PDF section (contour overlay on the same
    /// best-damage image `DeformationMatcher` actually scored) instead of
    /// duplicating the decode logic -- keeps there being exactly one
    /// "how do we pick + decode the best damage image without a wasteful
    /// full-size bitmap" implementation in the codebase. No behavior
    /// change.
    func bestDamageImage(in vehicle: Vehicle) -> CGImage? {
        bestDamagePhotoAndImage(in: vehicle)?.image
    }

    /// NOTE(AI Developer), added 2026-07 alongside the contour-overlay
    /// feature: same selection/decode logic as `bestDamageImage(in:)`
    /// above (kept as a thin wrapper over this for existing call sites),
    /// but also hands back the source `CapturedPhoto.id` so
    /// `ContourOverlay.sourcePhotoID` can record exactly which photo the
    /// persisted contour was traced on — needed because
    /// `DeformationMatcher.analyze` only ever sees a bare `CGImage`, not
    /// the `CapturedPhoto` it came from.
    func bestDamagePhotoAndImage(in vehicle: Vehicle) -> (photoID: UUID, image: CGImage)? {
        let candidates = vehicle.photos
            .filter { $0.photoType == .closeupDamage || $0.photoType == .paintTransfer }
            .sorted { $0.qualityScore > $1.qualityScore }
        guard let best = candidates.first,
              let source = CGImageSourceCreateWithData(best.imageData as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return (best.id, image)
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
    private func buildRecommendations(factors: [FactorScore], composite: Double, exclusionReason: String? = nil) -> [String] {
        var recs: [String] = []
        // NOTE(AI Developer), added 2026-07 for Sean's hard exclusion
        // rule -- surfaced as the FIRST recommendation (highest
        // visibility) whenever it fires, but does not suppress any of
        // the normal composite-score-driven guidance below it; the
        // investigator should still see the full picture.
        if let exclusionReason {
            recs.append("⚠️ \(exclusionReason)")
        }
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
