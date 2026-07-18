// DeformationMatcher.swift
// Vehicle Damage Investigation Assistant
// Extracts damage-shape signatures using the Vision framework
// (VNDetectContoursRequest) and scores how closely two contours match.
// Like puzzle-piece matching: an outward-deformation on the suspect
// should mirror an inward-deformation on the victim.

import Foundation
import Vision
import CoreImage
import UIKit

// MARK: - Deformation Matcher

struct DeformationMatcher {

    /// NOTE(AI Developer), added 2026-07 per Sean's request ("we need to
    /// show that we did something with the images in the report, not
    /// just show the pictures uploaded"). Bundles the scoring result
    /// together with the raw Vision-detected contour boundary
    /// (`normalizedPoints`, in Vision's own bottom-left-origin 0-1
    /// coordinate space) for BOTH vehicles, so `MatchScoreCalculator` can
    /// persist the contour once, here, at the same moment it's already
    /// paying the cost of running `VNDetectContoursRequest` -- and
    /// `PDFReportGenerator` can later draw that exact contour as a
    /// visible outline over the damage photo without ever re-running
    /// Vision at PDF-render/share time. Re-running Vision on the main
    /// thread inside `PDFReportGenerator.generate()` (called
    /// synchronously, not `Task`-wrapped, from `AnalysisViewModel
    /// .generateReport()`) would risk exactly the kind of UI-thread
    /// hang/memory-pressure incident Sean has already hit twice on this
    /// pipeline -- computing once and persisting avoids that risk
    /// entirely rather than trading it for a "nicer" report.
    struct DeformationResult {
        var factorScore: FactorScore
        var victimContourNormalizedPoints: [CGPoint]?
        var suspectContourNormalizedPoints: [CGPoint]?
    }

    /// Compare deformation patterns between paired damage photos.
    /// - Parameters:
    ///   - victimDamageImage: best closeup damage image of the victim,
    ///     already downsampled by the caller (see `MatchScoreCalculator
    ///     .bestDamageImage(in:)` — decoded directly at reduced size via
    ///     ImageIO rather than as a full-resolution `UIImage`, to avoid
    ///     an unnecessary ~48MB-per-image decode at analysis time).
    ///   - suspectDamageImage: best closeup damage image of the suspect,
    ///     same as above.
    /// - Returns: a `DeformationResult` — `factorScore` for
    ///   `.deformationPattern` plus each vehicle's detected contour
    ///   outline (`nil` when that vehicle's contour couldn't be
    ///   extracted, mirroring the existing "missing/inconclusive data is
    ///   never a fabricated result" convention used throughout this
    ///   engine).
    func analyze(victimDamageImage: CGImage?, suspectDamageImage: CGImage?) -> DeformationResult {
        guard let vCG = victimDamageImage, let sCG = suspectDamageImage else {
            return DeformationResult(factorScore: FactorScore(
                factor: .deformationPattern,
                rawScore: 0,
                dataQuality: .unavailable,
                notes: "Missing damage closeup imagery"
            ))
        }

        guard let vExtraction = extractContour(from: vCG),
              let sExtraction = extractContour(from: sCG) else {
            return DeformationResult(factorScore: FactorScore(
                factor: .deformationPattern,
                rawScore: 0,
                dataQuality: .partial,
                notes: "Could not extract contour signatures"
            ))
        }

        let similarity = compareSignatures(vExtraction.signature, sExtraction.signature)  // 0...1
        return DeformationResult(
            factorScore: FactorScore(
                factor: .deformationPattern,
                rawScore: similarity * 100.0,
                dataQuality: .full,
                notes: String(format: "Contour cosine similarity: %.3f", similarity)
            ),
            victimContourNormalizedPoints: vExtraction.normalizedPoints,
            suspectContourNormalizedPoints: sExtraction.normalizedPoints
        )
    }

    // MARK: Contour extraction

    /// The dominant-contour result: a fixed-length numeric `signature`
    /// (used for scoring — see `compareSignatures`) plus the actual
    /// boundary `normalizedPoints` Vision detected (used for drawing —
    /// see `PDFReportGenerator.drawContourOverlay`). Thinned to at most
    /// `maxOverlayPoints` points before being handed back so a very
    /// high-detail contour doesn't bloat persisted case JSON or PDF draw
    /// time for no visible benefit at report scale.
    struct ContourExtraction {
        var signature: [Double]
        var normalizedPoints: [CGPoint]
    }

    private static let maxOverlayPoints = 200

    /// Returns a fixed-length numeric signature describing the dominant contour.
    /// We use the Vision contour detector and sample its perimeter at a fixed
    /// number of equally-spaced angles, producing a 36-dimensional descriptor
    /// (10° resolution) that is rotation-stable and scale-stable.
    ///
    /// NOTE(AI Developer), widened from `private` and renamed from
    /// `signature(for:)` 2026-07 alongside the `DeformationResult`
    /// change above -- same Vision call, now also returns the raw
    /// contour boundary (not just the derived signature) so it doubles
    /// as the one place that runs `VNDetectContoursRequest` for both
    /// scoring and report-overlay purposes.
    func extractContour(from image: CGImage, samples: Int = 36) -> ContourExtraction? {
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 1.5
        request.maximumImageDimension = 1024

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        guard let observation = request.results?.first as? VNContoursObservation,
              observation.contourCount > 0 else { return nil }

        // Take the largest-perimeter top-level contour.
        // NOTE(AI Developer): The original code did `try? observation.topLevelContours[i]`.
        // Per Apple's docs (developer.apple.com/documentation/vision/vncontoursobservation),
        // `topLevelContours` is a plain, non-throwing `[VNContour]` array property —
        // subscripting it doesn't throw, so wrapping it in `try?` misuses the API and
        // will not compile as written. The actual throwing/bounds-checked accessor is
        // the separate method `contour(at:) throws -> VNContour`. Switched to that.
        var largest: VNContour?
        var bestLen: Double = 0
        for i in 0..<observation.topLevelContourCount {
            guard let c = try? observation.contour(at: i) else { continue }
            let len = perimeter(of: c.normalizedPoints)
            if len > bestLen {
                bestLen = len
                largest = c
            }
        }
        guard let contour = largest else { return nil }

        // Sample radii from the centroid at `samples` evenly-spaced angles.
        let pts = contour.normalizedPoints
        let cx = pts.map { Double($0.x) }.reduce(0, +) / Double(pts.count)
        let cy = pts.map { Double($0.y) }.reduce(0, +) / Double(pts.count)

        var radii: [Double] = Array(repeating: 0, count: samples)
        for p in pts {
            let dx = Double(p.x) - cx
            let dy = Double(p.y) - cy
            let theta = atan2(dy, dx) + .pi  // 0...2π
            let bin = min(samples - 1, Int(theta / (2 * .pi) * Double(samples)))
            let r = sqrt(dx * dx + dy * dy)
            radii[bin] = max(radii[bin], r)
        }

        // Normalize so the signature is scale-invariant.
        if let maxR = radii.max(), maxR > 0 {
            radii = radii.map { $0 / maxR }
        }

        // Thin the boundary points for the overlay (report-drawing use
        // only — the `radii` signature above was already derived from
        // the FULL-resolution `pts`, so thinning here has zero effect on
        // the actual similarity score).
        var overlayPoints = pts.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        if overlayPoints.count > Self.maxOverlayPoints {
            let stride = Double(overlayPoints.count) / Double(Self.maxOverlayPoints)
            overlayPoints = (0..<Self.maxOverlayPoints).map { overlayPoints[Int(Double($0) * stride)] }
        }

        return ContourExtraction(signature: radii, normalizedPoints: overlayPoints)
    }

    private func perimeter(of pts: [simd_float2]) -> Double {
        guard pts.count > 1 else { return 0 }
        var total: Double = 0
        for i in 0..<pts.count {
            let a = pts[i]
            let b = pts[(i + 1) % pts.count]
            let dx = Double(a.x - b.x)
            let dy = Double(a.y - b.y)
            total += sqrt(dx * dx + dy * dy)
        }
        return total
    }

    // MARK: Signature comparison

    /// Cosine similarity, then rotated to maximize alignment between the two
    /// signatures. Returns a value in 0...1.
    private func compareSignatures(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var best: Double = 0
        for shift in 0..<a.count {
            let rotated = Array(b[shift...]) + Array(b[..<shift])
            let sim = cosineSimilarity(a, rotated)
            best = max(best, sim)
        }
        return max(0, best)
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        var dot: Double = 0, magA: Double = 0, magB: Double = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (sqrt(magA) * sqrt(magB))
    }
}
