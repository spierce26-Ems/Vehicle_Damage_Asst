// CaptureViewModel.swift
// Vehicle Damage Forensic Matcher
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

    init(forensicCase: ForensicCase,
         storage: StorageService = .shared,
         cameraService: CameraService = CameraService()) {
        self.forensicCase = forensicCase
        self.storage = storage
        self.cameraService = cameraService
        startSensors()
    }

    // MARK: Public API

    /// Record a new photo into the case under the active vehicle role.
    func record(image: UIImage) async {
        guard let type = nextShotType else { return }
        let data = image.jpegData(compressionQuality: 0.85) ?? Data()
        let thumb = image.preparingThumbnail(of: CGSize(width: 240, height: 240))?
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

    /// Switch to capturing the suspect vehicle after victim is complete.
    func switchToSuspect() {
        captureRole = .suspect
        capturedPhotos.removeAll()
        statusMessage = "Capturing suspect vehicle. Maintain consistent angle and distance."
    }

    // MARK: Sensor monitoring

    private func startSensors() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.1
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, let m = motion else { return }
                self.currentSensorData = SensorData(
                    pitch: m.attitude.pitch,
                    roll: m.attitude.roll,
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

    private func updateGuidance() {
        guard let next = nextShotType else {
            statusMessage = "Capture complete. Tap Analyze to proceed."
            return
        }
        if abs(currentSensorData.rollDegrees) > 15 {
            statusMessage = "Phone not level — tilt to correct roll \(Int(currentSensorData.rollDegrees))°"
        } else if abs(currentSensorData.pitchDegrees) > 25 {
            statusMessage = "Pitch too steep — point phone more horizontally"
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
}
