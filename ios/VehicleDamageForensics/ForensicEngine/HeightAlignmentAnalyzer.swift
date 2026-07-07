// HeightAlignmentAnalyzer.swift
// Vehicle Damage Forensic Matcher
// Compares the height-from-ground of damage zones on both vehicles.
// Two vehicles can only have collided if the bumper / strike heights
// overlap within real-world tolerance (~2 inches).

import Foundation

// MARK: - Height Alignment Analyzer

struct HeightAlignmentAnalyzer {

    /// Compare bumper / damage heights on the victim and suspect.
    /// - Parameter toleranceInches: acceptable variance, default 2.0".
    func analyze(
        victim: DamageZone?,
        suspect: DamageZone?,
        victimBumperHeight: Double?,
        suspectBumperHeight: Double?,
        toleranceInches: Double = 2.0
    ) -> FactorScore {
        var componentScores: [Double] = []
        var notes: [String] = []
        var quality: DataQuality = .full

        // 1. Damage-zone center heights
        if let v = victim, let s = suspect {
            let score = MeasurementHelpers.heightAlignmentScore(
                v.centerHeightInches, s.centerHeightInches,
                toleranceInches: toleranceInches
            )
            componentScores.append(score)
            notes.append(String(format:
                "Damage center: victim %.1f\" vs suspect %.1f\" → %.0f",
                v.centerHeightInches, s.centerHeightInches, score))
        } else {
            quality = .partial
        }

        // 2. Top / bottom edges should also overlap.
        if let v = victim, let s = suspect {
            let topScore = MeasurementHelpers.heightAlignmentScore(
                v.topEdgeHeightInches, s.topEdgeHeightInches, toleranceInches: toleranceInches)
            let botScore = MeasurementHelpers.heightAlignmentScore(
                v.bottomEdgeHeightInches, s.bottomEdgeHeightInches, toleranceInches: toleranceInches)
            componentScores.append(topScore)
            componentScores.append(botScore)
            notes.append(String(format: "Top edge → %.0f, bottom edge → %.0f", topScore, botScore))
        }

        // 3. Bumper-to-bumper height check — corroborating evidence.
        if let vb = victimBumperHeight, let sb = suspectBumperHeight {
            let s = MeasurementHelpers.heightAlignmentScore(vb, sb, toleranceInches: toleranceInches)
            componentScores.append(s)
            notes.append(String(format: "Bumper heights → %.0f", s))
        } else {
            quality = (quality == .full) ? .partial : quality
        }

        guard componentScores.isEmpty == false else {
            return FactorScore(
                factor: .heightAlignment,
                rawScore: 0,
                dataQuality: .unavailable,
                notes: "No height measurements available"
            )
        }

        // Weighted average — central damage carries the most evidentiary weight.
        let raw = componentScores.reduce(0, +) / Double(componentScores.count)

        return FactorScore(
            factor: .heightAlignment,
            rawScore: raw,
            dataQuality: quality,
            notes: notes.joined(separator: "; ")
        )
    }
}
