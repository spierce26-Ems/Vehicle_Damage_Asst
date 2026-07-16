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
                    // NOTE(AI Developer), added 2026-07 per Sean's
                    // explicit request/example: "on the impact-location
                    // tap step, a one-line 'this helps confirm both
                    // vehicles were hit in a way that matches' would
                    // help a panicked/upset user understand why they're
                    // tapping a fender diagram instead of just taking
                    // photos." Wording matches Sean's own phrasing
                    // almost verbatim, placed directly under the step
                    // instructions so it reads as "why," not just
                    // "what."
                    whyThisMattersNote("This helps confirm both vehicles were hit in a way that matches — not just that damage exists on each one.")
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
                    // NOTE(AI Developer), added 2026-07: same "why this
                    // matters" pattern applied to the direction-of-travel
                    // step, since it feeds the exact same impact-geometry
                    // check as step 1 -- the tap point alone can't tell
                    // which way the vehicle was moving when it was hit.
                    whyThisMattersNote("Combined with the tap above, this shows the angle of impact — the key detail that ties this vehicle's damage to the other vehicle's.")

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

    // MARK: Why this matters

    /// A short, low-key "why" line placed directly under a step's
    /// instructions. NOTE(AI Developer), added 2026-07 per Sean's
    /// request for in-flow guidance on why each step matters -- kept
    /// deliberately understated (small font, lightbulb icon, secondary
    /// color) so it reads as a helpful aside rather than another
    /// instruction competing for attention with the actual task.
    @ViewBuilder
    private func whyThisMattersNote(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "lightbulb.fill")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom, 4)
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
/// NOTE(AI Developer), revised 2026-07 per Sean's second round of
/// feedback on the Car/Truck toggle ("I dont like the new truck
/// silhouette. Still a little confusing on how to mark the spot of
/// impact. need to see fenders and bumpers to clearing mark impact
/// spots."). The first revision only changed the truck's overall body
/// shape (cab + bed) but neither outline had any of the actual
/// recognizable landmarks people use to describe where a vehicle was
/// hit -- "front bumper," "driver-side front fender," etc. Both outlines
/// now draw:
///   - A distinct **front bumper** bar and **rear bumper** bar (each
///     labeled), instead of plain "FRONT"/"REAR" text floating with no
///     visual reference.
///   - Four **fender** bulges, one over each wheel position, each with a
///     darker **wheel well** ellipse inside it -- the corners of a real
///     vehicle where fender-bender damage most commonly lands, and
///     exactly the landmarks Sean asked to see.
/// `.truck` additionally keeps a narrower front cab / wider rear bed
/// distinction (subtler than the previous revision, since Sean's
/// complaint was specifically about that shape), so the truck silhouette
/// still reads as a truck and not just a second car.
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
/// `Vehicle.impactRelativeAngleDegrees` assumes. The bumper bars and
/// fender bulges are purely decorative landmarks layered on top of that
/// same 0-1 canvas; a tap on a fender or bumper is recorded at exactly
/// the screen point tapped, same as before. Only the drawing changes, not
/// the angle math.
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

    // MARK: Shared landmark pieces

    /// A short, wide capsule representing a bumper, with a caption
    /// centered on it. Used for both the front and rear bumper on both
    /// outlines.
    private func bumperBar(width: CGFloat, height: CGFloat, label: String) -> some View {
        ZStack {
            Capsule()
                .fill(Color(.systemGray3))
                .overlay(Capsule().stroke(Color(.systemGray2), lineWidth: 1.5))
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(width: width, height: height)
    }

    /// A fender bulge (rounded rectangle) with a darker wheel-well
    /// ellipse inside it, positioned at `centerX`/`centerY`. One of these
    /// sits over each of the vehicle's four wheel positions on both
    /// outlines -- these corners are where fender-bender damage most
    /// commonly lands, so making them visible landmarks (rather than an
    /// undifferentiated edge of a box) is the whole point of this
    /// revision.
    private func fenderMarker(centerX: CGFloat, centerY: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: height * 0.35)
                .fill(Color(.systemGray4))
                .overlay(
                    RoundedRectangle(cornerRadius: height * 0.35)
                        .stroke(Color(.systemGray3), lineWidth: 1.5)
                )
                .frame(width: width, height: height)
            Ellipse()
                .fill(Color(.systemGray2))
                .frame(width: width * 0.5, height: height * 0.55)
        }
        .position(x: centerX, y: centerY)
    }

    /// A sedan-like body: a rounded-rectangle cabin/body with a front
    /// bumper, rear bumper, and four fender+wheel-well bulges at the
    /// corners (front-left/right, rear-left/right).
    private func carOutline(w: CGFloat, h: CGFloat) -> some View {
        let bodyWidth = w * 0.64
        let bodyHeight = h * 0.90
        let cornerRadius = min(w, h) * 0.16
        let bumperHeight = h * 0.06
        let bumperWidth = bodyWidth * 0.82
        let fenderWidth = w * 0.15
        let fenderHeight = h * 0.13
        let frontAxleY = h * 0.24
        let rearAxleY = h * 0.80
        let leftFenderX = w * 0.15
        let rightFenderX = w * 0.85

        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.systemGray5))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color(.systemGray3), lineWidth: 2)
                )
                .frame(width: bodyWidth, height: bodyHeight)
                .position(x: w / 2, y: h / 2)

            bumperBar(width: bumperWidth, height: bumperHeight, label: "FRONT BUMPER")
                .position(x: w / 2, y: bumperHeight / 2 + 3)
            bumperBar(width: bumperWidth, height: bumperHeight, label: "REAR BUMPER")
                .position(x: w / 2, y: h - bumperHeight / 2 - 3)

            fenderMarker(centerX: leftFenderX, centerY: frontAxleY, width: fenderWidth, height: fenderHeight)
            fenderMarker(centerX: rightFenderX, centerY: frontAxleY, width: fenderWidth, height: fenderHeight)
            fenderMarker(centerX: leftFenderX, centerY: rearAxleY, width: fenderWidth, height: fenderHeight)
            fenderMarker(centerX: rightFenderX, centerY: rearAxleY, width: fenderWidth, height: fenderHeight)
        }
    }

    /// A pickup-truck-like body: a narrower front cab, a wider rear bed,
    /// a front bumper, a rear bumper (tailgate), and four fender+wheel-well
    /// bulges positioned under the cab (front axle) and under the bed
    /// (rear axle).
    private func truckOutline(w: CGFloat, h: CGFloat) -> some View {
        let cornerRadius = min(w, h) * 0.13
        let cabWidth = w * 0.58
        let cabHeight = h * 0.34
        let bedWidth = w * 0.82
        let bedTop = h * 0.38
        let bedHeight = h * 0.62
        let bumperHeight = h * 0.05
        let fenderWidth = w * 0.16
        let fenderHeight = h * 0.13
        let frontAxleY = h * 0.22
        let rearAxleY = h * 0.72
        let frontFenderX = (w * 0.19, w * 0.81)
        let rearFenderX = (w * 0.09, w * 0.91)

        return ZStack {
            // Cargo bed (rear two-thirds), drawn first.
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.systemGray5))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color(.systemGray3), lineWidth: 2)
                )
                .frame(width: bedWidth, height: bedHeight)
                .position(x: w / 2, y: bedTop + bedHeight / 2)

            // Cab (front third), narrower than the bed.
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.systemGray4))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color(.systemGray3), lineWidth: 2)
                )
                .frame(width: cabWidth, height: cabHeight)
                .position(x: w / 2, y: cabHeight / 2)

            bumperBar(width: cabWidth * 0.85, height: bumperHeight, label: "FRONT BUMPER")
                .position(x: w / 2, y: bumperHeight / 2 + 3)
            bumperBar(width: bedWidth * 0.7, height: bumperHeight, label: "TAILGATE")
                .position(x: w / 2, y: h - bumperHeight / 2 - 3)

            fenderMarker(centerX: frontFenderX.0, centerY: frontAxleY, width: fenderWidth, height: fenderHeight)
            fenderMarker(centerX: frontFenderX.1, centerY: frontAxleY, width: fenderWidth, height: fenderHeight)
            fenderMarker(centerX: rearFenderX.0, centerY: rearAxleY, width: fenderWidth, height: fenderHeight)
            fenderMarker(centerX: rearFenderX.1, centerY: rearAxleY, width: fenderWidth, height: fenderHeight)
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
