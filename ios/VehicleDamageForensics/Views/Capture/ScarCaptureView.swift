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

                lineMarkingArea
                    .frame(height: 320)

                if lineStart != nil && lineEnd != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Which end is toward this vehicle's front?")
                            .font(.headline)
                        whyThisMattersNote("Paint transfer piles up in the direction contact was sliding — knowing which end is front vs. rear lets the app read the true direction of motion straight off the scar, instead of relying on a guessed compass heading.")
                        Picker("Front end", selection: $frontEndpoint) {
                            Text("Red end (start)").tag(ScarEndpoint.start)
                            Text("Blue end (end)").tag(ScarEndpoint.end)
                        }
                        .pickerStyle(.segmented)
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
                if let lineStart {
                    endpointDot(color: .red, label: "S")
                        .position(x: lineStart.x * w, y: lineStart.y * h)
                }
                if let lineEnd {
                    endpointDot(color: .blue, label: "E")
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
            Circle().fill(color).frame(width: 26, height: 26)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
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
