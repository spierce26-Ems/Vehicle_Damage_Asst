// ColorAnalysis.swift
// Vehicle Damage Investigation Assistant
// RGB ↔ CIE Lab conversion + Delta E formulas (CIE76 + CIEDE2000).
// All math follows the public CIE specifications. Used by
// PaintTransferAnalyzer to produce perceptually-uniform color
// distance metrics that are court-defensible.

import Foundation
import UIKit

// MARK: - Lab Color

struct LabColor: Equatable {
    var L: Double  // 0...100
    var a: Double  // approx -128...127
    var b: Double  // approx -128...127
}

// MARK: - Color Analysis

enum ColorAnalysis {

    // MARK: RGB → XYZ → Lab

    /// Convert a sRGB color (0-255) to CIE Lab using the D65 illuminant.
    static func rgbToLab(_ rgb: ColorRGB) -> LabColor {
        // 1. sRGB → linearized sRGB (gamma decode)
        func linearize(_ c: Double) -> Double {
            let v = c / 255.0
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = linearize(rgb.r)
        let g = linearize(rgb.g)
        let b = linearize(rgb.b)

        // 2. Linear sRGB → XYZ (D65)
        let x = (r * 0.4124564 + g * 0.3575761 + b * 0.1804375) * 100
        let y = (r * 0.2126729 + g * 0.7151522 + b * 0.0721750) * 100
        let z = (r * 0.0193339 + g * 0.1191920 + b * 0.9503041) * 100

        // 3. XYZ → Lab using D65 reference white
        let xRef = 95.047, yRef = 100.000, zRef = 108.883
        func f(_ t: Double) -> Double {
            t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t) + (16.0 / 116.0)
        }
        let fx = f(x / xRef)
        let fy = f(y / yRef)
        let fz = f(z / zRef)

        let L = (116 * fy) - 16
        let a = 500 * (fx - fy)
        let bL = 200 * (fy - fz)
        return LabColor(L: L, a: a, b: bL)
    }

    // MARK: Delta E

    /// CIE76 Delta E — simple Euclidean distance in Lab. Fast, less accurate.
    static func deltaE76(_ a: LabColor, _ b: LabColor) -> Double {
        let dL = a.L - b.L
        let da = a.a - b.a
        let db = a.b - b.b
        return sqrt(dL * dL + da * da + db * db)
    }

    /// CIEDE2000 — modern perceptually-uniform Delta E.
    /// Implementation follows Sharma, Wu, Dalal (2005).
    static func deltaE2000(_ c1: LabColor, _ c2: LabColor,
                           kL: Double = 1, kC: Double = 1, kH: Double = 1) -> Double {
        let avgL = (c1.L + c2.L) / 2.0
        let C1 = sqrt(c1.a * c1.a + c1.b * c1.b)
        let C2 = sqrt(c2.a * c2.a + c2.b * c2.b)
        let avgC = (C1 + C2) / 2.0

        let G = 0.5 * (1 - sqrt(pow(avgC, 7) / (pow(avgC, 7) + pow(25.0, 7))))

        let a1p = c1.a * (1 + G)
        let a2p = c2.a * (1 + G)

        let C1p = sqrt(a1p * a1p + c1.b * c1.b)
        let C2p = sqrt(a2p * a2p + c2.b * c2.b)
        let avgCp = (C1p + C2p) / 2.0

        func toDeg(_ r: Double) -> Double { r * 180 / .pi }
        func toRad(_ d: Double) -> Double { d * .pi / 180 }

        var h1p = toDeg(atan2(c1.b, a1p)); if h1p < 0 { h1p += 360 }
        var h2p = toDeg(atan2(c2.b, a2p)); if h2p < 0 { h2p += 360 }

        let dhp: Double = {
            if C1p * C2p == 0 { return 0 }
            let diff = h2p - h1p
            if abs(diff) <= 180 { return diff }
            return diff > 180 ? diff - 360 : diff + 360
        }()

        let dLp = c2.L - c1.L
        let dCp = C2p - C1p
        let dHp = 2 * sqrt(C1p * C2p) * sin(toRad(dhp) / 2)

        let avghp: Double = {
            if C1p * C2p == 0 { return h1p + h2p }
            let diff = abs(h1p - h2p)
            if diff <= 180 { return (h1p + h2p) / 2 }
            return (h1p + h2p + (h1p + h2p < 360 ? 360 : -360)) / 2
        }()

        let T = 1
            - 0.17 * cos(toRad(avghp - 30))
            + 0.24 * cos(toRad(2 * avghp))
            + 0.32 * cos(toRad(3 * avghp + 6))
            - 0.20 * cos(toRad(4 * avghp - 63))

        let dTheta = 30 * exp(-pow((avghp - 275) / 25, 2))
        let Rc = 2 * sqrt(pow(avgCp, 7) / (pow(avgCp, 7) + pow(25.0, 7)))
        let Sl = 1 + (0.015 * pow(avgL - 50, 2)) / sqrt(20 + pow(avgL - 50, 2))
        let Sc = 1 + 0.045 * avgCp
        let Sh = 1 + 0.015 * avgCp * T
        let Rt = -sin(toRad(2 * dTheta)) * Rc

        let term1 = dLp / (kL * Sl)
        let term2 = dCp / (kC * Sc)
        let term3 = dHp / (kH * Sh)
        return sqrt(term1 * term1
                    + term2 * term2
                    + term3 * term3
                    + Rt * term2 * term3)
    }

    // MARK: Score mapping

    /// Map a CIEDE2000 Delta E to a 0-100 paint match score.
    /// ΔE ≤ 1 = imperceptible match (100), ΔE ≥ 25 = unrelated colors (0).
    static func paintScore(deltaE: Double) -> Double {
        let clamped = max(0, min(25, deltaE))
        return (1 - clamped / 25.0) * 100.0
    }

    // MARK: Dominant color extraction

    /// Compute the average color of an image. A real implementation would use
    /// k-means clustering; this average is good enough for an MVP.
    ///
    /// NOTE(AI Developer): Confirmed via exhaustive grep (2026-07, during
    /// the paint-color reference-normalization fix) that this function
    /// has ZERO call sites anywhere in the app -- it was dead code.
    /// Left in place rather than deleted since it's still a reasonable
    /// "whole image" utility that something else might want later, but
    /// `PaintReferenceMarkerView`'s tap-to-sample flow uses the new
    /// `sampleColor(from:at:radiusFraction:)` below instead, which is the
    /// function that actually feeds real paint-color data now.
    static func averageColor(of image: UIImage) -> ColorRGB? {
        guard let cg = image.cgImage else { return nil }
        let width = 1, height = 1
        var pixel: [UInt8] = [0, 0, 0, 0]
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: &pixel,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: cs,
            bitmapInfo: info
        ) else { return nil }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return ColorRGB(r: Double(pixel[0]), g: Double(pixel[1]), b: Double(pixel[2]))
    }

    // MARK: Localized reference-point sampling

    /// A single localized color sample plus the internal variance/outlier
    /// stats needed to judge whether the sample looks trustworthy.
    struct LocalSample {
        var color: ColorRGB
        /// Fraction (0-1) of pixels within the sample radius that were
        /// discarded as likely specular highlight or shadow before
        /// averaging the rest. High values mean the tap landed somewhere
        /// with a lot of glare/shadow contamination even after rejection.
        var rejectedFraction: Double
        /// Standard deviation of luminance across the *kept* pixels.
        /// High variance among the pixels that supposedly survived
        /// rejection suggests a genuinely inconsistent/unreliable patch
        /// (e.g. straddling a paint edge, dirt, or a reflection that
        /// wasn't extreme enough to be clipped outright).
        var luminanceStdDev: Double
    }

    /// Sample a small localized patch of `image` centered on `normalizedPoint`
    /// (0-1, 0-1, same convention as `Vehicle.impactTapPoint`), rejecting
    /// likely specular-highlight and shadow pixels before averaging the rest.
    ///
    /// NOTE(AI Developer), added 2026-07 as the core extraction step of the
    /// paint-color reference-normalization fix. This replaces the old
    /// (dead) whole-image `averageColor(of:)` for paint-transfer analysis:
    /// averaging an entire vehicle photo mixes damaged paint, clean paint,
    /// chrome, shadows, and background into one meaningless color, and
    /// gave no way to compare "the foreign paint smear" against "this
    /// vehicle's own clean panel" specifically. Instead this samples only
    /// a small radius (`radiusFraction` of the image's shorter dimension)
    /// around the exact point the user tapped, so it reflects the actual
    /// patch of interest.
    ///
    /// Highlight/shadow rejection: within the sampled patch, pixels whose
    /// luminance falls in the top/bottom `outlierPercentile` of the
    /// patch's own luminance distribution are discarded before averaging
    /// the remaining RGB values. A glossy/wet vehicle panel photographed
    /// outdoors routinely has small blown-out specular highlights and deep
    /// shadow creases within a few dozen pixels of any tap point; blending
    /// those extremes into the average would pull the sampled color away
    /// from the panel's true hue toward "washed out" or "near-black" --
    /// exactly the lighting-sensitivity failure mode Sean asked about.
    /// Percentile-based clipping (rather than a fixed brightness
    /// threshold) adapts to each photo's own exposure instead of assuming
    /// a universal "too bright"/"too dark" cutoff.
    ///
    /// - Parameters:
    ///   - image: the full captured photo to sample from.
    ///   - normalizedPoint: 0-1/0-1 tap location within the image.
    ///   - radiusFraction: sample radius as a fraction of the image's
    ///     shorter pixel dimension. Default 0.02 (~2%) targets roughly a
    ///     20-30px radius on a typical ~1200-1500px-shortest-side photo --
    ///     small enough to stay within a single paint patch, large enough
    ///     to average out sensor noise and JPEG compression artifacts.
    ///   - outlierPercentile: fraction of the darkest AND fraction of the
    ///     brightest pixels (by luminance) to discard before averaging.
    ///     Default 0.15 (discard the bottom 15% and top 15% by luminance,
    ///     keep the middle 70%).
    /// - Returns: `nil` if the image has no pixel data or the sample patch
    ///   is degenerate (zero pixels).
    static func sampleColor(
        from image: UIImage,
        at normalizedPoint: CGPoint,
        radiusFraction: Double = 0.02,
        outlierPercentile: Double = 0.15
    ) -> LocalSample? {
        guard let cg = image.cgImage else { return nil }
        let pixelWidth = cg.width
        let pixelHeight = cg.height
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let shortSide = Double(min(pixelWidth, pixelHeight))
        let radiusPx = max(6.0, shortSide * radiusFraction)

        let centerX = Double(normalizedPoint.x) * Double(pixelWidth)
        let centerY = Double(normalizedPoint.y) * Double(pixelHeight)

        let minX = max(0, Int((centerX - radiusPx).rounded(.down)))
        let maxX = min(pixelWidth - 1, Int((centerX + radiusPx).rounded(.up)))
        let minY = max(0, Int((centerY - radiusPx).rounded(.down)))
        let maxY = min(pixelHeight - 1, Int((centerY + radiusPx).rounded(.up)))
        guard maxX >= minX, maxY >= minY else { return nil }

        let cropWidth = maxX - minX + 1
        let cropHeight = maxY - minY + 1

        // Decode just the crop rectangle's pixels directly, rather than
        // rendering the full-resolution image into a CGContext -- avoids
        // materializing a second full-size bitmap on top of whatever
        // already holds `image` in memory (same "don't decode more than
        // you need" discipline as `MatchScoreCalculator.bestDamageImage`).
        guard let cropped = cg.cropping(to: CGRect(x: minX, y: minY, width: cropWidth, height: cropHeight)) else {
            return nil
        }

        var pixelData = [UInt8](repeating: 0, count: cropWidth * cropHeight * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: &pixelData,
            width: cropWidth,
            height: cropHeight,
            bitsPerComponent: 8,
            bytesPerRow: cropWidth * 4,
            space: cs,
            bitmapInfo: info
        ) else { return nil }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: cropWidth, height: cropHeight))

        // Only consider pixels actually within the circular sample radius
        // (the crop rect above is a bounding square around the circle),
        // so corners of the square don't quietly widen the effective
        // sample area.
        struct Px { var r: Double; var g: Double; var b: Double; var lum: Double }
        var pixels: [Px] = []
        pixels.reserveCapacity(cropWidth * cropHeight)
        for y in 0..<cropHeight {
            for x in 0..<cropWidth {
                let imgX = Double(minX + x)
                let imgY = Double(minY + y)
                let dx = imgX - centerX
                let dy = imgY - centerY
                guard (dx * dx + dy * dy) <= (radiusPx * radiusPx) else { continue }
                let offset = (y * cropWidth + x) * 4
                let r = Double(pixelData[offset])
                let g = Double(pixelData[offset + 1])
                let b = Double(pixelData[offset + 2])
                // Standard relative-luminance weighting (ITU-R BT.601).
                let lum = 0.299 * r + 0.587 * g + 0.114 * b
                pixels.append(Px(r: r, g: g, b: b, lum: lum))
            }
        }
        guard !pixels.isEmpty else { return nil }

        let sortedByLum = pixels.sorted { $0.lum < $1.lum }
        let n = sortedByLum.count
        let clipCount = Int((Double(n) * outlierPercentile).rounded())
        let kept: [Px]
        if n > 2 * clipCount, clipCount > 0 {
            kept = Array(sortedByLum[clipCount..<(n - clipCount)])
        } else {
            // Sample too small to safely clip both ends without
            // discarding everything -- use all pixels rather than
            // returning nothing.
            kept = sortedByLum
        }

        guard !kept.isEmpty else { return nil }
        let avgR = kept.reduce(0.0) { $0 + $1.r } / Double(kept.count)
        let avgG = kept.reduce(0.0) { $0 + $1.g } / Double(kept.count)
        let avgB = kept.reduce(0.0) { $0 + $1.b } / Double(kept.count)

        let meanLum = kept.reduce(0.0) { $0 + $1.lum } / Double(kept.count)
        let variance = kept.reduce(0.0) { $0 + pow($1.lum - meanLum, 2) } / Double(kept.count)
        let stdDev = sqrt(variance)

        return LocalSample(
            color: ColorRGB(r: avgR, g: avgG, b: avgB),
            rejectedFraction: Double(n - kept.count) / Double(n),
            luminanceStdDev: stdDev
        )
    }
}
