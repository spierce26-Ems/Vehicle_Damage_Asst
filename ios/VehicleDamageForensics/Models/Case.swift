// Case.swift
// Vehicle Damage Investigation Assistant
// Core case data model

import Foundation
import CoreLocation

// MARK: - Forensic Case

/// Top-level model representing a single forensic investigation case
struct ForensicCase: Identifiable, Codable, Equatable {
    let id: UUID
    var caseNumber: String

    /// NOTE(AI Developer): Added per Sean's decision (2026-07) — a
    /// human-readable label distinct from the auto-assigned serial
    /// `caseNumber` (e.g. "Sarah's Driveway Hit & Run" vs. "VD-2026-00001").
    /// Optional-style default (`""`) so it decodes safely from any case
    /// JSON persisted before this field existed; UI falls back to
    /// `caseNumber` for display when empty (see `displayTitle`).
    var caseName: String
    var caseType: CaseType
    var status: CaseStatus
    var dateCreated: Date
    var incidentDate: Date?
    var location: IncidentLocation?
    var notes: String
    var victimVehicle: Vehicle
    var suspectVehicle: Vehicle?
    var matchResult: MatchResult?
    var reportURL: URL?
    var metadata: CaseMetadata

    /// Chain-of-custody audit trail. NOTE(AI Developer): Added per Sean's
    /// decision (2026-07) to close the gap flagged earlier — Section 4 of
    /// the handoff brief claimed `Case.swift` already had `createdAt` +
    /// `auditLog` for chain-of-custody, but neither existed (only
    /// `dateCreated`, which is kept as-is to avoid a churny rename of every
    /// call site). This is additive and append-only from the app's
    /// perspective: entries are appended by `AppState`/`ViewModel`s at each
    /// mutation point (case creation, photo capture, analysis run, report
    /// generation) — never edited or removed — so the log itself becomes
    /// evidence of when/how the case was built. Defaults to `[]` and decodes
    /// safely from pre-existing case JSON files that predate this field
    /// (see custom `init(from:)` below).
    var auditLog: [AuditEntry]

    // MARK: Init

    init(
        id: UUID = UUID(),
        caseNumber: String = "",
        caseName: String = "",
        caseType: CaseType = .hitAndRun,
        status: CaseStatus = .inProgress,
        dateCreated: Date = Date(),
        incidentDate: Date? = nil,
        location: IncidentLocation? = nil,
        notes: String = "",
        victimVehicle: Vehicle = Vehicle(role: .victim),
        suspectVehicle: Vehicle? = nil,
        matchResult: MatchResult? = nil,
        reportURL: URL? = nil,
        metadata: CaseMetadata = CaseMetadata(),
        auditLog: [AuditEntry] = []
    ) {
        self.id = id
        self.caseNumber = caseNumber
        self.caseName = caseName
        self.caseType = caseType
        self.status = status
        self.dateCreated = dateCreated
        self.incidentDate = incidentDate
        self.location = location
        self.notes = notes
        self.victimVehicle = victimVehicle
        self.suspectVehicle = suspectVehicle
        self.matchResult = matchResult
        self.reportURL = reportURL
        self.metadata = metadata
        // A freshly-created case always gets a `.created` entry so the
        // audit trail's first line is never missing.
        self.auditLog = auditLog.isEmpty ? [AuditEntry(action: .created)] : auditLog
    }

    // MARK: Codable (custom, for backward-compatible decoding)

    /// NOTE(AI Developer): Custom `init(from:)` so that JSON case files
    /// written before `auditLog` existed (or hand-authored test fixtures)
    /// decode successfully instead of throwing `keyNotFound`. The compiler
    /// still auto-synthesizes `encode(to:)` and `CodingKeys` for us as long
    /// as we don't implement those ourselves — confirmed this is standard,
    /// supported Codable behavior (Apple docs: "Encoding and Decoding
    /// Custom Types"; Swift Forums: providing init(from:) alone does not
    /// suppress synthesis of encode(to:) or CodingKeys).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        caseNumber = try c.decode(String.self, forKey: .caseNumber)
        // Falls back to "" for case files persisted before this field
        // existed, same backward-compat pattern as `auditLog` below.
        caseName = try c.decodeIfPresent(String.self, forKey: .caseName) ?? ""
        caseType = try c.decode(CaseType.self, forKey: .caseType)
        status = try c.decode(CaseStatus.self, forKey: .status)
        dateCreated = try c.decode(Date.self, forKey: .dateCreated)
        incidentDate = try c.decodeIfPresent(Date.self, forKey: .incidentDate)
        location = try c.decodeIfPresent(IncidentLocation.self, forKey: .location)
        notes = try c.decode(String.self, forKey: .notes)
        victimVehicle = try c.decode(Vehicle.self, forKey: .victimVehicle)
        suspectVehicle = try c.decodeIfPresent(Vehicle.self, forKey: .suspectVehicle)
        matchResult = try c.decodeIfPresent(MatchResult.self, forKey: .matchResult)
        reportURL = try c.decodeIfPresent(URL.self, forKey: .reportURL)
        metadata = try c.decode(CaseMetadata.self, forKey: .metadata)
        // Falls back to [] for any case file persisted before this field
        // was introduced, rather than failing to decode the whole case.
        auditLog = try c.decodeIfPresent([AuditEntry].self, forKey: .auditLog) ?? []
    }

    // MARK: Computed Properties

    /// True if both vehicles have completed the required capture protocol.
    /// NOTE(AI Developer): Previously hardcoded `>= 4` here, while a
    /// duplicate declaration in ModelExtensions.swift (since removed)
    /// hardcoded `>= 5`, and the actual guided-capture UI
    /// (CaptureViewModel.protocolShots) requires 10 shots per vehicle.
    /// Per Sean's decision, this now derives from the single canonical
    /// shot list (`PhotoType.requiredCaptureProtocol`) so the three can
    /// never drift out of sync again.
    var isReadyForAnalysis: Bool {
        let required = PhotoType.requiredCaptureProtocol.count
        return victimVehicle.photos.count >= required &&
            (suspectVehicle?.photos.count ?? 0) >= required
    }

    /// Human-friendly title for lists/navigation: prefers the user-entered
    /// `caseName`, falls back to the auto-assigned `caseNumber`, then to a
    /// generic placeholder if somehow both are empty (e.g. very old data).
    var displayTitle: String {
        if !caseName.isEmpty { return caseName }
        if !caseNumber.isEmpty { return caseNumber }
        return "Untitled Case"
    }

    /// Display-friendly status label
    var statusLabel: String {
        switch status {
        case .inProgress: return "In Progress"
        case .analyzed: return "Analyzed"
        case .reported: return "Report Generated"
        case .closed: return "Closed"
        }
    }

    static func == (lhs: ForensicCase, rhs: ForensicCase) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Case Type

enum CaseType: String, Codable, CaseIterable {
    case hitAndRun = "hit_and_run"
    case collision = "collision"
    case insuranceClaim = "insurance_claim"
    case vandalism = "vandalism"
    case other = "other"

    var displayName: String {
        switch self {
        case .hitAndRun: return "Hit & Run"
        case .collision: return "Collision"
        case .insuranceClaim: return "Insurance Claim"
        case .vandalism: return "Vandalism"
        case .other: return "Other"
        }
    }

    var systemImageName: String {
        switch self {
        case .hitAndRun: return "car.2.fill"
        case .collision: return "exclamationmark.triangle.fill"
        case .insuranceClaim: return "doc.text.fill"
        case .vandalism: return "hammer.fill"
        case .other: return "questionmark.circle.fill"
        }
    }
}

// MARK: - Case Status

enum CaseStatus: String, Codable, CaseIterable {
    case inProgress = "in_progress"
    case analyzed = "analyzed"
    case reported = "reported"
    case closed = "closed"

    var sortPriority: Int {
        switch self {
        case .inProgress: return 0
        case .analyzed: return 1
        case .reported: return 2
        case .closed: return 3
        }
    }
}

// MARK: - Incident Location

/// NOTE(AI Developer): Reworked per Sean's decision (2026-07) — this used
/// to require a `CLLocationCoordinate2D` up front (GPS-first), which made
/// it impossible to build a plain manual-entry "type in the address" form
/// (you'd need a device location fix, or geocoding, just to create the
/// struct). Now text fields are the primary/required-feeling data
/// (`address`/`city`/`state`/`zip`, all still `Optional` for safe decoding
/// of old data and to allow a partially-filled form) and `latitude`/
/// `longitude` are optional, populated only when we do have a device GPS
/// fix (e.g. auto-captured during capture flow) or a future geocode step.
/// `coordinate` returns `nil` when no GPS fix is present instead of
/// synthesizing (0, 0).
struct IncidentLocation: Codable, Equatable {
    var address: String?
    var city: String?
    var state: String?
    var zip: String?
    var latitude: Double?
    var longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayAddress: String {
        let cityStateZip = [city, state].compactMap { $0 }.joined(separator: ", ")
        let line2 = [cityStateZip.isEmpty ? nil : cityStateZip, zip]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return [address, line2].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var isEmpty: Bool {
        [address, city, state, zip].allSatisfy { ($0 ?? "").isEmpty } && latitude == nil
    }

    init(
        address: String? = nil,
        city: String? = nil,
        state: String? = nil,
        zip: String? = nil,
        coordinate: CLLocationCoordinate2D? = nil
    ) {
        self.address = address
        self.city = city
        self.state = state
        self.zip = zip
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
    }

    /// NOTE(AI Developer): Custom decode so old JSON (from before this
    /// rework) that has non-optional `latitude`/`longitude` still decodes
    /// fine into the now-optional properties, and so an old record with
    /// coordinates but no `zip` key doesn't throw `keyNotFound`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        zip = try c.decodeIfPresent(String.self, forKey: .zip)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
    }
}

// MARK: - Case Metadata

struct CaseMetadata: Codable, Equatable {
    var createdBy: String
    var deviceID: String
    var appVersion: String
    var lastModified: Date

    init(
        createdBy: String = "",
        deviceID: String = UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
        lastModified: Date = Date()
    ) {
        self.createdBy = createdBy
        self.deviceID = deviceID
        self.appVersion = appVersion
        self.lastModified = lastModified
    }
}

// MARK: - Audit Entry (Chain of Custody)

/// A single immutable chain-of-custody event on a `ForensicCase`.
/// NOTE(AI Developer): Added per Sean's decision to close the audit-log
/// gap flagged during Phase 1 review. Entries are meant to be appended-only
/// — nothing in the app ever edits or removes an existing entry — so the
/// log itself is evidence that the case data wasn't silently altered after
/// the fact. Kept intentionally minimal for v1 (timestamp + action + device
/// + free-text detail) rather than a full diff/signature system.
struct AuditEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let action: AuditAction
    let deviceID: String
    let detail: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        action: AuditAction,
        deviceID: String = UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
        self.deviceID = deviceID
        self.detail = detail
    }
}

/// The kinds of chain-of-custody events we record against a case.
enum AuditAction: String, Codable {
    case created
    case photoCaptured = "photo_captured"
    case vehicleUpdated = "vehicle_updated"
    case analysisRun = "analysis_run"
    case reportGenerated = "report_generated"
    case caseEdited = "case_edited"
    case caseClosed = "case_closed"

    var displayName: String {
        switch self {
        case .created: return "Case Created"
        case .photoCaptured: return "Photo Captured"
        case .vehicleUpdated: return "Vehicle Info Updated"
        case .analysisRun: return "Analysis Run"
        case .reportGenerated: return "Report Generated"
        case .caseEdited: return "Case Edited"
        case .caseClosed: return "Case Closed"
        }
    }
}

extension ForensicCase {
    /// Appends an immutable audit entry to this case's chain-of-custody log.
    /// Call this at every mutation point (capture, analysis, report, etc.)
    /// rather than mutating `auditLog` directly, so entries stay consistent.
    mutating func recordAudit(_ action: AuditAction, detail: String? = nil) {
        auditLog.append(AuditEntry(action: action, detail: detail))
    }
}

// UIDevice import shim for non-UIKit previews
import UIKit
