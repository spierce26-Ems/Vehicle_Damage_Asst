// ColorAnalysis.swift
// Vehicle Damage Forensic Matcher
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
}
