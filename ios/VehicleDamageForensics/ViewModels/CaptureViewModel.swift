// CaptureViewModel.swift
// Vehicle Damage Investigation Assistant
// Drives the 30-shot guided photo capture protocol. Tracks shot
// progress, exposes the next required photo type, and handles the
// hand-off to the camera + LiDAR services.

import Foundation
import UIKit
import Combine
import CoreMotion
import CoreLocation

// MARK: - Capture View Model

@MainActor
final class CaptureViewModel: ObservableObject {

    // MARK: Published

    @Published var forensicCase: ForensicCase
    @Published var captureRole: VehicleRole = .victim
    @Published private(set) var currentSensorData: SensorData = SensorData()
    @Published private(set) var lastQualityFlags: QualityFlags = QualityFlags()
    @Published var statusMessage: String = "Position phone perpendicular to damage."
    @Published var isCapturing: Bool = false

    // MARK: Protocol definition

    /// Ordered list of shot types required for a complete capture.
    /// NOTE(AI Developer): Now sourced from `PhotoType.requiredCaptureProtocol`
    /// (Models/Vehicle.swift) — the single canonical v1 shot list — instead
    /// of a separately-maintained literal array, so this can't silently
    /// drift out of sync with `ForensicCase.isReadyForAnalysis` again.
    let protocolShots: [PhotoType] = PhotoType.requiredCaptureProtocol

    // NOTE(AI Developer), fixed 2026-07 per Sean's on-device report
    // ("terminated due to using too much memory", Xcode debug code 9,
    // recurring even after the CameraService-level fixes this same
    // round): this used to be `capturedPhotos.count`, backed by a
    // `@Published private(set) var capturedPhotos: [CapturedPhoto] = []`
    // that `record(photo:)`/`importPhoto(_:)` appended to on every shot
    // and `switchToSuspect()` cleared via `.removeAll()`. That array's
    // *only* real purpose was this shot count -- nothing ever read its
    // contents (confirmed via a full-codebase grep) -- but every photo
    // appended to it is *also* already stored in
    // `forensicCase.victimVehicle.photos`/`.suspectVehicle.photos` right
    // below in the same functions. That's the exact same dead-duplicate-
    // array bug fixed in `CameraService.capturedPhotos` two rounds ago,
    // just one level higher in the call stack, and it slipped through
    // that audit specifically because `.count` on it looked like a real
    // reader. A full two-vehicle, 30-shot protocol run was keeping a
    // *third* full-resolution copy of every photo's `imageData` in
    // memory for the entire capture session because of this. Removed
    // the array entirely; the shot count is derived directly from
    // whichever vehicle's photo list matches the active `captureRole`,
    // which is the actual source of truth and needs no separate
    // bookkeeping (it also naturally resets to 0 the moment
    // `switchToSuspect()` flips `captureRole`, since
    // `forensicCase.suspectVehicle?.photos` starts empty -- no explicit
    // `.removeAll()` call needed there anymore either).
    //
    // NOTE(AI Developer), updated 2026-07 per Sean's "skip a shot"
    // request: now counts explicitly-skipped slots (`Vehicle.
    // skippedShotIndices`) toward the pointer as well as actually
    // captured/imported photos, so skipping a slot correctly advances
    // to the next one instead of leaving `nextShotType` stuck asking for
    // the shot that was just skipped. Both `photos` and
    // `skippedShotIndices` are only ever appended to in protocol order,
    // so their combined count is still a correct pointer into
    // `protocolShots`.
    var currentShotIndex: Int {
        switch captureRole {
        case .victim:
            return forensicCase.victimVehicle.photos.count
                + forensicCase.victimVehicle.skippedShotIndices.count
        case .suspect:
            return (forensicCase.suspectVehicle?.photos.count ?? 0)
                + (forensicCase.suspectVehicle?.skippedShotIndices.count ?? 0)
        }
    }

    var nextShotType: PhotoType? {
        guard currentShotIndex < protocolShots.count else { return nil }
        return protocolShots[currentShotIndex]
    }

    var progress: Double {
        Double(currentShotIndex) / Double(protocolShots.count)
    }

    var isComplete: Bool {
        currentShotIndex >= protocolShots.count
    }

    /// True once the active vehicle's impact location + direction of
    /// travel have both been recorded. NOTE(AI Developer), added 2026-07
    /// per Sean's decision that this step is REQUIRED (unlike the
    /// skippable photo protocol) -- drives the "Continue to Suspect" /
    /// "Run Analysis" button gating in `CaptureFlowView` alongside
    /// `isComplete`. See `Vehicle.hasImpactProfile`.
    var hasImpactProfile: Bool {
        switch captureRole {
        case .victim: return forensicCase.victimVehicle.hasImpactProfile
        case .suspect: return forensicCase.suspectVehicle?.hasImpactProfile ?? false
        }
    }

    // MARK: Dependencies

    private let storage: StorageService
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()

    /// NOTE(AI Developer): `storage` defaults to `nil` here (rather than
    /// `= .shared` directly in the parameter list) because default-argument
    /// expressions are evaluated in a non-isolated context under Swift 6
    /// strict concurrency, and `StorageService.shared` is `@MainActor`-
    /// isolated. Resolving the actual default inside the (MainActor-
    /// isolated) init body avoids the "Call to main actor-isolated ...
    /// from synchronous nonisolated context" error.
    ///
    /// NOTE(AI Developer), fixed 2026-07 per Sean's on-device report
    /// ("terminated due to using too much memory", Xcode debug code 9):
    /// this used to also accept/store a `cameraService: CameraService?`
    /// parameter, defaulting to a brand-new `CameraService()` -- but
    /// nothing on `self.cameraService` was ever called anywhere in this
    /// class (confirmed via grep) and no caller ever passed one in either
    /// (`CaptureFlowView` only ever calls `CaptureViewModel(forensicCase:)`).
    /// `CaptureCameraView` creates and drives its own, completely separate
    /// `CameraService` instance for the actual live preview/capture --
    /// this one was a second, fully-idle copy, whose own `init()` starts
    /// a second `CMMotionManager` (30Hz device-motion updates) and a
    /// second `CLLocationManager` (continuous location updates) that ran
    /// for the entire capture session for no purpose. Removed the
    /// property and parameter entirely.
    init(forensicCase: ForensicCase,
         storage: StorageService? = nil) {
        self.forensicCase = forensicCase
        self.storage = storage ?? .shared
        startSensors()
    }

    // MARK: Public API

    /// Record a live-captured photo into the case under the active vehicle role.
    ///
    /// NOTE(AI Developer), fixed 2026-07 per Sean's on-device report
    /// ("terminated due to using too much memory", Xcode debug code 9):
    /// this used to take a `UIImage` and *rebuild* a brand-new
    /// `CapturedPhoto` from scratch -- but the caller
    /// (`CaptureCameraView.captureNextShot()`) already has a fully-formed
    /// `CapturedPhoto` straight from `CameraService.capturePhoto(...)`,
    /// complete with the correct GPS coordinate, gravity-corrected sensor
    /// reading (`SensorReading`/`CameraLevelMath`), and a real
    /// roll/pitch/brightness-based quality score. To call this old
    /// signature, the caller had to decode that photo's `imageData` back
    /// into a full-resolution `UIImage` (~46.5MB bitmap) purely so this
    /// method could re-encode it to JPEG *again* and throw together a
    /// second, strictly worse `CapturedPhoto` (`estimateQuality(for:)`'s
    /// placeholder score instead of the camera's real one, no GPS via
    /// `currentLocation()` -- see NOTE below -- and `currentSensorData`/
    /// `lastQualityFlags`, which are just late CoreMotion snapshots on
    /// this view model, not necessarily the exact reading at the instant
    /// of capture). That decode+re-encode round trip was a third
    /// full-resolution image operation per shot, on top of the two fixed
    /// in `CameraService.generateThumbnail`/`estimateBrightness` this same
    /// round -- and it was strictly *lossy* for the forensic record.
    /// Fixed by accepting the camera's own `CapturedPhoto` directly: no
    /// image decode of any kind happens here anymore, and the persisted
    /// record now uses the camera's own accurate metadata unconditionally.
    func record(photo capturedPhoto: CapturedPhoto) async {
        guard nextShotType != nil else { return }
        var photo = capturedPhoto
        photo.sequenceIndex = currentShotIndex + 1
        switch captureRole {
        case .victim:
            forensicCase.victimVehicle.photos.append(photo)
        case .suspect:
            if forensicCase.suspectVehicle == nil {
                forensicCase.suspectVehicle = Vehicle(role: .suspect)
            }
            forensicCase.suspectVehicle?.photos.append(photo)
        }
        // NOTE(AI Developer): Chain-of-custody entry per Sean's decision to
        // add the audit log (2026-07). Recorded before save so the entry is
        // persisted atomically with the photo it describes.
        forensicCase.recordAudit(.photoCaptured, detail: "\(captureRole.displayName): \(photo.photoType.displayName) (#\(photo.sequenceIndex))")
        await storage.save(forensicCase)
        updateGuidance()
    }

    /// Import an existing photo (e.g. from the camera roll) into the case
    /// under the active vehicle role, counting it toward the current
    /// required shot slot just like a live capture.
    ///
    /// NOTE(AI Developer), added 2026-07 per Sean's request ("we also
    /// should have the ability to upload images from camera roll") --
    /// useful when e.g. a bystander already snapped a photo of the
    /// suspect vehicle before Sean arrived, or a photo was taken on a
    /// different device and AirDropped over. Deliberately mirrors
    /// `record(photo:)`'s structure (same audit-then-save ordering, same
    /// role-based routing) so the two capture paths can't silently drift
    /// apart, but marks the result `wasImported: true` and skips
    /// sensor/GPS/quality scoring -- there's no live sensor reading for a
    /// photo that wasn't just taken by this device, and fabricating one
    /// would misrepresent the evidence record. See `CapturedPhoto.wasImported`.
    func importPhoto(_ image: UIImage) async {
        guard let type = nextShotType else { return }
        // NOTE(AI Developer), fixed 2026-07 per Sean's on-device report
        // ("its been 'running correlation analysis' for a few minutes
        // again"): unlike the live-capture path (`record(photo:)`), whose
        // source photo comes from `CameraService.capturePhoto()` (already
        // capped via `photoOutput.maxPhotoDimensions`), this path's `image` comes
        // straight from `PhotosPicker`/`loadTransferable` with NO
        // resolution cap -- a picked photo can be the device's full
        // native resolution (e.g. a 48MP ProRAW-derived JPEG), which
        // bloats `CapturedPhoto.imageData`, in turn bloating the case's
        // JSON file, and reproduces the same class of slow encode/write
        // that `StorageService`'s background-task fix addressed for the
        // *live-capture* path -- just via this different (import) entry
        // point. `resizedForStorage` applies the same ~12MP cap already
        // used in `CameraService.swift` before we ever call `jpegData`.
        let stored = resizedForStorage(image)
        let data = stored.jpegData(compressionQuality: 0.85) ?? Data()
        let thumb = stored.preparingThumbnail(of: CGSize(width: 240, height: 240))?
            .jpegData(compressionQuality: 0.6)

        let photo = CapturedPhoto(
            imageData: data,
            thumbnailData: thumb,
            captureDate: Date(),
            photoType: type,
            qualityScore: 0.0,
            qualityFlags: QualityFlags(),
            sensorData: SensorData(),
            gpsCoordinate: nil,
            cameraSettings: CameraSettings(),
            sequenceIndex: currentShotIndex + 1,
            annotationNotes: "Imported from photo library",
            wasImported: true
        )
        switch captureRole {
        case .victim:
            forensicCase.victimVehicle.photos.append(photo)
        case .suspect:
            if forensicCase.suspectVehicle == nil {
                forensicCase.suspectVehicle = Vehicle(role: .suspect)
            }
            forensicCase.suspectVehicle?.photos.append(photo)
        }
        forensicCase.recordAudit(.photoImported, detail: "\(captureRole.displayName): \(type.displayName) (#\(photo.sequenceIndex))")
        await storage.save(forensicCase)
        updateGuidance()
    }

    /// Explicitly skip the current required shot slot without capturing
    /// or importing a photo for it, advancing to the next shot in the
    /// protocol.
    ///
    /// NOTE(AI Developer), added 2026-07 per Sean's explicit request
    /// ("we should be able to skip a certain image view if we dont have
    /// an image in the camera roll or are no longer near the vehicle...
    /// most times this will likely be images uploaded after the fact")
    /// and his follow-up answers: skipping counts a slot as "done" for
    /// completion purposes ("a skipped shot should account for done
    /// unless the image is absolutely necessary"), and no shot type is
    /// mandatory/unskippable ("let's not allow mandatory shots" — every
    /// entry in `protocolShots` can be skipped). Records the skip in the
    /// chain-of-custody audit log (distinct `.photoSkipped` action, see
    /// `AuditAction`) with the shot type and reason so the gap is
    /// transparent in the report rather than silently missing -- see
    /// Sean's decision on the results/PDF wording ("Shot X was skipped:
    /// not available"), rendered by `MatchResultsView`/`PDFReportGenerator`
    /// reading `Vehicle.skippedShotIndices` against `protocolShots`.
    ///
    /// `reason` is free text describing *why* (surfaced to the button's
    /// confirmation dialog in `CaptureCameraView` — e.g. "No matching
    /// photo in camera roll" or "No longer near vehicle") so the audit
    /// trail records intent, not just the fact that a slot was skipped.
    func skipCurrentShot(reason: String) async {
        guard let type = nextShotType else { return }
        let skippedIndex = currentShotIndex
        switch captureRole {
        case .victim:
            forensicCase.victimVehicle.skippedShotIndices.append(skippedIndex)
        case .suspect:
            if forensicCase.suspectVehicle == nil {
                forensicCase.suspectVehicle = Vehicle(role: .suspect)
            }
            forensicCase.suspectVehicle?.skippedShotIndices.append(skippedIndex)
        }
        forensicCase.recordAudit(.photoSkipped, detail: "\(captureRole.displayName): \(type.displayName) (#\(skippedIndex + 1)) — \(reason)")
        await storage.save(forensicCase)
        updateGuidance()
    }

    /// Record the active vehicle's impact location (tap point on the
    /// top-down silhouette, normalized 0-1/0-1) and direction of travel
    /// at impact (compass degrees, 0-360).
    ///
    /// NOTE(AI Developer), added 2026-07 per Sean's request ("should we
    /// identify the location of the damage on each vehicle and always
    /// identify the direction of traveling at impact... to help
    /// correlating data") and his follow-up decision that this step is
    /// REQUIRED (unlike photo skipping). Called from `ImpactMarkerView`
    /// once the user has both tapped a damage location and set a heading
    /// (live compass or manual dial — see that view for the two entry
    /// modes). Feeds `MatchScoreCalculator.scoreImpactGeometry` via
    /// `Vehicle.impactBearingDegrees` — see that property's doc comment
    /// for why this specific combination of inputs produces a real,
    /// usable impact-angle-reciprocity score where none existed before.
    func recordImpactProfile(tapPoint: CGPoint, directionDegrees: Double) async {
        let wasAlreadyRecorded: Bool
        switch captureRole {
        case .victim:
            wasAlreadyRecorded = forensicCase.victimVehicle.hasImpactProfile
            forensicCase.victimVehicle.impactTapPoint = tapPoint
            forensicCase.victimVehicle.directionOfTravelDegrees = directionDegrees
        case .suspect:
            if forensicCase.suspectVehicle == nil {
                forensicCase.suspectVehicle = Vehicle(role: .suspect)
            }
            wasAlreadyRecorded = forensicCase.suspectVehicle?.hasImpactProfile ?? false
            forensicCase.suspectVehicle?.impactTapPoint = tapPoint
            forensicCase.suspectVehicle?.directionOfTravelDegrees = directionDegrees
        }
        // Only log the audit entry the first time this vehicle's profile
        // is completed, not on every subsequent adjustment/re-tap.
        if !wasAlreadyRecorded {
            forensicCase.recordAudit(.impactProfileRecorded, detail: "\(captureRole.displayName) vehicle")
        }
        await storage.save(forensicCase)
    }

    /// Record a physical damage height (inches) measured directly off the
    /// LiDAR-reconstructed mesh, via `LiDARScanView`'s tap-to-measure step
    /// (tap the ground, then tap the damage point; the vertical distance
    /// between the two raycast hits is `inches`).
    ///
    /// NOTE(AI Developer), added 2026-07 per Sean's explicit request ("wire
    /// LiDAR data into the Height Alignment factor as a next step... we
    /// need the use of Lidar as an extra tool"). Mirrors
    /// `recordImpactProfile(tapPoint:directionDegrees:)`'s structure
    /// (role-based switch, `wasAlreadyRecorded` guard so re-measuring
    /// doesn't spam the audit log, then persist). Sets
    /// `Vehicle.lidarMeasuredHeightInches`, which
    /// `Vehicle.effectiveBumperHeightInches` prefers over the
    /// never-actually-populated manual-entry `bumperHeightInches` field --
    /// see that computed property and its use in
    /// `MatchScoreCalculator.evaluate()`.
    func recordLiDARMeasurement(inches: Double) async {
        let wasAlreadyRecorded: Bool
        switch captureRole {
        case .victim:
            wasAlreadyRecorded = forensicCase.victimVehicle.hasLiDARMeasurement
            forensicCase.victimVehicle.lidarMeasuredHeightInches = inches
        case .suspect:
            if forensicCase.suspectVehicle == nil {
                forensicCase.suspectVehicle = Vehicle(role: .suspect)
            }
            wasAlreadyRecorded = forensicCase.suspectVehicle?.hasLiDARMeasurement ?? false
            forensicCase.suspectVehicle?.lidarMeasuredHeightInches = inches
        }
        // Only log the audit entry the first time this vehicle gets a
        // measurement, not on every subsequent re-measure.
        if !wasAlreadyRecorded {
            forensicCase.recordAudit(.lidarMeasurementRecorded, detail: "\(captureRole.displayName) vehicle: \(String(format: "%.1f", inches))\"")
        }
        await storage.save(forensicCase)
    }

    /// Switch to capturing the suspect vehicle after victim is complete.
    /// NOTE(AI Developer), simplified 2026-07 alongside the `capturedPhotos`
    /// removal above: no explicit reset needed here anymore --
    /// `currentShotIndex` now reads `forensicCase.suspectVehicle?.photos.count`
    /// for the `.suspect` role, which is naturally 0 until photos are
    /// actually appended to it.
    func switchToSuspect() {
        captureRole = .suspect
        statusMessage = "Capturing suspect vehicle. Maintain consistent angle and distance."
    }

    /// Apply case-level edits made via `EditCaseSheet` (case name/type,
    /// incident details, victim/suspect vehicle info) while a capture is
    /// in progress. NOTE(AI Developer): Added per Sean's decision
    /// (2026-07) so investigators can record suspect vehicle details
    /// (make/model/plate from a witness, say) as soon as they're known,
    /// without waiting for suspect photo capture to begin.
    func applyEdits(_ updated: ForensicCase) async {
        var updated = updated
        updated.recordAudit(.caseEdited)
        forensicCase = updated
        await storage.save(forensicCase)
    }

    // MARK: Sensor monitoring

    private func startSensors() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.1
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, let m = motion else { return }
                // NOTE(AI Developer), fixed 2026-07 per Sean's on-device
                // report ("why is the camera preferred to be pointing down
                // for everything?"): previously stored `m.attitude.pitch`/
                // `.roll` directly, but CMAttitude's zero-point is "phone
                // flat on a table" -- not "phone held up, aimed level at
                // the vehicle" (which is what `idealPitchDegrees: 0` in
                // CaptureProtocolStep actually means). That mismatch made
                // "pitch near 0" only achievable by flattening the phone
                // toward the ground. Fixed by deriving pitch/roll from the
                // raw gravity vector via `CameraLevelMath`, whose zero
                // point matches "phone held vertically, camera level" --
                // see CameraLevelMath.swift for the full derivation.
                let (pitchDeg, rollDeg) = CameraLevelMath.pitchRollDegrees(
                    fromGravity: (m.gravity.x, m.gravity.y, m.gravity.z)
                )
                self.currentSensorData = SensorData(
                    pitch: pitchDeg * .pi / 180.0,
                    roll: rollDeg * .pi / 180.0,
                    yaw: m.attitude.yaw,
                    accelerometer: SIMD3<Double>(m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z)
                )
                self.updateGuidance()
            }
        }
        locationManager.requestWhenInUseAuthorization()
    }

    /// NOTE(AI Developer), rewritten 2026-07 per Sean's feedback ("pitch
    /// and roll is tough to use, needs to be easier to follow and more
    /// intuitive... maybe add better directions or cues"). Previously this
    /// only printed the raw degree value with no indication of *which way*
    /// to move the phone. Now gives an explicit directional instruction
    /// ("tilt left/right", "aim up/down") derived from the sign of the
    /// (now correctly zeroed, see `startSensors`) pitch/roll. Also uses
    /// gentler thresholds (a "close" band before the hard warning) so the
    /// message doesn't flicker between two states right at the boundary.
    private func updateGuidance() {
        guard let next = nextShotType else {
            statusMessage = "Capture complete. Tap Analyze to proceed."
            return
        }
        let roll = currentSensorData.rollDegrees
        let pitch = currentSensorData.pitchDegrees

        if abs(roll) > 15 {
            let direction = roll > 0 ? "left" : "right"
            statusMessage = "Tilt \(direction) to level the horizon (\(Int(abs(roll)))° off)"
        } else if abs(pitch) > 25 {
            let direction = pitch > 0 ? "down" : "up"
            statusMessage = "Aim the camera more \(direction) — hold it level with the damage"
        } else {
            statusMessage = "Next: \(next.displayName) (\(currentShotIndex + 1)/\(protocolShots.count))"
        }
    }

    // NOTE(AI Developer), removed 2026-07: `estimateQuality(for:)` used to
    // live here -- a placeholder quality estimator (fixed 0.85 base
    // score, adjusted only by this view model's own late CoreMotion
    // snapshot) that `record(image:)` used to pass to a `CapturedPhoto`
    // it rebuilt from scratch. Now that `record(photo:)` takes the
    // camera's own already-scored `CapturedPhoto` directly (see NOTE on
    // `record(photo:)` above), this placeholder had no remaining caller
    // and would only ever have produced a *worse* score than
    // `CameraService.evaluateQuality` (which factors in real
    // roll/pitch-vs-step-target deltas and actual image brightness).
    // Removed rather than left dead, since it's strictly superseded, not
    // reserved for future use.

    /// Caps `image`'s pixel dimensions before it's ever handed to
    /// `jpegData(compressionQuality:)`, mirroring the ~12MP
    /// (4032x3024) ceiling `CameraService` already enforces on live
    /// captures via `photoOutput.maxPhotoDimensions`.
    ///
    /// NOTE(AI Developer), added 2026-07 as the fix for the recurred
    /// "Running correlation analysis" hang Sean reported after the
    /// original `StorageService`/`CameraService` fix: an imported
    /// camera-roll photo has no upstream cap the way a live capture
    /// does, so it can come in at the device's full native resolution
    /// (e.g. 48MP+). Embedding that directly into `CapturedPhoto.imageData`
    /// bloats the case's JSON file enough that even the *backgrounded*
    /// encode/write in `StorageService.save(_:)` can take minutes of
    /// real CPU+I/O time -- which surfaces to the user as a stuck
    /// "Running correlation analysis" spinner (analysis and the
    /// preceding save both compete for the same background executor).
    /// Downsampling here, once, before storage keeps every downstream
    /// consumer (JSON encode, Vision requests in `DeformationMatcher`,
    /// PDF export) working with a bounded-size image regardless of
    /// where the original bytes came from.
    private func resizedForStorage(_ image: UIImage) -> UIImage {
        let maxReasonablePixels = 4032.0 * 3024.0
        let pixelWidth = Double(image.size.width * image.scale)
        let pixelHeight = Double(image.size.height * image.scale)
        let pixelCount = pixelWidth * pixelHeight
        guard pixelCount > maxReasonablePixels, pixelWidth > 0, pixelHeight > 0 else {
            return image
        }
        let scaleFactor = (maxReasonablePixels / pixelCount).squareRoot()
        let targetSize = CGSize(
            width: max(1, (pixelWidth * scaleFactor).rounded(.down)),
            height: max(1, (pixelHeight * scaleFactor).rounded(.down))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // targetSize is already in pixel units
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
