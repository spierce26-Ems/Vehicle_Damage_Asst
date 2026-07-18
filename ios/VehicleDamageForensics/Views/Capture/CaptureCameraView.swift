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

    // NOTE(AI Developer), added 2026-07 per Sean's request ("i want to
    // have guided autocapture for every image along with current option
    // to use the camera roll as well") -- see `CameraService`'s
    // "Guided Auto-Capture State" MARK for the gate logic itself. This
    // view only needs to: (1) track which `PhotoType` the auto-capture
    // gates are currently tuned for so it can reset the streak and
    // re-derive `currentShotRequiresEvenLighting` when the protocol
    // advances to a new shot, and (2) briefly flash green + haptic on
    // an auto-fired capture, mirroring `ScarCaptureView.justAutoCapture`.
    @State private var lastGatedShotType: PhotoType?
    @State private var justAutoCapture = false

    var body: some View {
        ZStack {
            CameraPreviewView(cameraService: camera)
                .ignoresSafeArea()
                .task {
                    // NOTE(AI Developer), added 2026-07 for guided
                    // auto-capture: set the callback and the initial
                    // lighting-gate requirement BEFORE `setupSession()`
                    // starts the session, so the very first frame
                    // analyzed already has the right gate configuration
                    // -- mirrors `ScarCaptureView`'s identical ordering.
                    camera.onAutoCapture = { Task { await performAutoCapture() } }
                    camera.currentShotRequiresEvenLighting = viewModel.nextShotType?.usesEvenLightingGate ?? false
                    lastGatedShotType = viewModel.nextShotType
                    do {
                        try await camera.setupSession()
                        camera.startSession()
                    } catch {
                        lastError = error.localizedDescription
                    }
                }
                .onDisappear { camera.stopSession() }
                // NOTE(AI Developer), added 2026-07: the protocol
                // advances to a new `PhotoType` after every capture/
                // import/skip -- re-derive whether the new shot requires
                // the Even Lighting gate (see `PhotoType
                // .usesEvenLightingGate`) and reset the auto-capture
                // streak so a "good" streak measured against the OLD
                // shot's requirements can't immediately fire a capture
                // for the NEW shot before the camera's had a chance to
                // actually re-evaluate the new gate.
                .onChange(of: viewModel.nextShotType) { _, newType in
                    guard newType != lastGatedShotType else { return }
                    lastGatedShotType = newType
                    camera.currentShotRequiresEvenLighting = newType?.usesEvenLightingGate ?? false
                    camera.resetAutoCaptureStreak()
                }

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
                // NOTE(AI Developer), added 2026-07 for guided auto-
                // capture -- same Steady/Focused/(Lighting) status chips
                // as `ScarCaptureView.statusChips`, so the same "why
                // hasn't it fired yet" feedback is available here too.
                // The Lighting chip only appears when the current shot
                // type actually gates on it (`usesEvenLightingGate`);
                // showing it unconditionally would suggest wide/outdoor
                // shots need even lighting when they don't.
                autoCaptureStatusChips
                    .padding(.bottom, 10)

                // NOTE(AI Developer), added 2026-07 per Sean's on-device
                // report ("auto capture worked way too fast... need a
                // ready button... to trigger the autocapture when the
                // user is ready"). Shown only once the sensor gates
                // already look good AND the user hasn't armed yet, so
                // it never competes for attention while the phone is
                // still being repositioned/focused. Tapping it calls
                // `camera.armAutoCapture()`, which starts the
                // `autoCaptureHoldSeconds` countdown from that instant --
                // see `CameraService.isArmed` for why this actually
                // fixes the reported bug (a fresh hold-timer alone
                // wasn't enough, since the phone is often still
                // steady/focused/lit right after the previous shot).
                if camera.allGatesGood && !camera.isArmed {
                    readyButton
                        .padding(.bottom, 10)
                }

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

            // NOTE(AI Developer), added 2026-07: brief green "snap" flash
            // the instant auto-capture fires, identical to
            // `ScarCaptureView`'s `justAutoCapture` flash -- paired with
            // the success haptic in `performAutoCapture()`.
            // `.allowsHitTesting(false)` so it never blocks the shutter/
            // library/skip buttons beneath it.
            if justAutoCapture {
                Color.green.opacity(0.35)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: justAutoCapture)
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

    /// NOTE(AI Developer), added 2026-07 for guided auto-capture:
    /// wraps the pre-existing manual `shutterButton` with a filling
    /// progress ring (green, tracks `camera.autoCaptureProgress`) --
    /// same "hold still and watch it fill" affordance as
    /// `ScarCaptureView.autoCaptureRingAndShutter`. The manual button
    /// itself is completely unchanged (same label, same
    /// `captureNextShot()` action, same `.disabled` condition) so
    /// tapping it still works exactly as before regardless of gate
    /// state -- the ring is purely an additive visual layered around it.
    private var shutterButton: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.3), lineWidth: 4)
                .frame(width: 84, height: 84)
            Circle()
                .trim(from: 0, to: camera.autoCaptureProgress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 84, height: 84)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: camera.autoCaptureProgress)
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
    }

    /// NOTE(AI Developer), added 2026-07 alongside `CameraService
    /// .isArmed` -- explicit user confirmation that they're done
    /// repositioning and ready for the auto-capture countdown to start
    /// for this shot. Distinct styling (blue, pill-shaped, labeled) from
    /// the shutter/library/skip circles below so it reads as a
    /// deliberate "start the timer" action, not another capture button.
    private var readyButton: some View {
        Button {
            camera.armAutoCapture()
        } label: {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.blue, in: Capsule())
                .foregroundStyle(.white)
        }
    }

    /// NOTE(AI Developer), added 2026-07 for guided auto-capture, same
    /// chip layout/logic as `ScarCaptureView.statusChips` -- Lighting
    /// only shown when the current shot type gates on it (see
    /// `PhotoType.usesEvenLightingGate`; wide/context/profile shots
    /// don't show a Lighting chip at all since it's never a requirement
    /// for them).
    // NOTE(AI Developer), reworked 2026-07 alongside the identical fix in
    // `ScarCaptureView.statusChips` (see that file's comment for the full
    // root-cause writeup, confirmed via an on-device screenshot of that
    // screen) -- same three-`.fixedSize`-capsules-in-one-`HStack` pattern
    // here has the same latent overflow risk once the Lighting chip's
    // longer messages are shown, so it gets the same two-row fix:
    // Steady/Focused on row one, Lighting (when shown) alone on row two
    // at full width with `.minimumScaleFactor` instead of being clipped.
    private var autoCaptureStatusChips: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                autoCaptureStatusChip(label: "Steady", isGood: camera.isSteady, systemImage: "hand.raised.fill")
                autoCaptureStatusChip(label: "Focused", isGood: camera.isFocused, systemImage: "camera.metering.spot")
            }
            if viewModel.nextShotType?.usesEvenLightingGate == true {
                autoCaptureStatusChip(label: camera.lightingMessage, isGood: camera.isWellLit, systemImage: "sun.max.fill", fillWidth: true)
            }
        }
    }

    private func autoCaptureStatusChip(label: String, isGood: Bool, systemImage: String, fillWidth: Bool = false) -> some View {
        Label(label, systemImage: isGood ? "checkmark.circle.fill" : systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(fillWidth ? 0.75 : 1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isGood ? Color.green.opacity(0.75) : Color.black.opacity(0.55), in: Capsule())
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .fixedSize(horizontal: !fillWidth, vertical: false)
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

    /// NOTE(AI Developer), added 2026-07 for guided auto-capture:
    /// `camera.onAutoCapture` (wired in `.task` above) calls this
    /// exactly the way `ScarCaptureView.performCapture(auto: true)`
    /// works -- the success haptic + green flash are reserved for the
    /// auto path since a manual tap already gets its own implicit
    /// tactile confirmation from the button press. Guards on
    /// `camera.isCapturing`-equivalent via `viewModel.isComplete`/
    /// `captureNextShot`'s own `nextShotType` guard, so this can't fire
    /// a duplicate capture if the streak callback lands while a capture
    /// from a manual tap is already in flight.
    private func performAutoCapture() async {
        guard !viewModel.isComplete else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        justAutoCapture = true
        await captureNextShot()
        try? await Task.sleep(nanoseconds: 250_000_000)
        justAutoCapture = false
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
            // NOTE(AI Developer), added 2026-07 for guided auto-capture:
            // a fresh streak is required before auto-capture can fire
            // again for the shot the protocol advances to next --
            // otherwise a phone that's still steady/focused/well-lit
            // right after this shutter press could immediately
            // auto-fire a second capture before the user has had a
            // chance to reposition for the new shot. `.onChange(of:
            // viewModel.nextShotType)` above also resets this once the
            // published `nextShotType` actually changes, but resetting
            // it here too closes the brief window between this
            // capture completing and that change propagating.
            camera.resetAutoCaptureStreak()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
