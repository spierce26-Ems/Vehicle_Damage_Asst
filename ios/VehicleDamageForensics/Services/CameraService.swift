// CameraService.swift
// Vehicle Damage Investigation Assistant
// AVFoundation camera wrapper with sensor-guided capture and 30-shot protocol

import AVFoundation
import CoreMotion
import CoreLocation
import UIKit
import Combine

// MARK: - Camera Service

/// Manages AVFoundation capture session, sensor guidance, and the 30-shot forensic protocol
@MainActor
final class CameraService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var captureState: CaptureState = .idle
    @Published var sensorReading: SensorReading = SensorReading()
    @Published var capturedPhotos: [CapturedPhoto] = []
    @Published var currentProtocolStep: CaptureProtocolStep?
    @Published var errorMessage: String?
    @Published var flashMode: AVCaptureDevice.FlashMode = .auto

    // MARK: - Private Properties

    private let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var captureCompletions: [String: (CapturedPhoto?) -> Void] = [:]
    private var sessionQueue = DispatchQueue(label: "com.forensics.camera.session", qos: .userInitiated)

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

    private func configureSession() throws {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Input
        guard let device = bestCaptureDevice() else {
            throw CameraError.deviceUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.inputNotSupported }
        session.addInput(input)
        videoInput = input

        // Output
        guard session.canAddOutput(photoOutput) else { throw CameraError.outputNotSupported }
        session.addOutput(photoOutput)
        photoOutput.isHighResolutionCaptureEnabled = true
        if photoOutput.isDepthDataDeliverySupported {
            photoOutput.isDepthDataDeliveryEnabled = true
        }

        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        DispatchQueue.main.async { [weak self] in
            self?.previewLayer = layer
        }
    }

    private func bestCaptureDevice() -> AVCaptureDevice? {
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
    }

    // MARK: - Motion Sensing

    private func setupMotionManager() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.sensorReading = SensorReading(
                pitch: motion.attitude.pitch,
                roll: motion.attitude.roll,
                yaw: motion.attitude.yaw,
                heading: self.currentLocation?.course
            )
        }
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
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

        capturedPhotos.append(photo)
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

    private func generateThumbnail(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = CGSize(width: 200, height: 200)
        return UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.6) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
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

    private func estimateBrightness(from data: Data) -> Double {
        guard let image = UIImage(data: data),
              let cgImage = image.cgImage else { return 0.5 }
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
