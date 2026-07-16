// LiDARService.swift
// Vehicle Damage Investigation Assistant
// ARKit LiDAR depth scanning service — produces depth maps and 3D meshes
// for forensic-grade dimensional analysis of damaged vehicles.

import Foundation
import ARKit
import RealityKit
import Combine

// MARK: - LiDAR Service

/// Wraps an ARKit world-tracking session with scene reconstruction.
/// Only available on devices with the LiDAR sensor (iPhone Pro line, iPad Pro).
@MainActor
final class LiDARService: NSObject, ObservableObject {

    // MARK: Published state

    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var coveragePercent: Double = 0
    @Published private(set) var pointCloudCount: Int = 0
    @Published private(set) var lastError: ScanError?

    /// NOTE(AI Developer), added 2026-07 per Sean's on-device report
    /// ("Lidar took a while to start and the lidar crashed/stop"). This
    /// is a *transient* status message (tracking initializing/degraded),
    /// distinct from `lastError` (a hard failure) -- surfaced so the user
    /// sees *why* nothing seems to be happening ("Initializing — hold the
    /// phone steady") instead of an unexplained delay that looks frozen
    /// or crashed. `nil` when tracking is normal. See
    /// `session(_:cameraDidChangeTrackingState:)` below.
    @Published private(set) var trackingStateMessage: String?

    // MARK: Internal

    // NOTE(AI Developer), fixed 2026-07 per Sean's on-device report
    // ("Lidar scan is not visible on screen for user. Its just black."):
    // this `session` was `private`, so `LiDARScanView`'s visible `ARView`
    // had no way to actually display it -- it was instead wired to a
    // second, completely separate `ARSession.shared` singleton (defined in
    // LiDARScanView.swift) that this service never touches or calls
    // `.run()` on. Two independent ARSessions: one scanning invisibly,
    // one displayed but never started -- hence a permanently black
    // screen. Fixed by exposing this session so the view can render the
    // *actual* session doing the scanning.
    let session = ARSession()
    private var configuration: ARWorldTrackingConfiguration?
    private var meshAnchors: [UUID: ARMeshAnchor] = [:]

    // MARK: Lifecycle

    override init() {
        super.init()
        self.isAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        session.delegate = self
    }

    deinit {
        // ARSession will pause itself on deallocation; no manual call needed
        // since we cannot reach @MainActor methods from deinit.
    }

    // MARK: Public API

    /// Begins a LiDAR scan. Throws if the device lacks a LiDAR sensor.
    func startScan() throws {
        guard isAvailable else {
            // NOTE(AI Developer): publish to `lastError` in addition to
            // throwing, so `LiDARScanView`'s `.alert(... lidarService.lastError
            // ...)` actually shows this -- previously this only threw,
            // and the view's `catch` block was empty, so an
            // unsupported-device failure was silently invisible.
            lastError = .unsupportedDevice
            throw ScanError.unsupportedDevice
        }

        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .mesh
        config.frameSemantics.insert(.sceneDepth)
        config.environmentTexturing = .automatic
        config.planeDetection = [.horizontal, .vertical]
        configuration = config

        meshAnchors.removeAll()
        coveragePercent = 0
        pointCloudCount = 0
        lastError = nil

        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isScanning = true
    }

    /// NOTE(AI Developer), added 2026-07 alongside the new
    /// `LiDARScanView` error alert: `lastError` is `private(set)` (only
    /// this service can set it), so the alert's "OK" button needs an
    /// explicit way to clear it -- otherwise `.alert(isPresented:
    /// .constant(lidarService.lastError != nil), ...)` would never
    /// actually dismiss (a `.constant` binding ignores SwiftUI's own
    /// attempt to set it back to `false` on dismissal).
    func clearError() {
        lastError = nil
    }

    /// Stops the scan and returns a serialized snapshot of the captured data.
    func stopScan() -> LiDARScanData {
        session.pause()
        isScanning = false

        return LiDARScanData(
            pointCloudCount: pointCloudCount,
            coveragePercent: coveragePercent,
            meshFileURL: nil,
            scanDate: Date(),
            depthMapData: nil
        )
    }

    /// Captures the current scene depth as a serialized blob suitable for storage.
    func captureCurrentDepthMap() -> Data? {
        guard let frame = session.currentFrame,
              let depth = frame.sceneDepth else { return nil }
        return PixelBufferEncoder.encode(depth.depthMap)
    }

    // MARK: Tap-to-measure

    // NOTE(AI Developer), added 2026-07 per Sean's explicit request ("wire
    // LiDAR data into the Height Alignment factor as a next step... we
    // need the use of Lidar as an extra tool"). This is the piece that
    // turns a saved LiDAR scan into an actual usable measurement instead
    // of an inert blob: `LiDARScanView` calls this once for a tap on the
    // ground beside the vehicle and once for a tap on the damage point,
    // then hands both world-space Y values to
    // `heightFromWorldPositions(groundY:damageY:)` below to get a real
    // number of inches for `Vehicle.lidarMeasuredHeightInches`.
    //
    // Uses `ARView.raycast(from:allowing:alignment:)` with
    // `.estimatedPlane`, not `.existingPlaneGeometry` -- per Apple's own
    // scene-reconstruction docs ("Visualizing and interacting with a
    // reconstructed scene"), `.estimatedPlane` is the target that lets a
    // raycast intersect the *non-planar* reconstructed mesh triangles
    // (vehicle body panels, ground texture, etc.), not just the flat
    // plane anchors from `ARWorldTrackingConfiguration.planeDetection`.
    // That mesh-level intersection is exactly what `LiDARService.startScan()`
    // already enables via `config.sceneReconstruction = .mesh`.
    //
    // Returns `nil` if the tap doesn't land on any reconstructed surface
    // (e.g. pointed at open space) -- `LiDARScanView` should tell the user
    // to try again rather than silently recording a bogus measurement.
    func worldY(from arView: ARView, at screenPoint: CGPoint) -> Float? {
        let results = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .any)
        guard let hit = results.first else { return nil }
        // `worldTransform` is a simd_float4x4; column 3 is the translation
        // (position) component, and its `y` is the vertical (gravity-
        // aligned) world-space coordinate, in meters, matching how ARKit's
        // world-tracking origin is oriented (Y up).
        return hit.worldTransform.columns.3.y
    }

    /// Converts two world-space Y coordinates (meters, from `worldY`) into
    /// a positive height in inches. Order of the two taps doesn't matter --
    /// this is always the absolute vertical distance between them.
    func heightFromWorldPositions(groundY: Float, damageY: Float) -> Double {
        let meters = abs(Double(damageY) - Double(groundY))
        return MeasurementHelpers.convert(meters, from: .meters, to: .inches)
    }

    // MARK: Coverage estimation

    /// Rough coverage based on mesh anchor count and total tracked area.
    /// In production we'd compute actual surface area from the mesh geometry.
    private func recomputeCoverage() {
        let count = meshAnchors.count
        // Heuristic: ~10 mesh anchors ≈ full vehicle coverage.
        coveragePercent = min(100.0, Double(count) * 10.0)
    }
}

// MARK: - ARSessionDelegate

extension LiDARService: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let mesh = anchor as? ARMeshAnchor {
                    self.meshAnchors[mesh.identifier] = mesh
                    self.pointCloudCount += mesh.geometry.vertices.count
                }
            }
            self.recomputeCoverage()
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors where anchor is ARMeshAnchor {
                self.meshAnchors[anchor.identifier] = (anchor as! ARMeshAnchor)
            }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = .session(error.localizedDescription)
            self.isScanning = false
        }
    }

    // NOTE(AI Developer), added 2026-07 per Sean's on-device report
    // ("Lidar took a while to start and the lidar crashed/stop"). Two
    // separate gaps this closes:
    //
    // 1. "Took a while to start": ARKit's world-tracking + scene
    //    reconstruction needs a few seconds of camera motion/parallax
    //    before tracking quality reaches `.normal` -- this is normal
    //    ARKit behavior, not a hang, but the UI gave zero indication of
    //    it, so a genuinely slow-but-working start looked identical to a
    //    frozen one. `cameraDidChangeTrackingState` now publishes a
    //    human-readable `trackingStateMessage` (e.g. "Initializing... "
    //    or the specific `.limited(reason:)` text) that `LiDARScanView`
    //    shows in `topStatus`, `nil` once tracking is `.normal`.
    //
    // 2. "Crashed/stop": `didFailWithError` (above) only fires for a
    //    genuinely fatal session error -- it does NOT fire for a
    //    *interruption* (e.g. the system briefly takes the camera for a
    //    phone call / Control Center / multitasking), which instead
    //    calls `sessionWasInterrupted`/`sessionInterruptionEnded` and,
    //    critically, leaves `isScanning` sitting at `true` with no mesh
    //    data arriving -- from the user's point of view, indistinguishable
    //    from an actual crash ("the lidar... stop"). Previously this
    //    service had no `sessionWasInterrupted`/`sessionInterruptionEnded`
    //    handling at all. Now an interruption surfaces as a
    //    `trackingStateMessage` immediately, and ending the interruption
    //    resets tracking (matching Apple's own recommendation for
    //    scene-reconstruction sessions, where stale mesh anchors from
    //    before the interruption are not worth preserving) so scanning
    //    reliably resumes instead of silently sitting stalled.
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            self.trackingStateMessage = "Scan interrupted — hold the vehicle in view to resume."
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            guard let config = self.configuration else { return }
            self.trackingStateMessage = nil
            self.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        Task { @MainActor in
            switch camera.trackingState {
            case .normal:
                self.trackingStateMessage = nil
            case .notAvailable:
                self.trackingStateMessage = "Tracking not available yet…"
            case .limited(let reason):
                switch reason {
                case .initializing:
                    self.trackingStateMessage = "Initializing — hold the phone steady…"
                case .excessiveMotion:
                    self.trackingStateMessage = "Moving too fast — slow down for better tracking."
                case .insufficientFeatures:
                    self.trackingStateMessage = "Can't find enough detail — try better lighting or a less plain surface."
                case .relocalizing:
                    self.trackingStateMessage = "Relocalizing…"
                @unknown default:
                    self.trackingStateMessage = "Tracking limited…"
                }
            }
        }
    }
}

// MARK: - Errors

enum ScanError: LocalizedError, Equatable {
    case unsupportedDevice
    case session(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedDevice:
            return "This device does not support LiDAR scene reconstruction."
        case .session(let msg):
            return "AR session failed: \(msg)"
        }
    }
}

// MARK: - Helpers

private enum PixelBufferEncoder {
    /// Serialize a CVPixelBuffer holding depth values to plain Float32 binary data.
    static func encode(_ buffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        var data = Data(capacity: stride * height + 8)
        var w = UInt32(width).littleEndian
        var h = UInt32(height).littleEndian
        data.append(Data(bytes: &w, count: 4))
        data.append(Data(bytes: &h, count: 4))
        data.append(Data(bytes: base, count: stride * height))
        return data
    }
}
