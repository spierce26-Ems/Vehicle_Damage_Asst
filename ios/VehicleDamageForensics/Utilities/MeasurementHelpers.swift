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

    /// The height difference above which a collision between two damage
    /// zones is treated as physically impossible, ruling the suspect
    /// out. Documented in `ios/reference/ALGORITHM_EXPLAINER.md` §2 as
    /// "> 6\" difference = 0% (rule out suspect)".
    ///
    /// NOTE(AI Developer), added 2026-09. This is expressed as an
    /// absolute number of inches, NOT as a multiple of
    /// `toleranceInches`, and that is deliberate. The rule-out is a
    /// claim about vehicle geometry -- bumper and body-panel strike
    /// heights on real vehicles simply do not differ by more than half a
    /// foot and still contact each other -- so it does not scale with
    /// whatever measurement tolerance a caller happens to pass in.
    /// Tying it to `toleranceInches * 3` would have made the physical
    /// rule-out move whenever someone tuned measurement precision,
    /// which is how the previous linear-to-zero-at-5x-tolerance form
    /// ended up 10 inches wide by accident.
    static let heightRuleOutInches: Double = 6.0

    /// Returns a 0-100 score for height alignment quality.
    ///
    /// NOTE(AI Developer), rewritten 2026-09 (task #10a). The previous
    /// implementation was:
    ///
    ///     if diff >= toleranceInches * 5 { return 0 }
    ///     return max(0, 100 * (1 - diff / (toleranceInches * 5)))
    ///
    /// i.e. linear to zero at 5x tolerance = 10 inches. That contradicted
    /// `ALGORITHM_EXPLAINER.md` §2, which specifies a banded curve with a
    /// HARD RULE-OUT above 6 inches, and it is the most consequential
    /// scoring defect found in this engine: a 6.1-inch height mismatch --
    /// a difference that should exclude a suspect outright -- scored
    /// **39/100** and contributed a third of a 20%-weighted factor's
    /// credit toward implicating them. Measured divergence from the
    /// documented/Python behaviour:
    ///
    ///     diff:   1"    2"    4"    6"   6.1"    8"
    ///     was:   90    80    60    40     39    20
    ///     now:  100   100    75    50      0     0
    ///
    /// Wrong in the direction of implicating someone is the worst
    /// direction for this app to be wrong in, which is why this is
    /// banded exactly as documented rather than "improved" into some
    /// smoother curve of my own invention. The bands come from the
    /// reference, not from me.
    ///
    /// Note the bands are absolute inches per the spec, so
    /// `toleranceInches` now only widens the top ("perfect") band; it
    /// cannot move the rule-out (see `heightRuleOutInches`).
    static func heightAlignmentScore(_ a: Double, _ b: Double, toleranceInches: Double = 2.0) -> Double {
        let diff = abs(a - b)
        if diff > heightRuleOutInches { return 0 }   // rule-out band
        if diff <= toleranceInches { return 100 }    // within forensic tolerance
        if diff <= 4 { return 75 }
        return 50                                    // 4" < diff <= 6"
    }

    /// True when two heights differ by more than the physical rule-out
    /// threshold -- i.e. a collision between these two points is not
    /// physically possible, independent of every other factor.
    ///
    /// NOTE(AI Developer), added 2026-09 (task #10a). Separated from
    /// `heightAlignmentScore` because a rule-out is a different KIND of
    /// statement from a low score, and the two must not be conflated: a
    /// score of 0 gets multiplied by 0.20 and averaged into a composite
    /// that can still come out moderate, whereas a physical
    /// impossibility should be surfaced to the investigator as an
    /// exclusion. See `MatchScoreCalculator.evaluateExclusionRule`.
    static func heightsRuleOut(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) > heightRuleOutInches
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
