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
    case tapMissedSurface
}

struct LiDARScanView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @StateObject private var lidarService = LiDARService()
    @Environment(\.dismiss) private var dismiss
    @State private var measurementStep: MeasurementStep = .notStarted
    @State private var isSavingMeasurement = false

    var body: some View {
        ZStack {
            // NOTE(AI Developer), fixed 2026-07 per Sean's on-device report
            // ("Lidar scan is not visible on screen for user. Its just
            // black."): now points at `lidarService.session` -- the actual
            // session being scanned -- instead of the orphaned
            // `ARSession.shared` singleton, which was a second, never-run
            // ARSession. See the NOTE on `LiDARService.session` for the
            // full root cause.
            ARViewContainer(session: lidarService.session) { point, arView in
                handleTap(at: point, in: arView)
            }
            .ignoresSafeArea()

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
            catch { /* surface error */ }
        }
        .onDisappear {
            if lidarService.isScanning {
                _ = lidarService.stopScan()
            }
        }
    }

    // MARK: Tap-to-measure

    /// Routes a screen tap to whichever step of the ground/damage-point
    /// measurement flow is currently active. Taps are ignored entirely
    /// when `measurementStep == .notStarted` (the user hasn't pressed
    /// "Measure Height" yet), so ordinary scanning isn't disrupted by
    /// incidental taps on the AR view.
    private func handleTap(at point: CGPoint, in arView: ARView) {
        switch measurementStep {
        case .notStarted, .measured, .tapMissedSurface:
            return
        case .awaitingGroundTap:
            guard let y = lidarService.worldY(from: arView, at: point) else {
                measurementStep = .tapMissedSurface
                return
            }
            measurementStep = .awaitingDamageTap(groundY: y)
        case .awaitingDamageTap(let groundY):
            guard let damageY = lidarService.worldY(from: arView, at: point) else {
                measurementStep = .tapMissedSurface
                return
            }
            let inches = lidarService.heightFromWorldPositions(groundY: groundY, damageY: damageY)
            measurementStep = .measured(inches: inches)
        }
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
            case .awaitingDamageTap:
                Label("Now tap the damage point on the vehicle", systemImage: "hand.tap.fill")
            case .tapMissedSurface:
                Label("Couldn't find a surface there — keep scanning that area, then try again", systemImage: "exclamationmark.triangle.fill")
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

    private var topStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "scanner.fill")
                Text(lidarService.isAvailable
                     ? "LiDAR available"
                     : "LiDAR not supported on this device")
            }
            .foregroundStyle(.white)

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
            Button {
                measurementStep = .awaitingGroundTap
            } label: {
                Label("Measure Height", systemImage: "ruler")
            }
            .buttonStyle(.bordered)
            .disabled(!lidarService.isScanning || measurementStep != .notStarted)

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
