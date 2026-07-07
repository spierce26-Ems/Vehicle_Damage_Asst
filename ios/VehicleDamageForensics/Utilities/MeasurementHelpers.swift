// MeasurementHelpers.swift
// Vehicle Damage Investigation Assistant
// Unit conversions and measurement utilities. Forensic reports must be
// presented in both metric and imperial units, with preserved precision.

import Foundation

// MARK: - Length

enum LengthUnit: String, CaseIterable {
    case millimeters, centimeters, meters
    case inches, feet

    var abbreviation: String {
        switch self {
        case .millimeters: return "mm"
        case .centimeters: return "cm"
        case .meters: return "m"
        case .inches: return "in"
        case .feet: return "ft"
        }
    }
}

enum MeasurementHelpers {

    // MARK: Constants

    static let mmPerInch = 25.4
    static let cmPerInch = 2.54
    static let inchesPerFoot = 12.0

    // MARK: Conversions

    static func inchesToCM(_ inches: Double) -> Double { inches * cmPerInch }
    static func cmToInches(_ cm: Double) -> Double { cm / cmPerInch }
    static func mmToInches(_ mm: Double) -> Double { mm / mmPerInch }
    static func inchesToMM(_ inches: Double) -> Double { inches * mmPerInch }
    static func feetToInches(_ feet: Double) -> Double { feet * inchesPerFoot }
    static func inchesToFeet(_ inches: Double) -> Double { inches / inchesPerFoot }

    /// Convert any value between two `LengthUnit`s.
    static func convert(_ value: Double, from: LengthUnit, to: LengthUnit) -> Double {
        // Normalize to millimeters first
        let inMM: Double
        switch from {
        case .millimeters: inMM = value
        case .centimeters: inMM = value * 10
        case .meters:      inMM = value * 1000
        case .inches:      inMM = value * mmPerInch
        case .feet:        inMM = value * inchesPerFoot * mmPerInch
        }
        // Then convert to the target unit
        switch to {
        case .millimeters: return inMM
        case .centimeters: return inMM / 10
        case .meters:      return inMM / 1000
        case .inches:      return inMM / mmPerInch
        case .feet:        return inMM / mmPerInch / inchesPerFoot
        }
    }

    // MARK: Formatting

    /// Format a length in inches with a paired metric value, e.g. `38.0" (96.5cm)`.
    static func formatInchesWithMetric(_ inches: Double, decimals: Int = 1) -> String {
        let cm = inchesToCM(inches)
        return String(format: "%.\(decimals)f\" (%.\(decimals)fcm)", inches, cm)
    }

    /// Format a length in millimeters with a paired imperial value, e.g. `120mm (4.7")`.
    static func formatMMWithImperial(_ mm: Double, decimals: Int = 1) -> String {
        let inches = mmToInches(mm)
        return String(format: "%.\(decimals)fmm (%.\(decimals)f\")", mm, inches)
    }

    // MARK: Tolerance comparisons

    /// True if two heights agree within a tolerance (default 2 inches).
    static func heightsAlign(_ a: Double, _ b: Double, toleranceInches: Double = 2.0) -> Bool {
        abs(a - b) <= toleranceInches
    }

    /// Returns a 0-100 score for height alignment quality.
    static func heightAlignmentScore(_ a: Double, _ b: Double, toleranceInches: Double = 2.0) -> Double {
        let diff = abs(a - b)
        if diff >= toleranceInches * 5 { return 0 }
        return max(0, 100 * (1 - diff / (toleranceInches * 5)))
    }

    // MARK: Geometry

    /// Compute the included angle (degrees) between two 2-D vectors at the origin.
    static func angleBetween(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
        let dot = ax * bx + ay * by
        let magA = sqrt(ax * ax + ay * ay)
        let magB = sqrt(bx * bx + by * by)
        guard magA > 0, magB > 0 else { return 0 }
        let cosT = max(-1.0, min(1.0, dot / (magA * magB)))
        return acos(cosT) * 180.0 / .pi
    }
}
