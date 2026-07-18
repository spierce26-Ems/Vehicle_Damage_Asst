// ScarCaptureCameraService.swift
// Vehicle Damage Investigation Assistant
// Dedicated guided camera for the Scar-Direction Consistency capture step.
// Auto-captures once the phone is steady, focused, and the scar area is
// evenly lit -- mirroring the "hold steady and it captures automatically"
// UX of a mobile check-deposit scanner, per Sean's explicit request.
//
// NOTE(AI Developer), added 2026-07. This is a SEPARATE AVCaptureSession
// from `CameraService` (the 10-shot protocol camera), not a mode switch
// on it -- `CameraService.configureSession()` is a one-shot, guarded
// setup (`guard videoInput == nil else { return }`) built around a fixed
// photo-only pipeline; retrofitting a live `AVCaptureVideoDataOutput`
// frame-analysis pipeline onto it for this one screen would risk
// destabilizing the already-hardened 10-shot flow for a feature that's
// optional and independent of it (see `Vehicle.scarPhoto`'s doc comment).
// A second, focused session is safer and easier to reason about.
//
// WHY auto-capture matters for THIS specific shot (not just convenience):
// `ColorAnalysis.detectScarTaper` reads which end of the scar has more
// transferred paint by comparing ΔE2000 at each end against a reference
// color. An uneven-lit frame (glare on one end, shadow on the other) can
// fake a taper that isn't physically there, or mask a real one -- this
// isn't just a "nicer photo," it's what keeps the underlying measurement
// trustworthy. That's why "Even Lighting" is one of the three gates
// below, not merely a suggestion.
import AVFoundation
import CoreImage
import CoreMotion
import UIKit
import Combine

// MARK: - Scar Capture Camera Service

@MainActor
final class ScarCaptureCameraService: NSObject, ObservableObject {

    // MARK: Published guidance state

    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published private(set) var isSteady: Bool = false
    @Published private(set) var isFocused: Bool = true
    @Published private(set) var isWellLit: Bool = false
    @Published private(set) var lightingMessage: String = "Checking lighting…"
    /// 0-1 progress toward auto-capture while all three gates hold true
    /// continuously. Drives the filling-ring animation in `ScarCaptureView`
    /// -- same "hold still and watch it fill" affordance as a check-
    /// deposit scanner's capture ring.
    @Published private(set) var autoCaptureProgress: Double = 0
    @Published var errorMessage: String?
    @Published private(set) var isCapturing: Bool = false

    /// True once all three gates have held continuously long enough that
    /// `startAutoCaptureLoop` is about to (or just did) fire a capture.
    var allGatesGood: Bool { isSteady && isFocused && isWellLit }

    /// NOTE(AI Developer), added 2026-07 per Sean's on-device report on
    /// the main 30-shot camera ("auto capture worked way too fast...
    /// need a ready button... to trigger the autocapture when the user
    /// is ready") -- this camera shares the identical
    /// `updateGoodStreak`/`resetAutoCaptureStreak` pattern that caused
    /// that bug (right after a shot, the phone is usually still
    /// steady/focused/lit, so a fresh hold-timer alone can complete
    /// almost instantly), so the same fix applies here: the countdown
    /// only runs once the user has explicitly armed it via
    /// `armAutoCapture()`, called from `ScarCaptureView`'s new "Ready"
    /// button. See `CameraService.isArmed` for the full rationale.
    @Published private(set) var isArmed: Bool = false

    // MARK: Configuration

    /// Normalized (0-1, 0-1) guide rectangle within the camera frame that
    /// the user should fill with the scar -- also the region sampled for
    /// the lighting-evenness check. Generous center inset (not a thin
    /// band) since a scar's orientation isn't known in advance; the user
    /// aligns it inside this box however it naturally runs.
    static let guideRect = CGRect(x: 0.12, y: 0.28, width: 0.76, height: 0.44)

    private let autoCaptureHoldSeconds: TimeInterval = 0.65
    private let rotationRateThreshold: Double = 0.12 // rad/s
    private let unevenLightingThreshold: Double = 0.12 // 0-1 luma scale
    private let darkThreshold: Double = 0.12
    private let brightThreshold: Double = 0.93

    // MARK: Private AVFoundation state

    // NOTE(AI Developer): same `nonisolated(unsafe)` rationale as
    // `CameraService` -- exclusive access is actually guaranteed by the
    // serial `sessionQueue`, not by `@MainActor`; see that file's NOTE
    // for the full explanation.
    private nonisolated(unsafe) let session = AVCaptureSession()
    private nonisolated(unsafe) var photoOutput = AVCapturePhotoOutput()
    private nonisolated(unsafe) var videoDataOutput = AVCaptureVideoDataOutput()
    private nonisolated(unsafe) var videoInput: AVCaptureDeviceInput?
    private nonisolated(unsafe) weak var activeDevice: AVCaptureDevice?
    private let sessionQueue = DispatchQueue(label: "com.forensics.scarcamera.session", qos: .userInitiated)
    private let analysisQueue = DispatchQueue(label: "com.forensics.scarcamera.analysis", qos: .utility)
    private let ciContext = CIContext()

    private let motionManager = CMMotionManager()
    private var activePhotoCaptureDelegates: [ScarPhotoCaptureDelegate] = []
    private var deviceObservations: [NSKeyValueObservation] = []

    /// Frame-analysis is throttled to a few times a second (not every
    /// frame) -- CIAreaAverage-based sampling is cheap per call but there
    /// is no need to run it at full 30fps for a guidance signal that
    /// only needs to feel responsive, not instantaneous.
    ///
    /// NOTE(AI Developer): `nonisolated(unsafe)` for the same reason as
    /// `session`/`photoOutput` above -- this is only ever read/written
    /// from `captureOutput(_:didOutput:from:)`, which always runs on the
    /// single serial `analysisQueue` passed to
    /// `setSampleBufferDelegate(_:queue:)`, so that queue's own
    /// exclusivity (not `@MainActor`) is what actually makes this safe.
    private nonisolated(unsafe) var frameCounter = 0
    private let analyzeEveryNthFrame = 5

    /// Wall-clock time of the most recent instant at which all three
    /// gates were NOT simultaneously true; used to compute continuous
    /// "good" duration for `autoCaptureProgress` and the auto-capture
    /// trigger without a separate repeating Timer.
    private var lastNotGoodTime: Date = Date()
    private var hasFiredAutoCaptureForCurrentGoodStreak = false

    /// Set by `ScarCaptureView` once it has a completion handler ready;
    /// called at most once per continuous "good" streak.
    var onAutoCapture: (() -> Void)?

    // MARK: Setup

    override init() {
        super.init()
    }

    func setupSession() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else { continuation.resume(); return }
                do {
                    try self.configureSession()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        startMotionUpdates()
    }

    private nonisolated func configureSession() throws {
        guard videoInput == nil else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTripleCamera],
            mediaType: .video,
            position: .back
        ).devices.first else {
            throw CameraError.deviceUnavailable
        }

        // NOTE(AI Developer): continuous autofocus + autoexposure so
        // `isAdjustingFocus`/`isAdjustingExposure` (observed below) are
        // meaningful live signals of whether the lens has actually
        // settled on the scar, not a one-shot lock from whenever the
        // session first opened.
        try device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        device.unlockForConfiguration()
        activeDevice = device

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.inputNotSupported }
        session.addInput(input)
        videoInput = input

        guard session.canAddOutput(photoOutput) else { throw CameraError.outputNotSupported }
        session.addOutput(photoOutput)
        let maxReasonablePixels = 4032 * 3024
        if let capped = device.activeFormat.supportedMaxPhotoDimensions
            .filter({ Int($0.width) * Int($0.height) <= maxReasonablePixels })
            .max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
            photoOutput.maxPhotoDimensions = capped
        }

        guard session.canAddOutput(videoDataOutput) else { throw CameraError.outputNotSupported }
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: analysisQueue)
        session.addOutput(videoDataOutput)
        if let connection = videoDataOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90 // portrait
        }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        DispatchQueue.main.async { [weak self] in
            self?.previewLayer = layer
            self?.observeDevice(device)
        }
    }

    private func observeDevice(_ device: AVCaptureDevice) {
        deviceObservations.forEach { $0.invalidate() }
        deviceObservations = [
            device.observe(\.isAdjustingFocus, options: [.new]) { [weak self] dev, _ in
                Task { @MainActor [weak self] in
                    self?.isFocused = !dev.isAdjustingFocus && !dev.isAdjustingExposure
                }
            },
            device.observe(\.isAdjustingExposure, options: [.new]) { [weak self] dev, _ in
                Task { @MainActor [weak self] in
                    self?.isFocused = !dev.isAdjustingFocus && !dev.isAdjustingExposure
                }
            }
        ]
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
        motionManager.stopDeviceMotionUpdates()
        deviceObservations.forEach { $0.invalidate() }
        deviceObservations = []
    }

    // MARK: Motion (steadiness gate)

    /// NOTE(AI Developer): uses `rotationRate` (gyro, rad/s) rather than
    /// `CameraLevelMath`'s gravity-derived pitch/roll -- this gate is
    /// about "is the phone currently MOVING/shaking," not "is it aimed
    /// at a particular angle." A scar photo has no required pitch/roll
    /// the way the 30-shot protocol's coaching steps do (see
    /// `CaptureProtocolStep.idealPitchDegrees`); any angle is fine as
    /// long as the phone is genuinely still when the shutter fires.
    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            isSteady = true // no gyro available -- don't block capture on a signal we can't read
            return
        }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let r = motion.rotationRate
            let magnitude = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
            self.isSteady = magnitude < self.rotationRateThreshold
            self.updateGoodStreak()
        }
    }

    // MARK: Auto-capture streak tracking

    /// Called on every published-state change (motion callback and frame
    /// analysis both call this) to update `autoCaptureProgress` and fire
    /// `onAutoCapture` once a continuous "all gates good" streak reaches
    /// `autoCaptureHoldSeconds`. No repeating `Timer` needed -- each
    /// underlying sensor callback already arrives frequently enough
    /// (30Hz motion, ~6Hz frame analysis) to drive this smoothly.
    /// NOTE(AI Developer), added 2026-07 alongside `isArmed`: requires
    /// `isArmed` in addition to `allGatesGood` before the countdown
    /// progresses -- see `CameraService.updateGoodStreak`'s matching
    /// NOTE for the full rationale.
    private func updateGoodStreak() {
        let now = Date()
        if isArmed && allGatesGood {
            let streak = now.timeIntervalSince(lastNotGoodTime)
            autoCaptureProgress = min(1.0, streak / autoCaptureHoldSeconds)
            if streak >= autoCaptureHoldSeconds && !hasFiredAutoCaptureForCurrentGoodStreak && !isCapturing {
                hasFiredAutoCaptureForCurrentGoodStreak = true
                onAutoCapture?()
            }
        } else {
            lastNotGoodTime = now
            hasFiredAutoCaptureForCurrentGoodStreak = false
            autoCaptureProgress = 0
        }
    }

    /// Called by `ScarCaptureView` right after a capture (auto or
    /// manual) completes, so a NEW continuous streak is required before
    /// auto-capture can fire again -- prevents an immediate repeat
    /// capture if the phone happens to still be steady/well-lit right
    /// after the shutter. Also disarms (`isArmed = false`) so the user
    /// must tap "Ready" again before the next auto-capture countdown
    /// can start.
    func resetAutoCaptureStreak() {
        lastNotGoodTime = Date()
        hasFiredAutoCaptureForCurrentGoodStreak = false
        autoCaptureProgress = 0
        isArmed = false
    }

    /// Called when the user taps the "Ready" button in `ScarCaptureView`
    /// once they've finished aligning the scar in the guide box. Starts
    /// the continuous-good-streak clock now, so the full
    /// `autoCaptureHoldSeconds` hold is always required after arming.
    func armAutoCapture() {
        isArmed = true
        lastNotGoodTime = Date()
        hasFiredAutoCaptureForCurrentGoodStreak = false
        autoCaptureProgress = 0
    }

    // MARK: Photo capture

    func capturePhoto() async throws -> Data {
        guard session.isRunning else { throw CameraError.sessionNotRunning }
        isCapturing = true
        defer { isCapturing = false }
        return try await withCheckedThrowingContinuation { continuation in
            let settings = AVCapturePhotoSettings()
            var delegate: ScarPhotoCaptureDelegate!
            delegate = ScarPhotoCaptureDelegate { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let idx = self.activePhotoCaptureDelegates.firstIndex(where: { $0 === delegate }) {
                        self.activePhotoCaptureDelegates.remove(at: idx)
                    }
                }
                switch result {
                case .success(let data): continuation.resume(returning: data)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            activePhotoCaptureDelegates.append(delegate)
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

// MARK: - Video Data Output Delegate (lighting-evenness / exposure analysis)

extension ScarCaptureCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Throttle: only analyze every Nth frame. `frameCounter` is only
        // ever touched from this same delegate queue (`analysisQueue`),
        // so no synchronization is needed despite this method being
        // `nonisolated`.
        frameCounterIncrement { shouldAnalyze in
            guard shouldAnalyze else { return }
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let guide = ScarCaptureCameraService.guideRect
            let guideRectPixels = CGRect(
                x: guide.minX * CGFloat(width),
                y: guide.minY * CGFloat(height),
                width: guide.width * CGFloat(width),
                height: guide.height * CGFloat(height)
            )
            // Split the guide region into a 2x2 grid; compare the
            // brightest vs. dimmest quadrant to catch glare/shadow
            // gradients across the scar -- exactly the kind of uneven
            // lighting that can fake or mask a real paint-taper reading
            // in `ColorAnalysis.detectScarTaper`.
            let halfW = guideRectPixels.width / 2
            let halfH = guideRectPixels.height / 2
            let quadrants = [
                CGRect(x: guideRectPixels.minX, y: guideRectPixels.minY, width: halfW, height: halfH),
                CGRect(x: guideRectPixels.minX + halfW, y: guideRectPixels.minY, width: halfW, height: halfH),
                CGRect(x: guideRectPixels.minX, y: guideRectPixels.minY + halfH, width: halfW, height: halfH),
                CGRect(x: guideRectPixels.minX + halfW, y: guideRectPixels.minY + halfH, width: halfW, height: halfH)
            ]
            let brightnesses = quadrants.compactMap { self.averageLuma(of: ciImage, in: $0) }
            guard brightnesses.count == 4 else { return }
            let overall = brightnesses.reduce(0, +) / Double(brightnesses.count)
            let spread = (brightnesses.max() ?? 0) - (brightnesses.min() ?? 0)

            Task { @MainActor [weak self] in
                guard let self else { return }
                if overall < self.darkThreshold {
                    self.isWellLit = false
                    self.lightingMessage = "Too dark — add more light"
                } else if overall > self.brightThreshold {
                    self.isWellLit = false
                    self.lightingMessage = "Too bright — reduce glare/reflection"
                } else if spread > self.unevenLightingThreshold {
                    self.isWellLit = false
                    self.lightingMessage = "Uneven light across scar — even out shadows/glare"
                } else {
                    self.isWellLit = true
                    self.lightingMessage = "Lighting looks even"
                }
                self.updateGoodStreak()
            }
        }
    }

    /// Average luma (0-1) of `image` within `pixelRect`, via the same
    /// `CIAreaAverage` technique already used in
    /// `CameraService.estimateBrightness`. `nil` on a degenerate/empty
    /// rect (e.g. right at session startup before geometry is sane).
    nonisolated private func averageLuma(of image: CIImage, in pixelRect: CGRect) -> Double? {
        guard pixelRect.width > 1, pixelRect.height > 1 else { return nil }
        let clamped = pixelRect.intersection(image.extent)
        guard !clamped.isEmpty else { return nil }
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: clamped)
        ]), let output = filter.outputImage,
              let cgImage = ciContext.createCGImage(output, from: CGRect(x: 0, y: 0, width: 1, height: 1)) else {
            return nil
        }
        guard let data = cgImage.dataProvider?.data, CFDataGetLength(data) >= 4 else { return nil }
        let bytes = CFDataGetBytePtr(data)!
        // BGRA order.
        let b = Double(bytes[0]) / 255.0
        let g = Double(bytes[1]) / 255.0
        let r = Double(bytes[2]) / 255.0
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    /// Small helper isolating the mutable `frameCounter` touch to this
    /// nonisolated delegate queue context, called synchronously so the
    /// closure-based callback pattern stays simple at each call site.
    nonisolated private func frameCounterIncrement(_ body: (Bool) -> Void) {
        frameCounter += 1
        body(frameCounter % analyzeEveryNthFrame == 0)
    }
}

// MARK: - Photo Capture Delegate

private final class ScarPhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<Data, Error>) -> Void

    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { completion(.failure(error)); return }
        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(CameraError.noImageData))
            return
        }
        completion(.success(data))
    }
}
