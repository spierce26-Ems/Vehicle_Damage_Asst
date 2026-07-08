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
    @Published private(set) var capturedPhotos: [CapturedPhoto] = []
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

    var currentShotIndex: Int { capturedPhotos.count }

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

    // MARK: Dependencies

    private let storage: StorageService
    private let cameraService: CameraService
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()

    /// NOTE(AI Developer): `storage`/`cameraService` default to `nil` here
    /// (rather than `= .shared` / `= CameraService()` directly in the
    /// parameter list) because default-argument expressions are evaluated
    /// in a non-isolated context under Swift 6 strict concurrency, and
    /// both `StorageService.shared` and `CameraService.init()` are
    /// `@MainActor`-isolated. Resolving the actual default inside the
    /// (MainActor-isolated) init body avoids the "Call to main
    /// actor-isolated ... from synchronous nonisolated context" error.
    init(forensicCase: ForensicCase,
         storage: StorageService? = nil,
         cameraService: CameraService? = nil) {
        self.forensicCase = forensicCase
        self.storage = storage ?? .shared
        self.cameraService = cameraService ?? CameraService()
        startSensors()
    }

    // MARK: Public API

    /// Record a new photo into the case under the active vehicle role.
    func record(image: UIImage) async {
        guard let type = nextShotType else { return }
        // NOTE(AI Developer), 2026-07: `resizedForStorage` is a no-op here
        // in practice (CameraService already caps capture resolution
        // upstream), but calling it unconditionally means this path can't
        // silently regress into the oversized-payload hang class again if
        // that upstream cap is ever changed/removed. See `importPhoto(_:)`
        // for the case where this guard is load-bearing.
        let stored = resizedForStorage(image)
        let data = stored.jpegData(compressionQuality: 0.85) ?? Data()
        let thumb = stored.preparingThumbnail(of: CGSize(width: 240, height: 240))?
            .jpegData(compressionQuality: 0.6)

        let photo = CapturedPhoto(
            imageData: data,
            thumbnailData: thumb,
            captureDate: Date(),
            photoType: type,
            qualityScore: estimateQuality(for: image),
            qualityFlags: lastQualityFlags,
            sensorData: currentSensorData,
            gpsCoordinate: currentLocation(),
            cameraSettings: CameraSettings(),
            sequenceIndex: currentShotIndex + 1
        )
        capturedPhotos.append(photo)
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
        forensicCase.recordAudit(.photoCaptured, detail: "\(captureRole.displayName): \(type.displayName) (#\(photo.sequenceIndex))")
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
    /// `record(image:)`'s structure (same audit-then-save ordering, same
    /// role-based routing) so the two capture paths can't silently drift
    /// apart, but marks the result `wasImported: true` and skips
    /// sensor/GPS/quality scoring -- there's no live sensor reading for a
    /// photo that wasn't just taken by this device, and fabricating one
    /// would misrepresent the evidence record. See `CapturedPhoto.wasImported`.
    func importPhoto(_ image: UIImage) async {
        guard let type = nextShotType else { return }
        // NOTE(AI Developer), fixed 2026-07 per Sean's on-device report
        // ("its been 'running correlation analysis' for a few minutes
        // again"): unlike `record(image:)`, whose source `UIImage` comes
        // from `CameraService.capturePhoto()` (already capped via
        // `photoOutput.maxPhotoDimensions`), this path's `image` comes
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
        capturedPhotos.append(photo)
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

    /// Switch to capturing the suspect vehicle after victim is complete.
    func switchToSuspect() {
        captureRole = .suspect
        capturedPhotos.removeAll()
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

    private func currentLocation() -> GPSCoordinate? {
        guard let loc = locationManager.location else { return nil }
        return GPSCoordinate(location: loc)
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

    private func estimateQuality(for image: UIImage) -> Double {
        // Placeholder: real implementation would run a Core ML quality model
        // and combine with QualityFlags. For MVP we trust the sensor checks.
        var score = 0.85
        if abs(currentSensorData.rollDegrees) > 10 { score -= 0.2 }
        if abs(currentSensorData.pitchDegrees) > 20 { score -= 0.1 }
        return max(0, min(1, score))
    }

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
