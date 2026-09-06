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
                if measurementStep != .notStarted {
                    measurementBanner
                }
                Spacer()
                bottomControls
            }
            .padding()
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
                Label("Tap the ground beside the vehicle", systemImage: "hand.tap.fill")
                // NOTE(AI Developer), added 2026-07 per Sean's request
                // for in-flow "why this matters" guidance on steps that
                // aren't obviously self-explanatory -- measuring a
                // height off the ground is one of those (unlike a
                // photo, it's not obvious *why* you'd do this at all).
                whyThisMattersNote("This measures how high off the ground the damage is — useful for confirming both vehicles' damage lines up at the same height.")
            case .awaitingDamageTap:
                Label("Now tap the damage point on the vehicle", systemImage: "hand.tap.fill")
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
            case .measured(let inches):
                HStack {
                    Text("Measured height: \(MeasurementHelpers.formatInchesWithMetric(inches))")
                        .font(.headline)
                    Spacer()
                    Button("Retry") { measurementStep = .awaitingGroundTap }
                        .buttonStyle(.bordered)
                    Button {
                        confirmMeasurement()
                    } label: {
                        // NOTE(AI Developer): see the analogous NOTE in
                        // ImpactMarkerView.swift -- wrapping the if/else
                        // in `Group` is required here too, for the same
                        // ViewBuilder-modifier-chaining reason.
                        Group {
                            if isSavingMeasurement {
                                ProgressView().tint(.white)
                            } else {
                                Text("Save")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSavingMeasurement)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    /// A 44pt crosshair locked to the centre of the AR view, so the user
    /// aims the phone rather than a fingertip. Purely an aim indicator:
    /// it is not interactive and never consumes touches, so
    /// tap-to-raycast keeps working underneath it.
    private var setPointReticle: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 2)
                .frame(width: 44, height: 44)
            Circle()
                .fill(.white)
                .frame(width: 4, height: 4)
            // Short ticks rather than full crosshairs through the middle:
            // the centre must stay clear so the surface being aimed at
            // is visible, which is the whole point of aiming.
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

            ProgressView(value: lidarService.coveragePercent / 100.0) {
                Text("Coverage \(Int(lidarService.coveragePercent))% • Points \(lidarService.pointCloudCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
            }
            .tint(.green)
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
