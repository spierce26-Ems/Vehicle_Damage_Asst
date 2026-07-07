// LiDARScanView.swift
// Vehicle Damage Investigation Assistant
// Hosts an ARView for LiDAR scene reconstruction, displays coverage
// progress, and saves the scan back into the case when complete.

import SwiftUI
import ARKit
import RealityKit

struct LiDARScanView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @StateObject private var lidarService = LiDARService()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // NOTE(AI Developer), fixed 2026-07 per Sean's on-device report
            // ("Lidar scan is not visible on screen for user. Its just
            // black."): now points at `lidarService.session` -- the actual
            // session being scanned -- instead of the orphaned
            // `ARSession.shared` singleton, which was a second, never-run
            // ARSession. See the NOTE on `LiDARService.session` for the
            // full root cause.
            ARViewContainer(session: lidarService.session)
                .ignoresSafeArea()

            VStack {
                topStatus
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

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
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
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
