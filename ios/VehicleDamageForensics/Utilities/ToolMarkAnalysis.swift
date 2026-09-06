// ToolMarkAnalysis.swift
// Vehicle Damage Investigation Assistant
// Forensic tool-mark / striation comparison for a marked scar line -- finds
// the fine, closely-spaced parallel scratch/gouge lines ("tooling marks")
// physically transferred between two vehicles during contact, and compares
// the RHYTHM of their spacing (not their absolute size) between the
// victim's and suspect's scar photos.
//
// NOTE(AI Developer), added 2026-07 per Sean's explicit request, quoted in
// full because every design choice below traces back to a specific phrase
// in it: "scars, if just scraps of one vehicle to another should fit/match
// just like a finger print if we look close enough. we should be able to
// analyse both images and run them through an algorithm that looks closely
// and the lines and measure the distance between to see if the same
// fingerprint, granted it should be the opposite on the opposing vehicle
// similar to a stamp but we should be able to run it through a protocol
// that can determine if its a match regardless of the height or size of
// the picture. We should be able to match a close up of a scar with an
// image that is not a closeup... analyse the scars from all angles and
// possible sizes to rule the suspect image in or out. change the light
// rays of the image or change the spectrum some how to really bring out
// unique characteristics that can be matched at a high level of confidence
// just like finger prints. We are basically looking for tooling marks on
// each vehicle from the other."
//
// This is DELIBERATELY a different, complementary signal from
// `ScarFingerprintAnalysis.swift` (which finds a handful of DISCRETE
// isolated markings -- density/width peaks -- along the scar's LENGTH).
// This file instead looks ACROSS the mark's width, at several points
// along its length, for the fine parallel ridges/striae real tool-mark
// examiners compare -- the striation lines a hard edge leaves as it drags
// across a softer painted surface. What individualizes one scrape from
// another is not any single striation's position, but the RHYTHM of
// spacing between consecutive striations (how the gaps compare to each
// other), the same way a fingerprint examiner compares ridge SPACING
// patterns, not absolute ridge width in millimeters.
//
// Four requirements from Sean's message drove the specific design below:
//
//   1. "change the light rays... or change the spectrum... to really
//      bring out unique characteristics" -- a photo can't actually be
//      re-lit after the fact, but the computational equivalent of raking
//      (grazing) light is a high-pass filter: subtract a heavily-smoothed
//      version of the luminance profile from the raw profile, which
//      strips the broad, slow-varying shading/color gradient a real
//      raking light would also mostly ignore, and leaves only the fine,
//      fast-varying texture ripples raking light makes visible. See
//      `highPassFilter` below.
//
//   2. "regardless of the height or size of the picture" / "match a
//      close up... with an image that is not a closeup" -- scale
//      invariance. Rather than measuring gap widths in pixels (which
//      scale directly with camera distance and photo resolution), every
//      gap between two consecutive detected striations is expressed as a
//      RATIO of that same cross-section's own mean gap. A striation
//      rhythm of "wide, narrow, wide, wide" produces a similar ratio
//      sequence whether it occupies 40 pixels in a closeup or 8 pixels in
//      a wide shot -- only the physical rhythm survives, not the absolute
//      scale it was photographed at.
//
//   3. "analyse the scars from all angles" -- the exact local angle a
//      tool mark runs at within a photo isn't something the user marks
//      (they only mark the scar's overall line, in `ScarCaptureView`).
//      Rather than assuming striations run exactly perpendicular to that
//      marked line, this fans out across several candidate probe angles
//      at each position and keeps whichever angle actually reveals the
//      clearest periodic pattern there -- see `bestAngleProfile`.
//
//   4. "granted it should be the opposite on the opposing vehicle similar
//      to a stamp" -- a tool mark left ON one vehicle and the
//      complementary mark left BY that same contact ON the other vehicle
//      are a stamp/impression pair, not two identical photos of the same
//      thing. `ToolMarkMatcher.compare` explicitly tries comparing the
//      suspect's rhythm both forward AND reversed against the victim's,
//      and reports whichever orientation actually lines up -- see
//      `ToolMarkComparison.orientationUsed`.
//
// Per the same non-punitive principle used everywhere else in this app
// (`ScarFingerprintMatch`, `ScarDirectionCheck.notDeterminable`), a scar
// with too little real texture detail (too blurry, too far away, too
// smooth a scuff to show individual striations) never produces a
// fabricated low/negative score -- it simply reports "not enough distinct
// striation detail to compare," exactly like a real tool-mark examiner
// would decline to call an inconclusive comparison a non-match.
//
// Like `ScarFingerprintMatch`/`ScarDirectionCheck` before it, this is a
// SEPARATE, INDEPENDENT signal -- never blended into
// `MatchResult.compositeScore`/`factors` (see `MatchResult
// .toolMarkComparison`'s doc comment for why).
import Foundation
import UIKit

// MARK: - Striation Cross-Section Sample

/// One perpendicular "slice" across the scar's width, at a single point
/// along its length -- the raw material a tool-mark examiner would look
/// at under magnification at that spot.
struct StriationCrossSection: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    /// Position along the marked line, 0 (at `scarFrontEndpoint`'s end)
    /// to 1 (far end) -- same front-anchored convention as
    /// `ScarMinutia.positionAlongLine`, so this stays comparable across
    /// two independently-marked lines.
    var positionAlongLine: Double
    /// The probe angle (degrees, relative to the line's own perpendicular)
    /// that produced the clearest periodic pattern at this position --
    /// see `bestAngleProfile`. Supporting context for display only.
    var probeAngleOffsetDegrees: Double
    /// How many distinct striations (local high-pass peaks) were found
    /// crossing this probe.
    var peakCount: Int
    /// Each gap between two consecutive detected striations, expressed as
    /// a RATIO of this cross-section's own mean gap (so a value of 1.0
    /// means "exactly average spacing for this particular photo/probe").
    /// This is the scale-invariant "rhythm" data Sean asked for --
    /// comparable between a closeup and a non-closeup photo of the same
    /// physical mark even though the two photos' absolute pixel scales
    /// are completely different. Empty when fewer than 2 peaks were
    /// found (not enough to form a gap).
    var normalizedGapRatios: [Double]
    /// The raw mean gap in pixels, for display/debugging only -- NEVER
    /// used in matching (that would reintroduce the exact scale
    /// dependency `normalizedGapRatios` exists to remove).
    var rawMeanGapPixels: Double

    /// NOTE(AI Developer), added 2026-09 for item #5 (duplicate case for
    /// another suspect). A fresh id matters especially here: the
    /// per-cross-section exclude feature (item #4) records exclusions
    /// BY `crossSectionID`, so two cases sharing cross-section ids would
    /// let an exclusion recorded in one case address the other's data.
    /// See `Vehicle.duplicatedWithFreshIDs()`.
    func duplicatedWithFreshID() -> StriationCrossSection {
        StriationCrossSection(
            id: UUID(),
            positionAlongLine: positionAlongLine,
            probeAngleOffsetDegrees: probeAngleOffsetDegrees,
            peakCount: peakCount,
            normalizedGapRatios: normalizedGapRatios,
            rawMeanGapPixels: rawMeanGapPixels
        )
    }
}

// MARK: - Striation Profile (persisted per photo)

/// The full set of cross-section samples extracted from one photo's
/// marked scar line, plus the flattened comparison sequence derived from
/// them.
struct StriationProfile: Codable, Equatable {
    var crossSections: [StriationCrossSection]

    /// All cross-sections' `normalizedGapRatios`, concatenated in
    /// front-to-rear position order -- the actual sequence
    /// `ToolMarkMatcher` compares between two vehicles. Deliberately a
    /// flat sequence (not kept nested per cross-section) since the
    /// matcher needs to slide one vehicle's whole rhythm against the
    /// other's looking for the best-aligned overlapping run, the same
    /// way a fingerprint examiner's eye tracks a ridge-spacing rhythm
    /// continuously along a ridge, not cross-section by cross-section in
    /// isolation.
    var rhythmSequence: [Double] {
        crossSections.flatMap { $0.normalizedGapRatios }
    }

    /// Needs at least this many gaps in the combined rhythm sequence
    /// before a comparison is even attempted -- fewer than this is "not
    /// enough distinct striation detail," not a real signature. Chosen
    /// so a meaningful overlap window (see
    /// `ToolMarkMatcher.minimumOverlapLength`) is still possible on both
    /// sides even in the worst case.
    static let minimumRhythmLength = 6

    var isDeterminable: Bool { rhythmSequence.count >= Self.minimumRhythmLength }

    static func empty() -> StriationProfile { StriationProfile(crossSections: []) }

    /// NOTE(AI Developer), added 2026-09 for item #5 (duplicate case).
    /// See `StriationCrossSection.duplicatedWithFreshID()`.
    func duplicatedWithFreshIDs() -> StriationProfile {
        StriationProfile(crossSections: crossSections.map { $0.duplicatedWithFreshID() })
    }
}

// MARK: - Striation Extractor

/// Extracts a `StriationProfile` from a photo's marked scar line.
enum ToolMarkExtractor {

    /// How many evenly-spaced positions along the line to probe.
    /// NOTE(AI Developer): kept away from the very ends (see
    /// `positionsAlongLine` below) since a probe centered right at an
    /// endpoint often crosses OFF the actual mark into surrounding clean
    /// panel, which would corrupt the profile with a false, very-high-
    /// contrast "edge" rather than a real striation.
    static let crossSectionCount = 7

    /// Half-width of the perpendicular probe, as a fraction of the
    /// image's shorter pixel dimension -- same "fraction of shortSide"
    /// convention as `ColorAnalysis.sampleColor`'s `radiusFraction`, so
    /// this automatically adapts to whatever resolution/framing this
    /// particular photo happens to be, which is exactly what makes a
    /// closeup and a wide shot both produce a usable (if differently
    /// scaled) profile.
    static let probeHalfWidthFraction: Double = 0.06

    /// Number of samples taken across the full probe width (both
    /// directions combined). Deliberately fine-grained -- unlike
    /// `ScarFingerprintExtractor`'s coarse 25-sample line profile, this
    /// needs enough resolution to resolve individual striations that can
    /// be only a few pixels apart.
    static let profileSampleCount = 56

    /// Candidate probe angles to fan out across, in degrees relative to
    /// the line's own perpendicular -- see this file's header comment,
    /// point 3 ("analyse the scars from all angles"). Whichever angle
    /// reveals the clearest periodic pattern at a given position is kept;
    /// the others are discarded, not averaged (averaging across angles
    /// would blur exactly the fine texture this is trying to isolate).
    static let candidateAngleOffsetsDegrees: [Double] = [-25, -15, -8, 0, 8, 15, 25]

    /// Minimum number of high-pass peaks a single cross-section must show
    /// to be considered real striation detail rather than noise -- needs
    /// at least 2 gaps' worth (3 peaks) to say anything about a rhythm at
    /// all.
    static let minimumPeaksPerCrossSection = 3

    /// Minimum spacing between two accepted peaks, in samples, so two
    /// adjacent high-pass samples of the same physical ridge aren't
    /// double-counted as two separate striations.
    static let minimumPeakSeparationSamples = 2

    /// Extract a `StriationProfile` from `image`'s marked scar line.
    ///
    /// - Returns: `nil` only for a hard technical failure (no pixel data,
    ///   or a degenerate zero-length line) -- mirrors
    ///   `ScarFingerprintExtractor.extractMinutiae`'s `nil`-vs-empty
    ///   convention. A photo that decodes fine but simply doesn't show
    ///   enough real texture to find striations in still returns a
    ///   non-nil `StriationProfile` with an empty/short
    ///   `crossSections`/`rhythmSequence` -- a valid, non-punitive
    ///   outcome, not a failure.
    static func extractStriationProfile(
        in image: UIImage,
        lineStart: CGPoint,
        lineEnd: CGPoint,
        frontEndpoint: ScarEndpoint,
        focusRegion: CGRect? = nil
    ) -> StriationProfile? {
        guard let cg = image.cgImage else { return nil }
        let pixelWidth = cg.width
        let pixelHeight = cg.height
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let front = frontEndpoint == .start ? lineStart : lineEnd
        let rear = frontEndpoint == .start ? lineEnd : lineStart
        // Direction + perpendicular computed in the SAME normalized
        // (0-1, 0-1) space `ScarFingerprintExtractor`'s width-probing
        // already uses -- see this file's header for why matching that
        // existing convention (rather than correcting for pixel aspect
        // ratio) is the deliberate choice here, not an oversight.
        let dx = Double(rear.x - front.x)
        let dy = Double(rear.y - front.y)
        let lineLength = (dx * dx + dy * dy).squareRoot()
        guard lineLength > 0.001 else { return nil }
        let dirX = dx / lineLength
        let dirY = dy / lineLength
        let perpX = -dirY
        let perpY = dirX

        // Crop just the region actually needed (line's bounding box plus
        // probe margin) rather than decoding the whole photo's pixel
        // buffer -- same "don't decode more than you need" discipline as
        // `ColorAnalysis.sampleColor`.
        let shortSide = Double(min(pixelWidth, pixelHeight))
        let probeMarginPx = shortSide * probeHalfWidthFraction * 1.4 // headroom for angle fan
        let minXNorm = min(front.x, rear.x)
        let maxXNorm = max(front.x, rear.x)
        let minYNorm = min(front.y, rear.y)
        let maxYNorm = max(front.y, rear.y)
        var minPxX = max(0, Int((Double(minXNorm) * Double(pixelWidth) - probeMarginPx).rounded(.down)))
        var maxPxX = min(pixelWidth - 1, Int((Double(maxXNorm) * Double(pixelWidth) + probeMarginPx).rounded(.up)))
        var minPxY = max(0, Int((Double(minYNorm) * Double(pixelHeight) - probeMarginPx).rounded(.down)))
        var maxPxY = min(pixelHeight - 1, Int((Double(maxYNorm) * Double(pixelHeight) + probeMarginPx).rounded(.up)))

        // NOTE(AI Developer), added 2026-07 per Sean's on-device report
        // that this analysis "somehow use part of the image of the tape
        // measure as part of the vehicle damage." The margin-padded crop
        // above is generous enough (headroom for the ±25° angle fan) to
        // regularly reach a ruler, background trim, or another panel
        // sitting just outside the marked line's own bounding box -- and
        // a tape measure's printed tick marks are, by construction, fine
        // evenly-spaced high-contrast parallel lines, i.e. exactly the
        // signal `highPassFilter`/`findStriationPeaks` is built to treat
        // as a confident striation rhythm. `CapturedPhoto.scarFocusRegion`
        // (drawn by the user in `ScarCaptureView.focusRegionStage`) is a
        // HARD boundary against that: when present, it's intersected
        // with the margin-padded crop rect below, so `PixelCrop`'s own
        // bounds physically cannot include anything the user didn't draw
        // the box around -- not just a "prefer this area" hint. Falls
        // back to the unrestricted margin-padded crop (this function's
        // pre-existing behavior) when `focusRegion` is `nil`, i.e. for
        // any scar marked before this feature existed.
        if let focusRegion {
            let regionMinPxX = Int((Double(focusRegion.minX) * Double(pixelWidth)).rounded(.down))
            let regionMaxPxX = Int((Double(focusRegion.maxX) * Double(pixelWidth)).rounded(.up))
            let regionMinPxY = Int((Double(focusRegion.minY) * Double(pixelHeight)).rounded(.down))
            let regionMaxPxY = Int((Double(focusRegion.maxY) * Double(pixelHeight)).rounded(.up))
            minPxX = max(minPxX, regionMinPxX)
            maxPxX = min(maxPxX, regionMaxPxX)
            minPxY = max(minPxY, regionMinPxY)
            maxPxY = min(maxPxY, regionMaxPxY)
        }

        guard maxPxX > minPxX, maxPxY > minPxY,
              let crop = PixelCrop(cgImage: cg, pixelRect: CGRect(
                x: minPxX, y: minPxY,
                width: maxPxX - minPxX, height: maxPxY - minPxY
              ))
        else { return nil }

        var crossSections: [StriationCrossSection] = []
        for i in 0..<crossSectionCount {
            // Skip the outermost 10% at each end -- see the doc comment
            // on `crossSectionCount` above for why.
            let t = 0.10 + 0.80 * (Double(i) / Double(crossSectionCount - 1))
            let centerNorm = CGPoint(
                x: front.x + CGFloat(t) * (rear.x - front.x),
                y: front.y + CGFloat(t) * (rear.y - front.y)
            )
            guard let best = bestAngleProfile(
                crop: crop,
                pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                centerNorm: centerNorm,
                perpX: perpX, perpY: perpY,
                shortSide: shortSide
            ) else { continue }
            crossSections.append(StriationCrossSection(
                positionAlongLine: t,
                probeAngleOffsetDegrees: best.angleOffsetDegrees,
                peakCount: best.peakIndices.count,
                normalizedGapRatios: best.normalizedGapRatios,
                rawMeanGapPixels: best.rawMeanGapPixels
            ))
        }
        return StriationProfile(crossSections: crossSections)
    }

    // MARK: Per-position angle fan

    private struct AngleProfileResult {
        var angleOffsetDegrees: Double
        var peakIndices: [Int]
        var normalizedGapRatios: [Double]
        var rawMeanGapPixels: Double
    }

    /// Tries every candidate angle at this one position and keeps the
    /// result with the most qualifying peaks (tie-broken by total
    /// prominence) -- see this file's header, point 3.
    private static func bestAngleProfile(
        crop: PixelCrop,
        pixelWidth: Int, pixelHeight: Int,
        centerNorm: CGPoint,
        perpX: Double, perpY: Double,
        shortSide: Double
    ) -> AngleProfileResult? {
        var best: AngleProfileResult?
        var bestScore = -1.0

        for angleDeg in candidateAngleOffsetsDegrees {
            let rad = angleDeg * .pi / 180
            // Rotate the perpendicular vector by the candidate offset --
            // standard 2D rotation, applied in the same normalized-space
            // convention as `perpX`/`perpY` themselves.
            let rotatedX = perpX * cos(rad) - perpY * sin(rad)
            let rotatedY = perpX * sin(rad) + perpY * cos(rad)

            var rawProfile: [Double] = []
            rawProfile.reserveCapacity(profileSampleCount)
            for s in 0..<profileSampleCount {
                let frac = (Double(s) / Double(profileSampleCount - 1) - 0.5) * 2.0 * probeHalfWidthFraction
                let probeNormX = Double(centerNorm.x) + frac * rotatedX
                let probeNormY = Double(centerNorm.y) + frac * rotatedY
                let px = probeNormX * Double(pixelWidth)
                let py = probeNormY * Double(pixelHeight)
                guard let lum = crop.luminance(atOriginalPixelX: px, originalPixelY: py) else {
                    rawProfile.append(rawProfile.last ?? 0)
                    continue
                }
                rawProfile.append(lum)
            }
            guard rawProfile.count == profileSampleCount else { continue }

            // "Change the light rays" -- computational raking-light
            // equivalent. See this file's header, point 1.
            let filtered = highPassFilter(rawProfile)
            let (peakIndices, gaps) = findStriationPeaks(in: filtered)
            guard peakIndices.count >= minimumPeaksPerCrossSection, !gaps.isEmpty else { continue }

            let meanGap = gaps.reduce(0, +) / Double(gaps.count)
            guard meanGap > 0 else { continue }
            let normalizedGaps = gaps.map { $0 / meanGap }

            // Preference score: more peaks is better (a clearer, more
            // resolvable rhythm at this angle); ties broken by how
            // uniform the raw pixel gap is (a real striation rhythm is
            // rarely wildly irregular, whereas noise picked up as
            // "peaks" typically is).
            let gapConsistency = 1.0 / (1.0 + (gaps.map { abs($0 - meanGap) }.reduce(0, +) / Double(gaps.count)))
            let score = Double(peakIndices.count) + gapConsistency
            if score > bestScore {
                bestScore = score
                let meanGapPixels = meanGap * (2.0 * probeHalfWidthFraction * shortSide / Double(profileSampleCount))
                best = AngleProfileResult(
                    angleOffsetDegrees: angleDeg,
                    peakIndices: peakIndices,
                    normalizedGapRatios: normalizedGaps,
                    rawMeanGapPixels: meanGapPixels
                )
            }
        }
        return best
    }

    // MARK: High-pass filter ("computational raking light")

    /// Subtracts a wide moving average from `profile`, leaving only the
    /// fast-varying texture ripple -- the same broad-gradient-removal
    /// effect a real raking (grazing) light has on a textured surface:
    /// it doesn't change slow, overall shading, but it makes fine
    /// surface relief pop by throwing short shadows across it. Edges use
    /// a clamped window (no wraparound) rather than padding with zeros,
    /// so the filter doesn't invent a false edge artifact at either end
    /// of the probe.
    static func highPassFilter(_ profile: [Double]) -> [Double] {
        guard profile.count > 3 else { return profile }
        let windowRadius = max(2, profile.count / 6)
        var result: [Double] = []
        result.reserveCapacity(profile.count)
        for i in 0..<profile.count {
            let lo = max(0, i - windowRadius)
            let hi = min(profile.count - 1, i + windowRadius)
            let windowMean = profile[lo...hi].reduce(0, +) / Double(hi - lo + 1)
            result.append(profile[i] - windowMean)
        }
        return result
    }

    // MARK: Peak detection

    /// Local-maximum detection on the high-passed profile, with an
    /// adaptive (not fixed) prominence threshold -- a photo with strong,
    /// crisp texture naturally has a higher-contrast filtered signal than
    /// one that's slightly soft/distant, so the threshold scales with
    /// this specific profile's own standard deviation rather than a
    /// universal magic number (same self-normalizing philosophy as the
    /// gap-ratio normalization itself).
    private static func findStriationPeaks(in filtered: [Double]) -> (peakIndices: [Int], gapsInSamples: [Double]) {
        guard filtered.count > 4 else { return ([], []) }
        let mean = filtered.reduce(0, +) / Double(filtered.count)
        let variance = filtered.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(filtered.count)
        let stdDev = variance.squareRoot()
        guard stdDev > 0.5 else { return ([], []) } // essentially flat -- no real texture to speak of

        let threshold = mean + stdDev * 0.6
        var candidates: [Int] = []
        for i in 1..<(filtered.count - 1) {
            guard filtered[i] >= filtered[i - 1], filtered[i] >= filtered[i + 1], filtered[i] >= threshold else { continue }
            candidates.append(i)
        }

        // Enforce minimum separation, keeping the stronger of any two
        // peaks that are too close together (same "don't double-count
        // one ridge" intent as `minimumPeakSeparationSamples`'s doc
        // comment).
        var accepted: [Int] = []
        for c in candidates {
            if let lastIndex = accepted.last, c - lastIndex < minimumPeakSeparationSamples {
                if filtered[c] > filtered[lastIndex] {
                    accepted[accepted.count - 1] = c
                }
                continue
            }
            accepted.append(c)
        }

        guard accepted.count >= 2 else { return (accepted, []) }
        var gaps: [Double] = []
        for i in 1..<accepted.count {
            gaps.append(Double(accepted[i] - accepted[i - 1]))
        }
        return (accepted, gaps)
    }
}

// MARK: - Pixel Crop (shared low-level pixel access helper)

/// A small decoded RGBA8 window of a larger image, plus bilinear lookup
/// keyed by pixel coordinates IN THE ORIGINAL (uncropped) IMAGE's own
/// pixel space -- callers work entirely in original-image pixel
/// coordinates and never need to think about the crop offset themselves.
///
/// NOTE(AI Developer): factored out of `ToolMarkExtractor` (rather than
/// inlined) since fine-grained bilinear pixel access is a genuinely
/// distinct capability from `ColorAnalysis.sampleColor`'s radius-average-
/// with-outlier-rejection sampling -- that function answers "what's the
/// representative color of this patch," this one answers "what's the
/// exact texture value at this precise sub-pixel point," which is what
/// striation-spacing detection actually needs.
private struct PixelCrop {
    let width: Int
    let height: Int
    let data: [UInt8] // RGBA8, premultiplied-last
    let originPxX: Int
    let originPxY: Int

    init?(cgImage: CGImage, pixelRect: CGRect) {
        guard pixelRect.width > 0, pixelRect.height > 0,
              let cropped = cgImage.cropping(to: pixelRect) else { return nil }
        let w = Int(pixelRect.width)
        let h = Int(pixelRect.height)
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: &buffer, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: cs, bitmapInfo: info
        ) else { return nil }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
        self.width = w
        self.height = h
        self.data = buffer
        self.originPxX = Int(pixelRect.origin.x)
        self.originPxY = Int(pixelRect.origin.y)
    }

    /// Bilinearly-interpolated luminance (ITU-R BT.601 weighting, same
    /// formula as `ColorAnalysis.sampleColor`'s luminance calc) at a
    /// point given in the ORIGINAL image's pixel coordinate space.
    /// `nil` if the point falls outside this crop's bounds.
    func luminance(atOriginalPixelX origX: Double, originalPixelY origY: Double) -> Double? {
        let x = origX - Double(originPxX)
        let y = origY - Double(originPxY)
        guard x >= 0, y >= 0, x <= Double(width - 1), y <= Double(height - 1) else { return nil }
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let fx = x - Double(x0), fy = y - Double(y0)
        func lum(_ px: Int, _ py: Int) -> Double {
            let offset = (py * width + px) * 4
            let r = Double(data[offset])
            let g = Double(data[offset + 1])
            let b = Double(data[offset + 2])
            return 0.299 * r + 0.587 * g + 0.114 * b
        }
        let top = lum(x0, y0) * (1 - fx) + lum(x1, y0) * fx
        let bottom = lum(x0, y1) * (1 - fx) + lum(x1, y1) * fx
        return top * (1 - fy) + bottom * fy
    }
}

// MARK: - Tool-Mark Comparison

/// Which orientation of the suspect's rhythm sequence best aligned with
/// the victim's -- see this file's header, point 4 ("similar to a
/// stamp"). Reported (not just used internally) so an investigator can
/// see WHY a strong match was called a match -- a reversed-orientation
/// match is exactly what a genuine stamp/impression pair should produce.
enum ToolMarkOrientation: String, Codable {
    case sameDirection = "same_direction"
    case reversed = "reversed"
}

/// Result of comparing two vehicles' `StriationProfile`s. NOTE(AI
/// Developer): follows the exact same "independent signal, never blended
/// into the composite score" pattern as `ScarDirectionCheck`/
/// `ScarFingerprintMatch` before it -- see `MatchResult
/// .toolMarkComparison`'s doc comment for the full rationale.
struct ToolMarkComparison: Codable, Equatable {
    var victimProfile: StriationProfile
    var suspectProfile: StriationProfile
    /// `nil` when either side doesn't have enough striation detail to
    /// compare at all (`StriationProfile.isDeterminable == false`) or no
    /// overlapping alignment of at least `ToolMarkMatcher
    /// .minimumOverlapLength` elements scored well enough to report --
    /// never a fabricated low/negative score, same non-punitive
    /// principle as `ScarFingerprintMatch.matchScorePercent`.
    var matchScorePercent: Double?
    /// Which orientation (`sameDirection` vs `reversed`) produced the
    /// best-scoring alignment. `nil` alongside `matchScorePercent`.
    var orientationUsed: ToolMarkOrientation?
    /// How many consecutive rhythm elements actually overlapped at the
    /// best alignment -- context for how much of the striation pattern
    /// the score above is actually based on. `nil` alongside
    /// `matchScorePercent`.
    var overlapLength: Int?
    // NOTE(AI Developer), added 2026-07 per Sean's question "how do we
    // get two different suspect vehicles with 69% and 78% tool
    // mark/striation matching? how is that possible?" -- see
    // `ToolMarkMatcher.compare`'s header note for the full explanation
    // and `ToolMarkMatcher.nullModelBaseline` for how these three values
    // are computed. In short: `bestAlignment` already searches every
    // offset in both orientations and keeps only the best-scoring
    // result, which alone inflates a reported score above what a truly
    // UNRELATED scrape would score -- these three fields answer "how
    // much of this score is just that search's own selection bias?" so
    // two different raw percentages can be told apart by whether either
    // one is actually distinguishable from noise, not just by which
    // number is bigger.
    /// Mean score (0-100, same scale as `matchScorePercent`) that this
    /// exact same search produced when run against `ToolMarkMatcher
    /// .nullModelTrialCount` random shuffles of the suspect's own rhythm
    /// values (same values, order destroyed) -- i.e. what an UNRELATED
    /// scrape with similar overall texture would typically score by
    /// chance alone. `nil` alongside `matchScorePercent`.
    var nullModelMeanPercent: Double?
    /// Standard deviation of that same shuffled-baseline score
    /// distribution. `nil` alongside `matchScorePercent`.
    var nullModelStdDevPercent: Double?
    /// How many standard deviations `matchScorePercent` sits above
    /// `nullModelMeanPercent` -- the actual statistical test. `nil`
    /// alongside `matchScorePercent`.
    var zScore: Double?

    var isDeterminable: Bool { matchScorePercent != nil }

    /// `nil` alongside `matchScorePercent` (nothing to test yet). `true`
    /// only when `zScore` clears `ToolMarkMatcher
    /// .significanceZScoreThreshold` -- i.e. this specific score is
    /// meaningfully higher than what an unrelated scrape would be
    /// expected to score from this same search, not just a bigger raw
    /// number than some other comparison.
    var isStatisticallySignificant: Bool? {
        guard let zScore else { return nil }
        return zScore >= ToolMarkMatcher.significanceZScoreThreshold
    }

    /// Human-readable summary, deliberately in the same plain-language,
    /// non-overclaiming register as `ScarFingerprintMatch.summary` and
    /// `MatchResult`'s "correlation strength," not "match" (see
    /// `MatchResult`'s header doc comment on that framing decision).
    var summary: String {
        guard let score = matchScorePercent, let orientation = orientationUsed, let overlap = overlapLength else {
            if !victimProfile.isDeterminable && !suspectProfile.isDeterminable {
                return "Not enough distinct striation (tool-mark) detail was found on either vehicle's scar to compare -- the marks may be too faint, blurry, or distant in these photos."
            } else if !victimProfile.isDeterminable {
                return "Not enough distinct striation detail was found on the victim vehicle's scar to compare."
            } else if !suspectProfile.isDeterminable {
                return "Not enough distinct striation detail was found on the suspect vehicle's scar to compare."
            } else {
                return "Striation detail was found on both scars, but no consistent overlapping spacing rhythm was found between them."
            }
        }
        let orientationPhrase = orientation == .reversed
            ? "in reverse order, as expected for a stamp/impression pair from opposite sides of the same contact"
            : "in the same order on both vehicles"
        let baseSummary = String(format: "Striation spacing rhythm correlates at %.0f%% across %d overlapping marks, %@.", score, overlap, orientationPhrase)

        // NOTE(AI Developer), added 2026-07 -- see the header note on
        // `nullModelMeanPercent` above. This is the actual answer to
        // Sean's "how is that possible" question, surfaced directly in
        // the sentence an investigator reads, not buried in a separate
        // number they'd have to interpret themselves.
        guard let baselineMean = nullModelMeanPercent, let significant = isStatisticallySignificant else {
            return baseSummary
        }
        if significant {
            return baseSummary + String(format: " This is meaningfully higher than the ~%.0f%% an unrelated scrape would be expected to score from this same search by chance alone, so this correlation is unlikely to be a coincidence.", baselineMean)
        } else {
            return baseSummary + String(format: " However, unrelated/random spacing patterns of this same length typically score around %.0f%% with this same search purely by chance -- this result is NOT statistically distinguishable from random and should not be treated as meaningful evidence on its own.", baselineMean)
        }
    }

    static func notDeterminable(victim: StriationProfile = .empty(), suspect: StriationProfile = .empty()) -> ToolMarkComparison {
        ToolMarkComparison(
            victimProfile: victim, suspectProfile: suspect,
            matchScorePercent: nil, orientationUsed: nil, overlapLength: nil,
            nullModelMeanPercent: nil, nullModelStdDevPercent: nil, zScore: nil
        )
    }
}

// MARK: - Tool-Mark Matcher

enum ToolMarkMatcher {

    /// The shortest overlapping run of rhythm elements that's allowed to
    /// produce a score at all -- without a floor here, a 1- or 2-element
    /// "overlap" could trivially score 100% by chance and misrepresent a
    /// coincidence as a strong correlation. Chosen well below
    /// `StriationProfile.minimumRhythmLength` (6) so a real but partial
    /// overlap (e.g. the photos only show part of the same mark) still
    /// gets a chance to score.
    static let minimumOverlapLength = 4

    // NOTE(AI Developer), added 2026-07 per Sean's question: "how do we
    // get two different suspect vehicles with 69% and 78% tool
    // mark/striation matching? How is that possible?"
    //
    // The honest answer is that `bestAlignment` below tries EVERY offset
    // (sliding window), in BOTH orientations (forward/reversed), and
    // keeps only the single best-scoring result. Each of those is a
    // "keep the best of many independent tries" step, and each one
    // inflates the reported score above what a truly UNRELATED pair of
    // scrapes would score, purely because there were so many chances to
    // find something that happens to line up. On top of that, every gap
    // is stored as a RATIO to its own cross-section's mean gap
    // (`StriationCrossSection.normalizedGapRatios`), which compresses
    // most real-world rhythms toward ~1.0 -- so two completely unrelated
    // scrapes routinely land in a "50-85% moderately similar" band by
    // chance alone, with no way to tell that apart from a real match
    // using the raw score alone.
    //
    // The fix: a null-model / permutation-test baseline. For the exact
    // same pair of profiles, run this exact same search
    // (`bestOverallAlignment` -- same offsets, same both-orientations
    // check) against `nullModelTrialCount` randomly SHUFFLED copies of
    // the suspect's own rhythm values (same numbers, real order
    // destroyed). That produces a distribution of scores an UNRELATED
    // scrape with similar overall texture statistics would be expected
    // to produce from this same "keep the best" search, purely by
    // chance. The real score is then expressed as a z-score against that
    // distribution (`ToolMarkComparison.zScore`) -- only a real score
    // that clears `significanceZScoreThreshold` standard deviations
    // above the shuffled baseline is called "statistically significant"
    // (`ToolMarkComparison.isStatisticallySignificant`); otherwise the
    // app now says so explicitly instead of presenting a raw percentage
    // as if it were automatically meaningful. This is exactly the
    // "compare against chance" step a real tool-mark examiner's
    // statistical validation study would also require before calling a
    // correlation meaningful.
    //
    // A deterministic (not system-random) seeded generator is used for
    // the shuffles (see `SeededGenerator`/`nullModelSeed` below) so
    // re-running analysis on the exact same two profiles always reports
    // the exact same baseline/z-score -- a forensic tool must not give a
    // different answer each time it's asked the same question.
    /// Number of shuffled trials used to build the null-model baseline
    /// distribution. Chosen as a balance between statistical stability
    /// (more trials narrows the estimate of the baseline's mean/stdDev)
    /// and staying well within this function's existing "cheap enough to
    /// run synchronously" budget (see `MatchScoreCalculator.evaluate`) --
    /// even on the longest possible rhythm sequences this stays well
    /// under a second on-device.
    static let nullModelTrialCount = 120

    /// How many standard deviations above the shuffled-baseline mean a
    /// real score must reach to be called "statistically significant."
    /// 2.0 corresponds to roughly the 97.7th percentile of a one-tailed
    /// normal distribution (~2.3% false-positive rate if the null
    /// model's approximately-normal assumption holds) -- a standard,
    /// defensible threshold for this kind of screening comparison,
    /// deliberately not pushed higher/stricter given this is a
    /// screening/investigative aid, not a courtroom statistical claim.
    static let significanceZScoreThreshold = 2.0

    /// Compares two vehicles' extracted striation rhythms.
    static func compare(victim: StriationProfile, suspect: StriationProfile) -> ToolMarkComparison {
        guard victim.isDeterminable, suspect.isDeterminable else {
            return .notDeterminable(victim: victim, suspect: suspect)
        }

        let victimSeq = victim.rhythmSequence
        let suspectSeq = suspect.rhythmSequence

        guard let real = bestOverallAlignment(victimSeq: victimSeq, suspectSeq: suspectSeq) else {
            return .notDeterminable(victim: victim, suspect: suspect)
        }
        let realPercent = real.score * 100

        let baseline = nullModelBaseline(victimSeq: victimSeq, suspectSeq: suspectSeq)
        let zScore: Double? = {
            guard let baseline, baseline.stdDev > 0.0001 else { return nil }
            return (realPercent - baseline.mean) / baseline.stdDev
        }()

        return ToolMarkComparison(
            victimProfile: victim,
            suspectProfile: suspect,
            matchScorePercent: realPercent,
            orientationUsed: real.orientation,
            overlapLength: real.overlap,
            nullModelMeanPercent: baseline?.mean,
            nullModelStdDevPercent: baseline?.stdDev,
            zScore: zScore
        )
    }

    /// Tries both orientations (forward/reversed suspect rhythm) against
    /// the victim's rhythm and keeps whichever scores higher -- the
    /// exact same "which orientation" decision `compare` above used to
    /// make inline, factored out so `nullModelBaseline`'s shuffled trials
    /// can run the IDENTICAL search (both orientations, every offset)
    /// that produced the real score. Comparing a real score against a
    /// baseline built from a DIFFERENT, easier search would understate
    /// how much of the real score is just search-driven inflation.
    private static func bestOverallAlignment(
        victimSeq: [Double],
        suspectSeq: [Double]
    ) -> (score: Double, overlap: Int, orientation: ToolMarkOrientation)? {
        let forwardBest = bestAlignment(victimSeq, suspectSeq)
        let reversedBest = bestAlignment(victimSeq, Array(suspectSeq.reversed()))
        switch (forwardBest, reversedBest) {
        case (nil, nil):
            return nil
        case (let f?, nil):
            return (f.score, f.overlap, .sameDirection)
        case (nil, let r?):
            return (r.score, r.overlap, .reversed)
        case (let f?, let r?):
            return f.score >= r.score ? (f.score, f.overlap, .sameDirection) : (r.score, r.overlap, .reversed)
        }
    }

    /// Builds the shuffled-baseline distribution described in the header
    /// note above. `nil` when there aren't enough elements to shuffle
    /// meaningfully, or when too few trials produced any scoreable
    /// alignment at all to trust the resulting mean/stdDev (in which case
    /// `ToolMarkComparison.zScore` stays `nil` and the UI falls back to
    /// its pre-existing, non-statistical summary wording).
    private static func nullModelBaseline(
        victimSeq: [Double],
        suspectSeq: [Double]
    ) -> (mean: Double, stdDev: Double)? {
        guard suspectSeq.count >= 2 else { return nil }
        var rng = SeededGenerator(seed: nullModelSeed(victimSeq, suspectSeq))
        var scores: [Double] = []
        scores.reserveCapacity(nullModelTrialCount)
        for _ in 0..<nullModelTrialCount {
            let shuffled = suspectSeq.shuffled(using: &rng)
            guard let trial = bestOverallAlignment(victimSeq: victimSeq, suspectSeq: shuffled) else { continue }
            scores.append(trial.score * 100)
        }
        // If shuffling destroyed the overlap requirement often enough
        // that fewer than half the trials even produced a score, the
        // baseline itself isn't trustworthy -- report no baseline rather
        // than one built from a biased handful of trials.
        guard scores.count >= nullModelTrialCount / 2 else { return nil }
        let mean = scores.reduce(0, +) / Double(scores.count)
        let variance = scores.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(scores.count)
        return (mean: mean, stdDev: variance.squareRoot())
    }

    /// A small deterministic PRNG (SplitMix64) used ONLY for the
    /// null-model shuffles above. NOTE(AI Developer): deliberately NOT
    /// Swift's `SystemRandomNumberGenerator` -- this needs to produce the
    /// SAME shuffles (and therefore the same baseline/z-score) every time
    /// `compare` is called again on the exact same two profiles, which a
    /// forensic tool must guarantee; a truly random generator would make
    /// re-running analysis on unchanged data silently report a different
    /// significance verdict each time.
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
        mutating func next() -> UInt64 {
            state = state &+ 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    /// Deterministic hash of both rhythm sequences into a seed for
    /// `SeededGenerator`. NOTE(AI Developer): deliberately NOT Swift's
    /// `Hasher`/`hashValue` -- those incorporate a random per-process
    /// seed (hash-flooding protection) by design, so the same two
    /// profiles would hash differently across app launches and silently
    /// break the reproducibility this whole seeded-RNG approach exists
    /// for. This is a plain FNV-1a style mix over each `Double`'s raw bit
    /// pattern instead, which is stable across runs/launches/devices for
    /// the same input values.
    private static func nullModelSeed(_ a: [Double], _ b: [Double]) -> UInt64 {
        var h: UInt64 = 1469598103934665603 // FNV-1a 64-bit offset basis
        func mix(_ value: UInt64) {
            h ^= value
            h = h &* 1099511628211 // FNV-1a 64-bit prime
        }
        for v in a { mix(v.bitPattern) }
        mix(0x9E3779B97F4A7C15) // separator between the two sequences
        for v in b { mix(v.bitPattern) }
        return h
    }

    /// Slides `b` against `a` at every possible offset (in both
    /// directions, since neither sequence has a shared absolute
    /// starting reference -- the two scars were marked completely
    /// independently), and returns the best-scoring overlap of at least
    /// `minimumOverlapLength` elements.
    ///
    /// Per-element similarity uses a relative error (`|a-b| /
    /// max(a,b,epsilon)`), NOT a fixed absolute tolerance -- consistent
    /// with everything else in this file, a fixed absolute tolerance on
    /// a ratio-based signal would silently reintroduce a scale
    /// dependency.
    private static func bestAlignment(_ a: [Double], _ b: [Double]) -> (score: Double, overlap: Int)? {
        guard !a.isEmpty, !b.isEmpty else { return nil }
        var best: (score: Double, overlap: Int)?

        let minOffset = -(b.count - 1)
        let maxOffset = a.count - 1
        for offset in minOffset...maxOffset {
            var similarities: [Double] = []
            for i in 0..<a.count {
                let j = i - offset
                guard j >= 0, j < b.count else { continue }
                let av = a[i], bv = b[j]
                let denom = max(av, bv, 0.0001)
                let relativeError = min(1.0, abs(av - bv) / denom)
                similarities.append(1.0 - relativeError)
            }
            guard similarities.count >= minimumOverlapLength else { continue }
            let meanSimilarity = similarities.reduce(0, +) / Double(similarities.count)
            if best == nil || meanSimilarity > best!.score {
                best = (score: meanSimilarity, overlap: similarities.count)
            }
        }
        return best
    }
}
