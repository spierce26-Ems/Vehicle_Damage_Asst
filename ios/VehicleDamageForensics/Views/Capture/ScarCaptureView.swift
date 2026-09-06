// ScarCaptureView.swift
// Vehicle Damage Investigation Assistant
// Guided, auto-capturing camera for the Scar-Direction Consistency
// feature, followed by an in-photo line-marking step. Two stages in one
// view: `.aiming` (live camera + auto-capture) -> `.marking` (drag a line
// along the scar on the captured photo + say which end is toward the
// front).
//
// NOTE(AI Developer), added 2026-07 per Sean's explicit request: "can we
// have the hold the phone over the damage and automatically capture the
// image when the phone is in the correct position like the auto capture
// when I remote deposit a check with wells fargo?" -- see
// `ScarCaptureCameraService` for the three live gates (Steady / Focused /
// Even Lighting) that drive the auto-capture ring here, and that file's
// header comment for why "Even Lighting" specifically is not just a nice-
// to-have for this particular shot (it protects `ColorAnalysis
// .detectScarTaper`'s reading from being faked by a shadow/glare
// gradient across the scar).
//
// Presented as a sheet from `CaptureFlowView`'s footer, mirroring how
// `ImpactMarkerView` is presented -- see that file's `.sheet(isPresented:)`
// wiring for the pattern this follows.

import SwiftUI
import AVFoundation
import UIKit
import PhotosUI

// MARK: - Scar Capture View

struct ScarCaptureView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case aiming
        case focusRegion
        case marking
    }

    @State private var stage: Stage = .aiming
    @StateObject private var camera = ScarCaptureCameraService()
    @State private var lastError: String?
    @State private var capturedPhoto: CapturedPhoto?
    // NOTE(AI Developer), added 2026-07 per Sean's explicit request
    // ("we need to be able to upload an image for scar from the roll as
    // well"). Mirrors `CaptureCameraView`'s `selectedPhotoItem`/
    // `isImportingPhoto` pattern exactly (see that file's
    // `photoLibraryButton`/`importSelectedPhoto(_:)`) -- picked photo
    // goes straight into the same `capturedPhoto`/`uiImage` state the
    // live-capture path fills, then on to `.marking` exactly like a
    // fresh auto-capture would.
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isImportingPhoto = false
    // NOTE(AI Developer), added 2026-07 per Sean's explicit request: "I
    // want the option to pick from roll or take a picture right then for
    // the scar picture. Scar picture may also be the same picture with
    // paint transfer." Root cause this fixes: this screen previously only
    // accepted a BRAND NEW photo (live auto-capture or a fresh camera-roll
    // import) -- there was no way to reuse an already-excellent
    // `.closeupDamage`/`.paintTransfer` shot taken moments earlier in the
    // main protocol camera (`CaptureCameraView`), even when that exact
    // photo already clearly shows the scar and its paint-transfer taper
    // (Sean's own example: a single photo good enough for both). Drives
    // `existingPhotoPicker` -- a thumbnail grid of this vehicle's already-
    // captured photos -- and reuses the SAME `installFreshlyCapturedPhoto`
    // hand-off every other photo source already goes through, so a picked
    // existing photo lands in `.marking` identically to a fresh capture.
    @State private var showExistingPhotoPicker = false
    /// Briefly true right at the moment auto-capture fires, driving both
    /// the green full-screen flash (`autoCaptureFlash`) and a success
    /// haptic in `performCapture(auto:)` -- the "snap" feedback pairing
    /// Sean asked for by name ("like the auto capture when I remote
    /// deposit a check with wells fargo"). Reset back to false once the
    /// flash animation finishes so it can fire again on a retake.
    @State private var justAutoCapture = false

    // Marking-stage state
    @State private var lineStart: CGPoint?
    @State private var lineEnd: CGPoint?
    @State private var draggingEndpoint: LineEndpoint?
    /// Normalized (0-1, 0-1) location of the current in-progress drag,
    /// driving `magnifierLoupe(at:containerSize:)` -- `nil` whenever no
    /// drag is active, which hides the loupe entirely. NOTE(AI Developer),
    /// added 2026-07 per Sean's Answer A -- see `lineMarkingArea`'s
    /// `DragGesture` for where this is set/cleared.
    @State private var magnifierLocation: CGPoint?
    @State private var frontEndpoint: ScarEndpoint = .start
    @State private var isSaving = false
    @State private var uiImage: UIImage?
    /// True only for the first time this photo reaches the marking stage
    /// in this session (a fresh capture, not a re-open of an already-
    /// marked scar) -- drives the one-time line-drawing example overlay.
    /// NOTE(AI Developer), added 2026-07 per Sean's feedback that
    /// identifying scar direction "might be too hard... without clear
    /// easy to follow directions" -- see `lineDrawingExampleOverlay`.
    @State private var showDrawingExample = true
    /// True while `ScarLineSuggester` is analyzing the freshly-captured
    /// photo for a candidate scar line. NOTE(AI Developer), added 2026-07
    /// per Sean: identifying the exact scar edges "might take a trained
    /// eye" for an untrained user drawing blind. Vision's contour
    /// detector proposes a starting line so the user is confirming/
    /// nudging a suggestion (by dragging either end, same gesture as
    /// always) rather than drawing one from nothing -- see
    /// `ScarLineSuggester.suggestLine(in:)`.
    @State private var isSuggesting = false
    /// True once a Vision-suggested line has been placed into
    /// `lineStart`/`lineEnd` -- drives the "Auto-detected" banner text in
    /// `markingStage`. The user overrides a suggestion the same way they
    /// draw a line from scratch: dragging either endpoint dot moves it,
    /// exactly like the existing manual-draw gesture already handled by
    /// `lineMarkingArea`'s `DragGesture` -- no separate reset button
    /// needed, since "drag to adjust" already covers "drag to replace."
    @State private var lineWasAutoSuggested = false
    /// Guards against re-running the suggester every time `markingStage`
    /// re-renders (SwiftUI bodies are recomputed often) -- the analysis
    /// should fire at most once per freshly-captured photo.
    @State private var didAttemptSuggestion = false

    // MARK: Focus-region stage state
    //
    // NOTE(AI Developer), added 2026-07 per Sean's on-device report that
    // tool-mark/scar analysis "somehow use part of the image of the tape
    // measure as part of the vehicle damage." `.focusRegion` is a new
    // stage inserted between `.aiming` and `.marking`: the user drags a
    // resizable box around JUST the visible scar/scrape (excluding any
    // ruler, tape measure, or background clutter also in frame) before
    // marking the line -- see `focusRegionStage`/`CapturedPhoto
    // .scarFocusRegion`'s doc comment for the full rationale and how
    // this rect becomes a hard boundary for every scar/tool-mark
    // extractor downstream.

    /// Top-left corner of the working focus-region rectangle, normalized
    /// (0-1, 0-1) top-left-origin -- same convention as `lineStart`/
    /// `lineEnd`. Stored as two independent corner points (rather than a
    /// single `CGRect`) since each resize handle only ever needs to move
    /// ONE of these two points -- see `resizeFocusRegion(handle:to:)`.
    @State private var focusRegionMin = CGPoint(x: 0.15, y: 0.15)
    /// Bottom-right corner of the working focus-region rectangle, paired
    /// with `focusRegionMin` above. Together these two points define
    /// `focusRegionDraft` below. Defaults (0.15-0.85 on both axes)
    /// deliberately mirror `ScarCaptureCameraService.guideRect`'s own
    /// generous center inset, so the box the user sees already roughly
    /// matches what they were aiming at during capture, rather than
    /// starting as a jarring full-frame or tiny box they'd have to
    /// reposition from scratch every time.
    @State private var focusRegionMax = CGPoint(x: 0.85, y: 0.85)
    private var focusRegionDraft: CGRect {
        CGRect(
            x: focusRegionMin.x, y: focusRegionMin.y,
            width: focusRegionMax.x - focusRegionMin.x,
            height: focusRegionMax.y - focusRegionMin.y
        )
    }
    private enum FocusRegionHandle { case topLeft, topRight, bottomLeft, bottomRight }
    @State private var activeFocusHandle: FocusRegionHandle?
    @State private var isDraggingFocusBody = false
    /// Named struct (not an anonymous tuple) so `@State` holds a concrete,
    /// SourceKit-friendly type -- tuples in `@State` are legal but are a
    /// known rough edge for the editor's live type-checker.
    private struct FocusDragStart {
        var min: CGPoint
        var max: CGPoint
        var touch: CGPoint
    }
    /// Captured once at the start of a body-move drag (not updated mid-
    /// drag) so the whole rect translates by the touch's total offset
    /// from where the drag started, rather than compounding per-frame
    /// deltas -- same "capture the start state, apply cumulative offset"
    /// approach `DragGesture.onChanged`'s `value.translation` already
    /// uses natively; done manually here since the move needs to clamp
    /// against the image bounds using both corners together.
    @State private var focusBodyDragStart: FocusDragStart?
    /// Smallest allowed box dimension (normalized) -- prevents a resize
    /// drag from collapsing the box to zero/negative size, which would
    /// make `ToolMarkExtractor`/`ScarFingerprintExtractor`'s focus-region
    /// intersection produce an unusable (or crashing, for a
    /// zero-or-negative-size `CGRect`) crop.
    private let minimumFocusRegionSize: CGFloat = 0.08

    private enum LineEndpoint { case start, end }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .aiming: aimingStage
                case .focusRegion: focusRegionStage
                case .marking: markingStage
                }
            }
            .navigationTitle("Scar Direction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            if let existing = existingVehicle?.scarPhoto {
                capturedPhoto = existing
                uiImage = UIImage(data: existing.imageData)
                lineStart = existing.scarLineStart
                lineEnd = existing.scarLineEnd
                frontEndpoint = existing.scarFrontEndpoint ?? .start
                // Already-marked scar being reopened -- no need for the
                // one-time drawing example or an auto-suggested line.
                if existing.scarLineStart != nil { showDrawingExample = false }
                // NOTE(AI Developer), added 2026-07 alongside the focus-
                // region feature: an already-marked scar already has its
                // box drawn (or, for a scar marked before this feature
                // existed, `scarFocusRegion == nil` and the defaults
                // above simply stay put) -- either way there's nothing
                // new to draw, so this skips straight past
                // `.focusRegion` to `.marking`, exactly like the
                // pre-existing skip-past-`.aiming` behavior right below.
                if let region = existing.scarFocusRegion {
                    focusRegionMin = CGPoint(x: region.minX, y: region.minY)
                    focusRegionMax = CGPoint(x: region.maxX, y: region.maxY)
                }
                stage = .marking
            }
        }
    }

    private var existingVehicle: Vehicle? {
        viewModel.captureRole == .victim
            ? viewModel.forensicCase.victimVehicle
            : viewModel.forensicCase.suspectVehicle
    }

    // MARK: Aiming stage

    private var aimingStage: some View {
        ZStack {
            CameraPreviewView2(cameraService: camera)
                .ignoresSafeArea()
                .task {
                    camera.onAutoCapture = { Task { await performCapture(auto: true) } }
                    do {
                        try await camera.setupSession()
                        camera.startSession()
                    } catch {
                        lastError = error.localizedDescription
                    }
                }
                .onDisappear { camera.stopSession() }

            guideOverlay

            VStack {
                topInstruction
                Spacer()
                statusChips
                // NOTE(AI Developer), added 2026-07 per Sean's on-device
                // report on the main 30-shot camera ("need a ready
                // button... to trigger the autocapture when the user is
                // ready") -- this camera has the identical auto-capture
                // pattern, so the same fix applies: only shown once the
                // gates already look good and the user hasn't armed
                // yet, so it doesn't compete for attention while still
                // aligning the scar in the guide box.
                if camera.allGatesGood && !camera.isArmed {
                    readyButton
                        .padding(.bottom, 10)
                }
                // NOTE(AI Developer), reworked 2026-07 per Sean's
                // on-device report ("does not fit well within the
                // view... the [Ready button] is low on the screen and
                // can't activate it... cannot upload... from the
                // roll"). The library button used to be its own
                // stacked row ABOVE the shutter -- on top of
                // topInstruction/statusChips/readyButton already
                // stacked above THAT, the total column of bottom-
                // anchored content ran taller than some devices' visible
                // sheet height, pushing the library button and/or the
                // Ready button below the bottom edge where they existed
                // but couldn't be reached/tapped. Fixed by folding the
                // library button into the SAME row as the shutter
                // (`CaptureCameraView`'s existing library—shutter—skip
                // pattern, minus the skip slot this screen doesn't have)
                // instead of giving it its own row -- one fewer stacked
                // row, so everything above it (Ready button included)
                // sits that much higher and stays on-screen.
                HStack {
                    photoLibraryButton
                    Spacer()
                    autoCaptureRingAndShutter
                    Spacer()
                    // NOTE(AI Developer), added 2026-07: this slot used
                    // to be an inert `Color.clear` spacer only there to
                    // keep `autoCaptureRingAndShutter` visually centered
                    // against `photoLibraryButton`'s width -- now a real
                    // third photo-source button, see `showExistingPhotoPicker`'s
                    // doc comment above for why.
                    existingPhotoButton
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 24)
            }
            .padding(.horizontal)
            .padding(.top)

            // Brief green "snap" flash the instant auto-capture fires --
            // paired with the haptic in `performCapture(auto:)` to mirror
            // check-deposit apps' capture feedback. `.allowsHitTesting(false)`
            // so it never blocks the shutter/UI beneath it.
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
        .sheet(isPresented: $showExistingPhotoPicker) {
            ExistingPhotoForScarPicker(
                photos: existingVehicle?.photos.filter { $0.photoType == .closeupDamage || $0.photoType == .paintTransfer } ?? []
            ) { chosen in
                installFreshlyCapturedPhoto(chosen)
                camera.stopSession()
                showExistingPhotoPicker = false
            }
        }
    }

    /// Same 56x56 icon-circle affordance as `photoLibraryButton`, opening
    /// `ExistingPhotoForScarPicker` instead of the OS photo library.
    private var existingPhotoButton: some View {
        Button {
            showExistingPhotoPicker = true
        } label: {
            Circle()
                .fill(.black.opacity(0.45))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "square.grid.2x2")
                        .font(.title3)
                        .foregroundStyle(.white)
                )
        }
    }

    /// Dimmed everywhere except a cut-out matching
    /// `ScarCaptureCameraService.guideRect`, with a bright border --
    /// same visual language as a document/check scanner's alignment
    /// frame, so it reads as an immediately-familiar affordance.
    private var guideOverlay: some View {
        GeometryReader { geo in
            let guide = ScarCaptureCameraService.guideRect
            let rect = CGRect(
                x: guide.minX * geo.size.width,
                y: guide.minY * geo.size.height,
                width: guide.width * geo.size.width,
                height: guide.height * geo.size.height
            )
            ZStack {
                // "Punch a hole" dimming: a full-screen dark rectangle,
                // then a rounded-rect the size of the guide box composited
                // with `.destinationOut` inside a `.compositingGroup()` --
                // the standard SwiftUI technique for cutting a
                // transparent window out of an otherwise opaque overlay.
                Color.black.opacity(0.45)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .blendMode(.destinationOut)
                    )
                    .compositingGroup()
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(camera.allGatesGood ? Color.green : Color.white, lineWidth: 3)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private var topInstruction: some View {
        VStack(spacing: 4) {
            Text("Fill the box with the scar/scrape")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Hold steady — it captures automatically when ready.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(10)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    // NOTE(AI Developer), reworked 2026-07 per Sean's on-device report
    // ("the screen is not formatted properly... does not fit well") with
    // a screenshot showing the chip row clipped at BOTH edges ("teady"
    // on the left, the lighting message cut off mid-word on the right).
    // Root cause: three `.fixedSize(horizontal: true, ...)` capsules in
    // one `HStack` -- each forced to its own natural/unconstrained width
    // -- combined with `camera.lightingMessage`'s longest string
    // ("Uneven light across scar — even out shadows/glare", ~48 chars)
    // simply don't fit on a phone screen's width at once. Fixed by
    // splitting into two rows: Steady/Focused (always short, kept at
    // natural fixed width) on row one, and the Lighting chip alone on
    // row two -- given the FULL screen width to itself and allowed to
    // shrink its own text (`.minimumScaleFactor`) rather than being
    // truncated/clipped, since "Uneven light across scar — even out
    // shadows/glare" clipped mid-word is actively misleading (reads as
    // if lighting is fine when it isn't).
    private var statusChips: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                statusChip(label: "Steady", isGood: camera.isSteady, systemImage: "hand.raised.fill")
                statusChip(label: "Focused", isGood: camera.isFocused, systemImage: "camera.metering.spot")
            }
            statusChip(label: camera.lightingMessage, isGood: camera.isWellLit, systemImage: "sun.max.fill", fillWidth: true)
        }
        .padding(.bottom, 12)
    }

    private func statusChip(label: String, isGood: Bool, systemImage: String, fillWidth: Bool = false) -> some View {
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

    /// NOTE(AI Developer), added 2026-07 alongside `ScarCaptureCameraService
    /// .isArmed` -- explicit user confirmation that they're done
    /// aligning the scar in the guide box and are ready for the
    /// auto-capture countdown to start. See `CaptureCameraView
    /// .readyButton` for the matching control on the main protocol
    /// camera and the shared rationale.
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

    /// Filling ring (progress toward auto-capture) with a manual shutter
    /// button in the center as an always-available fallback -- per the
    /// same reasoning `PaintReferenceMarkerView`/`CaptureCameraView`
    /// already establish (glossy/dark paint or an awkward angle may
    /// never satisfy all three gates at once, and the user shouldn't be
    /// stuck).
    private var autoCaptureRingAndShutter: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.3), lineWidth: 5)
                .frame(width: 84, height: 84)
            Circle()
                .trim(from: 0, to: camera.autoCaptureProgress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 84, height: 84)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: camera.autoCaptureProgress)
            Button {
                Task { await performCapture(auto: false) }
            } label: {
                Circle()
                    .fill(.white)
                    .frame(width: 68, height: 68)
                    .overlay(Circle().stroke(.gray, lineWidth: 2))
            }
            .disabled(camera.isCapturing)
        }
    }

    private func performCapture(auto: Bool) async {
        guard !camera.isCapturing else { return }
        if auto {
            // "Snap" feedback pairing (visual flash + success haptic),
            // fired at the moment of capture rather than after -- mirrors
            // the instant confirmation check-deposit auto-capture gives,
            // per Sean's explicit request. Manual shutter taps already
            // get their own implicit tactile confirmation from the button
            // press, so this is reserved for the auto path.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            justAutoCapture = true
        }
        do {
            let data = try await camera.capturePhoto()
            let thumb = UIImage(data: data)?
                .preparingThumbnail(of: CGSize(width: 240, height: 240))?
                .jpegData(compressionQuality: 0.6)
            let photo = CapturedPhoto(
                imageData: data,
                thumbnailData: thumb,
                photoType: .paintTransfer,
                qualityScore: 1.0,
                annotationNotes: auto ? "Scar photo (auto-captured)" : "Scar photo (manual capture)"
            )
            camera.resetAutoCaptureStreak()
            camera.stopSession()
            installFreshlyCapturedPhoto(photo)
            // Let the green flash animate out, then clear the flag so a
            // future retake/auto-capture can trigger it again.
            try? await Task.sleep(nanoseconds: 250_000_000)
            justAutoCapture = false
        } catch {
            justAutoCapture = false
            lastError = error.localizedDescription
        }
    }

    /// NOTE(AI Developer), added 2026-07 per Sean's request to also allow
    /// picking a scar photo from the camera roll -- extracted out of
    /// `performCapture(auto:)` so the "install a new photo, reset
    /// marking state, advance to `.marking`" logic (previously inline
    /// there) is shared by both the live-capture path and this new
    /// import path, rather than drifting into two near-duplicate copies.
    private func installFreshlyCapturedPhoto(_ photo: CapturedPhoto) {
        capturedPhoto = photo
        uiImage = UIImage(data: photo.imageData)
        lineStart = nil
        lineEnd = nil
        // Fresh photo -- reset the example/suggestion state so both run
        // again for this new capture (a retake/import supersedes, so
        // whatever guidance played out for the old photo is stale).
        showDrawingExample = true
        lineWasAutoSuggested = false
        didAttemptSuggestion = false
        // Fresh photo -- reset the focus-region box back to its default
        // centered position too, rather than leaving whatever box (if
        // any) was drawn for a previous photo in this same session.
        focusRegionMin = CGPoint(x: 0.15, y: 0.15)
        focusRegionMax = CGPoint(x: 0.85, y: 0.85)
        // NOTE(AI Developer), added 2026-07: routes through the new
        // `.focusRegion` box-drawing step FIRST, before `.marking` --
        // see that stage's doc comment for why this ordering (draw the
        // boundary, then mark the line inside it) rather than the
        // reverse.
        withAnimation { stage = .focusRegion }
    }

    /// NOTE(AI Developer), added 2026-07 per Sean's explicit request ("we
    /// need to be able to upload an image for scar from the roll as
    /// well"); restyled 2026-07 to match `CaptureCameraView
    /// .photoLibraryButton`'s icon-only 56x56 circle exactly (was a
    /// labeled pill on its own row -- see that removed row's NOTE at its
    /// call site above for why the labeled-pill-on-its-own-row layout
    /// got folded into this screen's shutter row instead).
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
        .disabled(isImportingPhoto)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task { await importSelectedPhoto(newItem) }
        }
    }

    /// Loads the picked library image, marks it `wasImported: true` (same
    /// honesty-about-provenance convention as every other import path in
    /// the app -- see `CapturedPhoto.wasImported`'s doc comment) since
    /// there's no live sensor/gate reading for a photo that wasn't just
    /// taken by this device's guided camera, then hands off to the same
    /// `installFreshlyCapturedPhoto` used by a live auto/manual capture.
    private func importSelectedPhoto(_ item: PhotosPickerItem) async {
        isImportingPhoto = true
        defer {
            isImportingPhoto = false
            selectedPhotoItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                lastError = "Could not load the selected photo."
                return
            }
            let jpegData = uiImage.jpegData(compressionQuality: 0.85) ?? data
            let thumb = uiImage.preparingThumbnail(of: CGSize(width: 240, height: 240))?
                .jpegData(compressionQuality: 0.6)
            let photo = CapturedPhoto(
                imageData: jpegData,
                thumbnailData: thumb,
                photoType: .paintTransfer,
                qualityScore: 0.0,
                annotationNotes: "Scar photo (imported from photo library)",
                wasImported: true
            )
            camera.stopSession()
            installFreshlyCapturedPhoto(photo)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Focus-Region stage
    //
    // NOTE(AI Developer), added 2026-07 per Sean's on-device report that
    // tool-mark/scar analysis "somehow use part of the image of the tape
    // measure as part of the vehicle damage." Before marking the scar's
    // line, the user drags a resizable box to bound JUST the visible
    // scar/scrape -- excluding a ruler, tape measure, or background
    // clutter that may also be in frame. This box is saved as
    // `CapturedPhoto.scarFocusRegion` and becomes a HARD boundary for
    // every scar/tool-mark pixel-analysis step downstream (see that
    // field's doc comment, and `ToolMarkExtractor.extractStriationProfile`
    // / `ScarFingerprintExtractor.extractMinutiae`'s `focusRegion`
    // parameters) -- nothing outside it can ever be sampled as if it
    // were scar texture, no matter how close it sits to the marked line.
    //
    // Placed BEFORE `.marking` (not after) so the line the user marks
    // next is always drawn on an already-cropped mental frame -- makes
    // it natural to mark a line that stays well inside the box, rather
    // than drawing the line first and then having to remember to keep
    // the box clear of it afterward.
    private var focusRegionStage: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("Box in just the scar")
                        .font(.title3.bold())
                    Text("Drag the corners so the box covers ONLY the scar/scrape — keep any ruler, tape measure, or background clutter OUTSIDE the box. This keeps those objects from being mistaken for part of the damage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                whyThisMattersNote("Tool-mark matching looks for fine parallel scratch lines. A ruler's printed tick marks are exactly that kind of pattern — if one ends up inside the analyzed area, it can be mistaken for a real tool mark. This box guarantees only the scar itself gets analyzed.")

                focusRegionArea
                    .frame(height: 340)

                Button {
                    withAnimation { stage = .marking }
                } label: {
                    Label("Continue", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)

                Button("Retake Photo") {
                    withAnimation { stage = .aiming }
                    Task {
                        do {
                            try await camera.setupSession()
                            camera.startSession()
                        } catch {
                            lastError = error.localizedDescription
                        }
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    /// The photo with a draggable/resizable box overlay -- four corner
    /// handles (resize) plus a drag-anywhere-inside-the-box gesture
    /// (move, without resizing). NOTE(AI Developer): deliberately kept
    /// as two separate, non-overlapping gesture regions (handle circles
    /// vs. the box's interior) rather than one combined gesture with
    /// hit-test disambiguation, since a resize-vs-move decision only
    /// needs to be "which discrete region did the touch land in," unlike
    /// `lineMarkingArea`'s continuous nearest-endpoint calculation (that
    /// one has to disambiguate between two arbitrarily-close point
    /// targets; a corner handle vs. a large box interior are never
    /// ambiguous the same way).
    private var focusRegionArea: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let boxRect = CGRect(
                x: focusRegionDraft.minX * w,
                y: focusRegionDraft.minY * h,
                width: focusRegionDraft.width * w,
                height: focusRegionDraft.height * h
            )
            ZStack {
                if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray5))
                }

                // Dim everything OUTSIDE the box -- same "punch a hole"
                // technique as `guideOverlay` -- so it's immediately
                // visually obvious what will and won't be analyzed.
                Color.black.opacity(0.5)
                    .overlay(
                        Rectangle()
                            .frame(width: boxRect.width, height: boxRect.height)
                            .position(x: boxRect.midX, y: boxRect.midY)
                            .blendMode(.destinationOut)
                    )
                    .compositingGroup()
                    .allowsHitTesting(false)

                Rectangle()
                    .strokeBorder(Color.yellow, lineWidth: 3)
                    .frame(width: boxRect.width, height: boxRect.height)
                    .position(x: boxRect.midX, y: boxRect.midY)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if focusBodyDragStart == nil {
                                    focusBodyDragStart = FocusDragStart(min: focusRegionMin, max: focusRegionMax, touch: value.startLocation)
                                }
                                guard let start = focusBodyDragStart else { return }
                                let dxNorm = (value.location.x - start.touch.x) / w
                                let dyNorm = (value.location.y - start.touch.y) / h
                                let width = start.max.x - start.min.x
                                let height = start.max.y - start.min.y
                                // Clamp so the box can be dragged freely
                                // but never pushed off the image bounds
                                // (0-1 on both axes) -- moving, not
                                // resizing, so width/height stay fixed
                                // while only the shared offset is
                                // clamped.
                                let newMinX = min(max(0, start.min.x + dxNorm), 1 - width)
                                let newMinY = min(max(0, start.min.y + dyNorm), 1 - height)
                                focusRegionMin = CGPoint(x: newMinX, y: newMinY)
                                focusRegionMax = CGPoint(x: newMinX + width, y: newMinY + height)
                            }
                            .onEnded { _ in
                                focusBodyDragStart = nil
                            }
                    )

                focusHandle(at: CGPoint(x: boxRect.minX, y: boxRect.minY), handle: .topLeft, containerSize: CGSize(width: w, height: h))
                focusHandle(at: CGPoint(x: boxRect.maxX, y: boxRect.minY), handle: .topRight, containerSize: CGSize(width: w, height: h))
                focusHandle(at: CGPoint(x: boxRect.minX, y: boxRect.maxY), handle: .bottomLeft, containerSize: CGSize(width: w, height: h))
                focusHandle(at: CGPoint(x: boxRect.maxX, y: boxRect.maxY), handle: .bottomRight, containerSize: CGSize(width: w, height: h))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// A single draggable corner handle. NOTE(AI Developer): a
    /// deliberately large (44pt) invisible hit target around a small
    /// (22pt) visible dot -- same oversized-hit-target philosophy as
    /// `lineMarkingArea`'s endpoint dots (per Sean's "too hard to use"
    /// feedback on that screen), applied here up front rather than
    /// waiting for the same complaint to resurface on this screen too.
    private func focusHandle(at point: CGPoint, handle: FocusRegionHandle, containerSize: CGSize) -> some View {
        Circle()
            .fill(Color.yellow)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .frame(width: 22, height: 22)
            .contentShape(Circle().size(width: 44, height: 44))
            .position(x: point.x, y: point.y)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let normalized = CGPoint(
                            x: min(max(value.location.x / containerSize.width, 0), 1),
                            y: min(max(value.location.y / containerSize.height, 0), 1)
                        )
                        resizeFocusRegion(handle: handle, to: normalized)
                    }
            )
    }

    /// Moves exactly the one corner `handle` controls to `normalized`,
    /// clamping so the box never collapses below `minimumFocusRegionSize`
    /// on either axis -- the opposite corner (owned by whichever handle
    /// is diagonally across) never moves as a side effect, so resizing
    /// from one corner never surprises the user by shifting the corner
    /// they're not touching.
    private func resizeFocusRegion(handle: FocusRegionHandle, to normalized: CGPoint) {
        switch handle {
        case .topLeft:
            focusRegionMin.x = min(normalized.x, focusRegionMax.x - minimumFocusRegionSize)
            focusRegionMin.y = min(normalized.y, focusRegionMax.y - minimumFocusRegionSize)
        case .topRight:
            focusRegionMax.x = max(normalized.x, focusRegionMin.x + minimumFocusRegionSize)
            focusRegionMin.y = min(normalized.y, focusRegionMax.y - minimumFocusRegionSize)
        case .bottomLeft:
            focusRegionMin.x = min(normalized.x, focusRegionMax.x - minimumFocusRegionSize)
            focusRegionMax.y = max(normalized.y, focusRegionMin.y + minimumFocusRegionSize)
        case .bottomRight:
            focusRegionMax.x = max(normalized.x, focusRegionMin.x + minimumFocusRegionSize)
            focusRegionMax.y = max(normalized.y, focusRegionMin.y + minimumFocusRegionSize)
        }
    }

    // MARK: Marking stage

    private var markingStage: some View {
        ScrollView {
            VStack(spacing: 24) {
                // NOTE(AI Developer), reworked 2026-07 per Sean's Answer
                // A ("i'd rather it just auto-detect the line for you and
                // only let you nudge"): the header now reads differently
                // depending on whether Vision found a line to suggest --
                // "nudge to fine-tune" is the PRIMARY framing (the normal
                // case, since `attemptAutoSuggestion` always runs first),
                // with "draw it yourself" only surfaced as a fallback
                // instruction for the rarer case where nothing was
                // detected.
                VStack(spacing: 4) {
                    Text(lineWasAutoSuggested || (lineStart != nil && lineEnd != nil)
                         ? "Fine-tune the detected line"
                         : "Mark the scar as a line")
                        .font(.title3.bold())
                    Text(lineWasAutoSuggested || (lineStart != nil && lineEnd != nil)
                         ? "We found the scar automatically. Touch near either end to nudge it into place — use the magnifier for precision."
                         : "Touch one end of the visible scar/scrape, then the other, to place the line.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // NOTE(AI Developer), added 2026-07: a one-time worked
                // example showing exactly what "drag along the scar"
                // means on an actual scrape mark, shown once per fresh
                // photo before the user starts dragging -- per Sean's
                // "might be too hard... without clear easy to follow
                // directions" feedback. Dismissed by the user or
                // automatically once they place their own line.
                //
                // NOTE(AI Developer), scoped 2026-07 per Sean's Answer A:
                // this "draw from scratch" example only makes sense for
                // the fallback manual-draw path -- once a line exists
                // (whether from auto-detection or the user having placed
                // one), showing "how to draw" alongside "here's your
                // already-placed line to nudge" would be confusing, so
                // it's now suppressed as soon as both endpoints exist,
                // not just once the user has dragged.
                if showDrawingExample && (lineStart == nil || lineEnd == nil) {
                    lineDrawingExampleOverlay
                }

                if isSuggesting {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Looking for the scar in your photo…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else if lineWasAutoSuggested {
                    Label("Auto-detected — touch near either end to nudge it", systemImage: "wand.and.stars")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }

                lineMarkingArea
                    .frame(height: 320)
                    .task(id: capturedPhoto?.id) {
                        await attemptAutoSuggestion()
                    }

                if lineStart != nil && lineEnd != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The FRONT label below should be on the end closer to this vehicle's front.")
                            .font(.headline)
                        whyThisMattersNote("Paint transfer piles up in the direction contact was sliding — knowing which end is front vs. rear lets the app read the true direction of motion straight off the scar, instead of relying on a guessed compass heading.")
                        Button {
                            frontEndpoint = (frontEndpoint == .start) ? .end : .start
                        } label: {
                            Label("Swap Front / Rear", systemImage: "arrow.left.arrow.right")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    Task { await save() }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Label("Save Scar Direction", systemImage: "checkmark.circle.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .disabled(lineStart == nil || lineEnd == nil || isSaving)

                Button("Retake Photo") {
                    withAnimation { stage = .aiming }
                    Task {
                        do {
                            try await camera.setupSession()
                            camera.startSession()
                        } catch {
                            lastError = error.localizedDescription
                        }
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    /// A small, self-contained worked example of what "drag along the
    /// scar" means: a miniature stylized scrape mark with a dashed line
    /// already drawn tip-to-tip, labeled so the user can match the
    /// pattern on their own real photo below. NOTE(AI Developer), added
    /// 2026-07 -- deliberately a drawn illustration rather than a real
    /// photo crop, so it reads clearly as "here's the technique" and
    /// isn't mistaken for part of the user's own evidence.
    private var lineDrawingExampleOverlay: some View {
        VStack(spacing: 10) {
            HStack {
                Label("How to mark it", systemImage: "questionmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Got it") {
                    withAnimation { showDrawingExample = false }
                }
                .font(.caption.weight(.semibold))
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray5))
                // Stylized scrape mark: a tapered gray smear so the shape
                // itself hints at "this is a scar/scrape," not just an
                // abstract line.
                Capsule()
                    .fill(Color(.systemGray2))
                    .frame(width: 150, height: 14)
                    .rotationEffect(.degrees(-6))
                Path { path in
                    path.move(to: CGPoint(x: 40, y: 34))
                    path.addLine(to: CGPoint(x: 190, y: 22))
                }
                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                Circle().fill(.red).frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .position(x: 40, y: 34)
                Circle().fill(.blue).frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .position(x: 190, y: 22)
            }
            .frame(height: 60)

            Text("Drag from one visible tip of the scrape to the other — following its length, not just its width.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Runs the Vision-based contour suggester on the freshly-captured
    /// photo once (guarded by `didAttemptSuggestion`), placing the result
    /// straight into `lineStart`/`lineEnd` as a starting point the user
    /// can drag to adjust -- never overwrites a line the user already
    /// has in progress (e.g. a re-opened, already-marked scar, or a line
    /// the user started dragging before this finished). Runs off the
    /// main actor since Vision's contour detection is real CPU work, then
    /// hops back to publish the result -- same off-main/back-to-main
    /// pattern already used for photo analysis elsewhere in the app.
    private func attemptAutoSuggestion() async {
        guard !didAttemptSuggestion, lineStart == nil, lineEnd == nil, let uiImage else { return }
        didAttemptSuggestion = true
        isSuggesting = true
        // NOTE(AI Developer), added 2026-07 alongside the focus-region
        // feature: captured here (not read inside the detached task)
        // since `focusRegionDraft` is a `@MainActor`-isolated computed
        // property reading `@State` -- same "capture what's needed
        // before hopping off-main" pattern already used for `uiImage`
        // itself just above.
        let region = focusRegionDraft
        let result = await Task.detached(priority: .userInitiated) {
            ScarLineSuggester.suggestLine(in: uiImage, focusRegion: region)
        }.value
        isSuggesting = false
        guard lineStart == nil, lineEnd == nil, let result else { return }
        lineStart = result.start
        lineEnd = result.end
        lineWasAutoSuggested = true
    }

    @ViewBuilder
    private func whyThisMattersNote(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "lightbulb.fill")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom, 4)
    }

    private var lineMarkingArea: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray5))
                }

                if let lineStart, let lineEnd {
                    Path { path in
                        path.move(to: CGPoint(x: lineStart.x * w, y: lineStart.y * h))
                        path.addLine(to: CGPoint(x: lineEnd.x * w, y: lineEnd.y * h))
                    }
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                }
                // NOTE(AI Developer), changed 2026-07: the two endpoint
                // dots now show "FRONT"/"REAR" (matching whichever end
                // `frontEndpoint` currently points at) instead of the
                // old generic "S"/"E" -- per Sean's front/rear labeling
                // feedback, the picker used to make the user map an
                // arbitrary "Red end (start)/Blue end (end)" choice back
                // onto the photo themselves. Now the photo itself always
                // shows which end is currently front vs. rear, and the
                // "Swap Front / Rear" button (see `markingStage`) just
                // flips these two labels in place -- no separate mental
                // mapping required.
                //
                // NOTE(AI Developer), enlarged 2026-07 per Sean's "the
                // drag front and back are too hard to use" feedback --
                // bigger visual dot (was 54x22) so the endpoint the user
                // is nudging is easier to track under/near their finger.
                // The actual hit-testing fix (nearest-endpoint-always
                // disambiguation, no minimum-distance requirement) lives
                // in the `DragGesture` below, not in this view's size.
                if let lineStart {
                    endpointDot(color: .red, label: frontEndpoint == .start ? "FRONT" : "REAR")
                        .position(x: lineStart.x * w, y: lineStart.y * h)
                }
                if let lineEnd {
                    endpointDot(color: .blue, label: frontEndpoint == .end ? "FRONT" : "REAR")
                        .position(x: lineEnd.x * w, y: lineEnd.y * h)
                }

                // NOTE(AI Developer), added 2026-07 per Sean's Answer A
                // ("i'd rather it just auto-detect the line for you and
                // only let you nudge"): floating magnifier loupe shown
                // only while actively dragging, a zoomed circular crop of
                // the photo centered on the exact touch point (offset
                // above the finger, iOS-text-cursor-style, so the
                // fingertip never covers the very spot being placed).
                // See `magnifierLoupe(at:containerSize:)`.
                if let magnifierLocation {
                    magnifierLoupe(at: magnifierLocation, containerSize: CGSize(width: w, height: h))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let normalized = CGPoint(
                            x: min(max(value.location.x / w, 0), 1),
                            y: min(max(value.location.y / h, 0), 1)
                        )
                        // Any manual drag means the user is now
                        // authoring/adjusting the line themselves -- the
                        // one-time worked example has served its purpose,
                        // and once they've moved an endpoint the line is
                        // no longer purely "auto-detected" (even if it
                        // started that way), so drop that banner too.
                        if showDrawingExample { showDrawingExample = false }
                        lineWasAutoSuggested = false
                        magnifierLocation = normalized

                        if draggingEndpoint == nil {
                            // NOTE(AI Developer), reworked 2026-07 per
                            // Sean's Answer A and his "too hard to use"
                            // feedback: once BOTH endpoints already exist
                            // -- the normal case, since
                            // `attemptAutoSuggestion` always runs first
                            // and places both -- a fresh touch-down
                            // simply nudges whichever existing endpoint
                            // is NEARER, with no minimum-distance
                            // threshold at all. The user no longer needs
                            // to land precisely on the small dot; any
                            // touch closer to one end than the other
                            // unambiguously nudges that end, which is
                            // effectively a much larger, whole-region hit
                            // target for each endpoint rather than a tiny
                            // 22pt capsule. Drawing a brand-new line from
                            // scratch (the old "draw along the scar"
                            // behavior) only still applies in the
                            // fallback case where Vision found nothing to
                            // suggest and at least one endpoint is still
                            // genuinely unset.
                            if let lineStart, let lineEnd {
                                draggingEndpoint = distance(normalized, lineStart) <= distance(normalized, lineEnd) ? .start : .end
                            } else if lineStart == nil {
                                draggingEndpoint = .start
                            } else {
                                draggingEndpoint = .end
                            }
                        }
                        switch draggingEndpoint! {
                        case .start: lineStart = normalized
                        case .end: lineEnd = normalized
                        }
                    }
                    .onEnded { _ in
                        draggingEndpoint = nil
                        magnifierLocation = nil
                    }
            )
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private func endpointDot(color: Color, label: String) -> some View {
        ZStack {
            Capsule().fill(color)
                .overlay(Capsule().stroke(.white, lineWidth: 2))
                .frame(width: 66, height: 28)
            Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
        }
    }

    /// A circular, ~2.5x zoomed crop of the scar photo centered on
    /// `normalized`, floated just above the touch point so the user's own
    /// finger never obscures the exact pixel being placed -- the same
    /// "loupe" pattern iOS's native text-selection handles use.
    /// NOTE(AI Developer), added 2026-07 per Sean's Answer A ("only let
    /// you nudge") combined with his "hard to use" feedback: precisely
    /// nudging a small endpoint is difficult when a fingertip covers the
    /// exact spot being adjusted -- this gives the user a magnified,
    /// unobstructed view of that spot with a crosshair marking exactly
    /// where the endpoint will land if released now.
    private func magnifierLoupe(at normalized: CGPoint, containerSize: CGSize) -> some View {
        let loupeDiameter: CGFloat = 110
        let magnification: CGFloat = 2.5
        let w = containerSize.width
        let h = containerSize.height
        let touchPoint = CGPoint(x: normalized.x * w, y: normalized.y * h)
        // Hover the loupe above the touch point (clamped so it doesn't
        // render above the top edge of the marking area on a touch near
        // the top).
        let loupeCenterY = max(loupeDiameter / 2 + 4, touchPoint.y - loupeDiameter * 0.9)

        return ZStack {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w * magnification, height: h * magnification)
                    .offset(
                        x: -(touchPoint.x * magnification - loupeDiameter / 2),
                        y: -(touchPoint.y * magnification - loupeDiameter / 2)
                    )
            }
            // Crosshair marking the exact point that will be recorded.
            Rectangle().fill(Color.yellow.opacity(0.9)).frame(width: 1, height: loupeDiameter)
            Rectangle().fill(Color.yellow.opacity(0.9)).frame(width: loupeDiameter, height: 1)
            Circle().stroke(Color.yellow, lineWidth: 1.5).frame(width: 16, height: 16)
        }
        .frame(width: loupeDiameter, height: loupeDiameter)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 3))
        .shadow(radius: 4)
        .position(x: touchPoint.x, y: loupeCenterY)
        .allowsHitTesting(false)
    }

    private func save() async {
        guard var capturedPhoto, let lineStart, let lineEnd else { return }
        isSaving = true
        // NOTE(AI Developer), added 2026-07 alongside the focus-region
        // feature: stamps the box the user drew in `.focusRegion` onto
        // the photo being saved, so it's on hand for
        // `CaptureViewModel.recordScarDirection` to pass into the
        // extractors below -- see `CapturedPhoto.scarFocusRegion`'s doc
        // comment.
        capturedPhoto.scarFocusRegion = focusRegionDraft
        await viewModel.captureScarPhoto(capturedPhoto)
        await viewModel.recordScarDirection(
            lineStart: lineStart,
            lineEnd: lineEnd,
            frontEndpoint: frontEndpoint,
            focusRegion: focusRegionDraft
        )
        isSaving = false
        dismiss()
    }
}

// MARK: - Existing Case Photo Picker (for reusing an already-captured shot)

/// Thumbnail grid of this vehicle's already-captured `.closeupDamage`/
/// `.paintTransfer` photos, letting the user reuse one of them as the
/// scar photo instead of shooting/importing a brand new one.
///
/// NOTE(AI Developer), added 2026-07 per Sean's explicit request: "yes, I
/// want the option to pick from roll or take a picture right then for the
/// scar picture. Scar picture may also be the same picture with paint
/// transfer." Modeled on `PhotoReviewView.swift`'s `PhotoReviewCell`/
/// `LazyVGrid` layout for visual consistency with the rest of the app's
/// photo-grid UI, but far simpler -- this is a one-shot picker (tap a
/// tile, done), not an editable review grid, so there's no replace/retake
/// affordance here.
private struct ExistingPhotoForScarPicker: View {
    let photos: [CapturedPhoto]
    let onSelect: (CapturedPhoto) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if photos.isEmpty {
                    // NOTE(AI Developer): non-punitive empty state -- this
                    // vehicle simply hasn't had a closeup-damage or paint-
                    // transfer shot taken yet in the main protocol camera,
                    // which is a completely normal capture order (scar
                    // marking can happen before or after those shots).
                    // Explains why the grid is empty and what to do next,
                    // rather than just showing a blank screen.
                    ContentUnavailableView(
                        "No Case Photos Yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Take or import a Close-up Damage or Paint Transfer photo in the main capture flow first, then come back here to reuse it -- or use the camera or library buttons instead to shoot/import a photo just for this scar mark.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 14)], spacing: 18) {
                            ForEach(photos) { photo in
                                Button {
                                    onSelect(photo)
                                } label: {
                                    ExistingPhotoTile(photo: photo)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Choose a Case Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Single tappable thumbnail tile -- deliberately just a thumbnail + type
/// label with no per-tile controls (unlike `PhotoReviewCell`, which needs
/// replace/retake buttons; this grid's only action is "tap to choose").
private struct ExistingPhotoTile: View {
    let photo: CapturedPhoto

    var body: some View {
        VStack(spacing: 6) {
            Group {
                // Same non-optional-`Data` fix as `PhotoReviewView
                // .PhotoReviewCell.thumbnail` -- `thumbnailData ??
                // imageData` is already non-optional `Data`, so only the
                // final `UIImage(data:)` step belongs in `if let`.
                if let uiImage = UIImage(data: photo.thumbnailData ?? photo.imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 108, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.secondary.opacity(0.3), lineWidth: 1)
            )

            Text(photo.photoType.displayName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 28)
        }
    }
}

// MARK: - Camera Preview (UIViewRepresentable, for ScarCaptureCameraService)

/// NOTE(AI Developer): named `CameraPreviewView2` (rather than reusing
/// `CameraPreviewView` from `CaptureCameraView.swift`) since that struct
/// is hardcoded to `@ObservedObject var cameraService: CameraService` --
/// a distinct, unrelated service type from `ScarCaptureCameraService`.
/// Both wrap the same `PreviewUIView`/`AVCaptureVideoPreviewLayer`
/// pattern; only the observed service type differs.
struct CameraPreviewView2: UIViewRepresentable {
    @ObservedObject var cameraService: ScarCaptureCameraService

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.attach(layer: cameraService.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.attach(layer: cameraService.previewLayer)
    }
}
