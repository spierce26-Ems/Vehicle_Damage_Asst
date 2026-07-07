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

// MARK: - Sensor Level Bar (visual bubble level + directional cues)

/// Standalone Roll/Pitch level indicator, meant to be placed explicitly by
/// the caller (see `CaptureCameraView`'s bottom VStack) rather than
/// self-anchoring to a screen edge -- see the NOTE on `SensorGuidanceOverlay`
/// above for why.
///
/// NOTE(AI Developer), rewritten 2026-07 per Sean's on-device feedback
/// ("pitch and roll is tough to use, needs to be easier to follow and more
/// intuitive... maybe add better directions or cues"). The old version was
/// two raw "+12°" number readouts -- accurate, but not something you can
/// glance at for half a second while holding a phone up to a damaged
/// bumper. Replaced with a bubble-level-style visual: a crosshair target
/// that a dot needs to be centered in, plus a directional arrow that
/// points the way to move the phone. This mirrors the mental model most
/// people already have from a real carpenter's level / a phone's built-in
/// Measure app level, so it should read as intuitive without instructions.
struct SensorLevelBar: View {
    let sensorData: SensorData

    private let rollThreshold: Double = 15
    private let pitchThreshold: Double = 25

    private var roll: Double { sensorData.rollDegrees }
    private var pitch: Double { sensorData.pitchDegrees }
    private var isLevel: Bool { abs(roll) <= rollThreshold && abs(pitch) <= pitchThreshold }

    var body: some View {
        HStack(spacing: 16) {
            bubbleLevel
            directionCue
        }
        .padding(12)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
    }

    // MARK: Bubble level

    /// A crosshair target (screen-fixed) with a dot that moves off-center
    /// in the direction the phone is tilted. Center the dot in the ring to
    /// be level -- exactly like a real bubble level.
    private var bubbleLevel: some View {
        let size: CGFloat = 64
        // Clamp so the dot stays inside the ring even at extreme tilts;
        // 40° of tilt maps to the ring's outer edge.
        let maxTiltForDisplay: Double = 40
        let dx = CGFloat(max(-1, min(1, roll / maxTiltForDisplay))) * (size / 2 - 8)
        let dy = CGFloat(max(-1, min(1, pitch / maxTiltForDisplay))) * (size / 2 - 8)

        return ZStack {
            Circle()
                .stroke(.white.opacity(0.4), lineWidth: 1.5)
                .frame(width: size, height: size)
            // Crosshair
            Rectangle().fill(.white.opacity(0.3)).frame(width: size, height: 1)
            Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: size)
            // Target tolerance ring
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 1)
                .frame(width: 22, height: 22)
            // The moving bubble/dot
            Circle()
                .fill(isLevel ? .green : .orange)
                .frame(width: 16, height: 16)
                .offset(x: dx, y: dy)
                .animation(.easeOut(duration: 0.15), value: dx)
                .animation(.easeOut(duration: 0.15), value: dy)
        }
        .frame(width: size, height: size)
    }

    // MARK: Direction cue

    /// Plain-language "which way to move" text + arrow, driven by whichever
    /// axis is furthest out of tolerance right now.
    private var directionCue: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: isLevel ? "checkmark.circle.fill" : arrowSymbol)
                    .font(.title3)
                    .foregroundStyle(isLevel ? .green : .orange)
                Text(isLevel ? "Level" : cueText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            Text(String(format: "Roll %+.0f°  •  Pitch %+.0f°", roll, pitch))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    /// Whichever of roll/pitch is furthest out of tolerance drives the cue,
    /// so the operator is never given two conflicting instructions at once.
    private var rollIsWorse: Bool {
        abs(roll) / rollThreshold >= abs(pitch) / pitchThreshold
    }

    private var cueText: String {
        if rollIsWorse && abs(roll) > rollThreshold {
            return roll > 0 ? "Tilt left" : "Tilt right"
        } else if abs(pitch) > pitchThreshold {
            return pitch > 0 ? "Aim down" : "Aim up"
        }
        return "Almost level"
    }

    private var arrowSymbol: String {
        if rollIsWorse && abs(roll) > rollThreshold {
            return roll > 0 ? "arrow.counterclockwise" : "arrow.clockwise"
        } else if abs(pitch) > pitchThreshold {
            return pitch > 0 ? "arrow.down" : "arrow.up"
        }
        return "checkmark.circle"
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
