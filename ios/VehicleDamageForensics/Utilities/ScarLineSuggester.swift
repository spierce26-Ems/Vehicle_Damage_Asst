// ScarLineSuggester.swift
// Vehicle Damage Investigation Assistant
// Proposes a starting scar/scrape line on a freshly-captured photo using
// the Vision framework's contour detector, so the user is confirming and
// nudging a suggestion rather than drawing one entirely from scratch.
//
// NOTE(AI Developer), added 2026-07 per Sean's explicit feedback: "it
// might be too hard to get a user to properly identify the scar
// directions without clear easy to follow directions. it also might
// take a trained eye to really identify the scar directions." The
// line-endpoint-density comparison in `ColorAnalysis.detectScarTaper`
// (which end has more transferred paint) was already fully automated
// before this file existed -- see that function's doc comment. What was
// NOT automated, and is the actual "trained eye" step Sean is describing,
// is drawing the line itself: finding where the visible scar/scrape
// actually starts and ends in a photo that may have low contrast, an odd
// angle, or a subtle scuff. This gives the user a machine-proposed
// starting line for that step, using the same `VNDetectContoursRequest`
// approach already established in `DeformationMatcher.signature(for:)`
// for a different purpose (shape matching) -- reused here for its
// simpler, complementary job of finding the dominant elongated mark
// within the guide box the user aimed at.
//
// Method: run contour detection restricted to the same
// `ScarCaptureCameraService.guideRect` region the user filled during
// aiming, take each contour's simplified polygon approximation, and
// return the two most mutually distant points across all contours as
// the suggested line -- i.e. the long axis of whatever elongated mark
// Vision found, which for a scrape/scar is a reasonable proxy for its
// visible extent. This is a SUGGESTION ONLY: the user can drag either
// endpoint afterward exactly as before (see `ScarCaptureView.lineMarkingArea`'s
// `DragGesture`, which treats a suggested point no differently from a
// manually-placed one). Nothing about `ColorAnalysis.detectScarTaper` or
// `CaptureViewModel.recordScarDirection` changes -- they still operate on
// whatever `lineStart`/`lineEnd` end up being when the user taps Save,
// regardless of whether those points originated from this suggestion or
// a fully manual drag.
import Foundation
import Vision
import UIKit

enum ScarLineSuggester {

    /// Attempts to find a candidate scar/scrape line within `image`,
    /// restricted to the same normalized guide region the user aimed the
    /// camera at during capture.
    /// - Returns: normalized (top-left origin, y-down) start/end points
    ///   matching the same coordinate convention as
    ///   `CapturedPhoto.scarLineStart`/`scarLineEnd`, or `nil` if no
    ///   usable contour was found (photo too low-contrast, scar too
    ///   subtle, etc. -- the caller falls back to an empty manual-draw
    ///   state, exactly as if this feature didn't exist).
    static func suggestLine(in image: UIImage) -> (start: CGPoint, end: CGPoint)? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 2.0
        request.detectsDarkOnLight = true
        request.maximumImageDimension = 1024

        // Vision's `regionOfInterest` uses a normalized, BOTTOM-LEFT-
        // origin, y-UP coordinate space (matching Core Image/Vision
        // convention generally), whereas `ScarCaptureCameraService
        // .guideRect` and every scar-line point elsewhere in this app use
        // TOP-LEFT-origin, y-DOWN normalized coordinates (matching
        // UIKit/SwiftUI convention). This flip is the one place that
        // conversion has to happen going IN; the matching flip on the
        // way OUT is in the point-conversion below.
        let guide = ScarCaptureCameraService.guideRect
        request.regionOfInterest = CGRect(
            x: guide.minX,
            y: 1 - guide.maxY,
            width: guide.width,
            height: guide.height
        )

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        // NOTE(AI Developer): `regionOfInterest` only narrows WHERE Vision
        // searches for contours -- per Vision's standard convention
        // (consistent across observation types: face rects, contours,
        // etc.), returned point/rect coordinates are still normalized to
        // the FULL image, not re-based to the ROI. So no extra ROI-space
        // remapping is needed below beyond the one bottom-left/top-left
        // origin flip already described above.
        guard let observation = request.results?.first as? VNContoursObservation,
              observation.contourCount > 0 else { return nil }

        // Consider top-level contours only (avoid burrowing into nested
        // sub-contours from surface texture/noise), each reduced to a
        // simplified polygon so the most-distant-pair search below stays
        // cheap even on a complex/noisy contour.
        var bestStart: simd_float2?
        var bestEnd: simd_float2?
        var bestDistSquared: Float = 0

        for i in 0..<observation.topLevelContourCount {
            guard let contour = try? observation.contour(at: i) else { continue }
            // NOTE(AI Developer): the correct Vision API is
            // `polygonApproximation(epsilon:)` (Ramer-Douglas-Peucker
            // simplification), not a plain-data `polygonPoints` property
            // -- verified against Apple's Vision docs. Falls back to the
            // raw (denser) point set if simplification ever fails.
            let simplifiedContour = try? contour.polygonApproximation(epsilon: 0.01)
            let polygon = simplifiedContour?.normalizedPoints ?? contour.normalizedPoints
            guard polygon.count > 1 else { continue }

            for a in 0..<polygon.count {
                for b in (a + 1)..<polygon.count {
                    let p1 = polygon[a]
                    let p2 = polygon[b]
                    let dx = p1.x - p2.x
                    let dy = p1.y - p2.y
                    let distSquared = dx * dx + dy * dy
                    if distSquared > bestDistSquared {
                        bestDistSquared = distSquared
                        bestStart = p1
                        bestEnd = p2
                    }
                }
            }
        }

        guard let s = bestStart, let e = bestEnd else { return nil }
        // Flip Vision's bottom-left/y-up points back to this app's
        // top-left/y-down convention.
        let start = CGPoint(x: CGFloat(s.x), y: 1 - CGFloat(s.y))
        let end = CGPoint(x: CGFloat(e.x), y: 1 - CGFloat(e.y))
        return (start, end)
    }
}
