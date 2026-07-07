// PaintTransferAnalyzer.swift
// Vehicle Damage Investigation Assistant
// Computes a 0-100 paint-transfer match score between two damage zones
// using perceptual color distance (CIEDE2000) plus heuristic checks for
// foreign-paint reciprocity and material transfer.

import Foundation
import UIKit

// MARK: - Paint Transfer Analyzer

struct PaintTransferAnalyzer {

    /// Analyze paint transfer between victim and suspect damage zones.
    /// - Parameters:
    ///   - victim: damage zone on the victim vehicle
    ///   - suspect: damage zone on the suspect vehicle
    ///   - victimVehicleColor: nominal color of the victim vehicle (sRGB)
    ///   - suspectVehicleColor: nominal color of the suspect vehicle (sRGB)
    /// - Returns: a `FactorScore` keyed to `.paintTransfer`.
    func analyze(
        victim: DamageZone?,
        suspect: DamageZone?,
        victimVehicleColor: ColorRGB?,
        suspectVehicleColor: ColorRGB?
    ) -> FactorScore {
        guard let victim, let suspect,
              let vAnalysis = victim.paintAnalysis,
              let sAnalysis = suspect.paintAnalysis,
              let vColor = victimVehicleColor,
              let sColor = suspectVehicleColor
        else {
            return FactorScore(
                factor: .paintTransfer,
                rawScore: 0,
                dataQuality: .unavailable,
                notes: "Missing paint analysis data"
            )
        }

        // 1. Reciprocity: victim should carry suspect's paint, and vice versa.
        var components: [Double] = []
        var notes: [String] = []

        if let foreignOnVictim = vAnalysis.foreignPaintRGB {
            let dE = ColorAnalysis.deltaE2000(
                ColorAnalysis.rgbToLab(foreignOnVictim),
                ColorAnalysis.rgbToLab(sColor)
            )
            let s = ColorAnalysis.paintScore(deltaE: dE)
            components.append(s)
            notes.append(String(format: "Foreign paint on victim ↔ suspect color ΔE=%.2f → %.0f", dE, s))
        }

        if let foreignOnSuspect = sAnalysis.foreignPaintRGB {
            let dE = ColorAnalysis.deltaE2000(
                ColorAnalysis.rgbToLab(foreignOnSuspect),
                ColorAnalysis.rgbToLab(vColor)
            )
            let s = ColorAnalysis.paintScore(deltaE: dE)
            components.append(s)
            notes.append(String(format: "Foreign paint on suspect ↔ victim color ΔE=%.2f → %.0f", dE, s))
        }

        // 2. Boost when material transfer (rubber, plastic) corroborates the contact.
        if vAnalysis.hasRubberTransfer || sAnalysis.hasRubberTransfer {
            components.append(85)
            notes.append("Rubber transfer detected (+85)")
        }
        if vAnalysis.hasPlasticFragment || sAnalysis.hasPlasticFragment {
            components.append(80)
            notes.append("Plastic fragments detected (+80)")
        }

        // 3. Layer-count parity sanity check (factory paint ≈ 4 layers).
        let layerDelta = abs(vAnalysis.layerCount - sAnalysis.layerCount)
        if layerDelta > 0 {
            notes.append("Layer count delta: \(layerDelta)")
        }

        let rawScore: Double
        let quality: DataQuality
        if components.isEmpty {
            rawScore = 0
            quality = .unavailable
        } else {
            rawScore = components.reduce(0, +) / Double(components.count)
            quality = (vAnalysis.foreignPaintDetected && sAnalysis.foreignPaintDetected) ? .full : .partial
        }

        return FactorScore(
            factor: .paintTransfer,
            rawScore: rawScore,
            dataQuality: quality,
            notes: notes.joined(separator: "; ")
        )
    }
}
