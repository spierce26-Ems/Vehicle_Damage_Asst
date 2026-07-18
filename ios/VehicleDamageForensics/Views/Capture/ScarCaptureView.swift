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

// MARK: - Scar Capture View

struct ScarCaptureView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case aiming
        case marking
    }

    @State private var stage: Stage = .aiming
    @StateObject private var camera = ScarCaptureCameraService()
    @State private var lastError: String?
    @State private var capturedPhoto: CapturedPhoto?
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

    private enum LineEndpoint { case start, end }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .aiming: aimingStage
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
                autoCaptureRingAndShutter
                    .padding(.bottom, 32)
            }
            .padding()

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

    private var statusChips: some View {
        HStack(spacing: 10) {
            statusChip(label: "Steady", isGood: camera.isSteady, systemImage: "hand.raised.fill")
            statusChip(label: "Focused", isGood: camera.isFocused, systemImage: "camera.metering.spot")
            statusChip(label: camera.lightingMessage, isGood: camera.isWellLit, systemImage: "sun.max.fill")
        }
        .padding(.bottom, 12)
    }

    private func statusChip(label: String, isGood: Bool, systemImage: String) -> some View {
        Label(label, systemImage: isGood ? "checkmark.circle.fill" : systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isGood ? Color.green.opacity(0.75) : Color.black.opacity(0.55), in: Capsule())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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
            capturedPhoto = photo
            uiImage = UIImage(data: data)
            lineStart = nil
            lineEnd = nil
            // Fresh photo -- reset the example/suggestion state so both
            // run again for this new capture (a retake supersedes, so
            // whatever guidance played out for the old photo is stale).
            showDrawingExample = true
            lineWasAutoSuggested = false
            didAttemptSuggestion = false
            camera.resetAutoCaptureStreak()
            camera.stopSession()
            withAnimation { stage = .marking }
            // Let the green flash animate out, then clear the flag so a
            // future retake/auto-capture can trigger it again.
            try? await Task.sleep(nanoseconds: 250_000_000)
            justAutoCapture = false
        } catch {
            justAutoCapture = false
            lastError = error.localizedDescription
        }
    }

    // MARK: Marking stage

    private var markingStage: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("Mark the scar as a line")
                        .font(.title3.bold())
                    Text("Drag from one end of the visible scar/scrape to the other.")
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
                if showDrawingExample {
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
                    Label("Auto-detected — drag either end to adjust it", systemImage: "wand.and.stars")
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
        let result = await Task.detached(priority: .userInitiated) {
            ScarLineSuggester.suggestLine(in: uiImage)
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
                if let lineStart {
                    endpointDot(color: .red, label: frontEndpoint == .start ? "FRONT" : "REAR")
                        .position(x: lineStart.x * w, y: lineStart.y * h)
                }
                if let lineEnd {
                    endpointDot(color: .blue, label: frontEndpoint == .end ? "FRONT" : "REAR")
                        .position(x: lineEnd.x * w, y: lineEnd.y * h)
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
                        if draggingEndpoint == nil {
                            // Decide which endpoint this drag is setting: if
                            // neither is set yet, or we're closer to the
                            // existing start than the existing end, treat
                            // this as setting/moving the start; otherwise
                            // the end. This lets the user redraw either end
                            // without needing a separate mode toggle.
                            if lineStart == nil || (lineEnd == nil && distance(normalized, lineStart!) > 0.03) {
                                draggingEndpoint = lineStart == nil ? .start : .end
                            } else {
                                draggingEndpoint = .start
                            }
                        }
                        switch draggingEndpoint! {
                        case .start: lineStart = normalized
                        case .end: lineEnd = normalized
                        }
                    }
                    .onEnded { _ in draggingEndpoint = nil }
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
                .frame(width: 54, height: 22)
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
        }
    }

    private func save() async {
        guard let capturedPhoto, let lineStart, let lineEnd else { return }
        isSaving = true
        await viewModel.captureScarPhoto(capturedPhoto)
        await viewModel.recordScarDirection(
            lineStart: lineStart,
            lineEnd: lineEnd,
            frontEndpoint: frontEndpoint
        )
        isSaving = false
        dismiss()
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
