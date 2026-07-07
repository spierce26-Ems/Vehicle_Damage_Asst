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
            ARViewContainer(session: ARSession.shared)
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
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

// MARK: - ARSession singleton (used by both LiDARService and ARView)

extension ARSession {
    static let shared = ARSession()
}
