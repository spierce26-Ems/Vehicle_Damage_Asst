// SensorGuidanceOverlay.swift
// Vehicle Damage Investigation Assistant
// Real-time HUD overlay rendering pitch / roll / distance feedback to
// help the operator hold the camera correctly for forensic-grade shots.

import SwiftUI

struct SensorGuidanceOverlay: View {
    let sensorData: SensorData
    let nextShotType: PhotoType?
    let progress: Double

    var body: some View {
        VStack {
            topBar
            Spacer()
            bottomGuide
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

    // MARK: Bottom level + bubble guide

    private var bottomGuide: some View {
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
    SensorGuidanceOverlay(
        sensorData: SensorData(pitch: 0.1, roll: 0.05, yaw: 0),
        nextShotType: .closeupDamage,
        progress: 0.4
    )
    .background(.black)
}
