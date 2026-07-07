// SensorGuidanceOverlay.swift
// Vehicle Damage Investigation Assistant
// Real-time HUD overlay rendering pitch / roll / distance feedback to
// help the operator hold the camera correctly for forensic-grade shots.

import SwiftUI

/// NOTE(AI Developer), fixed 2026-07: this view previously rendered as a
/// single full-screen `VStack { topBar; Spacer(); bottomGuide }`, laid on
/// top of `CaptureCameraView`'s *own separate* bottom-anchored
/// `VStack { Spacer(); statusMessage; shutterButton }` inside a shared
/// `ZStack`. Both stacks independently pin their content to the screen's
/// bottom edge via their own internal `Spacer()`, so their bottom content
/// landed at (roughly) the same vertical position -- visually, the
/// shutter button sat directly on top of the Roll/Pitch readout,
/// truncating the "Roll" label to "Ro...". Confirmed via a real Simulator
/// screenshot, not a guess.
///
/// Fix: split this view into `topBar` (still a top-pinned, independent
/// overlay -- no conflict there, nothing else anchors to the top) and a
/// standalone `SensorLevelBar` view. `CaptureCameraView` now places
/// `SensorLevelBar` *inside its own bottom VStack*, directly above the
/// status message and shutter button, so all three are laid out in a
/// single top-to-bottom VStack with no independent bottom-anchoring --
/// SwiftUI stacks siblings in a VStack without overlap by construction,
/// so this class of bug can't recur here.
struct SensorGuidanceOverlay: View {
    let nextShotType: PhotoType?
    let progress: Double

    var body: some View {
        VStack {
            topBar
            Spacer()
        }
        .padding()
        .allowsHitTesting(false)
    }

    // MARK: Top progress bar + status

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(nextShotType?.displayName ?? "Capture Complete")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white)
            }
            ProgressView(value: progress)
                .tint(.green)
        }
        .padding(12)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Sensor Level Bar (Roll / Pitch readout)

/// Standalone Roll/Pitch level indicator, meant to be placed explicitly by
/// the caller (see `CaptureCameraView`'s bottom VStack) rather than
/// self-anchoring to a screen edge -- see the NOTE on `SensorGuidanceOverlay`
/// above for why.
struct SensorLevelBar: View {
    let sensorData: SensorData

    var body: some View {
        HStack(spacing: 24) {
            levelIndicator(label: "Roll",
                           degrees: sensorData.rollDegrees,
                           threshold: 15)
            levelIndicator(label: "Pitch",
                           degrees: sensorData.pitchDegrees,
                           threshold: 25)
        }
        .padding(12)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
    }

    private func levelIndicator(label: String, degrees: Double, threshold: Double) -> some View {
        let inTolerance = abs(degrees) <= threshold
        return HStack(spacing: 8) {
            Image(systemName: inTolerance ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(inTolerance ? .green : .orange)
            VStack(alignment: .leading) {
                Text(label).font(.caption).foregroundStyle(.white.opacity(0.8))
                Text(String(format: "%+.0f°", degrees))
                    .font(.title3.monospacedDigit().bold())
                    .foregroundStyle(.white)
            }
        }
    }
}

#Preview {
    VStack {
        SensorGuidanceOverlay(
            nextShotType: .closeupDamage,
            progress: 0.4
        )
        Spacer()
        SensorLevelBar(sensorData: SensorData(pitch: 0.1, roll: 0.05, yaw: 0))
            .padding()
    }
    .background(.black)
}
