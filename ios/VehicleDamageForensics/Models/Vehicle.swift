// Vehicle.swift
// Vehicle Damage Forensic Matcher
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
        lidarScanData: LiDARScanData? = nil
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
    }

    // MARK: Computed

    var displayName: String {
        let parts = [year.map { String($0) }, make, model].compactMap { $0 }
        return parts.isEmpty ? "\(role.displayName) Vehicle" : parts.joined(separator: " ")
    }

    var hasLiDARData: Bool { lidarScanData != nil }

    var photosByType: [PhotoType: [CapturedPhoto]] {
        Dictionary(grouping: photos) { $0.photoType }
    }

    var primaryDamageZone: DamageZone? {
        damageZones.first
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

    enum SurfaceCondition: String, Codable {
        case fresh, weathered, rusted, repainted
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
