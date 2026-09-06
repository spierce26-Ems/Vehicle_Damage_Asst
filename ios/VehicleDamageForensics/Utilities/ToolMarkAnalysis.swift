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

    // NOTE(AI Developer), added 2026-09 for the per-cross-section
    // exclude feature (item #4 of Sean's 5-item plan). Returns a copy of
    // this profile with the cross-sections whose `id` appears in
    // `excludedIDs` removed, so `rhythmSequence` (and therefore every
    // score derived from it) is rebuilt from only the kept probes.
    //
    // Deliberately a pure function returning a NEW profile rather than a
    // mutation: the original, complete profile must stay intact and
    // persisted, because the whole defensibility of this feature rests
    // on being able to show the full and filtered results side by side
    // (see `ToolMarkComparison.filtered`). A destructive filter would
    // make the unfiltered score unrecoverable and turn an auditable
    // examiner judgement into silent data loss.
    func excluding(_ excludedIDs: Set<UUID>) -> StriationProfile {
        guard !excludedIDs.isEmpty else { return self }
        return StriationProfile(crossSections: crossSections.filter { !excludedIDs.contains($0.id) })
    }

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

// MARK: - Per-Cross-Section Exclusion

/// One investigator decision to exclude a single striation cross-section
/// from the tool-mark comparison, with the reason why.
///
/// NOTE(AI Developer), added 2026-09 for item #4 of Sean's 5-item plan
/// ("per-cross-section exclude affordance in the results UI"). A probe
/// can legitimately land on something that isn't the scar at all -- a
/// tape measure edge, a panel gap, a reflection, a patch of dirt -- and
/// an examiner who can see that in the photo should be able to say so
/// rather than having the score silently polluted by it.
///
/// The `reason` is REQUIRED (non-optional, and the UI refuses to commit
/// an empty one). This is the single most important design decision in
/// this feature: excluding data points AFTER seeing the score they
/// produced is textbook post-hoc selection, exactly the bias the
/// null-model layer exists to detect. With only
/// `ToolMarkExtractor.crossSectionCount` (7) probes per photo, an
/// investigator could otherwise exclude their way from a weak score to a
/// strong-looking one with no record of having done so. Requiring a
/// stated reason per exclusion, timestamping it, and mirroring it into
/// the case's chain-of-custody `auditLog` turns that from invisible
/// score-shopping into a documented examiner judgement that opposing
/// counsel can read and challenge -- which is the only form in which
/// this feature is defensible at all.
struct StriationExclusion: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    /// `StriationCrossSection.id` this exclusion refers to.
    var crossSectionID: UUID
    /// Which vehicle's profile the excluded cross-section belongs to --
    /// needed because the two profiles are compared against each other
    /// and a bare `crossSectionID` alone wouldn't say which side to
    /// remove it from.
    var vehicleRole: VehicleRole
    /// Copied from the excluded `StriationCrossSection.positionAlongLine`
    /// at exclusion time so the audit trail and report stay readable
    /// ("the probe at 45% along the scar") even if the underlying
    /// profile is later re-extracted and the ids change.
    var positionAlongLine: Double
    /// Why the investigator excluded it. Required -- see this type's
    /// doc comment for why this is non-optional.
    var reason: String
    var timestamp: Date = Date()

    // NOTE(AI Developer), added 2026-09 per the Tech Lead's required
    // change and Ledger's EVIDENCE_APPENDIX sec.6 spec. THE ONE
    // MITIGATION HERE THAT CANNOT BE RETROFITTED.
    //
    // A legitimate exclusion (the probe wandered onto a tape measure)
    // and p-value shopping (excluding until the number improves) are
    // statistically IDENTICAL -- nothing in the data separates them.
    // The only discriminator is whether the examiner decided BEFORE or
    // AFTER seeing what the exclusion did to the result. That ordering
    // exists only at the instant of the decision; once the case is
    // saved it is gone forever. Every other mitigation on Prism's list
    // (exclusion caps, shopping-aware critical values, higher trial
    // counts) can be added later and applied retroactively. This one
    // cannot, for any case recorded without it.
    //
    // Per Ledger's spec this stores the INSTANT, not a pre-judged
    // before/after label: storing the label would freeze today's
    // interpretation into every saved case, whereas storing the two
    // timestamps records only what is known and lets the rendering rule
    // change later without invalidating history. The ordering is
    // derived at render time -- see `orderingSummary` and
    // `ToolMarkComparison.firstScoreDisplayedAt`.
    //
    // Optional per the persisted-model rule in PROCESS.md sec.1 and
    // Compass's preflight check: a non-optional field on a Codable type
    // throws `keyNotFound` for every case saved before it existed.
    var recordedAt: Date?

    /// One-line rendering for the audit log, the results UI, and the PDF.
    var displaySummary: String {
        String(format: "%@ probe at %.0f%% along the scar -- %@",
               vehicleRole.displayName, positionAlongLine * 100, reason)
    }

    /// Report/audit rendering of the decision ordering, DERIVED from
    /// this exclusion's `recordedAt` and the comparison's
    /// `firstScoreDisplayedAt`. Wording is locked copy -- Ledger's
    /// EVIDENCE_APPENDIX sec.6.3.
    ///
    /// Three states, never two. `nil` on either timestamp means the
    /// ordering was never captured, which is UNKNOWN and not CLEAN:
    /// rendering the "before" line for a `nil` would make an absence
    /// assert the one property this record exists to establish.
    ///
    /// States the ordering and stops -- sec.6.3. No adjudication, no
    /// ranking, no warning styling on the "after" case. "After" is not
    /// evidence of bad faith, and an app that renders it as such
    /// accuses an investigator of something it cannot know. The fact
    /// belongs in the report; the inference belongs to the reader.
    func orderingSummary(firstScoreDisplayedAt: Date?) -> String {
        guard let recordedAt, let shown = firstScoreDisplayedAt else {
            return "Ordering not recorded."
        }
        return recordedAt < shown
            ? "Recorded before any similarity figure was displayed for this comparison."
            : "Recorded after a similarity figure had been displayed for this comparison."
    }
}

// MARK: - Filtered Outcome

/// The tool-mark scores recomputed with the investigator's exclusions
/// applied. Deliberately a SEPARATE, additive record rather than an
/// overwrite of `ToolMarkComparison`'s own score fields.
///
/// NOTE(AI Developer), added 2026-09 for item #4. The full, unfiltered
/// score remains the headline number everywhere (screen and PDF); this
/// sits alongside it, clearly labelled as filtered, with the exclusions
/// that produced it listed. Sean's brief for this item was explicit that
/// exports must show BOTH -- and that is also what makes the feature
/// survivable under scrutiny: a reader can always see what the score was
/// before the examiner's judgement was applied and decide for themselves
/// whether that judgement was reasonable.
///
/// Critically, `nullModelMeanPercent`/`stdDev`/`zScore` here are
/// RECOMPUTED against the filtered rhythm sequences, not inherited from
/// the unfiltered run. A shorter sequence is easier to align by chance,
/// so the baseline for "what would an unrelated scrape score?" shifts
/// upward as probes are removed. Reusing the full run's baseline against
/// a filtered score would systematically overstate significance -- the
/// exact error this whole statistical layer was added to prevent.
struct ToolMarkFilteredOutcome: Codable, Equatable {
    var matchScorePercent: Double?
    var orientationUsed: ToolMarkOrientation?
    var overlapLength: Int?
    var nullModelMeanPercent: Double?
    var nullModelStdDevPercent: Double?
    var zScore: Double?
    /// How many cross-sections remained on each side after filtering --
    /// context for how much data the filtered score rests on.
    var victimCrossSectionsKept: Int
    var suspectCrossSectionsKept: Int

    var isDeterminable: Bool { matchScorePercent != nil }

    // NOTE(AI Developer), 2026-09: there is deliberately NO
    // `isStatisticallySignificant` on the filtered outcome, and this
    // absence is the point -- see `ToolMarkComparison.filteredSummary`.
    //
    // Prism measured the multiple-comparisons cost of exclusion on
    // unrelated pairs, with the null recomputed per filtered view exactly
    // as this feature does it: 3.3% false-positive with no exclusions,
    // 27.5% at best-of-one-exclusion, 57.5% at best-of-two. A 15.6x
    // inflation at two exclusions, and the MEDIAN unrelated pair lands on
    // p=0.05 once shopped. Recomputing the baseline for the filtered
    // subset (which this code does, and which was the right call) fixes
    // the wrong-baseline error but CANNOT fix this one: the reported
    // statistic is no longer "is this score significant" but "is the best
    // score over every subset the examiner could reach significant," and
    // that search needs its own null.
    //
    // The textbook correction is unshippable here. Bonferroni over the
    // reachable views needs alpha=0.0017 at 7 probes / 2 exclusions, but
    // a permutation p-value from `nullModelTrialCount` = 120 trials has a
    // hard floor of 1/121 = 0.0083 -- ABOVE that threshold. So it would
    // not make the test conservative, it would make it impossible to
    // pass, rejecting every true match as well. A shopping-aware critical
    // value (Prism measures the 5th percentile at p <= 0.016) plus an
    // exclusion cap is the real fix, and it needs a calibration table
    // that does not exist yet.
    //
    // Until it does, this type reports similarity and NOT a verdict.
    // Emitting `significant` at the unadjusted threshold would be stating
    // a conclusion we have measured to be wrong more than half the time.
    // The audit trail records that exclusions happened; it cannot record
    // that the number stopped meaning what it says. Same principle as the
    // no-baseline case: when a number can't be defended, say so rather
    // than showing a verdict that reads as though it can.
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
    /// `nullModelMeanPercent`.
    ///
    /// NOTE(AI Developer), 2026-09: retained for continuity of already-
    /// persisted results and as descriptive context, but NO LONGER the
    /// significance test -- see `permutationPValue` below and
    /// `ForensicNullModel.permutationPValue`'s doc comment for why a
    /// z-score was the wrong instrument for a bounded, strongly
    /// left-skewed null distribution. `nil` alongside
    /// `matchScorePercent`.
    var zScore: Double?

    /// NOTE(AI Developer), added 2026-09. Rank-based permutation
    /// p-value: the fraction of shuffled-baseline trials that scored at
    /// least as high as `matchScorePercent`. This is now THE
    /// significance test for this comparison -- it makes no assumption
    /// about the shape of the null distribution, which the previous
    /// z-score did and should not have. `nil` alongside
    /// `matchScorePercent`, or when too few trials produced a scoreable
    /// alignment to trust the baseline.
    var permutationPValue: Double?

    /// How many null-model trials actually produced a scoreable
    /// alignment and therefore back `permutationPValue`. Reported
    /// because it bounds the p-value's resolution: 120 trials cannot
    /// demonstrate anything smaller than p < 1/121.
    var nullTrialCount: Int?

    // NOTE(AI Developer), added 2026-09 for item #4 (per-cross-section
    // exclude). Both fields default to empty/nil so every
    // `ToolMarkComparison` persisted before this feature existed decodes
    // as "no exclusions, no filtered result" -- i.e. exactly the
    // unfiltered behavior it already had. Same non-punitive
    // backward-compat convention as every other optional field here.
    /// The investigator's exclusion decisions, in the order they were
    /// made. Empty means nobody has excluded anything and
    /// `filteredOutcome` is `nil`.
    var exclusions: [StriationExclusion] = []
    /// Scores recomputed with `exclusions` applied. `nil` whenever
    /// `exclusions` is empty. Never replaces the unfiltered fields above
    /// -- see `ToolMarkFilteredOutcome`'s doc comment.
    var filteredOutcome: ToolMarkFilteredOutcome?

    /// NOTE(AI Developer), added 2026-09 per Ledger's EVIDENCE_APPENDIX
    /// sec.6.2. WRITE-ONCE: set the first time any similarity figure for
    /// this pair is rendered to the screen, and never overwritten -- not
    /// on re-render, not on re-entry, not on recompute. It is the
    /// reference instant that makes each exclusion's `recordedAt`
    /// interpretable, so a value that moved would silently re-label
    /// every exclusion already recorded against it.
    ///
    /// Optional both because it is a new field on a persisted model
    /// (PROCESS.md sec.1) and because `nil` is meaningful: no figure has
    /// been displayed yet, so no exclusion can have been made after one.
    var firstScoreDisplayedAt: Date?

    // NOTE(AI Developer), added 2026-09 alongside item #4's `exclusions`
    // field. This custom `init(from:)` is REQUIRED, not stylistic: Swift's
    // synthesized `Codable` conformance does NOT fall back to a stored
    // property's default value when a key is absent from the JSON --
    // for a non-optional property it throws `keyNotFound` instead. So
    // adding `exclusions: [StriationExclusion] = []` above would, on its
    // own, make every `MatchResult` persisted before this feature
    // existed fail to decode, silently breaking every saved case on
    // upgrade. `decodeIfPresent ?? []` restores the intended
    // backward-compatible behavior.
    //
    // (`filteredOutcome` needs no such handling -- optional properties
    // are decoded with `decodeIfPresent` by the synthesized code
    // already, so a missing key correctly yields `nil`. It is listed
    // here only because writing `init(from:)` means decoding every
    // field explicitly.)
    //
    // `encode(to:)` and `CodingKeys` stay auto-synthesized: providing
    // only `init(from:)` does not suppress them, and every implied
    // CodingKey here maps to a real stored property -- unlike
    // `MatchResult`, whose `legacyProbabilityRange` key does not and
    // which therefore needed a hand-written `encode(to:)`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        victimProfile = try c.decode(StriationProfile.self, forKey: .victimProfile)
        suspectProfile = try c.decode(StriationProfile.self, forKey: .suspectProfile)
        matchScorePercent = try c.decodeIfPresent(Double.self, forKey: .matchScorePercent)
        orientationUsed = try c.decodeIfPresent(ToolMarkOrientation.self, forKey: .orientationUsed)
        overlapLength = try c.decodeIfPresent(Int.self, forKey: .overlapLength)
        nullModelMeanPercent = try c.decodeIfPresent(Double.self, forKey: .nullModelMeanPercent)
        nullModelStdDevPercent = try c.decodeIfPresent(Double.self, forKey: .nullModelStdDevPercent)
        zScore = try c.decodeIfPresent(Double.self, forKey: .zScore)
        permutationPValue = try c.decodeIfPresent(Double.self, forKey: .permutationPValue)
        nullTrialCount = try c.decodeIfPresent(Int.self, forKey: .nullTrialCount)
        exclusions = try c.decodeIfPresent([StriationExclusion].self, forKey: .exclusions) ?? []
        filteredOutcome = try c.decodeIfPresent(ToolMarkFilteredOutcome.self, forKey: .filteredOutcome)
        firstScoreDisplayedAt = try c.decodeIfPresent(Date.self, forKey: .firstScoreDisplayedAt)
    }

    /// Memberwise init, restored explicitly because declaring
    /// `init(from:)` above suppresses the compiler-synthesized one.
    init(
        victimProfile: StriationProfile,
        suspectProfile: StriationProfile,
        matchScorePercent: Double? = nil,
        orientationUsed: ToolMarkOrientation? = nil,
        overlapLength: Int? = nil,
        nullModelMeanPercent: Double? = nil,
        nullModelStdDevPercent: Double? = nil,
        zScore: Double? = nil,
        permutationPValue: Double? = nil,
        nullTrialCount: Int? = nil,
        exclusions: [StriationExclusion] = [],
        filteredOutcome: ToolMarkFilteredOutcome? = nil,
        firstScoreDisplayedAt: Date? = nil
    ) {
        self.victimProfile = victimProfile
        self.suspectProfile = suspectProfile
        self.matchScorePercent = matchScorePercent
        self.orientationUsed = orientationUsed
        self.overlapLength = overlapLength
        self.nullModelMeanPercent = nullModelMeanPercent
        self.nullModelStdDevPercent = nullModelStdDevPercent
        self.zScore = zScore
        self.permutationPValue = permutationPValue
        self.nullTrialCount = nullTrialCount
        self.exclusions = exclusions
        self.filteredOutcome = filteredOutcome
        self.firstScoreDisplayedAt = firstScoreDisplayedAt
    }

    var isDeterminable: Bool { matchScorePercent != nil }

    /// `StriationCrossSection.id`s excluded on the given side.
    func excludedIDs(for role: VehicleRole) -> Set<UUID> {
        Set(exclusions.filter { $0.vehicleRole == role }.map(\.crossSectionID))
    }

    /// True once the investigator has excluded at least one probe, i.e.
    /// the UI and PDF must present the full/filtered pair rather than a
    /// single number.
    var hasExclusions: Bool { !exclusions.isEmpty }

    /// `nil` alongside `matchScorePercent` (nothing to test yet).
    /// `true` only when the permutation p-value clears
    /// `ForensicNullModel.significanceLevel` -- i.e. this specific
    /// score is higher than what an unrelated scrape would be expected
    /// to score from this same search, not just a bigger raw number
    /// than some other comparison.
    /// NOTE(AI Developer), 2026-09: now driven by the permutation
    /// p-value rather than the z-score threshold. `nil` means "no
    /// significance test was possible" and must be rendered as such --
    /// never silently treated as either significant or insignificant.
    var isStatisticallySignificant: Bool? {
        guard let permutationPValue else { return nil }
        return permutationPValue < ForensicNullModel.significanceLevel
    }

    /// NOTE(AI Developer), added 2026-09 for the "no bare match %" rule.
    /// The ONLY string any UI or report surface may use as this
    /// comparison's headline number. A raw `matchScorePercent` must
    /// never be rendered on its own: the whole point of the null model
    /// is that 78% means nothing until you know what chance scores, and
    /// a percentage shown by itself invites exactly the misreading Sean
    /// ran into with two unrelated suspects scoring 69% and 78%.
    /// Returns `nil` when there is no score at all, in which case
    /// callers show `summary` and no headline.
    var headlineDisplay: String? {
        guard let score = matchScorePercent else { return nil }
        guard let p = permutationPValue, let trials = nullTrialCount else {
            return String(format: "%.0f%% similarity — significance not testable", score)
        }
        let pText = ForensicNullModel.pValueDisplay(p, trials: trials)
        let verdict = (isStatisticallySignificant == true)
            ? "above chance"
            : "NOT distinguishable from chance"
        return String(format: "%.0f%% similarity — %@, %@", score, pText, verdict)
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
        // NOTE(AI Developer), reworded 2026-09: the significance
        // sentence now quotes the permutation p-value, and the
        // no-baseline case is stated EXPLICITLY rather than falling
        // through to a bare similarity sentence. Previously, when the
        // null model could not be built, this returned `baseSummary`
        // alone -- an unqualified "correlates at 87%" with nothing
        // telling the reader that no significance test backed it. That
        // is the single most misleading thing this app could print, and
        // it is exactly what a uniform striation pattern (which matches
        // almost anything) would produce.
        guard let baselineMean = nullModelMeanPercent,
              let p = permutationPValue,
              let trials = nullTrialCount,
              let significant = isStatisticallySignificant else {
            return baseSummary + " No chance-level baseline could be computed for this pair, so this similarity has NOT been tested against coincidence and must not be read as evidence of a match on its own."
        }
        // NOTE(AI Developer), reworded 2026-09-06 per Ledger's copy
        // review. The count comes first because the sentence frame
        // ("in only ... of N chance trials") promises a count; the
        // p-value rides in parentheses where it does no grammatical
        // work. See `ForensicNullModel.trialCountAtLeastAsExtreme`.
        let pText = ForensicNullModel.pValueDisplay(p, trials: trials)
        let hits = ForensicNullModel.trialCountAtLeastAsExtreme(pValue: p, trials: trials)
        if significant {
            return baseSummary + String(format: " Unrelated scrapes scored this well or better in only %d of %d chance trials (%@; typical chance score ~%.0f%%), so this correlation is unlikely to be coincidence.", hits, trials, pText, baselineMean)
        } else {
            return baseSummary + String(format: " However, unrelated/random spacing patterns scored this well or better in %d of %d chance trials (%@; typical chance score ~%.0f%%) -- this result is NOT statistically distinguishable from random and must not be treated as meaningful evidence on its own.", hits, trials, pText, baselineMean)
        }
    }

    /// Plain-language summary of the FILTERED result, in the same
    /// non-overclaiming register as `summary` above. `nil` when no
    /// exclusions have been made.
    ///
    /// NOTE(AI Developer): deliberately leads with the fact that probes
    /// were excluded, before quoting any number. An investigator reading
    /// this months later (or a reviewer reading the PDF) must not be
    /// able to mistake a filtered score for the raw one, and the honest
    /// framing of a post-hoc filtered score is "here is what remains
    /// after a judgement call was made," never a bare percentage.
    var filteredSummary: String? {
        guard let outcome = filteredOutcome else { return nil }
        let excludedCount = exclusions.count
        let lead = String(
            format: "%d striation probe%@ excluded by the investigator; the figures below are recomputed from the remaining %d victim and %d suspect probe%@.",
            excludedCount, excludedCount == 1 ? "" : "s",
            outcome.victimCrossSectionsKept, outcome.suspectCrossSectionsKept,
            outcome.suspectCrossSectionsKept == 1 ? "" : "s"
        )
        guard let score = outcome.matchScorePercent, let overlap = outcome.overlapLength else {
            return lead + " After those exclusions there is no longer enough striation detail on both scars to produce a comparison at all."
        }
        var text = lead + String(format: " Filtered striation spacing rhythm correlates at %.0f%% across %d overlapping marks.", score, overlap)
        // NOTE(AI Developer), CHANGED 2026-09 per Prism's
        // multiple-comparisons measurement -- see the note on
        // `ToolMarkFilteredOutcome` for the numbers.
        //
        // This block previously reported a significance VERDICT against
        // the recomputed baseline ("still statistically distinguishable
        // from random"). That was wrong, and wrong in the dangerous
        // direction: at two exclusions the median UNRELATED pair reaches
        // p=0.05, so the verdict was measured to be a false positive
        // more than half the time. The baseline recomputation was
        // necessary but not sufficient -- once the examiner picks the
        // subset after seeing the score, the statistic being tested is
        // the best over all reachable subsets, and the unadjusted
        // threshold does not test that.
        //
        // So the verdict is SUPPRESSED whenever exclusions are active,
        // and the suppression is stated rather than silent: an omitted
        // significance line would read as "not yet computed," which is a
        // different and more forgiving claim than "cannot be established
        // for a filtered subset." The recomputed chance baseline is
        // still reported, because it is real and useful context; only
        // the significant/not-significant conclusion is withheld.
        if let baselineMean = outcome.nullModelMeanPercent {
            text += String(format: " Unrelated patterns of this length score around %.0f%% by chance against a baseline recomputed for this shorter sequence.", baselineMean)
        }
        text += " Statistical significance is deliberately NOT reported for a filtered result: because the probes were chosen after seeing the full score, the usual test would treat the best of several possible subsets as if it were a single prediction, which measurably overstates significance. Treat the filtered figure as a similarity measurement, not as evidence of a meaningful correlation, and rely on the unfiltered result above for that judgement."
        // NOTE(AI Developer): the comparison against the unfiltered
        // score is stated explicitly rather than left for the reader to
        // compute, because the direction of that change is the single
        // most diagnostic fact about whether the exclusions were
        // reasonable. Exclusions that happen to raise the score deserve
        // more scrutiny than ones that lower it, and saying so in the
        // report itself is what keeps this feature honest.
        if let full = matchScorePercent, let filtered = outcome.matchScorePercent {
            let delta = filtered - full
            if abs(delta) < 0.5 {
                text += String(format: " This is essentially unchanged from the full %.0f%% score.", full)
            } else {
                text += String(format: " This is %.0f points %@ than the full, unfiltered %.0f%% score.",
                               abs(delta), delta > 0 ? "HIGHER" : "lower", full)
            }
        }
        return text
    }

    static func notDeterminable(victim: StriationProfile = .empty(), suspect: StriationProfile = .empty()) -> ToolMarkComparison {
        ToolMarkComparison(
            victimProfile: victim, suspectProfile: suspect,
            matchScorePercent: nil, orientationUsed: nil, overlapLength: nil,
            nullModelMeanPercent: nil, nullModelStdDevPercent: nil, zScore: nil,
            permutationPValue: nil, nullTrialCount: nil
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
    // chance. The real score is then ranked against that distribution
    // as a permutation p-value (`ToolMarkComparison
    // .permutationPValue`) -- only a real score that chance beat less
    // often than `ForensicNullModel.significanceLevel` is called
    // "statistically significant"
    // (`ToolMarkComparison.isStatisticallySignificant`); otherwise the
    // app now says so explicitly instead of presenting a raw percentage
    // as if it were automatically meaningful.
    //
    // NOTE(AI Developer), 2026-09: this originally used a z-score
    // against the baseline's mean/stdDev; see
    // `significanceZScoreThreshold` below for why that was replaced by
    // the rank-based p-value (short version: its true error rate drifts
    // with rhythm-sequence length). This is exactly the
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
    ///
    /// NOTE(AI Developer), raised from 120 to 1000 on 2026-09-06 after a
    /// resolution audit of the shipped constants. A permutation p-value
    /// from `t` trials is a DISCRETE multiple of 1/(1+t), so the trial
    /// count sets a hard floor on the smallest p-value this test can
    /// express -- and at 120 trials that floor was 1/121 = 0.0083,
    /// only ~6 grid steps below the 0.05 significance level. The verdict
    /// was reachable, so nothing was broken, but 6 steps of resolution
    /// is the same marginal zone that made a separate critical-value
    /// calibration unshippable, and it left the p-value quoted to
    /// investigators quantised far more coarsely than its three printed
    /// decimals imply.
    ///
    /// Measured verdict disagreement between 120 and 2000 trials on
    /// 10-element rhythms: 3.0% of unrelated pairs and 4.0% of true
    /// matches flipped significance verdict purely on trial count. That
    /// is a real if modest instability in a number this app presents as
    /// evidence, and it is entirely avoidable.
    ///
    /// 1000 trials puts the floor at 0.001 (50 grid steps below 0.05)
    /// and costs an estimated ~5-40ms on the longest realistic rhythm
    /// sequences -- still comfortably inside the "cheap enough to run
    /// synchronously" budget this constant was originally chosen
    /// against. Determinism is unaffected: the seed still derives from
    /// the data, so the same two profiles always produce the same
    /// p-value.
    static let nullModelTrialCount = 1000

    /// NOTE(AI Developer), 2026-09: DEPRECATED as the significance
    /// test. Kept only so already-persisted `zScore` values remain
    /// interpretable; the live verdict now comes from
    /// `ForensicNullModel.significanceLevel` applied to a permutation
    /// p-value. The reason is in
    /// `ForensicNullModel.permutationPValue`'s doc comment: this null
    /// distribution is bounded and strongly left-skewed, so z = 2.0
    /// never delivered the ~2.3% tail a normal distribution would give
    /// it.
    @available(*, deprecated, message: "Significance now uses ForensicNullModel.permutationPValue; this constant is retained only to interpret previously-persisted zScore values.")
    static let significanceZScoreThreshold = 2.0

    // NOTE(AI Developer), added 2026-09 per the Tech Lead's accepted
    // mitigations, from Prism's multiple-comparisons analysis. These two
    // caps bound the SEARCH SPACE an examiner can explore, which is a
    // more effective control than any statistical correction applied
    // afterwards: the false-positive inflation comes from the number of
    // reachable subsets, so limiting that number attacks the cause
    // rather than adjusting for the symptom. Measured cost of an
    // unbounded search: 3.3% false-positive at zero exclusions, 27.5% at
    // one, 57.5% at two, and 90% at three on a 10-probe profile.
    /// The most exclusions allowed on one comparison.
    static let maximumExclusions = 2

    /// The fraction of each side's cross-sections that must survive
    /// filtering. Stops the cap above from being circumvented on a
    /// profile with few probes to begin with, where 2 exclusions could
    /// otherwise remove most of the data.
    static let minimumSurvivingProbeFraction = 0.60

    /// Whether one more exclusion is permitted on `comparison` for
    /// `role`. The UI uses this to disable the affordance rather than
    /// letting an examiner make a choice that will be refused.
    static func canExclude(from comparison: ToolMarkComparison, role: VehicleRole) -> Bool {
        guard comparison.exclusions.count < maximumExclusions else { return false }
        let profile = role == .victim ? comparison.victimProfile : comparison.suspectProfile
        let total = profile.crossSections.count
        guard total > 0 else { return false }
        let alreadyExcluded = comparison.excludedIDs(for: role).count
        let survivingAfter = Double(total - alreadyExcluded - 1) / Double(total)
        return survivingAfter >= minimumSurvivingProbeFraction
    }

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

        // NOTE(AI Developer), 2026-09: the baseline now hands back the
        // full trial score distribution, not just its mean/stdDev, so a
        // rank-based p-value can be computed from it. The summary
        // statistics are still reported (they are useful context -- "an
        // unrelated scrape typically scores ~62%" is a sentence an
        // investigator can act on) but they no longer decide the
        // verdict.
        let baseline = nullModelBaseline(victimSeq: victimSeq, suspectSeq: suspectSeq)
        let zScore: Double? = {
            guard let baseline, baseline.stdDev > 0.0001 else { return nil }
            return (realPercent - baseline.mean) / baseline.stdDev
        }()
        let pValue = baseline.flatMap {
            ForensicNullModel.permutationPValue(realScore: realPercent, nullScores: $0.scores)
        }

        return ToolMarkComparison(
            victimProfile: victim,
            suspectProfile: suspect,
            matchScorePercent: realPercent,
            orientationUsed: real.orientation,
            overlapLength: real.overlap,
            nullModelMeanPercent: baseline?.mean,
            nullModelStdDevPercent: baseline?.stdDev,
            zScore: zScore,
            permutationPValue: pValue,
            nullTrialCount: baseline?.scores.count
        )
    }

    // NOTE(AI Developer), added 2026-09 for item #4 (per-cross-section
    // exclude). Applies a set of exclusions to an EXISTING comparison
    // and returns a new comparison carrying both the untouched original
    // scores and a freshly computed `filteredOutcome`.
    //
    // Three properties this deliberately guarantees:
    //
    // 1. The unfiltered score fields are copied through untouched. The
    //    headline number an investigator (or a court) sees can never be
    //    silently rewritten by a later exclusion.
    // 2. The full `victimProfile`/`suspectProfile` are also kept intact,
    //    exclusions included -- so an exclusion is always reversible and
    //    the excluded probe's own data is still on record rather than
    //    deleted. Removing evidence from a forensic file because someone
    //    decided it was noise is not something this app should be able
    //    to do.
    // 3. The null model is re-run against the FILTERED sequences via the
    //    same `compare` path as the real score, so significance is
    //    judged against the right baseline for the shorter sequence.
    //
    /// Recomputes the tool-mark comparison with `exclusions` applied,
    /// preserving the original unfiltered result.
    static func applying(
        exclusions: [StriationExclusion],
        to comparison: ToolMarkComparison
    ) -> ToolMarkComparison {
        var updated = comparison
        updated.exclusions = exclusions

        guard !exclusions.isEmpty else {
            // Clearing the last exclusion returns the comparison to its
            // pristine unfiltered state rather than leaving a stale
            // filtered outcome behind.
            updated.filteredOutcome = nil
            return updated
        }

        let victimFiltered = comparison.victimProfile.excluding(
            Set(exclusions.filter { $0.vehicleRole == .victim }.map(\.crossSectionID))
        )
        let suspectFiltered = comparison.suspectProfile.excluding(
            Set(exclusions.filter { $0.vehicleRole == .suspect }.map(\.crossSectionID))
        )

        // Reuse `compare` wholesale rather than reimplementing the
        // scoring path: it already runs the identical both-orientations
        // search AND builds the matching null-model baseline for
        // whatever sequences it's handed. Any future change to the
        // scoring or baseline logic therefore applies to filtered
        // results automatically, with no chance of the two drifting.
        let refreshed = compare(victim: victimFiltered, suspect: suspectFiltered)

        updated.filteredOutcome = ToolMarkFilteredOutcome(
            matchScorePercent: refreshed.matchScorePercent,
            orientationUsed: refreshed.orientationUsed,
            overlapLength: refreshed.overlapLength,
            nullModelMeanPercent: refreshed.nullModelMeanPercent,
            nullModelStdDevPercent: refreshed.nullModelStdDevPercent,
            zScore: refreshed.zScore,
            victimCrossSectionsKept: victimFiltered.crossSections.count,
            suspectCrossSectionsKept: suspectFiltered.crossSections.count
        )
        return updated
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
    ) -> (mean: Double, stdDev: Double, scores: [Double])? {
        guard suspectSeq.count >= 2 else { return nil }
        // NOTE(AI Developer), 2026-09: generator and seed now come from
        // `ForensicNullModel` so this matcher and the scar-fingerprint
        // matcher draw their shuffles from the identical deterministic
        // source. Behaviour is unchanged for this matcher -- same
        // SplitMix64, same FNV-1a seeding over the same two sequences in
        // the same order.
        var rng = ForensicNullModel.SeededGenerator(
            seed: ForensicNullModel.seed(from: [victimSeq, suspectSeq])
        )
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
        return (mean: mean, stdDev: variance.squareRoot(), scores: scores)
    }

    // NOTE(AI Developer), 2026-09: the deterministic PRNG
    // (`SeededGenerator`) and the FNV-1a seed helper (`nullModelSeed`)
    // that used to live here privately were hoisted verbatim into
    // `ForensicNullModel` (see AlgorithmVersion.swift) so the
    // scar-fingerprint null model added in the same change uses the
    // identical generator instead of a second independently-written
    // one. Same algorithm, same seeding, same reproducibility
    // guarantee -- only the location changed.

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
