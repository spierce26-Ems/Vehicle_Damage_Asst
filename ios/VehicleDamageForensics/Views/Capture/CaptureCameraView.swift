// CaptureCameraView.swift
// Vehicle Damage Investigation Assistant
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

            // NOTE(AI Developer), fixed 2026-07: SensorGuidanceOverlay now
            // only renders the top progress bar (self-anchored to the top,
            // no conflict there). The Roll/Pitch readout (SensorLevelBar)
            // moved into *this* bottom VStack, directly above the status
            // message and shutter button -- previously it lived inside
            // SensorGuidanceOverlay's own independently bottom-anchored
            // VStack, which caused it to visually overlap/collide with the
            // shutter button (both stacks pinned content to the bottom via
            // their own Spacer()). Confirmed fixed via Simulator screenshot.
            SensorGuidanceOverlay(
                nextShotType: viewModel.nextShotType,
                progress: viewModel.progress
            )

            VStack {
                Spacer()
                SensorLevelBar(sensorData: viewModel.currentSensorData)
                    .padding(.bottom, 12)

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
            .padding(.horizontal)
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
    ///
    /// NOTE(AI Developer): `CaptureViewModel.protocolShots` (v1, 10 shots)
    /// and `CaptureProtocolStep.fullProtocol` (30 detailed coaching steps)
    /// are two different lists — see the NOTE on `PhotoType.requiredCaptureProtocol`
    /// for why v1 intentionally ships the shorter list. This method uses
    /// `fullProtocol` purely as a *coaching metadata* lookup (ideal pitch/
    /// roll/distance/instruction text) for whatever shot the 10-shot list
    /// is currently asking for. The original code picked that metadata via
    /// `.first(where: { $0.photoType == nextType })`, which is a real bug:
    /// several photoTypes repeat multiple times in `fullProtocol` (e.g.
    /// `.closeupDamage` appears at ids 5, 6, 7, 11-13, 21, 26), so it always
    /// silently returned the *first* match's coaching parameters (id 5's
    /// "straight-on closeup" framing) even when guiding the viewModel's 2nd
    /// closeup shot. Fixed by matching on the current shot's ordinal
    /// position among same-typed shots, so e.g. the 2nd `.closeupDamage`
    /// requested by the viewModel maps to the 2nd `.closeupDamage` entry in
    /// `fullProtocol`, giving distinct/appropriate coaching per repeat shot.
    private func captureNextShot() async {
        guard let nextType = viewModel.nextShotType else { return }

        // Which occurrence of `nextType` is this within the v1 protocol so
        // far (1st, 2nd, ...)? e.g. if this is the 2nd .closeupDamage shot
        // requested, we want the 2nd .closeupDamage entry in fullProtocol.
        let occurrenceIndex = viewModel.protocolShots[0..<viewModel.currentShotIndex]
            .filter { $0 == nextType }
            .count

        let matchingSteps = CaptureProtocolStep.fullProtocol.filter { $0.photoType == nextType }
        let step: CaptureProtocolStep
        if occurrenceIndex < matchingSteps.count {
            step = matchingSteps[occurrenceIndex]
        } else {
            step = matchingSteps.last ?? CaptureProtocolStep.fullProtocol[0]
        }
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
