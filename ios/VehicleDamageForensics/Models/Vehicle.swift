// Vehicle.swift
// Vehicle Damage Investigation Assistant
// Vehicle model with role, specs, damage zones, and captured photos

import Foundation
import UIKit

// MARK: - Vehicle

/// Represents either the victim or suspect vehicle in a forensic case
struct Vehicle: Identifiable, Codable, Equatable {
    let id: UUID
    var role: VehicleRole
    var make: String
    var model: String
    var year: Int?
    var color: String
    var colorRGB: ColorRGB?
    var licensePlate: String?
    var vin: String?
    var photos: [CapturedPhoto]
    var damageZones: [DamageZone]
    var bumperHeightInches: Double?
    var lidarScanData: LiDARScanData?

    /// NOTE(AI Developer), added 2026-07 per Sean's request ("can we have
    /// a better image to tap to show where the damage is on the vehicle?
    /// if its a truck we should be able to better identify the location
    /// of the impact instead of a generic square we tap"). A simple
    /// Car/Truck toggle -- deliberately not a fuller body-style enum
    /// (Sean's explicit choice: "something easy like Car vs Truck as a
    /// simple toggle") -- that drives which top-down outline
    /// `ImpactSilhouetteView` draws (see `Views/Capture/ImpactMarkerView.swift`).
    /// Defaults to `.car` so every case created before this field existed
    /// (and hasn't been re-edited yet) keeps showing the same silhouette
    /// it always has.
    var bodyType: VehicleBodyType = .car

    /// NOTE(AI Developer), added 2026-07 per Sean's request ("we need the
    /// use of Lidar as an extra tool"). A physical damage height, in
    /// inches, measured directly from the LiDAR-reconstructed mesh during
    /// `LiDARScanView`'s tap-to-measure step: the user taps the ground
    /// beside the vehicle, then taps the damage point on the vehicle
    /// body, and the vertical (gravity-aligned Y-axis) distance between
    /// those two AR-world-space raycast hits is this value. Unlike
    /// `bumperHeightInches` (a manual-entry field that nothing in the app
    /// has ever populated), this is captured directly from real 3D scan
    /// data, so `MatchScoreCalculator` prefers it over `bumperHeightInches`
    /// wherever both are present -- see the call site in
    /// `MatchScoreCalculator.evaluate()`. `nil` until a measurement is
    /// taken and saved.
    var lidarMeasuredHeightInches: Double?

    /// NOTE(AI Developer), added 2026-07 per Sean's request ("should we
    /// identify the location of the damage on each vehicle and always
    /// identify the direction of traveling at impact... to help
    /// correlating data"). Normalized (0-1, 0-1) tap point within the
    /// top-down car silhouette shown by `ImpactMarkerView` -- (0.5, 0) is
    /// front-center, (0.5, 1) is rear-center, (0, 0.5) is the left side,
    /// (1, 0.5) is the right side. `nil` until the user has tapped a
    /// location for this vehicle. Deliberately a free tap point rather
    /// than a fixed 8-zone picker per Sean's explicit choice ("tap impact
    /// location") -- gives a continuous, more precise damage-location
    /// signal than a coarse zone selector while still being a single fast
    /// tap to record.
    var impactTapPoint: CGPoint?

    /// Compass heading (0-360°, true or magnetic -- see `HeadingProvider`)
    /// the vehicle was traveling at the moment of impact. Captured either
    /// live from the device compass (when the investigator is physically
    /// at the scene) or set manually via `DirectionDialView` (for photos
    /// uploaded after the fact, when the investigator is no longer near
    /// either vehicle -- the scenario Sean specifically flagged as the
    /// common case for this data). `nil` until recorded.
    var directionOfTravelDegrees: Double?

    /// NOTE(AI Developer), added 2026-07 alongside the "skip a shot"
    /// feature (Sean: "we should be able to skip a certain image view if
    /// we dont have an image in the camera roll or are no longer near the
    /// vehicle"). Stores the *indices into `PhotoType.requiredCaptureProtocol`*
    /// that were explicitly skipped for this vehicle, rather than faking a
    /// placeholder `CapturedPhoto` with empty `imageData` -- a real photo
    /// model with no real bytes would risk being silently rendered as a
    /// blank tile anywhere a photo array is iterated (PDF evidence grid,
    /// `DeformationMatcher`'s `bestDamageImage` lookup, thumbnail grids
    /// added later). Kept as a separate index list instead: `photos.count
    /// + skippedShotIndices.count` is the number of protocol slots
    /// "filled" (captured or explicitly skipped) for this vehicle -- see
    /// `CaptureViewModel.currentShotIndex` and `ForensicCase.isReadyForAnalysis`.
    /// Per Sean's decision, EVERY shot in the protocol is skippable (no
    /// mandatory/unskippable carve-outs).
    var skippedShotIndices: [Int]

    // MARK: Init

    init(
        id: UUID = UUID(),
        role: VehicleRole,
        make: String = "",
        model: String = "",
        year: Int? = nil,
        color: String = "",
        colorRGB: ColorRGB? = nil,
        licensePlate: String? = nil,
        vin: String? = nil,
        photos: [CapturedPhoto] = [],
        damageZones: [DamageZone] = [],
        bumperHeightInches: Double? = nil,
        lidarScanData: LiDARScanData? = nil,
        bodyType: VehicleBodyType = .car,
        lidarMeasuredHeightInches: Double? = nil,
        impactTapPoint: CGPoint? = nil,
        directionOfTravelDegrees: Double? = nil,
        skippedShotIndices: [Int] = []
    ) {
        self.id = id
        self.role = role
        self.make = make
        self.model = model
        self.year = year
        self.color = color
        self.colorRGB = colorRGB
        self.licensePlate = licensePlate
        self.vin = vin
        self.photos = photos
        self.damageZones = damageZones
        self.bumperHeightInches = bumperHeightInches
        self.lidarScanData = lidarScanData
        self.bodyType = bodyType
        self.lidarMeasuredHeightInches = lidarMeasuredHeightInches
        self.impactTapPoint = impactTapPoint
        self.directionOfTravelDegrees = directionOfTravelDegrees
        self.skippedShotIndices = skippedShotIndices
    }

    // MARK: Codable (custom, for backward-compatible decoding)

    /// NOTE(AI Developer): Custom `init(from:)` added 2026-07 so case JSON
    /// persisted before `impactTapPoint`/`directionOfTravelDegrees`/
    /// `skippedShotIndices` existed (every case saved before this change)
    /// decodes safely instead of throwing `keyNotFound` on the
    /// non-optional `skippedShotIndices` array -- same backward-compat
    /// pattern already used in `CapturedPhoto.init(from:)` and
    /// `ForensicCase.init(from:)`. The two new Optional fields would
    /// actually decode safely even without this (synthesized Decodable
    /// uses `decodeIfPresent` for Optional properties), but
    /// `skippedShotIndices` needs an explicit fallback since it's a
    /// non-optional array with a default. Compiler still auto-synthesizes
    /// `encode(to:)`/`CodingKeys` since we don't implement those.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(VehicleRole.self, forKey: .role)
        make = try c.decode(String.self, forKey: .make)
        model = try c.decode(String.self, forKey: .model)
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        color = try c.decode(String.self, forKey: .color)
        colorRGB = try c.decodeIfPresent(ColorRGB.self, forKey: .colorRGB)
        licensePlate = try c.decodeIfPresent(String.self, forKey: .licensePlate)
        vin = try c.decodeIfPresent(String.self, forKey: .vin)
        photos = try c.decode([CapturedPhoto].self, forKey: .photos)
        damageZones = try c.decode([DamageZone].self, forKey: .damageZones)
        bumperHeightInches = try c.decodeIfPresent(Double.self, forKey: .bumperHeightInches)
        lidarScanData = try c.decodeIfPresent(LiDARScanData.self, forKey: .lidarScanData)
        // `bodyType` didn't exist before this change -- every case saved
        // before this update decodes it as `.car` (the same silhouette
        // those cases have always shown), same backward-compat pattern as
        // `skippedShotIndices` below.
        bodyType = try c.decodeIfPresent(VehicleBodyType.self, forKey: .bodyType) ?? .car
        lidarMeasuredHeightInches = try c.decodeIfPresent(Double.self, forKey: .lidarMeasuredHeightInches)
        impactTapPoint = try c.decodeIfPresent(CGPoint.self, forKey: .impactTapPoint)
        directionOfTravelDegrees = try c.decodeIfPresent(Double.self, forKey: .directionOfTravelDegrees)
        skippedShotIndices = try c.decodeIfPresent([Int].self, forKey: .skippedShotIndices) ?? []
    }

    // MARK: Computed

    var displayName: String {
        let parts = [year.map { String($0) }, make, model].compactMap { $0 }
        return parts.isEmpty ? "\(role.displayName) Vehicle" : parts.joined(separator: " ")
    }

    var hasLiDARData: Bool { lidarScanData != nil }

    /// True once a real physical height has been measured off the LiDAR
    /// mesh for this vehicle (see `lidarMeasuredHeightInches`). Distinct
    /// from `hasLiDARData`, which is just "a scan was saved" -- a scan
    /// can exist with no measurement taken yet if the user only did the
    /// mesh-coverage pass and skipped the tap-to-measure step.
    var hasLiDARMeasurement: Bool { lidarMeasuredHeightInches != nil }

    /// The damage height `HeightAlignmentAnalyzer` should actually use:
    /// the LiDAR-measured value when available (real 3D-scan data, more
    /// precise and harder to get wrong than a manual guess), falling back
    /// to the manually-entered `bumperHeightInches` otherwise. See
    /// `MatchScoreCalculator.evaluate()`'s call site.
    var effectiveBumperHeightInches: Double? {
        lidarMeasuredHeightInches ?? bumperHeightInches
    }

    var photosByType: [PhotoType: [CapturedPhoto]] {
        Dictionary(grouping: photos) { $0.photoType }
    }

    var primaryDamageZone: DamageZone? {
        damageZones.first
    }

    /// Angle (0-360°, clockwise) of the impact-tap point relative to the
    /// vehicle's own front-center, derived from `impactTapPoint`. 0° =
    /// front-center, 90° = right side, 180° = rear-center, 270° = left
    /// side -- i.e. clockwise around the vehicle as viewed from above.
    var impactRelativeAngleDegrees: Double? {
        guard let p = impactTapPoint else { return nil }
        let dx = Double(p.x) - 0.5
        let dy = Double(p.y) - 0.5
        var degrees = atan2(dx, -dy) * 180.0 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    /// NOTE(AI Developer), added 2026-07: combines *where* the vehicle was
    /// hit (`impactRelativeAngleDegrees`, relative to the vehicle's own
    /// nose) with *which way it was pointed* at the moment of impact
    /// (`directionOfTravelDegrees`, absolute compass heading) into a
    /// single absolute compass bearing for the impact itself. This is
    /// what actually feeds `MatchScoreCalculator.scoreImpactGeometry` now
    /// (see that function's doc comment for the reciprocity check this
    /// enables) -- previously that factor required `DamageZone.impactAngleDegrees`,
    /// which nothing in the app ever populated, so it was permanently
    /// "unavailable" (0 of its 15% weight ever contributed to any score).
    /// Verified algebraically that `victimBearing + suspectBearing ≈ 180°`
    /// holds for head-on, rear-end, AND T-bone geometries as long as both
    /// vehicles' bearings are computed this same way (travel heading +
    /// relative zone angle) -- e.g. head-on: A heading 0° hit on the nose
    /// (relative 0°) → bearing 0°; oncoming B heading 180° also hit on the
    /// nose → bearing 180°; sum 180°. Rear-end: A heading 0° hit on the
    /// rear (relative 180°) → bearing 180°; B (the one that rear-ended A)
    /// also heading 0°, hit on ITS nose (relative 0°) → bearing 0°; sum
    /// 180° again.
    var impactBearingDegrees: Double? {
        guard let travel = directionOfTravelDegrees,
              let relative = impactRelativeAngleDegrees else { return nil }
        var bearing = (travel + relative).truncatingRemainder(dividingBy: 360)
        if bearing < 0 { bearing += 360 }
        return bearing
    }

    /// True once both the impact location and direction of travel have
    /// been recorded for this vehicle. Per Sean's decision (2026-07) this
    /// is a REQUIRED step (unlike the skippable photo protocol) -- see
    /// `ForensicCase.isReadyForAnalysis` and `CaptureFlowView`'s
    /// "Continue"/"Run Analysis" button gating.
    var hasImpactProfile: Bool {
        impactTapPoint != nil && directionOfTravelDegrees != nil
    }

    /// Human-readable 8-point description of `impactRelativeAngleDegrees`,
    /// e.g. "Front-Right" -- used in the PDF report and results screen so
    /// the raw tap-derived angle reads as an actual damage-location
    /// description rather than a bare number.
    var impactZoneDescription: String? {
        guard let angle = impactRelativeAngleDegrees else { return nil }
        let zones = ["Front", "Front-Right", "Right", "Rear-Right",
                     "Rear", "Rear-Left", "Left", "Front-Left"]
        let index = Int((angle / 45.0).rounded()) % 8
        return zones[index]
    }

    static func == (lhs: Vehicle, rhs: Vehicle) -> Bool { lhs.id == rhs.id }
}

// MARK: - Vehicle Role

enum VehicleRole: String, Codable {
    case victim
    case suspect

    var displayName: String {
        switch self {
        case .victim: return "Victim"
        case .suspect: return "Suspect"
        }
    }

    var accentColor: String {
        switch self {
        case .victim: return "systemBlue"
        case .suspect: return "systemOrange"
        }
    }
}

// MARK: - Vehicle Body Type

/// NOTE(AI Developer), added 2026-07 per Sean's request for a simple
/// Car/Truck toggle to drive which top-down silhouette
/// `ImpactSilhouetteView` shows. See `Vehicle.bodyType`.
enum VehicleBodyType: String, Codable, CaseIterable {
    case car
    case truck

    var displayName: String {
        switch self {
        case .car: return "Car"
        case .truck: return "Truck"
        }
    }
}

// MARK: - Damage Zone

/// Describes a specific region of damage on the vehicle
struct DamageZone: Identifiable, Codable, Equatable {
    let id: UUID
    var zoneID: String          // e.g. "rear_bumper_driver_side"
    var centerHeightInches: Double
    var topEdgeHeightInches: Double
    var bottomEdgeHeightInches: Double
    var widthMM: Double
    var heightMM: Double
    var maxDepthMM: Double
    var paintAnalysis: PaintAnalysis?
    var impactAngleDegrees: Double?
    var transferDirection: TransferDirection?

    /// NOTE(AI Developer): Schema reservation only — 2026-07. Not created,
    /// mutated, or displayed anywhere yet. Reserves the slot for the future
    /// "send a physical paint sample to a partner lab" feature Sean asked
    /// about, so that when we build it we don't have to retrofit the model
    /// (and its Codable/decoding) the way we just had to for `auditLog`.
    /// See `PaintSampleKit.swift` and
    /// `ios/reference/PAINT_ANALYSIS_KIT_FUTURE_FEATURE.md`. Optional, so
    /// synthesized Codable already decodes missing/old JSON safely (no
    /// custom init(from:) needed here).
    var paintSampleKit: PaintSampleKit?

    init(
        id: UUID = UUID(),
        zoneID: String = "primary_damage",
        centerHeightInches: Double = 0,
        topEdgeHeightInches: Double = 0,
        bottomEdgeHeightInches: Double = 0,
        widthMM: Double = 0,
        heightMM: Double = 0,
        maxDepthMM: Double = 0,
        paintAnalysis: PaintAnalysis? = nil,
        impactAngleDegrees: Double? = nil,
        transferDirection: TransferDirection? = nil,
        paintSampleKit: PaintSampleKit? = nil
    ) {
        self.id = id
        self.zoneID = zoneID
        self.centerHeightInches = centerHeightInches
        self.topEdgeHeightInches = topEdgeHeightInches
        self.bottomEdgeHeightInches = bottomEdgeHeightInches
        self.widthMM = widthMM
        self.heightMM = heightMM
        self.maxDepthMM = maxDepthMM
        self.paintAnalysis = paintAnalysis
        self.impactAngleDegrees = impactAngleDegrees
        self.transferDirection = transferDirection
        self.paintSampleKit = paintSampleKit
    }

    var areaMM2: Double { widthMM * heightMM }
}

// MARK: - Paint Analysis

struct PaintAnalysis: Codable, Equatable {
    var primaryColorRGB: ColorRGB
    var foreignPaintDetected: Bool
    var foreignPaintRGB: ColorRGB?
    var layerCount: Int
    var hasRubberTransfer: Bool
    var hasPlasticFragment: Bool
    var surfaceCondition: SurfaceCondition

    /// NOTE(AI Developer), added 2026-07 as part of the paint-color
    /// reference-normalization fix. True when the two localized samples
    /// that produced this analysis (damage-area tap + clean-panel tap,
    /// see `CaptureViewModel.recordPaintReferenceTaps`) both looked
    /// internally consistent -- low specular-highlight/shadow rejection,
    /// low residual luminance variance. False means the underlying photo
    /// likely had poor/uneven lighting at one or both tap points; callers
    /// (`PaintTransferAnalyzer`) downgrade `FactorScore.dataQuality` to
    /// `.partial` rather than `.full` in that case, instead of silently
    /// trusting a bad capture the way the app used to trust (nonexistent)
    /// data unconditionally. Defaults `true` so any other code path that
    /// constructs a `PaintAnalysis` without reasoning about sample
    /// quality doesn't get spuriously downgraded.
    var sampleQualityIsGood: Bool = true

    enum SurfaceCondition: String, Codable {
        case fresh, weathered, rusted, repainted
    }

    init(
        primaryColorRGB: ColorRGB,
        foreignPaintDetected: Bool,
        foreignPaintRGB: ColorRGB? = nil,
        layerCount: Int = 0,
        hasRubberTransfer: Bool = false,
        hasPlasticFragment: Bool = false,
        surfaceCondition: SurfaceCondition = .fresh,
        sampleQualityIsGood: Bool = true
    ) {
        self.primaryColorRGB = primaryColorRGB
        self.foreignPaintDetected = foreignPaintDetected
        self.foreignPaintRGB = foreignPaintRGB
        self.layerCount = layerCount
        self.hasRubberTransfer = hasRubberTransfer
        self.hasPlasticFragment = hasPlasticFragment
        self.surfaceCondition = surfaceCondition
        self.sampleQualityIsGood = sampleQualityIsGood
    }

    // MARK: Codable (custom, for backward-compatible decoding)

    /// NOTE(AI Developer): Custom `init(from:)` added 2026-07 alongside
    /// `sampleQualityIsGood` -- same backward-compat pattern used
    /// elsewhere in this file (`Vehicle.init(from:)`). In practice no
    /// case has ever persisted a real `PaintAnalysis` (confirmed dead
    /// before this fix), but this keeps the type honest for any archived
    /// JSON regardless. Compiler still auto-synthesizes `encode(to:)`/
    /// `CodingKeys` since we don't implement those.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primaryColorRGB = try c.decode(ColorRGB.self, forKey: .primaryColorRGB)
        foreignPaintDetected = try c.decode(Bool.self, forKey: .foreignPaintDetected)
        foreignPaintRGB = try c.decodeIfPresent(ColorRGB.self, forKey: .foreignPaintRGB)
        layerCount = try c.decode(Int.self, forKey: .layerCount)
        hasRubberTransfer = try c.decode(Bool.self, forKey: .hasRubberTransfer)
        hasPlasticFragment = try c.decode(Bool.self, forKey: .hasPlasticFragment)
        surfaceCondition = try c.decode(SurfaceCondition.self, forKey: .surfaceCondition)
        sampleQualityIsGood = try c.decodeIfPresent(Bool.self, forKey: .sampleQualityIsGood) ?? true
    }
}

// MARK: - Color RGB

struct ColorRGB: Codable, Equatable {
    var r: Double  // 0-255
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init(uiColor: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.r = Double(r) * 255
        self.g = Double(g) * 255
        self.b = Double(b) * 255
    }

    var uiColor: UIColor {
        UIColor(red: CGFloat(r/255), green: CGFloat(g/255), blue: CGFloat(b/255), alpha: 1)
    }
}

// MARK: - Transfer Direction

enum TransferDirection: String, Codable {
    case inward   // paint received (victim)
    case outward  // paint deposited (suspect)
    case both
}

// MARK: - LiDAR Scan Data

struct LiDARScanData: Codable, Equatable {
    var pointCloudCount: Int
    var coveragePercent: Double
    var meshFileURL: URL?
    var scanDate: Date
    var depthMapData: Data?

    var isComplete: Bool { coveragePercent >= 80.0 }
}

// MARK: - Photo Type

enum PhotoType: String, Codable, CaseIterable {
    case heightMeasurement = "height_measurement"
    case closeupDamage = "closeup_damage"
    case wideAngle = "wide_angle"
    case contextShot = "context"
    case paintTransfer = "paint_transfer"
    case licenseDetail = "license_detail"
    case lidarReference = "lidar_reference"

    var displayName: String {
        switch self {
        case .heightMeasurement: return "Height Reference"
        case .closeupDamage: return "Damage Closeup"
        case .wideAngle: return "Wide Angle"
        case .contextShot: return "Context"
        case .paintTransfer: return "Paint Transfer"
        case .licenseDetail: return "License/VIN"
        case .lidarReference: return "LiDAR Reference"
        }
    }

    var isRequired: Bool {
        switch self {
        case .heightMeasurement, .closeupDamage, .wideAngle: return true
        default: return false
        }
    }
}

// MARK: - Canonical Capture Protocol

extension PhotoType {
    /// NOTE(AI Developer): Single source of truth for "how many / which
    /// shots are required per vehicle" for v1. Previously this number was
    /// duplicated and inconsistent in three places (Case.swift's
    /// `isReadyForAnalysis` hardcoded 4, a since-removed duplicate in
    /// ModelExtensions.swift hardcoded 5, and `CaptureViewModel.protocolShots`
    /// had its own literal 10-shot array). Per Sean's decision (2026-07,
    /// "ship the 10-shot v1 flow, don't promote to the 30-shot protocol
    /// yet"), this is now the one place that defines the v1 shot list;
    /// `CaptureViewModel.protocolShots` and `ForensicCase.isReadyForAnalysis`
    /// both derive from this so they can't drift out of sync again. The
    /// richer 30-step `CaptureProtocolStep.fullProtocol` in
    /// Services/CameraService.swift remains as a coaching-metadata lookup
    /// table (ideal pitch/roll/distance/instruction per shot), not as a
    /// second "how many shots" source of truth.
    static let requiredCaptureProtocol: [PhotoType] = [
        .wideAngle, .wideAngle,                 // 2 wide context shots
        .closeupDamage, .closeupDamage,         // 2 closeups
        .paintTransfer, .paintTransfer,         // 2 paint transfer macros
        .heightMeasurement, .heightMeasurement, // 2 reference heights
        .licenseDetail,                         // license / VIN
        .lidarReference                         // marker shot before LiDAR scan
    ]
}
