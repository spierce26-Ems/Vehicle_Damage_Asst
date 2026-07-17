// CaptureCameraView.swift
// Vehicle Damage Investigation Assistant
// Wraps an AVCaptureSession into a SwiftUI view via UIViewRepresentable.
// Provides a live preview, a shutter button binding, and a callback
// that returns a captured UIImage to the caller.

import SwiftUI
import AVFoundation
import UIKit
import PhotosUI

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
    // NOTE(AI Developer), added 2026-07 per Sean's request ("we also
    // should have the ability to upload images from camera roll").
    // `PhotosPickerItem` is `PhotosUI`'s selection handle; the actual
    // `UIImage` is loaded asynchronously in `importSelectedPhoto` below.
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isImportingPhoto = false
    // NOTE(AI Developer), added 2026-07 per Sean's "skip a shot" request
    // -- see `skipButton`/`skipConfirmationDialog` below.
    @State private var showSkipConfirmation = false
    // NOTE(AI Developer), added 2026-07 as part of the paint-color
    // reference-normalization fix ("yes build it now"). Holds the
    // just-captured photo when it was a `.paintTransfer` shot, which
    // drives presenting `PaintReferenceMarkerView` as a sheet immediately
    // after capture -- see `captureNextShot()` below for the trigger
    // point. `nil` the rest of the time (sheet dismissed).
    @State private var pendingPaintReferencePhoto: CapturedPhoto?

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

                // NOTE(AI Developer), added 2026-07 per Sean's request
                // ("we also should have the ability to upload images from
                // camera roll"). Laid out either side of the shutter
                // button, mirroring the classic Camera.app layout
                // (thumbnail/library button opposite the flash toggle,
                // shutter centered) so it reads as a familiar affordance
                // rather than a bolted-on extra control.
                //
                // NOTE(AI Developer), updated 2026-07 per Sean's explicit
                // answer on where the skip control should live ("a button
                // next to the shutter/photo-library buttons"): the trailing
                // slot that used to be an empty `Color.clear` spacer
                // (there purely to keep the shutter button visually
                // centered against `photoLibraryButton`'s width) is now
                // `skipButton`, so the row reads library — shutter — skip,
                // and the shutter stays centered since both side buttons
                // are the same 56x56 size.
                HStack {
                    photoLibraryButton
                    Spacer()
                    shutterButton
                    Spacer()
                    skipButton
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .padding(.horizontal)

            if isImportingPhoto {
                Color.black.opacity(0.4).ignoresSafeArea()
                ProgressView("Importing…")
                    .tint(.white)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Camera Error",
               isPresented: .constant(lastError != nil),
               actions: { Button("OK") { lastError = nil } },
               message: { Text(lastError ?? "") })
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task { await importSelectedPhoto(newItem) }
        }
        // NOTE(AI Developer), added 2026-07 per Sean's "skip a shot"
        // request. A confirmation dialog (rather than skipping instantly
        // on tap) avoids an accidental tap silently dropping a required
        // shot -- and the two reason options double as the audit-log
        // detail text, directly reflecting the two scenarios Sean
        // described ("if we dont have an image in the camera roll or are
        // no longer near the vehicle").
        .confirmationDialog(
            "Skip this shot?",
            isPresented: $showSkipConfirmation,
            titleVisibility: .visible
        ) {
            Button("No matching photo in camera roll", role: .destructive) {
                Task { await viewModel.skipCurrentShot(reason: "No matching photo in camera roll") }
            }
            Button("No longer near the vehicle", role: .destructive) {
                Task { await viewModel.skipCurrentShot(reason: "No longer near vehicle") }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let type = viewModel.nextShotType {
                Text("\(type.displayName) will be marked as skipped and excluded from the analysis. This shot type isn't required — you can still run the full analysis without it.")
            }
        }
        // NOTE(AI Developer), added 2026-07 as part of the paint-color
        // reference-normalization fix. Presented immediately after a
        // `.paintTransfer` shot is captured (see `captureNextShot()`),
        // while the investigator is still standing at the vehicle and the
        // photo's lighting/framing is fresh -- tapping the damage area
        // and a clean reference panel right away is far more reliable
        // than trying to do it later from a gallery with no context.
        .sheet(item: $pendingPaintReferencePhoto) { photo in
            NavigationStack {
                PaintReferenceMarkerView(viewModel: viewModel, photo: photo)
            }
        }
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

    /// NOTE(AI Developer), added 2026-07 per Sean's request ("we also
    /// should have the ability to upload images from camera roll").
    /// `PhotosPicker` is Apple's modern (iOS 16+) picker API -- unlike the
    /// older `UIImagePickerController`/`PHPickerViewController` UIKit
    /// bridges, it runs out-of-process, so the app is never granted
    /// access to the user's full photo library (only the specific
    /// image(s) the user explicitly selects come back through the
    /// picker). This satisfies the already-declared
    /// `NSPhotoLibraryUsageDescription` intent ("import existing damage
    /// photos") with the least-privilege mechanism available.
    private var photoLibraryButton: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            Circle()
                .fill(.black.opacity(0.45))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "photo.on.rectangle")
                        .font(.title3)
                        .foregroundStyle(.white)
                )
        }
        .disabled(viewModel.isComplete || isImportingPhoto)
    }

    /// NOTE(AI Developer), added 2026-07 per Sean's "skip a shot" request
    /// -- placed as the third button in the shutter row (his explicit
    /// answer: "a button next to the shutter/photo-library buttons"),
    /// same 56x56 footprint as `photoLibraryButton` so the shutter button
    /// stays visually centered between the two. Disabled once the
    /// protocol is already complete, mirroring `shutterButton`/
    /// `photoLibraryButton`'s own disabled conditions.
    private var skipButton: some View {
        Button {
            showSkipConfirmation = true
        } label: {
            Circle()
                .fill(.black.opacity(0.45))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "arrow.uturn.forward")
                        .font(.title3)
                        .foregroundStyle(.white)
                )
        }
        .disabled(viewModel.isComplete || isImportingPhoto)
    }

    private func importSelectedPhoto(_ item: PhotosPickerItem) async {
        isImportingPhoto = true
        defer {
            isImportingPhoto = false
            selectedPhotoItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                lastError = "Could not load the selected photo."
                return
            }
            await viewModel.importPhoto(image)
        } catch {
            lastError = error.localizedDescription
        }
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
            // NOTE(AI Developer), fixed 2026-07 per Sean's on-device
            // report ("terminated due to using too much memory", Xcode
            // debug code 9): this used to do `UIImage(data: photo.imageData)`
            // -- decoding the ~12MP JPEG `CameraService` just produced
            // back into a full ~46.5MB uncompressed bitmap -- purely to
            // hand it to `viewModel.record(image:)`, which then
            // re-encoded it to JPEG *again* and rebuilt a second, weaker
            // `CapturedPhoto` from scratch (see NOTE on
            // `CaptureViewModel.record(photo:)`). `camera.capturePhoto`
            // already returns a complete, correctly-scored
            // `CapturedPhoto` with real GPS/sensor data -- there was
            // never a reason to go through `UIImage` here at all. Passing
            // it straight through removes a third full-resolution
            // decode+re-encode per shot and fixes a real metadata-quality
            // regression at the same time.
            await viewModel.record(photo: photo)
            // NOTE(AI Developer), added 2026-07 as part of the paint-color
            // reference-normalization fix: right after a `.paintTransfer`
            // shot is recorded, immediately prompt for the two reference-
            // swatch taps (damage area + clean panel) on THIS photo, while
            // the investigator is still at the vehicle. Triggered after
            // `record(photo:)` (not before) so the photo already carries
            // its final `id`/`sequenceIndex` from the stored case, and
            // `PaintReferenceMarkerView.save()` can look it up reliably by
            // `photoID` in `CaptureViewModel.recordPaintReferenceTaps`.
            if photo.photoType == .paintTransfer {
                pendingPaintReferencePhoto = photo
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
