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
        guard isAvailable else { throw ScanError.unsupportedDevice }

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
