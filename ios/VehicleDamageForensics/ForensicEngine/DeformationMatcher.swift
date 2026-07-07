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

    /// Compare deformation patterns between paired damage photos.
    /// - Parameters:
    ///   - victimDamageImage: best closeup damage image of the victim
    ///   - suspectDamageImage: best closeup damage image of the suspect
    /// - Returns: a `FactorScore` for `.deformationPattern`.
    func analyze(victimDamageImage: UIImage?, suspectDamageImage: UIImage?) -> FactorScore {
        guard let v = victimDamageImage, let s = suspectDamageImage,
              let vCG = v.cgImage, let sCG = s.cgImage else {
            return FactorScore(
                factor: .deformationPattern,
                rawScore: 0,
                dataQuality: .unavailable,
                notes: "Missing damage closeup imagery"
            )
        }

        guard let vSig = signature(for: vCG),
              let sSig = signature(for: sCG) else {
            return FactorScore(
                factor: .deformationPattern,
                rawScore: 0,
                dataQuality: .partial,
                notes: "Could not extract contour signatures"
            )
        }

        let similarity = compareSignatures(vSig, sSig)  // 0...1
        return FactorScore(
            factor: .deformationPattern,
            rawScore: similarity * 100.0,
            dataQuality: .full,
            notes: String(format: "Contour cosine similarity: %.3f", similarity)
        )
    }

    // MARK: Signature extraction

    /// Returns a fixed-length numeric signature describing the dominant contour.
    /// We use the Vision contour detector and sample its perimeter at a fixed
    /// number of equally-spaced angles, producing a 36-dimensional descriptor
    /// (10° resolution) that is rotation-stable and scale-stable.
    private func signature(for image: CGImage, samples: Int = 36) -> [Double]? {
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
        return radii
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
