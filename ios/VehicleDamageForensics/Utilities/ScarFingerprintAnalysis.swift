// ScarFingerprintAnalysis.swift
// Vehicle Damage Investigation Assistant
// Discrete-feature ("minutiae") extraction and nearest-neighbor matching
// for a marked scar/scrape line -- the fingerprint-style analysis Sean
// asked for.
//
// NOTE(AI Developer), added 2026-07 per Sean's explicit question ("do we
// currently analyse the scar similar to a fingerprint? if not we should.
// we should identify and isolate clear markings and use those to
// match") and his follow-up "let's start building this as well."
//
// Before this file, the scar pipeline did two things, neither of which is
// fingerprint-style feature matching:
//   1. `ScarLineSuggester.suggestLine` -- finds ONE dominant line (the
//      long axis of the most elongated Vision contour in the guide box).
//   2. `ColorAnalysis.detectScarTaper` -- a single BINARY classification
//      (which end has denser transferred paint) used only to resolve
//      forward-vs-reversing direction of travel.
// Neither isolates individual marks *within* the scar the way a
// fingerprint examiner isolates individual ridge endings/bifurcations
// and compares their type+position+spacing between two prints.
//
// This file adds that missing layer, built from data already on hand
// (the marked line + the same photo) rather than requiring a new capture
// step:
//   1. Sample two independent 1D signal profiles along the marked scar
//      line, evenly spaced start-to-end:
//        - PAINT DENSITY: ΔE2000 vs. this vehicle's own clean-panel
//          reference color, reusing the exact extraction
//          (`ColorAnalysis.sampleColor`) and perceptual-distance math
//          (`ColorAnalysis.deltaE2000`) already validated for Paint
//          Transfer and scar-taper detection -- never a second,
//          independently-invented color metric.
//        - MARK WIDTH: how far perpendicular to the line, at each sample
//          position, the color keeps looking like transferred paint
//          rather than clean panel -- a cheap proxy for how wide/deep
//          the physical gouge or scuff is at that point along its
//          length, using the same clean-panel reference and ΔE math.
//   2. Extract LOCAL PEAKS in each profile as discrete features
//      (`ScarMinutia`) -- a sharp local increase in either density or
//      width along an otherwise-tapering/uniform scar is exactly the
//      kind of "clear, isolated marking" (a gouge, a paint-transfer
//      blob, a chip) an investigator's trained eye would pick out and
//      use to individualize one scrape from another, rather than
//      treating the whole scar as one undifferentiated line -- the
//      direct analog of a fingerprint's ridge-ending/bifurcation
//      minutiae.
//   3. Match two vehicles' minutiae sets with `ScarFingerprintMatcher`:
//      nearest-neighbor pairing by normalized along-line position
//      within a tolerance, requiring same feature type, producing a
//      match count / total-features score.
//
// Per the same non-punitive principle used everywhere else in this app
// (`DataQuality.unavailable`, `ScarDirectionCheck.notDeterminable`), a
// scar with too few/no extractable features is never scored as a
// negative -- it simply produces fewer minutiae (or none), and the
// matcher reports that plainly rather than fabricating a confident
// verdict from noise.
import Foundation
import UIKit

// MARK: - Scar Minutia

/// One discrete, isolated feature found along a marked scar line --
/// deliberately named after fingerprint "minutiae" (the ridge-ending/
/// bifurcation points an examiner actually compares) since that's the
/// concept this is standing in for: not a full trace of the scar's
/// shape, just the handful of points along it that most individualize
/// this specific scrape from a generic one.
struct ScarMinutia: Codable, Equatable, Identifiable {
    var id: UUID = UUID()

    enum FeatureType: String, Codable {
        /// A local spike in transferred-paint density -- e.g. a heavier
        /// paint-transfer blob partway along an otherwise more evenly
        /// scraped line.
        case densityPeak = "density_peak"
        /// A local widening of the mark -- e.g. a gouge or deeper chip
        /// partway along an otherwise narrower scuff.
        case widthPeak = "width_peak"
    }

    var type: FeatureType
    /// Position along the line, 0 (at `scarFrontEndpoint`'s end) to 1
    /// (at the far end) -- always measured from the SAME anchor
    /// (`CapturedPhoto.scarFrontEndpoint`) `CapturedPhoto
    /// .scarLineAngleInPhotoDegrees` already uses, so two vehicles'
    /// minutiae positions are comparable despite each line being marked
    /// independently and possibly in either raw start/end order.
    var positionAlongLine: Double
    /// The signal value at this feature's peak (ΔE2000 for
    /// `.densityPeak`, normalized perpendicular reach 0-1 for
    /// `.widthPeak`) -- supporting context for display, not itself part
    /// of the match tolerance.
    var magnitude: Double
    /// How much this peak stands out above its local surroundings
    /// (peak value minus the mean of its immediate neighbors) -- how
    /// "clear/isolated" this marking actually is, the same quality bar
    /// a real fingerprint minutia needs to be usable at all. Low-
    /// prominence peaks are filtered out before this struct is even
    /// created -- see `ScarFingerprintExtractor.minimumProminence`.
    var prominence: Double
}

// MARK: - Scar Fingerprint Extractor

/// Extracts `ScarMinutia` from a marked scar line on a single photo.
enum ScarFingerprintExtractor {

    /// Number of evenly-spaced points sampled along the line for each
    /// signal profile. NOTE(AI Developer): higher than
    /// `ColorAnalysis.detectScarTaper`'s default 9 -- that function only
    /// needs a coarse start-third-vs-end-third comparison, whereas
    /// finding LOCAL peaks needs enough resolution along the line to
    /// tell a real, several-samples-wide bump from single-sample noise.
    static let sampleCount = 25

    /// A peak must exceed its local neighborhood's mean by at least this
    /// much to count as a real, isolated feature rather than ordinary
    /// sample-to-sample noise. Density peaks are measured in ΔE2000
    /// units; width peaks are measured in normalized (0-1) perpendicular-
    /// reach units. Same dual-unit pattern as `ColorAnalysis
    /// .detectScarTaper`'s `minimumConclusiveDeltaE`, just per-profile
    /// since the two signals have different natural scales.
    static let minimumDensityProminence: Double = 2.0
    static let minimumWidthProminence: Double = 0.08

    /// How far out (as a fraction of the line's own length) to probe
    /// perpendicular to the line, at each sample position, when
    /// measuring mark width.
    static let widthProbeMaxFraction: Double = 0.15
    static let widthProbeSteps = 6

    /// Extract minutiae from `image`'s marked scar line
    /// (`lineStart`/`lineEnd`, normalized 0-1/0-1, same convention as
    /// `CapturedPhoto.scarLineStart`/`scarLineEnd`), oriented so
    /// `positionAlongLine == 0` is at `frontEndpoint`'s end.
    ///
    /// - Parameters:
    ///   - referenceColor: this vehicle's own clean-panel color (same
    ///     `Vehicle.primaryDamageZone?.paintAnalysis?.primaryColorRGB`
    ///     input `ColorAnalysis.detectScarTaper` already requires).
    ///     `nil` produces an empty result (no reference to measure
    ///     transfer density against) rather than a fabricated one --
    ///     mirrors `detectScarTaper`'s own `nil`-reference handling.
    /// - Returns: minutiae sorted by `positionAlongLine`, ordered
    ///   front-to-rear. Empty (never `nil`) when extraction ran but
    ///   found nothing above the prominence threshold -- a scar with no
    ///   standout features is a valid, common outcome, not a failure.
    static func extractMinutiae(
        in image: UIImage,
        lineStart: CGPoint,
        lineEnd: CGPoint,
        frontEndpoint: ScarEndpoint,
        referenceColor: ColorRGB?
    ) -> [ScarMinutia] {
        guard let referenceColor else { return [] }
        let front = frontEndpoint == .start ? lineStart : lineEnd
        let rear = frontEndpoint == .start ? lineEnd : lineStart
        let referenceLab = ColorAnalysis.rgbToLab(referenceColor)

        // Perpendicular unit vector to the line, for width probing.
        let dx = Double(rear.x - front.x)
        let dy = Double(rear.y - front.y)
        let lineLength = (dx * dx + dy * dy).squareRoot()
        guard lineLength > 0.001 else { return [] }
        let perp = (x: -dy / lineLength, y: dx / lineLength)

        var densityProfile: [Double] = []
        var widthProfile: [Double] = []
        densityProfile.reserveCapacity(sampleCount)
        widthProfile.reserveCapacity(sampleCount)

        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleCount - 1)
            let point = CGPoint(
                x: front.x + CGFloat(t) * (rear.x - front.x),
                y: front.y + CGFloat(t) * (rear.y - front.y)
            )
            // Density: same localized-sample + ΔE2000 approach as
            // `detectScarTaper`, just at finer resolution.
            if let sample = ColorAnalysis.sampleColor(from: image, at: point, radiusFraction: 0.012) {
                densityProfile.append(ColorAnalysis.deltaE2000(referenceLab, ColorAnalysis.rgbToLab(sample.color)))
            } else {
                densityProfile.append(0)
            }

            // Width: walk outward perpendicular to the line in both
            // directions until the sampled color no longer reads as
            // "still transferred paint, not clean panel" (ΔE vs.
            // reference drops back under half the on-line density at
            // this position) -- a deliberately simple proxy, not a
            // segmentation algorithm, since all this needs is a
            // RELATIVE width signal to find local widening, not an
            // absolute physical measurement.
            let onLineDeltaE = densityProfile.last ?? 0
            let widthThreshold = max(1.0, onLineDeltaE * 0.5)
            var maxReach = 0.0
            for direction in [1.0, -1.0] {
                for step in 1...widthProbeSteps {
                    let reachFraction = widthProbeMaxFraction * Double(step) / Double(widthProbeSteps)
                    let probePoint = CGPoint(
                        x: point.x + CGFloat(direction * reachFraction * perp.x),
                        y: point.y + CGFloat(direction * reachFraction * perp.y)
                    )
                    guard let probeSample = ColorAnalysis.sampleColor(from: image, at: probePoint, radiusFraction: 0.012) else { break }
                    let probeDeltaE = ColorAnalysis.deltaE2000(referenceLab, ColorAnalysis.rgbToLab(probeSample.color))
                    if probeDeltaE < widthThreshold { break }
                    maxReach = max(maxReach, reachFraction)
                }
            }
            widthProfile.append(maxReach / widthProbeMaxFraction) // normalized 0-1
        }

        var minutiae: [ScarMinutia] = []
        minutiae.append(contentsOf: findPeaks(
            in: densityProfile, type: .densityPeak, minimumProminence: minimumDensityProminence
        ))
        minutiae.append(contentsOf: findPeaks(
            in: widthProfile, type: .widthPeak, minimumProminence: minimumWidthProminence
        ))
        return minutiae.sorted { $0.positionAlongLine < $1.positionAlongLine }
    }

    /// Local-maximum peak detection with a neighborhood-relative
    /// prominence filter -- deliberately simple (not a full topographic
    /// persistence algorithm) since these profiles are short (25
    /// samples) and only need to reject ordinary sample noise, not
    /// resolve subtly nested peaks.
    private static func findPeaks(
        in profile: [Double],
        type: ScarMinutia.FeatureType,
        minimumProminence: Double,
        neighborhoodRadius: Int = 3
    ) -> [ScarMinutia] {
        guard profile.count >= 3 else { return [] }
        var results: [ScarMinutia] = []
        for i in 1..<(profile.count - 1) {
            let value = profile[i]
            guard value >= profile[i - 1], value >= profile[i + 1] else { continue }

            let lo = max(0, i - neighborhoodRadius)
            let hi = min(profile.count - 1, i + neighborhoodRadius)
            let neighborhood = (lo...hi).filter { $0 != i }.map { profile[$0] }
            guard !neighborhood.isEmpty else { continue }
            let neighborhoodMean = neighborhood.reduce(0, +) / Double(neighborhood.count)
            let prominence = value - neighborhoodMean
            guard prominence >= minimumProminence else { continue }

            let position = Double(i) / Double(profile.count - 1)
            results.append(ScarMinutia(type: type, positionAlongLine: position, magnitude: value, prominence: prominence))
        }
        return results
    }
}

// MARK: - Scar Fingerprint Match

/// One matched pair of minutiae between the victim's and suspect's scar
/// -- the fingerprint-style analog of a matched ridge-ending pair
/// between two prints.
struct ScarMinutiaMatch: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var victimMinutia: ScarMinutia
    var suspectMinutia: ScarMinutia
    /// Absolute difference in `positionAlongLine` between the two
    /// matched features (0 = perfectly aligned). Never negative.
    var positionDeltaNormalized: Double
}

/// Result of matching one vehicle pair's extracted minutiae sets.
/// NOTE(AI Developer): follows the exact same "second, independent,
/// never-blended-into-the-composite-score" pattern already established
/// by `ScarDirectionCheck` -- see that struct's doc comment. This is a
/// SEPARATE, complementary signal (individual isolated markings) from
/// `ScarDirectionCheck` (overall taper-derived direction of travel);
/// both can be shown side by side without one replacing the other.
struct ScarFingerprintMatch: Codable, Equatable {
    var victimMinutiae: [ScarMinutia]
    var suspectMinutiae: [ScarMinutia]
    var matchedPairs: [ScarMinutiaMatch]

    /// `nil` when either vehicle has zero extractable minutiae -- not
    /// enough signal to say anything, never scored as a negative (same
    /// non-punitive principle as `ScarDirectionCheck.notDeterminable`).
    var matchScorePercent: Double? {
        let smallerSetCount = min(victimMinutiae.count, suspectMinutiae.count)
        guard smallerSetCount > 0 else { return nil }
        return (Double(matchedPairs.count) / Double(smallerSetCount)) * 100
    }

    var isDeterminable: Bool { matchScorePercent != nil }

    /// Human-readable summary for UI/PDF, mirroring the plain-language
    /// framing Sean asked for elsewhere in this feature ("match the
    /// scars with a high level of probability/confidence one way or
    /// another").
    var summary: String {
        guard let score = matchScorePercent else {
            if victimMinutiae.isEmpty && suspectMinutiae.isEmpty {
                return "No isolated markings were identified on either vehicle's scar — not enough distinct detail to compare beyond the overall line."
            } else if victimMinutiae.isEmpty {
                return "No isolated markings were identified on the victim vehicle's scar — not enough distinct detail to compare."
            } else {
                return "No isolated markings were identified on the suspect vehicle's scar — not enough distinct detail to compare."
            }
        }
        return String(format: "%d of %d comparable markings matched in position and type (%.0f%%).",
                       matchedPairs.count, min(victimMinutiae.count, suspectMinutiae.count), score)
    }

    static func notDeterminable() -> ScarFingerprintMatch {
        ScarFingerprintMatch(victimMinutiae: [], suspectMinutiae: [], matchedPairs: [])
    }
}

// MARK: - Scar Fingerprint Matcher

enum ScarFingerprintMatcher {

    /// Maximum along-line position difference (normalized 0-1) for two
    /// minutiae of the SAME type to be considered a candidate match --
    /// the fingerprint-matching analog of a minutia-comparison
    /// tolerance radius. Deliberately loose (15% of the line's length)
    /// since the two scars are marked on independently-taken photos
    /// with no shared physical scale or guaranteed identical framing --
    /// this is about relative position along each vehicle's own line,
    /// not an exact physical distance.
    static let positionToleranceNormalized: Double = 0.15

    /// Greedy nearest-neighbor matching: for each victim minutia (in
    /// position order), pick the closest same-type, not-yet-used
    /// suspect minutia within tolerance. NOTE(AI Developer): greedy
    /// rather than a full optimal-assignment (e.g. Hungarian algorithm)
    /// solve -- with the small minutiae counts a scar realistically
    /// produces (typically well under 10 per vehicle), a greedy
    /// nearest-match is a reasonable, easily-auditable approximation,
    /// and any assignment ambiguity it might get wrong only affects
    /// which specific pair is drawn as "matched," not the overall
    /// match-count/score meaningfully.
    static func match(victim: [ScarMinutia], suspect: [ScarMinutia]) -> ScarFingerprintMatch {
        guard !victim.isEmpty, !suspect.isEmpty else {
            return ScarFingerprintMatch(victimMinutiae: victim, suspectMinutiae: suspect, matchedPairs: [])
        }

        var usedSuspectIDs = Set<UUID>()
        var pairs: [ScarMinutiaMatch] = []

        for vMinutia in victim.sorted(by: { $0.positionAlongLine < $1.positionAlongLine }) {
            var bestCandidate: ScarMinutia?
            var bestDelta = Double.greatestFiniteMagnitude
            for sMinutia in suspect {
                guard sMinutia.type == vMinutia.type, !usedSuspectIDs.contains(sMinutia.id) else { continue }
                let delta = abs(vMinutia.positionAlongLine - sMinutia.positionAlongLine)
                guard delta <= positionToleranceNormalized, delta < bestDelta else { continue }
                bestDelta = delta
                bestCandidate = sMinutia
            }
            if let bestCandidate {
                usedSuspectIDs.insert(bestCandidate.id)
                pairs.append(ScarMinutiaMatch(victimMinutia: vMinutia, suspectMinutia: bestCandidate, positionDeltaNormalized: bestDelta))
            }
        }

        return ScarFingerprintMatch(victimMinutiae: victim, suspectMinutiae: suspect, matchedPairs: pairs)
    }
}
