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
/// NOTE(AI Developer), revised 2026-07 (third revision) per Sean's latest
/// feedback: "it doesn't look anything like a vehicle so some users may
/// be confused on how to use it." The previous revision (bumper
/// bars/fender blobs on a plain rounded rectangle) still just looked like
/// a decorated box, not a car. This revision replaces the rectangle
/// entirely with a single continuous `Path` traced as an actual top-down
/// car/truck outline -- tapered nose, flared front fenders, a narrower
/// greenhouse/cabin waist, flared rear fenders, and a tapered tail --
/// the same silhouette language used by parking apps and insurance
/// damage diagrams, so it reads as "car" at a glance instead of needing
/// bumper labels to explain what the shape is supposed to be. The bumper
/// bars and wheel-well ellipses from the prior revision are kept as
/// landmarks layered on top of the new body outline (Sean's earlier
/// explicit ask: "need to see fenders and bumpers to clearly mark impact
/// spots"), but now they sit on a shape that actually looks like the
/// part of the car they're labeling.
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
/// `Vehicle.impactRelativeAngleDegrees` assumes. The body outline, bumper
/// bars, and fender markers are purely decorative layers on top of that
/// same 0-1 canvas; a tap anywhere in the view is recorded at exactly the
/// screen point tapped, same as before. Only the drawing changes, not the
/// angle math.
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
                .fill(Color(.systemGray2))
                .overlay(Capsule().stroke(Color(.systemGray).opacity(0.6), lineWidth: 1.5))
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: width, height: height)
    }

    /// A darker wheel-well ellipse marking one of the vehicle's four
    /// wheel positions, sitting just inside the body outline where a
    /// real fender bulge would be -- these corners are where
    /// fender-bender damage most commonly lands, so keeping them as
    /// visible landmarks (rather than an undifferentiated edge) is the
    /// point of layering them on top of the new silhouette.
    private func wheelWell(centerX: CGFloat, centerY: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        Ellipse()
            .fill(Color(.systemGray2))
            .overlay(Ellipse().stroke(Color(.systemGray).opacity(0.5), lineWidth: 1))
            .frame(width: width, height: height)
            .position(x: centerX, y: centerY)
    }

    /// A sedan-like top-down body outline: tapered rounded nose, front
    /// fenders flaring out to the widest point at the front axle, a
    /// narrower cabin/greenhouse waist across the middle, rear fenders
    /// flaring back out at the rear axle, and a tapered rounded tail --
    /// traced as a single mirrored `Path` so the shape actually reads as
    /// "car," with a front bumper, rear bumper, and four wheel-well
    /// markers layered on top as tap landmarks.
    private func carOutline(w: CGFloat, h: CGFloat) -> some View {
        let bumperHeight = h * 0.05
        let bumperWidth = w * 0.5
        let fenderWidth = w * 0.14
        let fenderHeight = h * 0.11
        let frontAxleY = h * 0.235
        let rearAxleY = h * 0.79
        let leftFenderX = w * 0.155
        let rightFenderX = w * 0.845

        // Half-width (from the vertical centerline) at each key
        // longitudinal fraction of the body, front-to-back. Mirroring
        // this profile across the centerline and connecting the points
        // with smooth curves produces the tapered-nose / flared-fender /
        // narrow-waist / flared-fender / tapered-tail car silhouette.
        let profile: [(y: CGFloat, halfWidth: CGFloat)] = [
            (0.03, 0.16),   // front bumper center -- rounded nose tip
            (0.07, 0.24),   // nose widening
            (0.16, 0.33),   // front fender leading edge
            (0.25, 0.34),   // front fender widest point (front axle)
            (0.34, 0.27),   // cowl / base of windshield -- narrowing in
            (0.50, 0.235),  // cabin waist (roofline), narrowest point
            (0.68, 0.27),   // rear window base -- widening back out
            (0.77, 0.34),   // rear fender widest point (rear axle)
            (0.86, 0.33),   // rear fender trailing edge
            (0.95, 0.24),   // tail narrowing
            (0.98, 0.16)    // rear bumper center -- rounded tail tip
        ]

        return ZStack {
            bodyPath(w: w, h: h, profile: profile)
                .fill(Color(.systemGray5))
                .overlay(bodyPath(w: w, h: h, profile: profile).stroke(Color(.systemGray3), lineWidth: 2))

            bumperBar(width: bumperWidth, height: bumperHeight, label: "FRONT")
                .position(x: w / 2, y: h * 0.045)
            bumperBar(width: bumperWidth, height: bumperHeight, label: "REAR")
                .position(x: w / 2, y: h * 0.965)

            wheelWell(centerX: leftFenderX, centerY: frontAxleY, width: fenderWidth, height: fenderHeight)
            wheelWell(centerX: rightFenderX, centerY: frontAxleY, width: fenderWidth, height: fenderHeight)
            wheelWell(centerX: leftFenderX, centerY: rearAxleY, width: fenderWidth, height: fenderHeight)
            wheelWell(centerX: rightFenderX, centerY: rearAxleY, width: fenderWidth, height: fenderHeight)
        }
    }

    /// A pickup-truck-like top-down body outline: a narrower front cab
    /// (with the same tapered nose/flared-fender shaping as the car
    /// outline) flowing into a wider, boxier rear cargo bed with a
    /// squared-off tailgate -- still one continuous mirrored `Path`, kept
    /// visually distinct from the sedan outline (Sean's explicit
    /// complaint on the prior revision was specifically about the truck
    /// shape reading as "just a second car").
    private func truckOutline(w: CGFloat, h: CGFloat) -> some View {
        let bumperHeight = h * 0.045
        let cabBumperWidth = w * 0.42
        let bedBumperWidth = w * 0.62
        let fenderWidth = w * 0.155
        let fenderHeight = h * 0.115
        let frontAxleY = h * 0.20
        let rearAxleY = h * 0.735
        let frontFenderX = (w * 0.185, w * 0.815)
        let rearFenderX = (w * 0.095, w * 0.905)

        let profile: [(y: CGFloat, halfWidth: CGFloat)] = [
            (0.03, 0.14),   // front bumper center -- rounded nose tip
            (0.06, 0.20),   // nose widening
            (0.14, 0.29),   // cab front fender leading edge
            (0.20, 0.30),   // cab front fender widest point (front axle)
            (0.30, 0.24),   // windshield base -- cab narrows slightly
            (0.38, 0.23),   // cab roofline, narrowest point
            (0.44, 0.27),   // back of cab widening into the bed
            (0.50, 0.41),   // bed side rail begins -- sharp step out
            (0.735, 0.42),  // rear fender widest point (rear axle), boxy bed
            (0.90, 0.41),   // bed continues near-full-width toward tailgate
            (0.97, 0.38)    // tailgate -- squared-off, only a slight taper
        ]

        return ZStack {
            bodyPath(w: w, h: h, profile: profile)
                .fill(Color(.systemGray5))
                .overlay(bodyPath(w: w, h: h, profile: profile).stroke(Color(.systemGray3), lineWidth: 2))

            bumperBar(width: cabBumperWidth, height: bumperHeight, label: "FRONT")
                .position(x: w / 2, y: h * 0.04)
            bumperBar(width: bedBumperWidth, height: bumperHeight, label: "TAILGATE")
                .position(x: w / 2, y: h * 0.965)

            wheelWell(centerX: frontFenderX.0, centerY: frontAxleY, width: fenderWidth, height: fenderHeight)
            wheelWell(centerX: frontFenderX.1, centerY: frontAxleY, width: fenderWidth, height: fenderHeight)
            wheelWell(centerX: rearFenderX.0, centerY: rearAxleY, width: fenderWidth, height: fenderHeight)
            wheelWell(centerX: rearFenderX.1, centerY: rearAxleY, width: fenderWidth, height: fenderHeight)
        }
    }

    /// Builds a smooth, mirrored top-down body outline from a
    /// front-to-back `profile` of (normalized-y, half-width-from-center)
    /// control points. Traces down the right-hand side through each
    /// point with quadratic curves (using the midpoint between
    /// consecutive points as the curve target, a simple and robust way
    /// to get a smooth silhouette from a coarse set of hand-tuned
    /// measurements), caps the tail, mirrors back up the left-hand side,
    /// and caps the nose -- one continuous closed shape, so a single
    /// fill/stroke draws the whole vehicle body.
    private func bodyPath(w: CGFloat, h: CGFloat, profile: [(y: CGFloat, halfWidth: CGFloat)]) -> Path {
        Path { path in
            guard profile.count > 1 else { return }
            let cx = w / 2

            func point(_ p: (y: CGFloat, halfWidth: CGFloat), side: CGFloat) -> CGPoint {
                CGPoint(x: cx + side * p.halfWidth * w, y: p.y * h)
            }

            // Down the right side.
            path.move(to: point(profile[0], side: 1))
            for i in 1..<profile.count {
                let prev = point(profile[i - 1], side: 1)
                let curr = point(profile[i], side: 1)
                let mid = CGPoint(x: (prev.x + curr.x) / 2, y: (prev.y + curr.y) / 2)
                path.addQuadCurve(to: curr, control: mid)
            }
            // Across the tail cap.
            path.addLine(to: point(profile[profile.count - 1], side: -1))
            // Back up the left side (mirror image of the descent).
            for i in stride(from: profile.count - 1, through: 1, by: -1) {
                let prev = point(profile[i], side: -1)
                let curr = point(profile[i - 1], side: -1)
                let mid = CGPoint(x: (prev.x + curr.x) / 2, y: (prev.y + curr.y) / 2)
                path.addQuadCurve(to: curr, control: mid)
            }
            path.closeSubpath()
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
