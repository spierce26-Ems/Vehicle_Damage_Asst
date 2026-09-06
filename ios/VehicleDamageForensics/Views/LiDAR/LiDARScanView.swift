// LiDARScanView.swift
// Vehicle Damage Investigation Assistant
// Hosts an ARView for LiDAR scene reconstruction, displays coverage
// progress, and saves the scan back into the case when complete.

import SwiftUI
import UIKit
import ARKit
import RealityKit

// NOTE(AI Developer), added 2026-07 per Sean's explicit request ("wire
// LiDAR data into the Height Alignment factor as a next step... we need
// the use of Lidar as an extra tool"). Drives the tap-to-measure flow:
// the user taps the ground beside the vehicle, then taps the damage
// point on the vehicle body, and `LiDARScanView` computes the vertical
// distance between the two raycast hits via
// `LiDARService.worldY(from:at:)` / `heightFromWorldPositions(groundY:
// damageY:)`. Kept as a simple explicit state machine (rather than just
// optionals) so the instructional text in `measurementBanner` always has
// an unambiguous "what do I do next" answer.
private enum MeasurementStep: Equatable {
    case notStarted
    case awaitingGroundTap
    case awaitingDamageTap(groundY: Float)
    case measured(inches: Double)
    /// A raycast found no reconstructed surface under the aim point.
    ///
    /// NOTE(AI Developer), 2026-09: this now CARRIES the ground point
    /// recorded before the miss (`nil` when the ground point itself was
    /// what missed). It used to be a payload-free case, and retrying
    /// from it re-entered `.awaitingGroundTap` unconditionally -- so a
    /// miss on the SECOND (damage) point silently threw away a
    /// successfully-measured ground point and made the user re-do both,
    /// with no indication that had happened. Missing a surface is the
    /// normal outcome of aiming at an unscanned patch; it must not undo
    /// work that succeeded.
    case missedSurface(pendingGroundY: Float?)

    /// NOTE(AI Developer), added 2026-09 with the set-point reticle
    /// (spec B.1). The crosshair appears only while a point is actually
    /// being aimed, so it never clutters plain mesh scanning, and it
    /// stays visible through `tapMissedSurface` -- that state used to be
    /// a dead end reached by aiming a fingertip precisely, and recovery
    /// is now "re-aim and press again", which requires the reticle to
    /// still be on screen.
    /// The dark instructional banner is for the aiming steps only. Once
    /// a value exists, `LiDARScanView.measurementConfirmation` takes the
    /// screen instead -- see its NOTE for why this number does not share
    /// space with instructions.
    var showsBanner: Bool {
        switch self {
        case .notStarted, .measured: return false
        case .awaitingGroundTap, .awaitingDamageTap, .missedSurface: return true
        }
    }

    var showsReticle: Bool {
        switch self {
        case .awaitingGroundTap, .awaitingDamageTap, .missedSurface: return true
        case .notStarted, .measured: return false
        }
    }

    /// What `Set point` will record next, or `nil` when there is nothing
    /// to set. Drives the button's label so it can never say "set the
    /// ground point" while the state machine is waiting for the damage
    /// point.
    var setPointLabel: String? {
        switch self {
        case .awaitingGroundTap: return "Set ground point"
        case .awaitingDamageTap: return "Set damage point"
        // The retry label names whichever point actually missed, so it
        // matches what pressing the button will record.
        case .missedSurface(let pendingGroundY):
            return pendingGroundY == nil ? "Set ground point" : "Set damage point"
        case .notStarted, .measured: return nil
        }
    }
}

/// Keeps a weak reference to the live `ARView` so a button press -- not
/// only a tap gesture -- can raycast through it.
///
/// NOTE(AI Developer), added 2026-09 (spec B.1). Weak on purpose: the
/// `ARView` is owned by UIKit via `ARViewContainer`, and a strong
/// reference here would outlive the view's own lifecycle and keep an
/// ARKit-backed view (and its session's mesh buffers) alive after this
/// screen is gone. That is the same retain shape as the duplicate-photo
/// leaks fixed in `CameraService` and `CaptureViewModel`.
@MainActor
private final class ARViewHolder: ObservableObject {
    weak var arView: ARView?
}

struct LiDARScanView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @StateObject private var lidarService = LiDARService()
    @Environment(\.dismiss) private var dismiss
    @State private var measurementStep: MeasurementStep = .notStarted
    @State private var isSavingMeasurement = false

    /// Holds the live `ARView` so the `Set point` button can raycast
    /// through the reticle centre without a tap to supply one.
    ///
    /// NOTE(AI Developer), added 2026-09 with the set-point reticle
    /// (spec B.1). The centre is read from `arView.bounds` at press
    /// time, deliberately NOT from `UIScreen.main.bounds`: the AR view
    /// is inset by the navigation bar, so a screen-space centre would
    /// raycast some distance from where the crosshair is drawn -- the
    /// user would aim at the damage and measure the panel below it. The
    /// crosshair is centred in the same `.ignoresSafeArea()` layer as
    /// the AR view, so the two agree by construction.
    @StateObject private var arViewHolder = ARViewHolder()

    var body: some View {
        ZStack {
            // NOTE(AI Developer), fixed 2026-07 per Sean's on-device report
            // ("Lidar scan is not visible on screen for user. Its just
            // black."): now points at `lidarService.session` -- the actual
            // session being scanned -- instead of the orphaned
            // `ARSession.shared` singleton, which was a second, never-run
            // ARSession. See the NOTE on `LiDARService.session` for the
            // full root cause.
            ARViewContainer(
                session: lidarService.session,
                onTap: { point, arView in
                    handleTap(at: point, in: arView)
                },
                onViewReady: { [weak arViewHolder] arView in
                    arViewHolder?.arView = arView
                }
            )
            .ignoresSafeArea()

            // The reticle lives in its own centred layer, NOT in the
            // VStack below -- inside that stack its position would
            // depend on the banner's height and drift as the
            // instructional text changed length, which is exactly the
            // kind of moving aim point this change exists to remove.
            if measurementStep.showsReticle {
                setPointReticle
            }

            VStack {
                topStatus
                if measurementStep.showsBanner {
                    measurementBanner
                }
                Spacer()
                // While a measurement is awaiting confirmation, the
                // scan controls are replaced rather than stacked
                // underneath it: Save Scan and Cancel next to "Use this
                // measurement" is three plausible-looking commitments
                // for one decision, and only one of them is the
                // decision being asked for.
                if case .measured = measurementStep {
                    EmptyView()
                } else {
                    bottomControls
                }
            }
            .padding()

            // Last in the ZStack so it sits above the AR passthrough and
            // the status/controls layer.
            if case .measured(let inches) = measurementStep {
                measurementConfirmation(inches: inches)
            }
        }
        .navigationTitle("LiDAR Scan")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { try lidarService.startScan() }
            catch {
                // NOTE(AI Developer): previously this catch block was
                // empty (the "surface error" comment was aspirational,
                // not actually implemented) -- an unsupported-device
                // failure here left the screen just sitting there with
                // no feedback at all, indistinguishable from a hang.
                // `LiDARService.startScan()` already published this same
                // failure to `lastError` before throwing, so the `.alert`
                // below picks it up; this catch only needs to exist so
                // the `do/catch` compiles (the thrown error is otherwise
                // unused here).
            }
        }
        .onDisappear {
            if lidarService.isScanning {
                _ = lidarService.stopScan()
            }
        }
        // NOTE(AI Developer), added 2026-07 per Sean's on-device report
        // ("Lidar took a while to start and the lidar crashed/stop").
        // Surfaces a hard session failure (`LiDARService.lastError`) as
        // an actual alert instead of silently leaving the user staring at
        // a stalled scan with zero explanation -- previously nothing in
        // this view ever read `lastError` at all.
        .alert("LiDAR Scan Error",
               isPresented: .constant(lidarService.lastError != nil),
               actions: { Button("OK") { lidarService.clearError() } },
               message: { Text(lidarService.lastError?.errorDescription ?? "") })
    }

    // MARK: Tap-to-measure

    /// Routes a screen tap to whichever step of the ground/damage-point
    /// measurement flow is currently active. Taps are ignored entirely
    /// when `measurementStep == .notStarted` (the user hasn't pressed
    /// "Measure Height" yet), so ordinary scanning isn't disrupted by
    /// incidental taps on the AR view.
    private func handleTap(at point: CGPoint, in arView: ARView) {
        switch measurementStep {
        case .notStarted, .measured, .missedSurface:
            return
        case .awaitingGroundTap:
            guard let y = lidarService.worldY(from: arView, at: point) else {
                measurementStep = .missedSurface(pendingGroundY: nil)
                return
            }
            measurementStep = .awaitingDamageTap(groundY: y)
        case .awaitingDamageTap(let groundY):
            guard let damageY = lidarService.worldY(from: arView, at: point) else {
                // Carry the ground point through the miss -- see the
                // NOTE on `missedSurface`.
                measurementStep = .missedSurface(pendingGroundY: groundY)
                return
            }
            let inches = lidarService.heightFromWorldPositions(groundY: groundY, damageY: damageY)
            measurementStep = .measured(inches: inches)
        }
    }

    /// Raycasts through the reticle centre and advances the same state
    /// machine `handleTap` drives.
    ///
    /// NOTE(AI Developer), added 2026-09 (spec B.1). This is the primary
    /// path now: the previous flow required aiming a fingertip at a
    /// specific point on a live camera feed, one-handed, possibly
    /// gloved, in sun -- and a near-miss landed in `tapMissedSurface`.
    /// Aiming the whole phone is a coarse gesture the device is steady
    /// for. The raycast, the height math and the state machine are
    /// unchanged: only the source point and the trigger moved. Tap
    /// remains wired as a secondary path (see `handleTap`) because it
    /// costs nothing and some users will try it.
    private func setPointAtReticle() {
        guard let arView = arViewHolder.arView else { return }
        // Centre of the AR view's OWN bounds -- see `arViewHolder`'s
        // NOTE on why this must not come from screen bounds.
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        // A miss is a recoverable state, not a step: retry resumes
        // whichever point missed, and an already-recorded ground point
        // survives (see the NOTE on `missedSurface`).
        if case .missedSurface(let pendingGroundY) = measurementStep {
            measurementStep = pendingGroundY.map { .awaitingDamageTap(groundY: $0) } ?? .awaitingGroundTap
        }
        handleTap(at: center, in: arView)
    }

    private func confirmMeasurement() {
        guard case .measured(let inches) = measurementStep else { return }
        isSavingMeasurement = true
        Task {
            await viewModel.recordLiDARMeasurement(inches: inches)
            isSavingMeasurement = false
            measurementStep = .notStarted
        }
    }

    @ViewBuilder
    private var measurementBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch measurementStep {
            case .notStarted:
                EmptyView()
            case .awaitingGroundTap:
                Label("Aim the circle at the ground beside the vehicle, then press Set ground point", systemImage: "scope")
                // NOTE(AI Developer), added 2026-07 per Sean's request
                // for in-flow "why this matters" guidance on steps that
                // aren't obviously self-explanatory -- measuring a
                // height off the ground is one of those (unlike a
                // photo, it's not obvious *why* you'd do this at all).
                whyThisMattersNote("This measures how high off the ground the damage is — useful for confirming both vehicles' damage lines up at the same height.")
            case .awaitingDamageTap:
                Label("Now aim the circle at the damage point on the vehicle, then press Set damage point", systemImage: "scope")
            case .missedSurface(let pendingGroundY):
                // NOTE(AI Developer), 2026-09: says which point still
                // needs setting, because the ground point now survives a
                // miss on the damage point -- telling the user to "try
                // again" without saying what to aim at would invite them
                // to re-set a ground point that is already recorded.
                Label(pendingGroundY == nil
                      ? "Couldn't find a surface there — keep scanning that area, then aim at the ground and press Set ground point"
                      : "Couldn't find a surface there — the ground point is still recorded. Keep scanning, then aim at the damage and press Set damage point",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            case .measured:
                // Handled by `measurementConfirmation`, which gets the
                // whole screen -- see its own NOTE. Nothing renders here,
                // and `showsBanner` keeps this branch unreachable.
                EmptyView()
            }
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    /// The measured value gets the screen: large numeral, both units
    /// beneath it, one line on why it matters, then the two decisions.
    ///
    /// NOTE(AI Developer), added 2026-09 (spec B.3). This is the
    /// highest-consequence measurement in the app -- a height mismatch
    /// is one of the two conditions that can rule a vehicle out -- and
    /// it was previously confirmed in a one-line banner sharing a row
    /// with Retry and Save, where a digit misread on scene becomes a
    /// number in a report nobody re-derives. A wrong measurement has to
    /// be catchable at arm's length, in sun.
    ///
    /// The numeral uses a Dynamic Type text style, NOT a fixed point
    /// size: this is exactly the place a hard-coded 48pt would have to
    /// be undone for the deferred field theme, and it is also where a
    /// user with large accessibility text most needs the value to scale.
    private func measurementConfirmation(inches: Double) -> some View {
        VStack(spacing: 16) {
            Text("Measured height above ground")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            // Both units in one string, always: the report is dual-unit,
            // and a value confirmed in one unit and printed in another
            // is a transcription error waiting to happen. Reuses
            // `formatInchesWithMetric` rather than formatting here, so
            // the number the examiner confirms is character-for-
            // character the number the report prints.
            Text(MeasurementHelpers.formatInchesWithMetric(inches))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            // NOTE(AI Developer): the spec asked for a "± 0.4 in"
            // tolerance beside the number, and said to omit it entirely
            // rather than invent one if a real tolerance is not
            // available. It is not available -- `worldY` returns a
            // raycast hit's Y with no accuracy estimate and
            // `heightFromWorldPositions` is a plain subtraction, so any
            // ± here would be a literal chosen to look authoritative.
            // Omitted, and raised with the engine owner: a fabricated
            // tolerance on the one measurement that can exclude a
            // vehicle is the worst possible place for an invented
            // number.

            Label {
                Text("This is compared against the other vehicle's damage height. A mismatch here is one of the two conditions that can rule a vehicle out.")
            } icon: {
                Image(systemName: "info.circle.fill")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.85))
            .multilineTextAlignment(.leading)

            VStack(spacing: 10) {
                Button {
                    confirmMeasurement()
                } label: {
                    Group {
                        if isSavingMeasurement {
                            ProgressView().tint(.white)
                        } else {
                            Text("Use this measurement")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSavingMeasurement)

                // Re-measuring restarts from the ground point on
                // purpose: a user rejecting the value has no way to know
                // which of the two points was wrong.
                Button {
                    measurementStep = .awaitingGroundTap
                } label: {
                    Text("Measure again")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSavingMeasurement)
            }

            Text("Recorded to the case audit log with a timestamp.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }

    /// Coverage as a filled arc over a top-down vehicle silhouette, with
    /// the percentage demoted to a caption underneath.
    ///
    /// NOTE(AI Developer), added 2026-09 (spec B.2). The spec offered two
    /// implementations and said to take the cheaper one, on the grounds
    /// that a confidently wrong compass is worse than a bare percentage.
    /// I took the honest single arc, and the reason is stronger than
    /// cost: `LiDARService.coveragePercent` is
    /// `min(100, meshAnchors.count * 10)` -- an anchor COUNT heuristic
    /// with no bearing, no area, and no notion of which side of the
    /// vehicle anything is on. A directional compass drawn off that
    /// number would put a claim on screen ("the left side is scanned")
    /// the data cannot support, and the user would then trust it to
    /// decide where NOT to walk.
    ///
    /// So the arc claims no side: it grows from the nose clockwise as a
    /// proportion only, and the caption says so in words rather than
    /// leaving the user to infer it. If per-anchor bearings ever land in
    /// `LiDARService`, this becomes a real compass by filling buckets
    /// instead of one sweep -- the silhouette and layout do not change.
    private var coverageIndicator: some View {
        VStack(alignment: .leading, spacing: 4) {
            CoverageArcView(fraction: coverageFraction)
                .frame(width: 118, height: 52)
                .accessibilityLabel("Scan coverage \(Int(lidarService.coveragePercent)) percent. Proportion only — this does not indicate which part of the vehicle has been scanned.")

            // The percentage stays, demoted to a caption.
            Text("\(Int(lidarService.coveragePercent))% scanned • Points \(lidarService.pointCloudCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
            Text("Proportion only — not which part of the vehicle.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    /// `coveragePercent` clamped into 0...1. Clamped rather than
    /// trusted: a fraction above 1 would draw an arc wrapping past the
    /// nose and read as a fresh scan starting over.
    private var coverageFraction: Double {
        min(max(lidarService.coveragePercent / 100.0, 0), 1)
    }

    /// A 44pt crosshair locked to the centre of the AR view, so the user
    /// aims the phone rather than a fingertip. Purely an aim indicator:
    /// not interactive and never consumes touches, so tap-to-raycast
    /// keeps working underneath it.
    private var setPointReticle: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 2)
                .frame(width: 44, height: 44)
            Circle()
                .fill(.white)
                .frame(width: 4, height: 4)
            // Short ticks rather than crosshairs through the middle: the
            // centre must stay clear so the surface being aimed at is
            // visible, which is the whole point of aiming.
            ForEach([0.0, 90.0, 180.0, 270.0], id: \.self) { angle in
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 2, height: 10)
                    .offset(y: -30)
                    .rotationEffect(.degrees(angle))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .shadow(radius: 2)
    }

    /// See the identical-purpose helper in `ImpactMarkerView.swift`.
    /// Duplicated (rather than shared) since this view's banner sits on
    /// a dark/black background, needing different text styling
    /// (smaller caption, translucent white) than `ImpactMarkerView`'s
    /// light-material card.
    private func whyThisMattersNote(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "lightbulb.fill")
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.75))
    }

    private var topStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "scanner.fill")
                Text(lidarService.isAvailable
                     ? "LiDAR available"
                     : "LiDAR not supported on this device")
            }
            .foregroundStyle(.white)

            // NOTE(AI Developer), added 2026-07 per Sean's on-device
            // report ("Lidar took a while to start and the lidar
            // crashed/stop"): a slow-but-normal tracking start (ARKit
            // needs a few seconds of camera motion before quality
            // settles) previously looked identical to a hang, since
            // nothing told the user *why* coverage was stuck at 0%. Now
            // shows `LiDARService.trackingStateMessage` (e.g.
            // "Initializing — hold the phone steady…") whenever tracking
            // isn't yet `.normal`, and disappears once it is.
            if let message = lidarService.trackingStateMessage {
                Label(message, systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }

            coverageIndicator
        }
        .padding(12)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var bottomControls: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)

            Spacer()

            // NOTE(AI Developer), added 2026-07 per Sean's explicit
            // request ("wire LiDAR data into the Height Alignment
            // factor... we need the use of Lidar as an extra tool"):
            // starts the tap-to-measure flow (see `MeasurementStep` /
            // `handleTap`). Deliberately independent of "Save Scan" --
            // a user can measure a height on a scan they don't intend
            // to keep saved as a full mesh, or vice versa. Disabled
            // once a measurement is in flight so a second tap-sequence
            // can't start mid-flow; "Retry" in `measurementBanner`
            // restarts it cleanly.
            // NOTE(AI Developer), 2026-09: while a point is being aimed,
            // this slot becomes the `Set point` button rather than adding
            // a sixth control -- the bottom row on the capture screens
            // has a history of overflowing off-device, and "Measure
            // Height" is meaningless once measuring has started.
            if let label = measurementStep.setPointLabel {
                Button {
                    setPointAtReticle()
                } label: {
                    Label(label, systemImage: "scope")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!lidarService.isScanning || arViewHolder.arView == nil)
                .accessibilityHint("Records the point the centre circle is aimed at. No precise tapping needed.")
            } else {
                Button {
                    measurementStep = .awaitingGroundTap
                } label: {
                    Label("Measure Height", systemImage: "ruler")
                }
                .buttonStyle(.bordered)
                .disabled(!lidarService.isScanning || measurementStep != .notStarted)
            }

            Spacer()

            Button {
                let data = lidarService.stopScan()
                save(scan: data)
                dismiss()
            } label: {
                Label("Save Scan", systemImage: "checkmark.circle.fill")
                    .font(.title3.bold())
            }
            .buttonStyle(.borderedProminent)
            .disabled(!lidarService.isScanning)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func save(scan: LiDARScanData) {
        switch viewModel.captureRole {
        case .victim:
            viewModel.forensicCase.victimVehicle.lidarScanData = scan
        case .suspect:
            viewModel.forensicCase.suspectVehicle?.lidarScanData = scan
        }
    }
}

// MARK: - ARView wrapper

struct ARViewContainer: UIViewRepresentable {
    let session: ARSession
    // NOTE(AI Developer), added 2026-07 per Sean's explicit request
    // ("wire LiDAR data into the Height Alignment factor... we need the
    // use of Lidar as an extra tool"). `UIViewRepresentable` has no
    // built-in tap callback, so this routes a plain `UITapGestureRecognizer`
    // added in `makeUIView` back up to SwiftUI via the standard
    // `Coordinator` pattern -- `onTap` is called with the tap's location
    // (in `arView`'s local coordinate space, exactly what
    // `ARView.raycast(from:allowing:alignment:)` expects) plus the
    // `ARView` itself, since `LiDARService.worldY(from:at:)` needs both.
    var onTap: (CGPoint, ARView) -> Void = { _, _ in }
    /// NOTE(AI Developer), added 2026-09 for the set-point reticle (spec
    /// B.1). Hands the live `ARView` up to SwiftUI once, at creation, so
    /// a BUTTON press can raycast through the reticle centre -- the
    /// `onTap` callback above only ever fires with a real touch
    /// location, which is precisely the input the reticle exists to stop
    /// requiring. Called from `makeUIView`, not `updateUIView`, so it
    /// fires exactly once per view rather than on every SwiftUI update.
    var onViewReady: (ARView) -> Void = { _ in }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        // NOTE(AI Developer), added 2026-07 per Sean's on-device report
        // ("the lidar never activated during scan"). `ARView` defaults
        // `automaticallyConfigureSession` to `true`, which means RealityKit
        // silently runs (and can re-run, e.g. on scene-phase/window
        // changes) its *own* auto-generated `ARWorldTrackingConfiguration`
        // on this session -- one that, per Apple's own scene-reconstruction
        // sample doc ("Visualizing and interacting with a reconstructed
        // scene"), does NOT enable `.sceneReconstruction` by default,
        // since RealityKit only turns that on for occlusion/physics when
        // it judges it necessary. That auto-config can stomp on (replace)
        // the custom `.sceneReconstruction = .mesh` configuration that
        // `LiDARService.startScan()` explicitly builds and runs on this
        // exact `session` an instant later -- which matches Sean's report
        // that tap-to-measure raycasts still worked (raycasts can still
        // hit plane-detection-derived surfaces) while the mesh-scanning
        // wireframe/coverage never visibly engaged. Must be set to `false`
        // before the session is even assigned below, so RealityKit never
        // gets a chance to auto-run anything on it -- `LiDARService`'s own
        // `session.run(config, ...)` in `startScan()` becomes the *only*
        // thing that ever configures/runs this session.
        arView.automaticallyConfigureSession = false
        arView.session = session
        arView.environment.sceneUnderstanding.options = [.occlusion, .receivesLighting]
        // NOTE(AI Developer), added 2026-07 per Sean's on-device feedback
        // ("Lidar scan is not visible on screen for user"): even once the
        // session/view mismatch above is fixed, ARKit's LiDAR mesh scan
        // has *no visible feedback by default* -- you'd just see plain
        // camera passthrough with zero indication of what area has
        // actually been captured. `.showSceneUnderstanding` overlays a
        // live wireframe on every reconstructed mesh triangle as it's
        // scanned, so coverage is visually obvious in real time (this is
        // the same debug option Apple's own sample scanning apps enable).
        arView.debugOptions.insert(.showSceneUnderstanding)

        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapRecognizer)
        context.coordinator.arView = arView
        onViewReady(arView)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    final class Coordinator: NSObject {
        let onTap: (CGPoint, ARView) -> Void
        weak var arView: ARView?

        init(onTap: @escaping (CGPoint, ARView) -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView else { return }
            onTap(recognizer.location(in: arView), arView)
        }
    }
}

// MARK: - Coverage arc

/// A top-down vehicle silhouette with a proportional coverage arc.
///
/// NOTE(AI Developer), added 2026-09 (spec B.2). Deliberately claims no
/// direction -- see the NOTE on `LiDARScanView.coverageIndicator` for
/// why a real compass cannot be built off today's `coveragePercent`.
/// The arc starts at the nose and sweeps clockwise as a pure proportion;
/// nothing here should be read as "this side is done", and the caption
/// says so in words rather than relying on the user to infer it.
///
/// The silhouette reuses the shape language of `ImpactMarkerView`'s car
/// outline (tapered nose, flared fenders, narrow cabin waist) at a much
/// coarser resolution, since at 118x52pt a detailed path is wasted --
/// this only has to read as "a vehicle from above" so the arc has
/// something to orbit.
struct CoverageArcView: View {
    /// 0...1. Callers clamp; this view does not silently rescale a bad
    /// value into something plausible-looking.
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let center = CGPoint(x: w / 2, y: h / 2)
            let radius = min(w, h) / 2 - 3

            ZStack {
                // Unscanned remainder, so the arc is read against a
                // whole rather than floating in space.
                Circle()
                    .stroke(.white.opacity(0.25), lineWidth: 5)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)

                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: radius * 2, height: radius * 2)
                    // `trim` starts at 3 o'clock; rotate so the sweep
                    // begins at the nose, which is the end of the
                    // silhouette the user can actually identify.
                    .rotationEffect(.degrees(-90))
                    .position(center)

                vehicleSilhouette(w: w, h: h)
            }
        }
    }

    /// A coarse top-down body outline: rounded nose, flared fenders,
    /// narrow waist, tapered tail. One mirrored path, same profile idea
    /// as `ImpactMarkerView.carOutline` but with a fraction of the
    /// points -- at this size more detail is invisible.
    private func vehicleSilhouette(w: CGFloat, h: CGFloat) -> some View {
        // Fractions of the silhouette's own box, which is inset well
        // inside the arc so the two never overlap.
        let boxW = w * 0.34
        let boxH = h * 0.66
        let profile: [(y: CGFloat, halfWidth: CGFloat)] = [
            (0.04, 0.30),   // nose tip
            (0.20, 0.46),   // front fender
            (0.50, 0.34),   // cabin waist
            (0.80, 0.46),   // rear fender
            (0.96, 0.30)    // tail
        ]

        return Path { path in
            func point(_ p: (y: CGFloat, halfWidth: CGFloat), side: CGFloat) -> CGPoint {
                CGPoint(x: boxW / 2 + side * p.halfWidth * boxW, y: p.y * boxH)
            }
            // Down the right side, then back up the left, closed --
            // a single continuous shape so one fill/stroke covers it.
            path.move(to: point(profile[0], side: 0))
            for p in profile.dropFirst() { path.addLine(to: point(p, side: 1)) }
            for p in profile.reversed() { path.addLine(to: point(p, side: -1)) }
            path.closeSubpath()
        }
        .fill(.white.opacity(0.35))
        .frame(width: boxW, height: boxH)
        .overlay(alignment: .top) {
            // The nose marker exists so the arc's start point is
            // identifiable on the vehicle. It marks the FRONT, not a
            // scanned region.
            Text("front")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .offset(y: -10)
        }
        .position(x: w / 2, y: h / 2)
    }
}
