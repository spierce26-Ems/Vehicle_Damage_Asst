// CameraService.swift
// Vehicle Damage Investigation Assistant
// AVFoundation camera wrapper with sensor-guided capture and 30-shot protocol

import AVFoundation
import CoreMotion
import CoreLocation
import CoreImage
import UIKit
import ImageIO
import Combine

// MARK: - Camera Service

/// Manages AVFoundation capture session, sensor guidance, and the 30-shot forensic protocol
@MainActor
final class CameraService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var captureState: CaptureState = .idle
    @Published var sensorReading: SensorReading = SensorReading()
    @Published var currentProtocolStep: CaptureProtocolStep?
    @Published var errorMessage: String?
    @Published var flashMode: AVCaptureDevice.FlashMode = .auto

    // MARK: - Guided Auto-Capture State
    //
    // NOTE(AI Developer), added 2026-07 per Sean's request ("i want to
    // have guided autocapture for every image along with current option
    // to use the camera roll as well") -- extends the Steady/Focused/
    // Even-Lighting auto-capture gates first built for the standalone
    // Scar-Direction shot (`ScarCaptureCameraService`) to the main
    // 30-shot protocol camera, WITHOUT removing the manual shutter,
    // `PhotosPicker` camera-roll import, or skip button already on
    // `CaptureCameraView` -- auto-capture only adds a fourth way to
    // advance the protocol; the other three remain exactly as they were.
    //
    // Unlike the scar shot, which is a single fixed-box macro framing,
    // this protocol spans very different shot types (macro closeups vs.
    // wide establishing shots taken outdoors from several feet away).
    // "Even Lighting" only has real justification on the macro/closeup
    // types -- see `PhotoType.usesEvenLightingGate` -- so it's gated
    // per-shot via `currentShotRequiresEvenLighting`, set by
    // `CaptureCameraView` whenever `viewModel.nextShotType` changes.
    // Steady + Focused apply unconditionally to every shot type.
    //
    // Per Sean's own follow-up ("we can distance gate later if
    // needed"), there is deliberately no distance/framing gate here --
    // `CaptureProtocolStep.idealDistanceMeters` is coaching metadata
    // only (surfaced via the existing pitch/roll `SensorLevelBar`), not
    // an auto-capture trigger, since there's no reliable no-LiDAR way to
    // measure real-world distance from a single 2D frame.
    @Published private(set) var isSteady: Bool = false
    @Published private(set) var isFocused: Bool = true
    @Published private(set) var isWellLit: Bool = false
    @Published private(set) var lightingMessage: String = "Checking lighting…"
    /// 0-1 progress toward auto-capture while all required gates hold
    /// true continuously -- drives the filling-ring animation around
    /// `CaptureCameraView`'s shutter button, same affordance as the
    /// Scar-Direction screen.
    @Published private(set) var autoCaptureProgress: Double = 0

    /// NOTE(AI Developer), added 2026-07 per Sean's on-device report
    /// ("auto capture worked way too fast. it autocaptured really quick
    /// and did not allow time to move the camera to a new position...
    /// we need to add a ready button or something to trigger the
    /// autocapture when the user is ready"). Root cause: right after a
    /// shot fires, the phone is usually STILL steady/focused/well-lit
    /// (it hasn't moved yet), so the old code's `resetAutoCaptureStreak`
    /// only cleared the *timer* -- with `allGatesGood` already true
    /// again on the very next sensor callback, a fresh
    /// `autoCaptureHoldSeconds` (0.65s) streak completed almost
    /// immediately, firing a second shot before the user could
    /// reposition. `isArmed` decouples "sensors currently look good"
    /// (`allGatesGood`, unchanged -- still drives the status chips) from
    /// "the user has confirmed they're ready for auto-capture to start
    /// counting down for THIS shot." `updateGoodStreak()` below now
    /// requires both. Starts `false` for every new shot; set `true` only
    /// via `armAutoCapture()`, called when the user taps the new "Ready"
    /// button in `CaptureCameraView`. Cleared back to `false` after every
    /// capture (auto or manual) and on every shot-type change, so the
    /// user must explicitly re-arm for each new shot -- there is no way
    /// for this to silently stay armed across a reposition.
    @Published private(set) var isArmed: Bool = false

    /// Set by `CaptureCameraView` whenever `viewModel.nextShotType`
    /// changes, from `PhotoType.usesEvenLightingGate` -- determines
    /// whether `allGatesGood` requires `isWellLit` for the shot
    /// currently being aimed at. Not `@Published`: it's read only from
    /// inside `allGatesGood`/`updateGoodStreak`, both already driven by
    /// the `@Published` gate signals above, so a redundant publish here
    /// would just trigger extra, unnecessary view updates.
    var currentShotRequiresEvenLighting: Bool = false

    /// True once all currently-required gates (Steady + Focused, plus
    /// Even Lighting only if `currentShotRequiresEvenLighting`) have
    /// held continuously long enough that auto-capture is about to (or
    /// just did) fire.
    var allGatesGood: Bool {
        isSteady && isFocused && (!currentShotRequiresEvenLighting || isWellLit)
    }

    /// Set by `CaptureCameraView` right after `setupSession()`
    /// succeeds; called at most once per continuous "good" streak, same
    /// contract as `ScarCaptureCameraService.onAutoCapture`.
    var onAutoCapture: (() -> Void)?

    /// Normalized center region analyzed for lighting evenness when the
    /// current shot type requires it. Unlike
    /// `ScarCaptureCameraService.guideRect`, this camera has no single
    /// "fill this box" framing across all 30 shot types (macro vs. wide
    /// vs. profile) -- this generous center crop is a reasonable proxy
    /// for "the subject" on a centered macro/closeup shot without
    /// needing 30 separate per-shot boxes.
    static let lightingSampleRect = CGRect(x: 0.2, y: 0.25, width: 0.6, height: 0.5)

    private let autoCaptureHoldSeconds: TimeInterval = 0.65
    private let rotationRateThreshold: Double = 0.12 // rad/s
    private let unevenLightingThreshold: Double = 0.12 // 0-1 luma scale
    private let darkThreshold: Double = 0.12
    private let brightThreshold: Double = 0.93

    // MARK: - Private Properties

    // NOTE(AI Developer): `session`/`photoOutput`/`videoInput` are marked
    // `nonisolated(unsafe)` per Sean's report of Swift 6 actor-isolation
    // warnings (2026-07): although `CameraService` is `@MainActor`, all
    // configuration/start/stop of the AVCaptureSession happens on the
    // dedicated serial `sessionQueue` background queue (as Apple's own
    // AVCam sample does, and as Apple's docs require -- `startRunning()`/
    // `stopRunning()` are blocking calls that must not run on the main
    // thread). `sessionQueue` being serial is what actually guarantees
    // exclusive access, not `@MainActor`, so `nonisolated(unsafe)` here
    // just tells the compiler to trust that existing guarantee instead of
    // wrongly assuming these properties are only ever touched on the main
    // actor. `capturePhoto`/`captureImageData` in this file only *read*
    // these properties from the main actor between session-queue
    // operations, which AVFoundation documents as safe.
    private nonisolated(unsafe) let session = AVCaptureSession()
    private nonisolated(unsafe) var photoOutput = AVCapturePhotoOutput()
    private nonisolated(unsafe) var videoInput: AVCaptureDeviceInput?
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var captureCompletions: [String: (CapturedPhoto?) -> Void] = [:]
    private let sessionQueue = DispatchQueue(label: "com.forensics.camera.session", qos: .userInitiated)

    // NOTE(AI Developer), added 2026-07 for guided auto-capture (see the
    // MARK above): same `nonisolated(unsafe)` rationale as `session`/
    // `photoOutput` -- `videoDataOutput` is only mutated during
    // `configureSession()` on `sessionQueue`, and `deviceObservations`/
    // `activeDevice` are only touched from the main actor (KVO callbacks
    // are dispatched to `.main` explicitly below), matching the pattern
    // already established in `ScarCaptureCameraService`.
    private nonisolated(unsafe) var videoDataOutput = AVCaptureVideoDataOutput()
    private nonisolated(unsafe) weak var activeDevice: AVCaptureDevice?
    private let analysisQueue = DispatchQueue(label: "com.forensics.camera.analysis", qos: .utility)
    private let ciContext = CIContext()
    private var deviceObservations: [NSKeyValueObservation] = []

    /// Frame-analysis is throttled the same way as
    /// `ScarCaptureCameraService` -- cheap per call, but no need to run
    /// at full 30fps for a guidance signal that only needs to feel
    /// responsive. `nonisolated(unsafe)` for the same reason as that
    /// file's identical property: only ever touched from
    /// `captureOutput(_:didOutput:from:)`, which always runs on the
    /// single serial `analysisQueue`.
    private nonisolated(unsafe) var frameCounter = 0
    private let analyzeEveryNthFrame = 5

    /// Wall-clock time of the most recent instant at which the required
    /// gates were NOT simultaneously true; drives `autoCaptureProgress`
    /// and the auto-capture trigger without a separate repeating Timer,
    /// identical approach to `ScarCaptureCameraService`.
    private var lastNotGoodTime: Date = Date()
    private var hasFiredAutoCaptureForCurrentGoodStreak = false

    // NOTE(AI Developer): `objc_setAssociatedObject`'s real signature is
    // `func objc_setAssociatedObject(_ object: Any, _ key: UnsafeRawPointer, _ value: Any?, _ policy: objc_AssociationPolicy)`
    // (confirmed against Apple's Objective-C runtime docs). The original code
    // passed `UUID().uuidString as NSString` as the key, but that parameter
    // requires an `UnsafeRawPointer`, not an `NSString` — a real type
    // mismatch that will not compile. A stable, unique-address token is
    // needed instead. We retain each in-flight delegate in a small array
    // keyed by object identity rather than trying to synthesize a raw
    // pointer per-call (which would require unsafe/unstable tricks); this
    // keeps every delegate alive until its callback fires and avoids
    // fighting the associated-object API for something that doesn't need it.
    private var activePhotoCaptureDelegates: [PhotoCaptureDelegate] = []

    // 30-shot protocol definition
    static let captureProtocol: [CaptureProtocolStep] = CaptureProtocolStep.fullProtocol

    // MARK: - Setup

    override init() {
        super.init()
        setupMotionManager()
        setupLocationManager()
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
    }

    // NOTE(AI Developer): Marked `nonisolated` (2026-07 fix) -- this method
    // is only ever invoked from inside the `sessionQueue.async { ... }`
    // block in `setupSession()`, i.e. off the main actor by design (per
    // Apple's guidance that `AVCaptureSession` configuration must not run
    // on the main thread). Calling a MainActor-isolated method from that
    // background closure was the actual source of Sean's build warning
    // ("Call to main actor-isolated instance method 'configureSession()'
    // in a synchronous nonisolated context"). Safe to de-isolate because
    // it only touches `session`/`photoOutput`/`videoInput`, which are now
    // `nonisolated(unsafe)` and exclusively mutated on this same serial
    // `sessionQueue`.
    private nonisolated func configureSession() throws {
        // NOTE(AI Developer), fixed 2026-07 per Sean's on-device crash
        // report ("Start Analysis" appears not to work): SwiftUI's
        // `.task` on `CaptureCameraView` re-runs every time that view
        // reappears (e.g. popping back from the LiDAR scan screen),
        // which re-invokes `setupSession()` -> `configureSession()` on a
        // session that's *already* configured. On that second run,
        // `session.canAddInput(input)` returns false (a video input is
        // already attached), so the function threw `.inputNotSupported`
        // -- but that throw happened *before* `session.commitConfiguration()`
        // ever ran, leaving `session` permanently stuck mid-configuration.
        // Any later `stopRunning()` call (e.g. `.onDisappear` firing when
        // navigating away to run analysis) is then an AVFoundation
        // contract violation -- "stopRunning may not be called between
        // calls to beginConfiguration and commitConfiguration" -- which
        // is a fatal, uncatchable exception, not a normal Swift error.
        // That crash was what actually made "Start Analysis" look broken:
        // it fired the instant the capture screen was dismissed, before
        // the analysis screen ever got a chance to appear.
        //
        // Two independent fixes: (1) skip reconfiguration entirely once
        // `videoInput` shows the session is already set up -- there's
        // nothing to redo on a reappear, the existing session/preview
        // layer are still valid; (2) `defer { session.commitConfiguration() }`
        // immediately after `beginConfiguration()` so *any* future
        // early-throw in this method (e.g. a genuinely new failure, like
        // camera permission being revoked mid-session) can never again
        // leave begin/commit unbalanced.
        guard videoInput == nil else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        // Input
        guard let device = bestCaptureDevice() else {
            throw CameraError.deviceUnavailable
        }

        // NOTE(AI Developer), added 2026-07 for guided auto-capture:
        // continuous autofocus/autoexposure so `isAdjustingFocus`/
        // `isAdjustingExposure` (observed in `observeDevice` below) are
        // meaningful live signals of whether the lens has actually
        // settled, not a one-shot lock from whenever the session first
        // opened -- same reasoning and API calls as
        // `ScarCaptureCameraService.configureSession`. Propagates like
        // that file does; `AVCaptureDevice.lockForConfiguration()`
        // failing here would mean the device is in a broken state that
        // manual capture couldn't recover from either, so there's
        // nothing gained by swallowing the error.
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

        // Output
        guard session.canAddOutput(photoOutput) else { throw CameraError.outputNotSupported }
        session.addOutput(photoOutput)
        // NOTE(AI Developer): `isHighResolutionCaptureEnabled` was
        // deprecated in iOS 16 in favor of `maxPhotoDimensions` (2026-07
        // fix, per Sean's build warning). Since our deployment target is
        // iOS 17, switch to the new API.
        //
        // NOTE(AI Developer), fixed 2026-07 per Sean's report ("running
        // correlation analysis" stuck for several minutes): this used to
        // pick the *largest* dimensions the sensor supports at all, which
        // on any LiDAR-capable iPhone (this app requires LiDAR) means up
        // to 48MP per photo. Every photo is embedded as base64 inside a
        // single case JSON document (see `StorageService`), so 20
        // full-resolution photos (10-shot protocol x 2 vehicles) could
        // balloon that document into the hundreds of MB -- which is what
        // was actually taking minutes to encode/write, not the analysis
        // math itself (confirmed by reading every analyzer in
        // `ForensicEngine/` end to end; all are bounded/fast). Forensic
        // damage documentation and Vision's contour analysis (capped at
        // 1024px, see `DeformationMatcher`) don't need 48MP -- 12MP
        // (4032x3024, the long-standing "full size" iPhone photo
        // resolution) is already far more detail than this app can use,
        // at a fraction of the file size. Pick the largest *supported*
        // dimension that is still <= 12MP, falling back to the sensor's
        // true max only if every supported mode somehow exceeds that
        // (shouldn't happen on any current device).
        let maxReasonablePixels = 4032 * 3024
        let candidateDimensions = device.activeFormat.supportedMaxPhotoDimensions
        if let capped = candidateDimensions
            .filter({ Int($0.width) * Int($0.height) <= maxReasonablePixels })
            .max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
            photoOutput.maxPhotoDimensions = capped
        } else if let fallbackMax = candidateDimensions.max(by: {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }) {
            photoOutput.maxPhotoDimensions = fallbackMax
        }
        if photoOutput.isDepthDataDeliverySupported {
            photoOutput.isDepthDataDeliveryEnabled = true
        }

        // NOTE(AI Developer), added 2026-07 for guided auto-capture: a
        // second output on this SAME session (not a separate
        // AVCaptureSession) for live frame analysis, feeding the Even
        // Lighting gate. Sean's initial question was whether this would
        // risk destabilizing the already-hardened photo pipeline -- it
        // doesn't: `AVCapturePhotoOutput` and `AVCaptureVideoDataOutput`
        // are independent, additive outputs on one session (Apple's own
        // AVCam sample runs both simultaneously), and
        // `ScarCaptureCameraService` already proved this exact
        // combination works reliably on-device. Frame analysis below is
        // throttled and uses only a cheap `CIAreaAverage` sample (no
        // full-resolution decode), matching that file's approach, to
        // avoid reopening the memory issues fixed elsewhere in this file
        // (see `generateThumbnail`/`estimateBrightness`'s NOTEs).
        guard session.canAddOutput(videoDataOutput) else { throw CameraError.outputNotSupported }
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: analysisQueue)
        session.addOutput(videoDataOutput)
        if let connection = videoDataOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90 // portrait
        }
        // `commitConfiguration()` now runs via the `defer` above -- no
        // explicit call needed here, and this way it's guaranteed to run
        // even if a future edit adds another early `throw` below.

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        DispatchQueue.main.async { [weak self] in
            self?.previewLayer = layer
            self?.observeDevice(device)
        }
    }

    // NOTE(AI Developer), added 2026-07 for guided auto-capture, same
    // pattern as `ScarCaptureCameraService.observeDevice`: KVO on the
    // active device's focus/exposure-adjustment flags drives the
    // Focused gate. Runs on the main actor (the closures below hop back
    // via `Task { @MainActor in ... }`) since `isFocused` is `@Published`.
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

    private nonisolated func bestCaptureDevice() -> AVCaptureDevice? {
        // Prefer wide-angle with autofocus
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTripleCamera],
            mediaType: .video,
            position: .back
        )
        return discovery.devices.first
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
        // NOTE(AI Developer), added 2026-07: mirrors
        // `ScarCaptureCameraService.stopSession` -- invalidate the
        // focus/exposure KVO observers on teardown so they don't fire
        // against a device this view no longer owns after
        // `.onDisappear`. Motion updates themselves stay running (they
        // already did before this change, driving `sensorReading` for
        // the pitch/roll level bar across the whole capture flow), so
        // only the device-specific observations are torn down here.
        deviceObservations.forEach { $0.invalidate() }
        deviceObservations = []
    }

    // MARK: - Motion Sensing

    // NOTE(AI Developer), fixed 2026-07 per Sean's on-device report ("why
    // is the camera preferred to be pointing down for everything?"): this
    // is the sensor reading actually used by `capturePhoto` to score shot
    // quality against each `CaptureProtocolStep`'s `idealPitchDegrees`/
    // `maxRollDegrees` -- so it had the same zero-point bug as
    // `CaptureViewModel.startSensors` (raw `attitude.pitch/roll` use "flat
    // on a table" as zero, not "held up, aimed level at the vehicle").
    // Every captured photo's quality score and off-angle flag were being
    // computed against the wrong physical baseline. Fixed the same way:
    // derive pitch/roll from the gravity vector via `CameraLevelMath`.
    private func setupMotionManager() {
        guard motionManager.isDeviceMotionAvailable else {
            // NOTE(AI Developer), added 2026-07: no gyro available --
            // don't block auto-capture on a signal we can't read, same
            // fallback as `ScarCaptureCameraService.startMotionUpdates`.
            isSteady = true
            return
        }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let (pitchDeg, rollDeg) = CameraLevelMath.pitchRollDegrees(
                fromGravity: (motion.gravity.x, motion.gravity.y, motion.gravity.z)
            )
            self.sensorReading = SensorReading(
                pitch: pitchDeg * .pi / 180.0,
                roll: rollDeg * .pi / 180.0,
                yaw: motion.attitude.yaw,
                heading: self.currentLocation?.course
            )
            // NOTE(AI Developer), added 2026-07 for guided auto-capture:
            // uses `rotationRate` (gyro, rad/s) rather than the
            // gravity-derived pitch/roll above -- this gate is about "is
            // the phone currently MOVING/shaking," not "is it aimed at a
            // particular angle" (that's what `SensorLevelBar`'s existing
            // pitch/roll guidance is for). Same distinction and approach
            // as `ScarCaptureCameraService.startMotionUpdates`.
            let r = motion.rotationRate
            let magnitude = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
            self.isSteady = magnitude < self.rotationRateThreshold
            self.updateGoodStreak()
        }
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    // MARK: - Auto-Capture Streak Tracking
    //
    // NOTE(AI Developer), added 2026-07: identical approach to
    // `ScarCaptureCameraService.updateGoodStreak`/`resetAutoCaptureStreak`
    // -- called on every published gate-state change (motion callback
    // and frame analysis both call this) to update `autoCaptureProgress`
    // and fire `onAutoCapture` once a continuous "all required gates
    // good" streak reaches `autoCaptureHoldSeconds`.

    /// NOTE(AI Developer), added 2026-07 alongside `isArmed`: the
    /// countdown now requires `isArmed` in addition to `allGatesGood` --
    /// gate state can be true or false at any moment regardless of
    /// arming (the status chips above the shutter still reflect the raw
    /// sensor state either way), but the actual `autoCaptureProgress`
    /// countdown, and the `onAutoCapture` fire, only happen once the
    /// user has tapped "Ready" for this shot.
    private func updateGoodStreak() {
        let now = Date()
        if isArmed && allGatesGood {
            let streak = now.timeIntervalSince(lastNotGoodTime)
            autoCaptureProgress = min(1.0, streak / autoCaptureHoldSeconds)
            if streak >= autoCaptureHoldSeconds && !hasFiredAutoCaptureForCurrentGoodStreak,
               case .idle = captureState {
                hasFiredAutoCaptureForCurrentGoodStreak = true
                onAutoCapture?()
            }
        } else {
            lastNotGoodTime = now
            hasFiredAutoCaptureForCurrentGoodStreak = false
            autoCaptureProgress = 0
        }
    }

    /// Called by `CaptureCameraView` right after a capture (auto or
    /// manual) completes, or whenever `viewModel.nextShotType` changes
    /// (a new shot's framing/lighting requirements make any in-progress
    /// streak toward the PREVIOUS shot meaningless) -- a new continuous
    /// streak is required before auto-capture can fire again. Also
    /// disarms (`isArmed = false`) so the user must explicitly tap
    /// "Ready" again for the next shot -- this is what actually fixes
    /// Sean's "fired again before I could move" report; without this,
    /// arming would otherwise persist across shots.
    func resetAutoCaptureStreak() {
        lastNotGoodTime = Date()
        hasFiredAutoCaptureForCurrentGoodStreak = false
        autoCaptureProgress = 0
        isArmed = false
    }

    /// Called by `CaptureCameraView` when the user taps the new "Ready"
    /// button, once they've finished repositioning for the current
    /// shot. Starts (or restarts) the continuous-good-streak clock right
    /// now rather than trusting whatever streak may have accumulated
    /// while unarmed -- so the full `autoCaptureHoldSeconds` hold is
    /// always required AFTER arming, never satisfied instantly by a
    /// streak that happened to already be running.
    func armAutoCapture() {
        isArmed = true
        lastNotGoodTime = Date()
        hasFiredAutoCaptureForCurrentGoodStreak = false
        autoCaptureProgress = 0
    }

    // MARK: - Photo Capture

    func capturePhoto(
        forStep step: CaptureProtocolStep,
        sequenceIndex: Int
    ) async throws -> CapturedPhoto {
        guard session.isRunning else { throw CameraError.sessionNotRunning }
        captureState = .capturing

        let imageData = try await captureImageData()
        let thumbnail = generateThumbnail(from: imageData)
        let sensor = sensorReading
        let gps = currentLocation.map { GPSCoordinate(location: $0) }

        let qualityScore = evaluateQuality(imageData: imageData, sensor: sensor, step: step)
        let flags = buildQualityFlags(imageData: imageData, sensor: sensor, step: step)

        let photo = CapturedPhoto(
            imageData: imageData,
            thumbnailData: thumbnail,
            photoType: step.photoType,
            qualityScore: qualityScore,
            qualityFlags: flags,
            sensorData: SensorData(
                pitch: sensor.pitch,
                roll: sensor.roll,
                yaw: sensor.yaw,
                heading: sensor.heading
            ),
            gpsCoordinate: gps,
            cameraSettings: CameraSettings(),
            sequenceIndex: sequenceIndex,
            annotationNotes: step.instruction
        )

        // NOTE(AI Developer), fixed 2026-07 per Sean's on-device report
        // ("Terminated by the operating system because it is using too
        // much memory" -- Xcode debug code 9 / iOS jetsam): this used to
        // `capturedPhotos.append(photo)` here, into a second
        // `@Published [CapturedPhoto]` array on `CameraService` that was
        // written to on every capture but never read anywhere in the app
        // (confirmed via a full-codebase grep -- nothing ever accesses
        // `camera.capturedPhotos`). Every returned `photo` is also stored
        // by the caller in `CaptureViewModel.capturedPhotos` and, from
        // there, in `forensicCase.victimVehicle`/`.suspectVehicle.photos`
        // -- so this dead array was holding a *third* full-resolution copy
        // of every captured photo's `imageData` in memory for the entire
        // capture session (worst case ~20-30 photos x 2 vehicles,
        // each already capped at ~12MP but still real memory), on top of
        // the two copies that are actually used. That's a plausible
        // contributor to hitting the OS memory ceiling over a full
        // protocol run. Removed the array entirely -- `capturePhoto(...)`
        // already returns the photo to its caller, which is the only
        // thing that ever needs it.
        captureState = .idle
        return photo
    }

    private func captureImageData() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            let settings = AVCapturePhotoSettings()
            settings.flashMode = flashMode
            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                // Use HEVC for smaller file sizes
            }
            var delegate: PhotoCaptureDelegate!
            delegate = PhotoCaptureDelegate { [weak self] result in
                // Release our strong reference now that the callback fired.
                if let self, let idx = self.activePhotoCaptureDelegates.firstIndex(where: { $0 === delegate }) {
                    self.activePhotoCaptureDelegates.remove(at: idx)
                }
                switch result {
                case .success(let data): continuation.resume(returning: data)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            // Retain delegate until its callback fires. AVCapturePhotoCaptureDelegate
            // is held weakly by AVCapturePhotoOutput, so something must keep a
            // strong reference alive for the duration of the async capture.
            activePhotoCaptureDelegates.append(delegate)
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    // NOTE(AI Developer), fixed 2026-07 per Sean's on-device report
    // ("terminated due to using too much memory", Xcode debug code 9,
    // screenshot showing CameraService.swift behind the dialog -- i.e.
    // this happened during capture, not during analysis): this used to
    // do `UIImage(data: data)` on the *original* ~12MP JPEG straight out
    // of the camera (up to ~46.5MB once decoded to an uncompressed
    // bitmap) purely to draw a 200x200 thumbnail from it -- on every
    // single shot of the 30-shot protocol, for both vehicles. Combined
    // with the identical mistake in `estimateBrightness` below (also
    // called on every shot, also decoding the same full-size JPEG a
    // second time), that's ~93MB of transient full-resolution decode
    // churn per shutter press, ~5.6GB of churn across a full two-vehicle
    // protocol run -- on top of whatever the camera preview, previously
    // captured JPEGs, and (if the LiDAR screen was visited) ARKit are
    // already holding. That repeated pressure is a very plausible
    // contributor to hitting the OS memory ceiling mid-capture.
    //
    // Fixed by switching to `CGImageSourceCreateThumbnailAtIndex`
    // (ImageIO), the same technique used in `MatchScoreCalculator`'s
    // `bestDamageImage` fix last round: this decodes the JPEG directly
    // at the target thumbnail size *during* decompression, so the full
    // ~46.5MB bitmap is never materialized at all -- only pixels at (or
    // near) the actual output size are ever decoded.
    private func generateThumbnail(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 200
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let thumbImage = UIImage(cgImage: cgThumb)
        return thumbImage.jpegData(compressionQuality: 0.6)
    }

    // MARK: - Quality Evaluation

    private func evaluateQuality(
        imageData: Data,
        sensor: SensorReading,
        step: CaptureProtocolStep
    ) -> Double {
        var score = 1.0
        if abs(sensor.rollDegrees) > step.maxRollDegrees { score -= 0.3 }
        if abs(sensor.pitchDegrees - step.idealPitchDegrees) > 20 { score -= 0.2 }
        let brightness = estimateBrightness(from: imageData)
        if brightness < 0.2 { score -= 0.25 }
        if brightness > 0.9 { score -= 0.15 }
        return max(0, min(1, score))
    }

    private func buildQualityFlags(
        imageData: Data,
        sensor: SensorReading,
        step: CaptureProtocolStep
    ) -> QualityFlags {
        var flags = QualityFlags()
        let brightness = estimateBrightness(from: imageData)
        flags.isUnderexposed = brightness < 0.2
        flags.isOverexposed = brightness > 0.9
        flags.isOffAngle = abs(sensor.rollDegrees) > step.maxRollDegrees
        return flags
    }

    // NOTE(AI Developer), fixed 2026-07 alongside `generateThumbnail`
    // above, same root cause: `UIImage(data: data)` here decoded the
    // *original* full-resolution JPEG a second time (this function and
    // `generateThumbnail` are both called from `capturePhoto` on every
    // shot) purely to compute a single average-brightness value via
    // `CIAreaAverage` -- a filter that averages over the *entire* image
    // extent regardless of input resolution, so a small thumbnail
    // produces effectively the same average as the full 12MP original,
    // at a fraction of the decode cost. Switched to the same
    // `CGImageSourceCreateThumbnailAtIndex` pattern (256px cap is more
    // than enough resolution for a single averaged brightness value) so
    // the full-size bitmap is never materialized here either.
    private func estimateBrightness(from data: Data) -> Double {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return 0.5 }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return 0.5
        }
        let context = CIContext()
        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: ciImage.extent)
        ])
        guard let output = filter?.outputImage,
              let bitmap = context.createCGImage(output, from: CGRect(x: 0, y: 0, width: 1, height: 1)) else {
            return 0.5
        }
        let data = bitmap.dataProvider?.data.flatMap { Data($0 as Data) }
        guard let bytes = data, bytes.count >= 3 else { return 0.5 }
        let r = Double(bytes[0]) / 255.0
        let g = Double(bytes[1]) / 255.0
        let b = Double(bytes[2]) / 255.0
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}

// MARK: - CLLocationManagerDelegate

extension CameraService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.currentLocation = locations.last
        }
    }
}

// MARK: - Video Data Output Delegate (lighting-evenness gate)
//
// NOTE(AI Developer), added 2026-07 for guided auto-capture -- same
// `CIAreaAverage`-based 2x2-quadrant luma-spread technique as
// `ScarCaptureCameraService`'s identical extension, sampling
// `CameraService.lightingSampleRect` instead of a scar-specific
// `guideRect` since this camera has no single fixed subject box across
// all 30 shot types. Only feeds `isWellLit`/`lightingMessage`;
// `allGatesGood` only actually requires `isWellLit` when
// `currentShotRequiresEvenLighting` is true for the shot in progress
// (see `PhotoType.usesEvenLightingGate`), so this analysis quietly runs
// for every shot but is only load-bearing for macro/closeup types.
extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        frameCounterIncrement { shouldAnalyze in
            guard shouldAnalyze else { return }
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let sample = CameraService.lightingSampleRect
            let sampleRectPixels = CGRect(
                x: sample.minX * CGFloat(width),
                y: sample.minY * CGFloat(height),
                width: sample.width * CGFloat(width),
                height: sample.height * CGFloat(height)
            )
            let halfW = sampleRectPixels.width / 2
            let halfH = sampleRectPixels.height / 2
            let quadrants = [
                CGRect(x: sampleRectPixels.minX, y: sampleRectPixels.minY, width: halfW, height: halfH),
                CGRect(x: sampleRectPixels.minX + halfW, y: sampleRectPixels.minY, width: halfW, height: halfH),
                CGRect(x: sampleRectPixels.minX, y: sampleRectPixels.minY + halfH, width: halfW, height: halfH),
                CGRect(x: sampleRectPixels.minX + halfW, y: sampleRectPixels.minY + halfH, width: halfW, height: halfH)
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
                    self.lightingMessage = "Uneven light — even out shadows/glare"
                } else {
                    self.isWellLit = true
                    self.lightingMessage = "Lighting looks even"
                }
                self.updateGoodStreak()
            }
        }
    }

    /// Average luma (0-1) of `image` within `pixelRect`, same technique
    /// as `estimateBrightness(from:)` below and
    /// `ScarCaptureCameraService.averageLuma`.
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
    /// nonisolated delegate queue context, same pattern as
    /// `ScarCaptureCameraService.frameCounterIncrement`.
    nonisolated private func frameCounterIncrement(_ body: (Bool) -> Void) {
        frameCounter += 1
        body(frameCounter % analyzeEveryNthFrame == 0)
    }
}

// MARK: - Photo Capture Delegate

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
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

// MARK: - Supporting Types

struct SensorReading {
    var pitch: Double = 0
    var roll: Double = 0
    var yaw: Double = 0
    var heading: Double?

    var pitchDegrees: Double { pitch * 180 / .pi }
    var rollDegrees: Double { roll * 180 / .pi }
    var isLevel: Bool { abs(rollDegrees) <= 10.0 }
}

enum CaptureState {
    case idle, capturing, processing, error(String)
}

enum CameraError: LocalizedError {
    case deviceUnavailable
    case inputNotSupported
    case outputNotSupported
    case sessionNotRunning
    case noImageData

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: return "No suitable camera found"
        case .inputNotSupported: return "Camera input not supported"
        case .outputNotSupported: return "Photo output not supported"
        case .sessionNotRunning: return "Camera session not active"
        case .noImageData: return "Failed to capture image data"
        }
    }
}

// MARK: - Capture Protocol Step

struct CaptureProtocolStep: Identifiable {
    let id: Int
    let shotNumber: Int
    let photoType: PhotoType
    let instruction: String
    let idealPitchDegrees: Double
    let maxRollDegrees: Double
    let idealDistanceMeters: Double?

    static let fullProtocol: [CaptureProtocolStep] = [
        CaptureProtocolStep(id: 0, shotNumber: 1, photoType: .wideAngle,
            instruction: "Wide shot: entire vehicle from 10 ft, level",
            idealPitchDegrees: 0, maxRollDegrees: 10, idealDistanceMeters: 3.0),
        CaptureProtocolStep(id: 1, shotNumber: 2, photoType: .wideAngle,
            instruction: "Wide shot: 45° driver side angle",
            idealPitchDegrees: -5, maxRollDegrees: 10, idealDistanceMeters: 3.0),
        CaptureProtocolStep(id: 2, shotNumber: 3, photoType: .wideAngle,
            instruction: "Wide shot: 45° passenger side angle",
            idealPitchDegrees: -5, maxRollDegrees: 10, idealDistanceMeters: 3.0),
        CaptureProtocolStep(id: 3, shotNumber: 4, photoType: .heightMeasurement,
            instruction: "Height reference: bumper at ground level, perpendicular",
            idealPitchDegrees: 0, maxRollDegrees: 5, idealDistanceMeters: 1.0),
        CaptureProtocolStep(id: 4, shotNumber: 5, photoType: .heightMeasurement,
            instruction: "Height reference: ruler or tape measure at damage center",
            idealPitchDegrees: 0, maxRollDegrees: 5, idealDistanceMeters: 0.5),
        CaptureProtocolStep(id: 5, shotNumber: 6, photoType: .closeupDamage,
            instruction: "Primary damage: straight-on closeup (2 ft)",
            idealPitchDegrees: 0, maxRollDegrees: 8, idealDistanceMeters: 0.6),
        CaptureProtocolStep(id: 6, shotNumber: 7, photoType: .closeupDamage,
            instruction: "Primary damage: upper edge detail",
            idealPitchDegrees: -15, maxRollDegrees: 10, idealDistanceMeters: 0.5),
        CaptureProtocolStep(id: 7, shotNumber: 8, photoType: .closeupDamage,
            instruction: "Primary damage: lower edge / ground contact",
            idealPitchDegrees: 15, maxRollDegrees: 10, idealDistanceMeters: 0.5),
        CaptureProtocolStep(id: 8, shotNumber: 9, photoType: .paintTransfer,
            instruction: "Paint transfer zone: macro closeup, fill frame",
            idealPitchDegrees: 0, maxRollDegrees: 5, idealDistanceMeters: 0.3),
        CaptureProtocolStep(id: 9, shotNumber: 10, photoType: .paintTransfer,
            instruction: "Paint transfer: raking light from left",
            idealPitchDegrees: 0, maxRollDegrees: 5, idealDistanceMeters: 0.3),
        CaptureProtocolStep(id: 10, shotNumber: 11, photoType: .paintTransfer,
            instruction: "Paint transfer: raking light from right",
            idealPitchDegrees: 0, maxRollDegrees: 5, idealDistanceMeters: 0.3),
        CaptureProtocolStep(id: 11, shotNumber: 12, photoType: .closeupDamage,
            instruction: "Deformation depth: side-profile of crumple",
            idealPitchDegrees: 0, maxRollDegrees: 5, idealDistanceMeters: 0.5),
        CaptureProtocolStep(id: 12, shotNumber: 13, photoType: .closeupDamage,
            instruction: "Damage edges: left boundary",
            idealPitchDegrees: 0, maxRollDegrees: 10, idealDistanceMeters: 0.4),
        CaptureProtocolStep(id: 13, shotNumber: 14, photoType: .closeupDamage,
            instruction: "Damage edges: right boundary",
            idealPitchDegrees: 0, maxRollDegrees: 10, idealDistanceMeters: 0.4),
        CaptureProtocolStep(id: 14, shotNumber: 15, photoType: .contextShot,
            instruction: "Context: damage area with surroundings for scale",
            idealPitchDegrees: -5, maxRollDegrees: 12, idealDistanceMeters: 2.0),
        CaptureProtocolStep(id: 15, shotNumber: 16, photoType: .wideAngle,
            instruction: "Vehicle rear three-quarter view",
            idealPitchDegrees: -5, maxRollDegrees: 10, idealDistanceMeters: 3.0),
        CaptureProtocolStep(id: 16, shotNumber: 17, photoType: .wideAngle,
            instruction: "Vehicle front three-quarter view",
            idealPitchDegrees: -5, maxRollDegrees: 10, idealDistanceMeters: 3.0),
        CaptureProtocolStep(id: 17, shotNumber: 18, photoType: .licenseDetail,
            instruction: "License plate: front",
            idealPitchDegrees: 0, maxRollDegrees: 8, idealDistanceMeters: 0.8),
        CaptureProtocolStep(id: 18, shotNumber: 19, photoType: .licenseDetail,
            instruction: "License plate: rear",
            idealPitchDegrees: 0, maxRollDegrees: 8, idealDistanceMeters: 0.8),
        CaptureProtocolStep(id: 19, shotNumber: 20, photoType: .licenseDetail,
            instruction: "VIN plate (if visible)",
            idealPitchDegrees: 0, maxRollDegrees: 8, idealDistanceMeters: 0.5),
        CaptureProtocolStep(id: 20, shotNumber: 21, photoType: .lidarReference,
            instruction: "LiDAR reference: damage zone perpendicular (AR mode)",
            idealPitchDegrees: 0, maxRollDegrees: 5, idealDistanceMeters: 0.8),
        CaptureProtocolStep(id: 21, shotNumber: 22, photoType: .closeupDamage,
            instruction: "Secondary damage zone (if present)",
            idealPitchDegrees: 0, maxRollDegrees: 10, idealDistanceMeters: 0.5),
        CaptureProtocolStep(id: 22, shotNumber: 23, photoType: .paintTransfer,
            instruction: "Foreign paint fragment closeup",
            idealPitchDegrees: 0, maxRollDegrees: 5, idealDistanceMeters: 0.25),
        CaptureProtocolStep(id: 23, shotNumber: 24, photoType: .contextShot,
            instruction: "Adjacent undamaged panel for color baseline",
            idealPitchDegrees: 0, maxRollDegrees: 10, idealDistanceMeters: 0.8),
        CaptureProtocolStep(id: 24, shotNumber: 25, photoType: .heightMeasurement,
            instruction: "Ground-to-rocker height reference",
            idealPitchDegrees: 5, maxRollDegrees: 5, idealDistanceMeters: 0.8),
        CaptureProtocolStep(id: 25, shotNumber: 26, photoType: .contextShot,
            instruction: "Scene overview: vehicle in environment",
            idealPitchDegrees: -10, maxRollDegrees: 15, idealDistanceMeters: 6.0),
        CaptureProtocolStep(id: 26, shotNumber: 27, photoType: .closeupDamage,
            instruction: "Scratches or gouges: extreme closeup",
            idealPitchDegrees: 0, maxRollDegrees: 8, idealDistanceMeters: 0.2),
        CaptureProtocolStep(id: 27, shotNumber: 28, photoType: .wideAngle,
            instruction: "Vehicle profile: driver side",
            idealPitchDegrees: 0, maxRollDegrees: 5, idealDistanceMeters: 4.0),
        CaptureProtocolStep(id: 28, shotNumber: 29, photoType: .wideAngle,
            instruction: "Vehicle profile: passenger side",
            idealPitchDegrees: 0, maxRollDegrees: 5, idealDistanceMeters: 4.0),
        CaptureProtocolStep(id: 29, shotNumber: 30, photoType: .contextShot,
            instruction: "Final verification: all damage in one frame",
            idealPitchDegrees: -5, maxRollDegrees: 10, idealDistanceMeters: 2.5),
    ]
}
