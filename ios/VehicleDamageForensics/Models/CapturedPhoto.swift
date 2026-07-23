// CapturedPhoto.swift
// Vehicle Damage Investigation Assistant
// Photo model with full forensic metadata, GPS, sensor data

import Foundation
import CoreLocation
import CoreMotion
import AVFoundation

// MARK: - Captured Photo

/// A single forensic photo with rich metadata for evidentiary integrity
struct CapturedPhoto: Identifiable, Codable, Equatable {
    let id: UUID
    var imageData: Data
    var thumbnailData: Data?
    var captureDate: Date
    var photoType: PhotoType
    var qualityScore: Double          // 0.0 – 1.0
    var qualityFlags: QualityFlags
    var sensorData: SensorData
    var gpsCoordinate: GPSCoordinate?
    var cameraSettings: CameraSettings
    var sequenceIndex: Int            // shot 1-of-30 in the protocol
    var annotationNotes: String

    /// NOTE(AI Developer), added 2026-07 per Sean's request ("we also
    /// should have the ability to upload images from camera roll"). Photos
    /// imported from the photo library have no live sensor/GPS reading at
    /// the moment of *this app's* capture -- `sensorData`/`gpsCoordinate`
    /// on an imported photo are simply absent/default rather than a real
    /// on-scene measurement. For a forensic/chain-of-custody tool, quietly
    /// blending "phone was physically at the scene, level, GPS-tagged"
    /// photos with "pulled from an existing library, no live sensor data"
    /// photos would be misleading. This flag keeps that distinction on the
    /// record (persisted in the photo itself and in the audit log via
    /// `AuditAction.photoImported`) so it can be surfaced anywhere a photo
    /// is displayed or reported on -- there's no dedicated photo-gallery/
    /// thumbnail-grid view in the app yet to render a badge in, but the
    /// data needed to add one later is captured here now rather than lost
    /// at capture time.
    var wasImported: Bool

    /// NOTE(AI Developer), added 2026-07 as part of the paint-color
    /// reference-normalization fix (Sean: "on the color matching, wont
    /// we run into issues matching OEM if we have poor lighting
    /// conditions or bad images taken?"). Normalized (0-1, 0-1) tap
    /// points recorded by `PaintReferenceMarkerView` against THIS
    /// specific photo -- `paintDamagePoint` marks the damaged/transfer-
    /// paint area, `paintReferencePoint` marks a clean/undamaged panel,
    /// both tapped on the same photo so they share the same lighting,
    /// camera, and white balance. `nil` until the reference-sample step
    /// has been completed for this photo (only meaningful for
    /// `.paintTransfer` shots). Kept on the photo itself (rather than
    /// only on the derived `DamageZone.paintAnalysis`) so re-opening
    /// this shot's reference-sample sheet later shows the previously
    /// tapped points instead of appearing untouched. See
    /// `ColorAnalysis.sampleColor(from:at:)` for the extraction step and
    /// `CaptureViewModel.recordPaintReferenceTaps` for how these points
    /// turn into an actual `PaintAnalysis`.
    var paintDamagePoint: CGPoint?
    var paintReferencePoint: CGPoint?

    /// NOTE(AI Developer), added 2026-07 as part of the "Scar-Direction
    /// Consistency" feature (Sean: "infer direction of travel from the
    /// physical scar's own paint-density taper" -- his fix for the
    /// parallel-parking blind spot in the existing Impact Geometry check,
    /// where a self-reported direction-of-travel heading can't
    /// distinguish "reversing in" from "pulling forward out" when both
    /// produce identical damage locations). These two points mark the
    /// visible scar/scrape as a LINE (not a single point) on this same
    /// `.paintTransfer` photo -- `scarLineStart`/`scarLineEnd`, normalized
    /// 0-1/0-1 same convention as `paintDamagePoint`. `nil` until the scar
    /// line has been marked. Optional/skippable: not every damage zone has
    /// a linear scrape (a blunt dent has no taper to read), so leaving
    /// this unset is expected and handled -- see
    /// `DamageZone.scarTravelBearingDegrees`'s "not determinable" case.
    var scarLineStart: CGPoint?
    var scarLineEnd: CGPoint?

    /// NOTE(AI Developer), added 2026-07 for the fingerprint-style Scar
    /// Matching feature (Sean: "do we currently analyse the scar similar
    /// to a fingerprint? if not we should. we should identify and
    /// isolate clear markings and use those to match"). The discrete,
    /// isolated features (density/width peaks) `ScarFingerprintExtractor
    /// .extractMinutiae` found along this photo's marked scar line --
    /// the fingerprint-style "minutiae" this feature is named after.
    /// Computed once, alongside `scarSlideDirection`, whenever the scar
    /// line is (re-)marked -- see `CaptureViewModel.recordScarDirection`
    /// -- and persisted here so re-analysis never has to re-run Vision/
    /// pixel sampling. Empty (not nil) is a valid, common result: a scar
    /// with no standout isolated markings beyond its overall taper still
    /// has `scarLineStart`/`scarLineEnd`, it simply contributes nothing
    /// to `ScarFingerprintMatch` — never treated as a negative result,
    /// same non-punitive principle as `scarSlideDirection == nil`.
    var scarMinutiae: [ScarMinutia] = []

    /// NOTE(AI Developer), added 2026-07 per Sean's explicit request:
    /// "we should be able to analyse both images and run them through an
    /// algorithm that looks closely and the lines and measure the
    /// distance between to see if the same fingerprint... We are
    /// basically looking for tooling marks on each vehicle from the
    /// other." The fine parallel striation/scratch-spacing rhythm
    /// `ToolMarkExtractor.extractStriationProfile` found ACROSS this
    /// photo's marked scar's width (a different signal from
    /// `scarMinutiae`, which only looks along the scar's LENGTH -- see
    /// `ToolMarkAnalysis.swift`'s header for the full rationale).
    /// Computed and persisted alongside `scarMinutiae`, same "extract
    /// once at mark time, never re-run Vision/pixel sampling later"
    /// discipline. `nil` until the scar line is (re-)marked; distinct
    /// from an empty/non-determinable `StriationProfile` (which means
    /// extraction ran but found too little texture detail -- see
    /// `StriationProfile.isDeterminable`).
    var toolMarkStriationProfile: StriationProfile?

    /// NOTE(AI Developer), added 2026-07 per Sean's on-device report that
    /// scar analysis "somehow use part of the image of the tape measure
    /// as part of the vehicle damage" -- a hard boundary the user draws
    /// (drag to move, drag the corner to resize) around JUST the visible
    /// scar/scrape on this photo, normalized (0-1, 0-1) top-left-origin
    /// same convention as `scarLineStart`/`scarLineEnd`. Once set,
    /// `ToolMarkExtractor`/`ScarFingerprintExtractor`/`ScarLineSuggester`
    /// all treat anything OUTSIDE this rect as if it weren't part of the
    /// photo at all -- a tape measure, background trim, or another body
    /// panel sitting just outside the marked line's own bounding box can
    /// no longer be sampled as if it were scar texture. See
    /// `ScarCaptureView.focusRegionStage` for the drawing UI.
    ///
    /// `nil` for any scar photo captured before this feature existed, or
    /// (in principle) if a caller somehow skips the focus-region step --
    /// every extractor treats `nil` as "no region drawn," falling back to
    /// its own generous default margin around the marked line, i.e. the
    /// exact unrestricted behavior this app had before this field
    /// existed. Non-punitive by the same convention as every other
    /// optional scar field: a missing region is a fallback, never an
    /// error.
    var scarFocusRegion: CGRect?

    /// Which of the two line endpoints above is nearer this vehicle's own
    /// front. NOTE(AI Developer): a close-up photo of a scrape has no
    /// inherent "which way is toward the front" reference on its own
    /// (unlike the top-down schematic `ImpactSilhouetteView` used for
    /// Impact Geometry, whose (0.5,0)/(0.5,1) convention IS front/rear by
    /// construction) -- the user provides this one anchor bit so the
    /// line's real 2D orientation in the photo can be converted into a
    /// body-relative fore/aft fact without needing any compass/heading
    /// input at all. This is exactly the design choice that keeps
    /// Scar-Direction Consistency independent of `directionOfTravelDegrees`
    /// (the field whose forward/reverse ambiguity created the
    /// parallel-parking blind spot in the first place) -- see
    /// `MatchScoreCalculator.scoreScarDirectionConsistency`'s doc comment
    /// for the full rationale. `nil` until set (only meaningful once both
    /// line endpoints are also set).
    var scarFrontEndpoint: ScarEndpoint?

    // MARK: Init

    init(
        id: UUID = UUID(),
        imageData: Data,
        thumbnailData: Data? = nil,
        captureDate: Date = Date(),
        photoType: PhotoType,
        qualityScore: Double = 0.0,
        qualityFlags: QualityFlags = QualityFlags(),
        sensorData: SensorData = SensorData(),
        gpsCoordinate: GPSCoordinate? = nil,
        cameraSettings: CameraSettings = CameraSettings(),
        sequenceIndex: Int = 0,
        annotationNotes: String = "",
        wasImported: Bool = false,
        paintDamagePoint: CGPoint? = nil,
        paintReferencePoint: CGPoint? = nil,
        scarLineStart: CGPoint? = nil,
        scarLineEnd: CGPoint? = nil,
        scarMinutiae: [ScarMinutia] = [],
        toolMarkStriationProfile: StriationProfile? = nil,
        scarFocusRegion: CGRect? = nil,
        scarFrontEndpoint: ScarEndpoint? = nil
    ) {
        self.id = id
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.captureDate = captureDate
        self.photoType = photoType
        self.qualityScore = qualityScore
        self.qualityFlags = qualityFlags
        self.sensorData = sensorData
        self.gpsCoordinate = gpsCoordinate
        self.cameraSettings = cameraSettings
        self.sequenceIndex = sequenceIndex
        self.annotationNotes = annotationNotes
        self.wasImported = wasImported
        self.paintDamagePoint = paintDamagePoint
        self.paintReferencePoint = paintReferencePoint
        self.scarLineStart = scarLineStart
        self.scarLineEnd = scarLineEnd
        self.scarMinutiae = scarMinutiae
        self.toolMarkStriationProfile = toolMarkStriationProfile
        self.scarFocusRegion = scarFocusRegion
        self.scarFrontEndpoint = scarFrontEndpoint
    }

    // MARK: Codable (custom, for backward-compatible decoding)

    /// NOTE(AI Developer): Custom `init(from:)` so photo JSON persisted
    /// before `wasImported` existed (every case saved before this change)
    /// decodes safely instead of throwing `keyNotFound` -- same
    /// backward-compat pattern already used in `ForensicCase.init(from:)`
    /// and `IncidentLocation.init(from:)`. Compiler still auto-synthesizes
    /// `encode(to:)`/`CodingKeys` since we don't implement those.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        imageData = try c.decode(Data.self, forKey: .imageData)
        thumbnailData = try c.decodeIfPresent(Data.self, forKey: .thumbnailData)
        captureDate = try c.decode(Date.self, forKey: .captureDate)
        photoType = try c.decode(PhotoType.self, forKey: .photoType)
        qualityScore = try c.decode(Double.self, forKey: .qualityScore)
        qualityFlags = try c.decode(QualityFlags.self, forKey: .qualityFlags)
        sensorData = try c.decode(SensorData.self, forKey: .sensorData)
        gpsCoordinate = try c.decodeIfPresent(GPSCoordinate.self, forKey: .gpsCoordinate)
        cameraSettings = try c.decode(CameraSettings.self, forKey: .cameraSettings)
        sequenceIndex = try c.decode(Int.self, forKey: .sequenceIndex)
        annotationNotes = try c.decode(String.self, forKey: .annotationNotes)
        wasImported = try c.decodeIfPresent(Bool.self, forKey: .wasImported) ?? false
        // `paintDamagePoint`/`paintReferencePoint` didn't exist before
        // this change -- every photo saved before this update decodes
        // both as `nil` (no reference sample taken yet), same
        // backward-compat pattern as `wasImported` above.
        paintDamagePoint = try c.decodeIfPresent(CGPoint.self, forKey: .paintDamagePoint)
        paintReferencePoint = try c.decodeIfPresent(CGPoint.self, forKey: .paintReferencePoint)
        // `scarLineStart`/`scarLineEnd`/`scarFrontEndpoint` didn't exist
        // before the Scar-Direction Consistency feature -- every photo
        // saved before this update decodes all three as `nil` (no scar
        // line marked yet), same backward-compat pattern as
        // `paintDamagePoint`/`paintReferencePoint` above.
        scarLineStart = try c.decodeIfPresent(CGPoint.self, forKey: .scarLineStart)
        scarLineEnd = try c.decodeIfPresent(CGPoint.self, forKey: .scarLineEnd)
        // `scarMinutiae` didn't exist before the fingerprint-style Scar
        // Matching feature -- every photo saved before this update
        // decodes an empty array (no isolated markings extracted yet),
        // same non-punitive backward-compat pattern as every other
        // scar-related field above.
        scarMinutiae = try c.decodeIfPresent([ScarMinutia].self, forKey: .scarMinutiae) ?? []
        // `toolMarkStriationProfile` didn't exist before the tool-mark/
        // striation matching feature -- every photo saved before this
        // update decodes `nil` (no striation extraction attempted yet),
        // same non-punitive backward-compat pattern as `scarMinutiae`
        // above.
        toolMarkStriationProfile = try c.decodeIfPresent(StriationProfile.self, forKey: .toolMarkStriationProfile)
        // `scarFocusRegion` didn't exist before the tape-measure-
        // contamination fix -- every photo saved before this update
        // decodes `nil` (no drawn boundary; extractors fall back to
        // their unrestricted default margin, i.e. this update's
        // behavior is purely additive for old data), same non-punitive
        // backward-compat pattern as every other optional scar field
        // above.
        scarFocusRegion = try c.decodeIfPresent(CGRect.self, forKey: .scarFocusRegion)
        scarFrontEndpoint = try c.decodeIfPresent(ScarEndpoint.self, forKey: .scarFrontEndpoint)
    }

    // MARK: Computed

    var qualityLabel: QualityLabel {
        switch qualityScore {
        case 0.8...: return .excellent
        case 0.6..<0.8: return .good
        case 0.4..<0.6: return .acceptable
        default: return .poor
        }
    }

    // NOTE(AI Developer), fixed 2026-07 alongside adding camera-roll
    // import (Sean's request): imported photos get `qualityScore = 0.0`
    // (there's no live sensor/on-device scoring possible for a photo not
    // just captured by this app -- see `wasImported`). Without this
    // exemption, every imported photo would silently fail `isUsable`
    // (threshold 0.4) and be dropped from the PDF evidence report by
    // `PDFReportGenerator.drawPhotoEvidence`, even though it's perfectly
    // good, user-selected evidence.
    var isUsable: Bool { wasImported || qualityScore >= 0.4 }

    /// True once a scar line (both endpoints + which end is toward the
    /// front) has been marked on this photo. See `scarLineStart`/
    /// `scarLineEnd`/`scarFrontEndpoint`'s doc comment for the feature
    /// this powers.
    var hasScarLine: Bool {
        scarLineStart != nil && scarLineEnd != nil && scarFrontEndpoint != nil
    }

    /// NOTE(AI Developer), added 2026-07 for the "Scar Line Comparison"
    /// feature (Sean's Answer B2: "use already-recorded scar data... to
    /// show victim vs. suspect scar line length/angle/position side-by-
    /// side"). Euclidean distance between `scarLineStart`/`scarLineEnd`
    /// in this photo's own normalized (0-1, 0-1) frame -- e.g. `0.4` means
    /// the marked line spans 40% of the photo's diagonal.
    ///
    /// DELIBERATELY NOT a real-world/physical length: two scar photos are
    /// shot from whatever distance each vehicle's damage happened to
    /// require, with no shared scale reference (no ruler, no LiDAR tie-in
    /// for this specific shot) -- so a raw normalized-distance comparison
    /// between two DIFFERENT photos does not mean "the scars are the same
    /// physical length." This value is only ever surfaced labeled as
    /// "relative to each photo's own frame" (see `MatchResultsView`'s
    /// Scar Line Comparison section / `PDFReportGenerator
    /// .drawScarLineComparison`) -- it is supporting visual context, not
    /// a scored match factor. `nil` unless both endpoints are set.
    var scarLineLengthNormalized: Double? {
        guard let a = scarLineStart, let b = scarLineEnd else { return nil }
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// NOTE(AI Developer), added 2026-07 alongside
    /// `scarLineLengthNormalized` for the same B2 feature. The scar
    /// line's orientation IN THIS PHOTO's own 2D frame, 0-360°, measured
    /// clockwise from "pointing right" in the image (standard screen
    /// convention: 0° = +x/right, 90° = +y/down, matching this struct's
    /// existing top-left-origin normalized point convention). Always
    /// reported as the angle from `scarFrontEndpoint`'s end TOWARD the
    /// other end, so "0°" consistently means "front-to-rear points right
    /// in the photo" regardless of which raw endpoint happens to be
    /// `.start` vs. `.end` -- this makes the value meaningfully
    /// comparable across two vehicles' independently-marked lines despite
    /// each photo being framed differently by whoever held the phone.
    ///
    /// Like `scarLineLengthNormalized`, this is an IN-PHOTO orientation,
    /// not a real-world compass bearing -- `Vehicle.scarTravelBearingDegrees`
    /// (which combines this vehicle's own recorded direction-of-travel and
    /// impact geometry) is the actual physically-grounded bearing used for
    /// scoring; this angle is supporting visual context only. `nil`
    /// unless both endpoints and `scarFrontEndpoint` are set.
    var scarLineAngleInPhotoDegrees: Double? {
        guard let start = scarLineStart, let end = scarLineEnd, let scarFrontEndpoint else { return nil }
        let front = scarFrontEndpoint == .start ? start : end
        let rear = scarFrontEndpoint == .start ? end : start
        let dx = Double(rear.x - front.x)
        let dy = Double(rear.y - front.y)
        var degrees = atan2(dy, dx) * 180.0 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    static func == (lhs: CapturedPhoto, rhs: CapturedPhoto) -> Bool { lhs.id == rhs.id }
}

// MARK: - Scar Endpoint

/// NOTE(AI Developer), added 2026-07 as part of the Scar-Direction
/// Consistency feature. Identifies which end of a marked scar line
/// (`CapturedPhoto.scarLineStart`/`scarLineEnd`) the user indicated is
/// nearer this vehicle's own front -- see that pair's doc comment for why
/// this single anchor bit is what lets a 2D line drawn on a close-up photo
/// (which has no built-in "which way is front" reference the way the
/// top-down `ImpactSilhouetteView` schematic does) be converted into a
/// body-relative fore/aft direction.
enum ScarEndpoint: String, Codable {
    case start
    case end
}

// MARK: - Quality Label

enum QualityLabel: String {
    case excellent = "Excellent"
    case good = "Good"
    case acceptable = "Acceptable"
    case poor = "Poor"

    var colorName: String {
        switch self {
        case .excellent: return "systemGreen"
        case .good: return "systemBlue"
        case .acceptable: return "systemOrange"
        case .poor: return "systemRed"
        }
    }
}

// MARK: - Quality Flags

/// Specific quality issues detected at capture time
struct QualityFlags: Codable, Equatable {
    var isBlurry: Bool = false
    var isUnderexposed: Bool = false
    var isOverexposed: Bool = false
    var isTooFar: Bool = false
    var isTooClose: Bool = false
    var hasMotionBlur: Bool = false
    var isOffAngle: Bool = false

    var issueDescriptions: [String] {
        var issues: [String] = []
        if isBlurry { issues.append("Out of focus") }
        if isUnderexposed { issues.append("Too dark") }
        if isOverexposed { issues.append("Too bright") }
        if isTooFar { issues.append("Too far away") }
        if isTooClose { issues.append("Too close") }
        if hasMotionBlur { issues.append("Motion blur detected") }
        if isOffAngle { issues.append("Wrong angle") }
        return issues
    }

    var hasIssues: Bool { issueDescriptions.isEmpty == false }
}

// MARK: - Sensor Data

/// Device sensor readings captured at photo time for forensic correlation
struct SensorData: Codable, Equatable {
    var pitch: Double       // device tilt in radians
    var roll: Double
    var yaw: Double
    var altitudeMeters: Double?
    var heading: Double?    // compass degrees 0-360
    var distanceEstimateMeters: Double?   // estimated from AF depth hint
    var accelerometer: SIMD3<Double>?     // g-force at capture

    init(
        pitch: Double = 0,
        roll: Double = 0,
        yaw: Double = 0,
        altitudeMeters: Double? = nil,
        heading: Double? = nil,
        distanceEstimateMeters: Double? = nil,
        accelerometer: SIMD3<Double>? = nil
    ) {
        self.pitch = pitch
        self.roll = roll
        self.yaw = yaw
        self.altitudeMeters = altitudeMeters
        self.heading = heading
        self.distanceEstimateMeters = distanceEstimateMeters
        self.accelerometer = accelerometer
    }

    /// Pitch in degrees for display
    var pitchDegrees: Double { pitch * (180.0 / .pi) }
    var rollDegrees: Double { roll * (180.0 / .pi) }

    /// True if device is approximately horizontal (±15°)
    var isLevel: Bool { abs(rollDegrees) <= 15.0 }
}

// MARK: - GPS Coordinate

struct GPSCoordinate: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var horizontalAccuracyMeters: Double
    var timestamp: Date

    var clLocation: CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude ?? 0,
            horizontalAccuracy: horizontalAccuracyMeters,
            verticalAccuracy: -1,
            timestamp: timestamp
        )
    }

    var isAccurate: Bool { horizontalAccuracyMeters <= 10.0 }

    init(location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude > 0 ? location.altitude : nil
        self.horizontalAccuracyMeters = location.horizontalAccuracy
        self.timestamp = location.timestamp
    }
}

// MARK: - Camera Settings

/// EXIF-style metadata for evidentiary record
struct CameraSettings: Codable, Equatable {
    var focalLengthMM: Double?
    var aperture: Double?        // f-number
    var shutterSpeed: Double?    // seconds
    var iso: Int?
    var whiteBalance: String?
    var lensModel: String?
    var deviceModel: String
    var osVersion: String

    init(
        focalLengthMM: Double? = nil,
        aperture: Double? = nil,
        shutterSpeed: Double? = nil,
        iso: Int? = nil,
        whiteBalance: String? = nil,
        lensModel: String? = nil
    ) {
        self.focalLengthMM = focalLengthMM
        self.aperture = aperture
        self.shutterSpeed = shutterSpeed
        self.iso = iso
        self.whiteBalance = whiteBalance
        self.lensModel = lensModel
        self.deviceModel = UIDevice.current.model
        self.osVersion = UIDevice.current.systemVersion
    }
}

import UIKit
