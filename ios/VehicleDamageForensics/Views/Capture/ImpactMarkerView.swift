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
                    ImpactSilhouetteView(tapPoint: $tapPoint, bodyType: vehicle.bodyType)
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
                    // NOTE(AI Developer): `.frame`/`.font` cannot be
                    // chained directly onto the closing brace of an
                    // if/else *statement* inside a ViewBuilder closure --
                    // that produced "Instance member 'frame' cannot be
                    // used on type 'View'" at build time. Wrapping the
                    // conditional in `Group` gives the modifiers a single
                    // View instance to attach to.
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Label("Save Impact Profile", systemImage: "checkmark.circle.fill")
                        }
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

/// A simplified top-down vehicle outline the user taps to mark where the
/// vehicle was struck.
///
/// NOTE(AI Developer): Originally a single generic rounded-rectangle used
/// for every vehicle. Per Sean's follow-up request ("can we have a better
/// image to tap... if its a truck we should be able to better identify
/// the location of the impact instead of a generic square we tap") this
/// now draws one of two outlines based on `Vehicle.bodyType`
/// (`Vehicle.bodyType`, set via the Car/Truck toggle in
/// `EditCaseSheet.swift`):
///   - `.car`: the original rounded-rectangle body (unchanged).
///   - `.truck`: a narrower front cab plus a separate, visually distinct
///     rear cargo bed -- so a tap in "the bed" vs. "the cab" is an
///     obviously different part of the outline, not just a different spot
///     on the same undifferentiated box.
///
/// Deliberately still not a make/model-accurate shape -- precision within
/// a few percent of the vehicle's actual perimeter is more than
/// sufficient for a front/rear/side/corner damage-location signal, and
/// two generic outlines (rather than per-model artwork) keep this simple
/// per Sean's explicit choice ("something easy like Car vs Truck as a
/// simple toggle").
///
/// IMPORTANT: both outlines keep the exact same (0,0)-(1,1) tap-point
/// contract -- front-center at (0.5, 0), rear-center at (0.5, 1) -- that
/// `Vehicle.impactRelativeAngleDegrees` assumes. The truck outline's cab
/// and bed are simply drawn at different points within that same 0-1
/// vertical range (cab in the front third, bed in the back two-thirds),
/// so the existing angle math is unaffected; only the drawing changes.
struct ImpactSilhouetteView: View {
    @Binding var tapPoint: CGPoint?
    var bodyType: VehicleBodyType = .car

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                switch bodyType {
                case .car:
                    carOutline(w: w, h: h)
                case .truck:
                    truckOutline(w: w, h: h)
                }

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

    /// The original generic rounded-rectangle body, unchanged.
    private func carOutline(w: CGFloat, h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: min(w, h) * 0.18)
            .fill(Color(.systemGray5))
            .overlay(
                RoundedRectangle(cornerRadius: min(w, h) * 0.18)
                    .stroke(Color(.systemGray3), lineWidth: 2)
            )
    }

    /// A narrower front cab plus a wider, visually separate rear cargo
    /// bed, so tapping "on the bed" vs. "on the cab" is unambiguous. Cab
    /// occupies roughly the front third (y: 0-0.38), bed the rear
    /// two-thirds (y: 0.42-1.0), with a small gap between them so the two
    /// pieces read as distinct sections at a glance.
    private func truckOutline(w: CGFloat, h: CGFloat) -> some View {
        let cornerRadius = min(w, h) * 0.14
        let cabWidth = w * 0.62
        let cabHeight = h * 0.38
        let bedTop = h * 0.42
        let bedHeight = h * 0.58

        return ZStack {
            // Cargo bed (rear two-thirds) -- drawn first so the cab
            // visually overlaps/sits in front of it at the seam.
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.systemGray5))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color(.systemGray3), lineWidth: 2)
                )
                .frame(width: w, height: bedHeight)
                .position(x: w / 2, y: bedTop + bedHeight / 2)

            // Cab (front third) -- narrower than the bed, echoing a real
            // pickup truck's silhouette from above.
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.systemGray4))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color(.systemGray3), lineWidth: 2)
                )
                .frame(width: cabWidth, height: cabHeight)
                .position(x: w / 2, y: cabHeight / 2)

            Text("BED").font(.caption2.bold()).foregroundStyle(.secondary)
                .position(x: w / 2, y: bedTop + 14)
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
