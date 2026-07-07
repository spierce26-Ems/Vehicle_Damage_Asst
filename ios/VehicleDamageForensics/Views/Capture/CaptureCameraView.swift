// CaptureCameraView.swift
// Vehicle Damage Forensic Matcher
// Wraps an AVCaptureSession into a SwiftUI view via UIViewRepresentable.
// Provides a live preview, a shutter button binding, and a callback
// that returns a captured UIImage to the caller.

import SwiftUI
import AVFoundation
import UIKit

// MARK: - Camera View (UIViewRepresentable)

/// Hosts the AVCaptureVideoPreviewLayer published by `CameraService`.
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraService: CameraService

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.attach(layer: cameraService.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.attach(layer: cameraService.previewLayer)
    }
}

/// UIView that owns the AVCaptureVideoPreviewLayer published by the service.
final class PreviewUIView: UIView {
    private weak var attachedLayer: AVCaptureVideoPreviewLayer?

    func attach(layer: AVCaptureVideoPreviewLayer?) {
        guard let layer, attachedLayer !== layer else { return }
        attachedLayer?.removeFromSuperlayer()
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        attachedLayer = layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachedLayer?.frame = bounds
    }
}

// MARK: - Capture Camera View (full SwiftUI screen)

struct CaptureCameraView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @StateObject private var camera = CameraService()
    @State private var lastError: String?

    var body: some View {
        ZStack {
            CameraPreviewView(cameraService: camera)
                .ignoresSafeArea()
                .task {
                    do {
                        try await camera.setupSession()
                        camera.startSession()
                    } catch {
                        lastError = error.localizedDescription
                    }
                }
                .onDisappear { camera.stopSession() }

            SensorGuidanceOverlay(
                sensorData: viewModel.currentSensorData,
                nextShotType: viewModel.nextShotType,
                progress: viewModel.progress
            )

            VStack {
                Spacer()
                Text(viewModel.statusMessage)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.5), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.bottom, 16)

                shutterButton
                    .padding(.bottom, 40)
            }
        }
        .alert("Camera Error",
               isPresented: .constant(lastError != nil),
               actions: { Button("OK") { lastError = nil } },
               message: { Text(lastError ?? "") })
    }

    private var shutterButton: some View {
        Button {
            Task { await captureNextShot() }
        } label: {
            Circle()
                .fill(.white)
                .frame(width: 72, height: 72)
                .overlay(Circle().stroke(.gray, lineWidth: 3).padding(4))
        }
        .disabled(viewModel.isComplete)
    }

    /// Bridge between the camera service's protocol-step API and our
    /// view-model's simpler `record(image:)` recorder.
    private func captureNextShot() async {
        guard let nextType = viewModel.nextShotType else { return }
        let step = CaptureProtocolStep.fullProtocol
            .first(where: { $0.photoType == nextType })
            ?? CaptureProtocolStep.fullProtocol[0]
        do {
            let photo = try await camera.capturePhoto(
                forStep: step,
                sequenceIndex: viewModel.currentShotIndex + 1
            )
            if let img = UIImage(data: photo.imageData) {
                await viewModel.record(image: img)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
