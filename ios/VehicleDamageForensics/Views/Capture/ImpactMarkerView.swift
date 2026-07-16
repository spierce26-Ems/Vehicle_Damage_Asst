// ImpactMarkerView.swift
// Vehicle Damage Investigation Assistant
// Required capture step: tap the damage location on a top-down vehicle
// silhouette, then set the vehicle's direction of travel at impact
// (live compass or manual dial). Together these feed
// `Vehicle.impactBearingDegrees`, which is what actually powers the
// "Impact Geometry" correlation factor.
//
// NOTE(AI Developer), added 2026-07 per Sean's request ("should we
// identify the location of the damage on each vehicle and always
// identify the direction of traveling at impact... to help correlating
// data") and his explicit answers on the follow-up questions:
// (1) tap-anywhere-on-outline location (not a fixed 8-zone picker),
// (2) this step is REQUIRED, not skippable, for both vehicles.
// See `Vehicle.impactTapPoint`/`directionOfTravelDegrees`/
// `impactBearingDegrees` for the data model and the geometry rationale,
// and `CaptureViewModel.recordImpactProfile` for how this view's result
// is persisted.

import SwiftUI

struct ImpactMarkerView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @StateObject private var heading = HeadingProvider()
    @Environment(\.dismiss) private var dismiss

    @State private var tapPoint: CGPoint?
    @State private var directionDegrees: Double = 0
    @State private var useLiveHeading: Bool = true
    @State private var isSaving = false

    private var vehicle: Vehicle {
        switch viewModel.captureRole {
        case .victim: return viewModel.forensicCase.victimVehicle
        case .suspect: return viewModel.forensicCase.suspectVehicle ?? Vehicle(role: .suspect)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Tap the point of impact")
                        .font(.headline)
                    Text("Tap the top-down outline below at the spot where this vehicle was hit.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ImpactSilhouetteView(tapPoint: $tapPoint)
                        .frame(height: 260)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 12) {
                    Text("2. Direction of travel at impact")
                        .font(.headline)
                    Text("Which way was this vehicle heading the moment it was hit?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // NOTE(AI Developer): Two entry modes per the design
                    // discussion with Sean -- live compass only makes
                    // sense when physically at the scene; the manual
                    // dial covers "uploaded after the fact"/"no longer
                    // near the vehicle" (the scenario Sean flagged as the
                    // common case), where there's nothing live to read.
                    Picker("Source", selection: $useLiveHeading) {
                        Text("Live Compass").tag(true)
                        Text("Set Manually").tag(false)
                    }
                    .pickerStyle(.segmented)

                    if useLiveHeading {
                        liveHeadingSection
                    } else {
                        DirectionDialView(degrees: $directionDegrees)
                            .frame(height: 220)
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Label("Save Impact Profile", systemImage: "checkmark.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .disabled(tapPoint == nil || isSaving)
            }
            .padding()
        }
        .navigationTitle("Impact Location & Direction")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let v = vehicle
            if let existing = v.impactTapPoint { tapPoint = existing }
            if let existingDirection = v.directionOfTravelDegrees {
                directionDegrees = existingDirection
                useLiveHeading = false
            }
            heading.start()
        }
        .onDisappear { heading.stop() }
        .onChange(of: heading.headingDegrees) { _, newValue in
            if useLiveHeading, let newValue { directionDegrees = newValue }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("\(viewModel.captureRole.displayName) Vehicle")
                .font(.title3.bold())
            Text("This step is required to correlate impact geometry between both vehicles.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Live heading

    private var liveHeadingSection: some View {
        VStack(spacing: 8) {
            if heading.isAvailable {
                Text(String(format: "%.0f°", directionDegrees))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(compassLabel(for: directionDegrees))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if heading.headingDegrees == nil {
                    Text("Waiting for a compass reading — hold the phone level.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                Label("Compass unavailable on this device. Use manual entry instead.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func compassLabel(for degrees: Double) -> String {
        let labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees / 45.0).rounded()) % 8
        return labels[(index + 8) % 8]
    }

    // MARK: Save

    private func save() async {
        guard let point = tapPoint else { return }
        isSaving = true
        await viewModel.recordImpactProfile(tapPoint: point, directionDegrees: directionDegrees)
        isSaving = false
        dismiss()
    }
}

// MARK: - Top-down silhouette (tap-to-mark)

/// A simplified top-down car outline the user taps to mark where the
/// vehicle was struck. NOTE(AI Developer): Deliberately drawn as a
/// generic rounded-rectangle-with-wheels silhouette rather than a
/// make/model-accurate shape -- precision within a few percent of the
/// vehicle's actual perimeter is more than sufficient for a
/// front/rear/side/corner damage-location signal, and a generic outline
/// means this works identically for any vehicle without needing per-model
/// artwork.
struct ImpactSilhouetteView: View {
    @Binding var tapPoint: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: min(w, h) * 0.18)
                    .fill(Color(.systemGray5))
                    .overlay(
                        RoundedRectangle(cornerRadius: min(w, h) * 0.18)
                            .stroke(Color(.systemGray3), lineWidth: 2)
                    )

                // Directional labels around the silhouette.
                Text("FRONT").font(.caption2.bold()).foregroundStyle(.secondary)
                    .position(x: w / 2, y: 12)
                Text("REAR").font(.caption2.bold()).foregroundStyle(.secondary)
                    .position(x: w / 2, y: h - 12)

                if let tapPoint {
                    Circle()
                        .fill(.red)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .position(x: tapPoint.x * w, y: tapPoint.y * h)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let normalized = CGPoint(
                    x: min(max(location.x / w, 0), 1),
                    y: min(max(location.y / h, 0), 1)
                )
                tapPoint = normalized
            }
        }
    }
}

// MARK: - Manual direction-of-travel dial

/// A draggable compass dial for manually setting direction of travel
/// when there's no live heading to read (photo imported after the fact,
/// investigator no longer at the scene). NOTE(AI Developer): Chosen over
/// a plain numeric stepper per the "should be easier to follow and more
/// intuitive" UX lesson already learned this session with pitch/roll
/// guidance -- dragging a needle around a compass face is a far more
/// natural way to answer "which way was it pointed" than typing degrees.
struct DirectionDialView: View {
    @Binding var degrees: Double

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 2)
                    .frame(width: size, height: size)

                ForEach(["N", "E", "S", "W"], id: \.self) { label in
                    let angle = compassAngle(for: label)
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .position(
                            x: center.x + (size / 2 - 16) * sin(angle),
                            y: center.y - (size / 2 - 16) * cos(angle)
                        )
                }

                // Needle pointing in the direction of travel.
                Rectangle()
                    .fill(.red)
                    .frame(width: 4, height: size / 2 - 20)
                    .offset(y: -(size / 4 - 10))
                    .rotationEffect(.degrees(degrees))
                    .position(center)

                Circle()
                    .fill(.red)
                    .frame(width: 14, height: 14)
                    .position(center)

                Text(String(format: "%.0f°", degrees))
                    .font(.headline.monospacedDigit())
                    .position(x: center.x, y: center.y + size / 2 + 24)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = value.location.x - center.x
                        let dy = value.location.y - center.y
                        var angle = atan2(dx, -dy) * 180.0 / .pi
                        if angle < 0 { angle += 360 }
                        degrees = angle
                    }
            )
        }
    }

    private func compassAngle(for label: String) -> Double {
        switch label {
        case "N": return 0
        case "E": return .pi / 2
        case "S": return .pi
        case "W": return 3 * .pi / 2
        default: return 0
        }
    }
}
