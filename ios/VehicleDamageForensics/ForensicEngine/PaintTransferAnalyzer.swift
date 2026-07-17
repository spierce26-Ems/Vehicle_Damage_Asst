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
    ///
    /// NOTE(AI Developer), rewritten 2026-07 as part of the paint-color
    /// reference-normalization fix Sean approved ("yes build it now")
    /// after asking "on the color matching, wont we run into issues
    /// matching OEM if we have poor lighting conditions or bad images
    /// taken?". The investigation into that question found something
    /// bigger than lighting sensitivity: this factor (30% weight, the
    /// highest of the 7) was PERMANENTLY `.unavailable` in every real
    /// case, because the old signature required `victimVehicleColor`/
    /// `suspectVehicleColor` (`Vehicle.colorRGB`) which nothing in the
    /// app ever populated (only the free-text `Vehicle.color` string was
    /// settable via `EditCaseSheet`) -- so the old guard clause always
    /// failed.
    ///
    /// Dropped the `victimVehicleColor`/`suspectVehicleColor` parameters
    /// entirely. The new methodology (per the approved 4-part spec)
    /// doesn't compare against a "nominal vehicle color" at all -- it
    /// compares each vehicle's own `PaintAnalysis`, which is now built
    /// from two SAME-PHOTO tap points (damage area + clean panel, see
    /// `CaptureViewModel.recordPaintReferenceTaps` and
    /// `PaintReferenceMarkerView`):
    ///   - `primaryColorRGB` = this vehicle's own clean-panel reference,
    ///     sampled under the same lighting as its damage-area tap.
    ///   - `foreignPaintRGB` = the color found at the damage-area tap,
    ///     if it looked meaningfully different from the clean panel.
    ///
    /// The reciprocity check is: does the foreign paint found on
    /// vehicle A's damage sit closer (in ΔE2000) to vehicle B's OWN
    /// clean-panel reference than to vehicle A's own clean-panel
    /// reference? That's a relative, same-photo-anchored comparison --
    /// it doesn't require any absolute color-space assumption to hold
    /// across two different photos taken in two different lighting
    /// conditions, which is the specific failure mode Sean's question
    /// identified with the old (never-actually-running) approach.
    /// - Parameters:
    ///   - victim: damage zone on the victim vehicle
    ///   - suspect: damage zone on the suspect vehicle
    /// - Returns: a `FactorScore` keyed to `.paintTransfer`.
    func analyze(
        victim: DamageZone?,
        suspect: DamageZone?
    ) -> FactorScore {
        guard let victim, let suspect,
              let vAnalysis = victim.paintAnalysis,
              let sAnalysis = suspect.paintAnalysis
        else {
            return FactorScore(
                factor: .paintTransfer,
                rawScore: 0,
                dataQuality: .unavailable,
                notes: "Missing paint reference sample data — record a paint reference sample (damage area + clean panel tap) for both vehicles"
            )
        }

        var components: [Double] = []
        var notes: [String] = []

        // 1. Reciprocity, same-photo-relative: foreign paint found on
        // victim's damage should sit closer to suspect's OWN clean-panel
        // reference than to victim's own clean-panel reference — and
        // vice versa. Each side of this check only ever compares colors
        // sampled under consistent lighting relative to *their own*
        // photo's clean reference, never assuming absolute color values
        // are comparable across two different photos/lighting setups.
        if let foreignOnVictim = vAnalysis.foreignPaintRGB {
            let dEToSuspect = ColorAnalysis.deltaE2000(
                ColorAnalysis.rgbToLab(foreignOnVictim),
                ColorAnalysis.rgbToLab(sAnalysis.primaryColorRGB)
            )
            let s = ColorAnalysis.paintScore(deltaE: dEToSuspect)
            components.append(s)
            notes.append(String(format: "Foreign paint on victim ↔ suspect's own paint ΔE=%.2f → %.0f", dEToSuspect, s))
        }

        if let foreignOnSuspect = sAnalysis.foreignPaintRGB {
            let dEToVictim = ColorAnalysis.deltaE2000(
                ColorAnalysis.rgbToLab(foreignOnSuspect),
                ColorAnalysis.rgbToLab(vAnalysis.primaryColorRGB)
            )
            let s = ColorAnalysis.paintScore(deltaE: dEToVictim)
            components.append(s)
            notes.append(String(format: "Foreign paint on suspect ↔ victim's own paint ΔE=%.2f → %.0f", dEToVictim, s))
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
        var quality: DataQuality
        if components.isEmpty {
            rawScore = 0
            quality = .unavailable
            notes.append("No foreign paint detected at either vehicle's damage-area tap relative to its own clean-panel reference")
        } else {
            rawScore = components.reduce(0, +) / Double(components.count)
            quality = (vAnalysis.foreignPaintDetected && sAnalysis.foreignPaintDetected) ? .full : .partial
        }

        // 4. Confidence downgrade: if either vehicle's underlying
        // localized samples looked internally inconsistent (heavy
        // glare/shadow rejection, high residual luminance variance —
        // see `ColorAnalysis.sampleColor`'s outlier handling and
        // `CaptureViewModel.buildPaintAnalysis`'s quality check), don't
        // let this factor claim `.full` confidence even if both vehicles
        // technically show `foreignPaintDetected`. This is the "mark
        // photo-derived paint data `.partial` when lighting/variance
        // signals suggest a bad capture, rather than silently trusting
        // bad data" part of the approved spec.
        if quality != .unavailable, !(vAnalysis.sampleQualityIsGood && sAnalysis.sampleQualityIsGood) {
            quality = .partial
            notes.append("Downgraded: one or both reference samples showed uneven lighting/glare at the tap point")
        }

        return FactorScore(
            factor: .paintTransfer,
            rawScore: rawScore,
            dataQuality: quality,
            notes: notes.joined(separator: "; ")
        )
    }
}
