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

    /// NOTE(AI Developer), added 2026-07 per Sean's monetization decision:
    /// this app serves both one-time consumers (pay per case) and
    /// professional/subscriber users (unlimited access). `isUnlocked`
    /// records whether *this specific case* has had its full report
    /// (per-factor breakdown, recommendations, PDF export) unlocked --
    /// either by spending a purchased case credit
    /// (`PurchaseManager.consumeCreditForUnlock()`) or because the user
    /// held an active Pro subscription at the time. Deliberately stored
    /// on the case itself (not derived live from subscription status)
    /// so that a case a subscriber unlocked stays unlocked even if their
    /// subscription later lapses -- consistent with how a one-time
    /// consumer's paid unlock works, and avoiding the surprising/hostile
    /// UX of a previously-viewable report suddenly re-locking. Defaults
    /// to `false` so pre-existing case JSON (from before this field
    /// existed, i.e. every case saved during development before
    /// monetization was scoped) decodes as locked rather than granting
    /// free access -- see custom `init(from:)` below.
    var isUnlocked: Bool

    /// NOTE(AI Developer), added 2026-09 for item #5 of Sean's 5-item
    /// plan ("Duplicate Case for Another Suspect"), implemented as
    /// Option B per the Tech Lead's decision -- a clone action rather
    /// than refactoring `suspectVehicle` into an array (~88 references
    /// across 15 files).
    ///
    /// The `id` of the case this one was duplicated from, or `nil` for a
    /// case created from scratch. Set once at clone time and never
    /// changed afterwards.
    ///
    /// This exists for evidential rather than functional reasons. Two
    /// cases that share the same victim-vehicle photographs are not
    /// independent observations, and anyone reviewing a
    /// "suspect A scored 74%, suspect B scored 71%" comparison needs to
    /// know that. Without this link the duplication is invisible in the
    /// data, and the same victim evidence could be presented twice as if
    /// it had been gathered twice. It is deliberately a plain `UUID?`
    /// and NOT a resolved reference: the source case may later be
    /// deleted, and a dangling id that still records "this came from
    /// somewhere" is more honest than a reference that must be kept
    /// valid or silently dropped.
    var sourceCaseID: UUID?

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
        auditLog: [AuditEntry] = [],
        isUnlocked: Bool = false,
        sourceCaseID: UUID? = nil
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
        self.isUnlocked = isUnlocked
        self.sourceCaseID = sourceCaseID
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
        // Falls back to `false` (locked) for any case file persisted
        // before monetization existed -- see the field's doc comment.
        isUnlocked = try c.decodeIfPresent(Bool.self, forKey: .isUnlocked) ?? false
        // Optional, so `decodeIfPresent` is what the synthesized code
        // would do anyway -- `nil` for every case saved before
        // duplication existed, which is exactly right: those cases were
        // created from scratch.
        sourceCaseID = try c.decodeIfPresent(UUID.self, forKey: .sourceCaseID)
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
    ///
    /// NOTE(AI Developer), updated 2026-07 per Sean's "skip a shot"
    /// request: a slot is now considered "filled" if it was either
    /// captured/imported (`photos.count`) OR explicitly skipped
    /// (`skippedShotIndices.count`) -- per Sean's answer ("a skipped shot
    /// should account for done unless the image is absolutely necessary"
    /// + "let's not allow mandatory shots"), every shot in the protocol is
    /// skippable, so `photos.count + skippedShotIndices.count >= required`
    /// is the full completion condition, not just `photos.count`.
    ///
    /// Also now requires `hasImpactProfile` on both vehicles per Sean's
    /// explicit decision that impact location + direction of travel is a
    /// REQUIRED (non-skippable) step, separate from the skippable photo
    /// protocol -- see `Vehicle.hasImpactProfile`.
    var isReadyForAnalysis: Bool {
        let required = PhotoType.requiredCaptureProtocol.count
        let victimFilled = victimVehicle.photos.count + victimVehicle.skippedShotIndices.count
        let suspectFilled = (suspectVehicle?.photos.count ?? 0) + (suspectVehicle?.skippedShotIndices.count ?? 0)
        let photosReady = victimFilled >= required && suspectFilled >= required
        let impactReady = victimVehicle.hasImpactProfile && (suspectVehicle?.hasImpactProfile ?? false)
        return photosReady && impactReady
    }

    /// Human-friendly title for lists/navigation: prefers the user-entered
    /// `caseName`, falls back to the auto-assigned `caseNumber`, then to a
    /// generic placeholder if somehow both are empty (e.g. very old data).
    var displayTitle: String {
        if !caseName.isEmpty { return caseName }
        if !caseNumber.isEmpty { return caseNumber }
        return "Untitled Case"
    }

    /// NOTE(AI Developer), added 2026-07 per Sean's request ("Case-list
    /// thumbnail polish -- CaseRow currently shows an icon + text only,
    /// a small photo thumbnail per case would make the list easier to
    /// scan visually"). Picks the first *usable* captured/imported photo
    /// across both vehicles to represent this case in `CaseRow` --
    /// victim vehicle photos first (sorted by `sequenceIndex` so it's
    /// always the earliest shot, not whatever order they happen to be
    /// stored in), falling back to the suspect vehicle's photos if the
    /// victim vehicle has none yet (e.g. right after creating a case and
    /// only photographing the other vehicle first). Returns `nil` for a
    /// brand-new case with no photos at all, letting `CaseRow` fall back
    /// to its existing icon-only display.
    ///
    /// Deliberately reads `thumbnailData` (a small pre-generated JPEG --
    /// see `CameraService.generateThumbnail`) rather than the full-size
    /// `imageData`, since every photo already carries one and decoding a
    /// small thumbnail for every row in a potentially long case list is
    /// far cheaper than decoding full-resolution capture photos just to
    /// downscale them for a 44x44 row icon.
    var thumbnailPhoto: CapturedPhoto? {
        let victimPhoto = victimVehicle.photos
            .filter { $0.isUsable && $0.thumbnailData != nil }
            .sorted { $0.sequenceIndex < $1.sequenceIndex }
            .first
        if let victimPhoto { return victimPhoto }
        return suspectVehicle?.photos
            .filter { $0.isUsable && $0.thumbnailData != nil }
            .sorted { $0.sequenceIndex < $1.sequenceIndex }
            .first
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
    // NOTE(AI Developer), added 2026-07 per Sean's request ("we also
    // should have the ability to upload images from camera roll"): a
    // distinct audit action (rather than reusing `.photoCaptured`) so the
    // chain-of-custody log honestly distinguishes "captured live, on
    // scene, by this app" from "imported from an existing library photo" --
    // see the NOTE on `CapturedPhoto.wasImported` for the full rationale.
    case photoImported = "photo_imported"
    case vehicleUpdated = "vehicle_updated"
    case analysisRun = "analysis_run"
    case reportGenerated = "report_generated"
    case caseEdited = "case_edited"
    case caseClosed = "case_closed"
    // NOTE(AI Developer), added 2026-07 per Sean's monetization decision:
    // records how a case's full report was unlocked (purchased case
    // credit vs. active Pro subscription) -- kept in the chain-of-custody
    // log alongside every other meaningful mutation, and useful for
    // Sean's own support/troubleshooting if a user disputes a charge.
    case caseUnlocked = "case_unlocked"
    // NOTE(AI Developer), added 2026-07 per Sean's "skip a shot" request:
    // a distinct audit action (rather than silently omitting the slot) so
    // the chain-of-custody log honestly records that a required shot was
    // deliberately not captured for this case, and why (see
    // `CaptureViewModel.skipCurrentShot(reason:)`'s `detail` string).
    case photoSkipped = "photo_skipped"
    // NOTE(AI Developer), added 2026-07 per Sean's request ("should we
    // identify the location of the damage on each vehicle and always
    // identify the direction of traveling at impact"). Recorded once per
    // vehicle when `Vehicle.hasImpactProfile` first becomes true.
    case impactProfileRecorded = "impact_profile_recorded"
    // NOTE(AI Developer), added 2026-07 per Sean's explicit request ("wire
    // LiDAR data into the Height Alignment factor... we need the use of
    // Lidar as an extra tool"). Recorded once per vehicle when a real
    // ground-to-damage height is captured via `LiDARScanView`'s
    // tap-to-measure step -- see `Vehicle.lidarMeasuredHeightInches` and
    // `CaptureViewModel.recordLiDARMeasurement(inches:)`.
    case lidarMeasurementRecorded = "lidar_measurement_recorded"
    // NOTE(AI Developer), added 2026-07 as part of the paint-color
    // reference-normalization fix (Sean: "yes build it now"). Recorded
    // once per photo the first time its damage-area + clean-panel taps
    // are both saved via `PaintReferenceMarkerView` -- see
    // `CaptureViewModel.recordPaintReferenceTaps`. Distinct from
    // `.photoCaptured`/`.photoImported` since it's a separate, later
    // step against an already-captured photo, not the capture itself.
    case paintReferenceRecorded = "paint_reference_recorded"
    // NOTE(AI Developer), added 2026-07 as part of the Scar-Direction
    // Consistency feature (Sean's fix for the parallel-parking
    // direction-of-travel blind spot). Recorded once per vehicle the
    // first time a scar line's paint-transfer taper is successfully
    // resolved into a `Vehicle.scarSlideDirection` -- see
    // `CaptureViewModel.recordScarDirection`. Distinct from
    // `.paintReferenceRecorded` since this is a separate, later,
    // optional step against the same paint-transfer photo, not the
    // required damage/reference color sampling itself.
    case scarDirectionRecorded = "scar_direction_recorded"
    // NOTE(AI Developer), added 2026-07 alongside the dedicated guided
    // scar-capture camera (`ScarCaptureView`). Recorded once per
    // successful capture of `Vehicle.scarPhoto` -- distinct from
    // `.photoCaptured` since this photo is NOT part of the counted
    // 10-shot protocol (see `Vehicle.scarPhoto`'s doc comment), and
    // distinct from `.scarDirectionRecorded` since capturing the photo
    // and successfully resolving a direction from its marked line are
    // two separate steps that can each fail/retry independently.
    case scarPhotoCaptured = "scar_photo_captured"
    // NOTE(AI Developer), added 2026-07 per Sean's explicit request ("we
    // need the ability to go back and change the images once it is
    // submitted. I chose the wrong image from my roll and i could not go
    // back and fix"). Recorded whenever `PhotoReviewView`/
    // `CaptureViewModel.replacePhoto(...)` overwrites an ALREADY-filled
    // protocol slot (captured, imported, or previously-skipped) with a
    // new photo -- distinct from `.photoCaptured`/`.photoImported`
    // (which only ever fire when advancing into a fresh, previously-empty
    // slot) so the chain-of-custody log is explicit about a slot's
    // evidence having been superseded after the fact, not just filled
    // once.
    case photoReplaced = "photo_replaced"
    // NOTE(AI Developer), added 2026-09 for item #5 (duplicate case for
    // another suspect). Recorded on the NEW case, naming the case its
    // victim evidence was copied from -- so the clone's chain of custody
    // states on its very first line that its victim photographs were not
    // captured for this case. Also recorded on the SOURCE case, so
    // someone reading the original can tell its evidence was reused
    // elsewhere. Both directions matter: the link is only useful for
    // assessing independence if it is discoverable from either end.
    case caseDuplicated = "case_duplicated"

    var displayName: String {
        switch self {
        case .created: return "Case Created"
        case .photoCaptured: return "Photo Captured"
        case .photoImported: return "Photo Imported"
        case .vehicleUpdated: return "Vehicle Info Updated"
        case .analysisRun: return "Analysis Run"
        case .reportGenerated: return "Report Generated"
        case .caseEdited: return "Case Edited"
        case .caseClosed: return "Case Closed"
        case .caseUnlocked: return "Report Unlocked"
        case .photoSkipped: return "Photo Skipped"
        case .impactProfileRecorded: return "Impact Location/Direction Recorded"
        case .lidarMeasurementRecorded: return "LiDAR Height Measurement Recorded"
        case .paintReferenceRecorded: return "Paint Reference Sample Recorded"
        case .scarDirectionRecorded: return "Scar Direction Recorded"
        case .scarPhotoCaptured: return "Scar Photo Captured"
        case .photoReplaced: return "Photo Replaced"
        case .caseDuplicated: return "Case Duplicated for Another Suspect"
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

    // MARK: Duplication for another suspect (item #5)

    /// NOTE(AI Developer), added 2026-09 for item #5 of Sean's 5-item
    /// plan, built as Option B per the Tech Lead's decision: a clone
    /// action rather than refactoring `suspectVehicle` from `Vehicle?`
    /// into an array (~88 references across 15 files -- a far riskier
    /// rewrite for the same investigator-visible outcome).
    ///
    /// Produces a NEW case that reuses this case's victim-vehicle
    /// evidence and incident details, ready to be compared against a
    /// different suspect vehicle. What is deliberately carried over vs.
    /// cleared:
    ///
    /// CARRIED OVER -- facts about the incident and the victim vehicle,
    /// which are identical no matter who is suspected: the victim
    /// vehicle and all its photos/scans/markings, case type, incident
    /// date, location, and notes.
    ///
    /// CLEARED -- everything that is a statement about a SUSPECT or a
    /// conclusion drawn about one:
    /// - `suspectVehicle` (nil): the whole point is a different suspect.
    /// - `matchResult` (nil): a score computed against suspect A is
    ///   meaningless in a case about suspect B. Carrying it over would
    ///   be the single most dangerous possible bug in this feature --
    ///   a case showing a 78% correlation against a vehicle it was never
    ///   compared to.
    /// - `reportURL` (nil): that PDF documents the other comparison.
    /// - `status` (.inProgress): the new case genuinely is incomplete.
    /// - `isUnlocked` (false): an unlock is a purchase against one
    ///   case's report. Inheriting it would let one payment unlock
    ///   unlimited cases -- see `PurchaseManager`. Deliberately NOT
    ///   inherited even though it makes the feature slightly less
    ///   convenient.
    /// - `id`, `caseNumber`, `dateCreated`, `metadata`: this is a new
    ///   case record, created now, on this device.
    /// - `auditLog`: starts fresh, because a chain of custody belongs to
    ///   one case. It is NOT empty though -- see below.
    ///
    /// The new case's audit log opens with the standard `.created` entry
    /// plus a `.caseDuplicated` entry naming the source case, so the
    /// clone's chain of custody discloses on its first two lines that
    /// its victim photographs were captured for a different case. That
    /// disclosure, together with `sourceCaseID`, is what keeps
    /// "suspect A: 74%, suspect B: 71%" from being read as two
    /// independent investigations when they share one set of victim
    /// evidence.
    ///
    /// - Parameters:
    ///   - caseNumber: the newly assigned serial. Callers must pass a
    ///     freshly generated one (see `CaseListViewModel.nextCaseNumber`)
    ///     -- this type has no access to the set of existing cases and
    ///     so cannot generate a unique number itself.
    ///   - caseName: name for the new case. Callers should offer the
    ///     user a sensible prefilled default rather than reusing the
    ///     source's name verbatim, or the case list ends up with several
    ///     identically-named rows.
    func duplicatedForNewSuspect(caseNumber: String, caseName: String) -> ForensicCase {
        var clone = ForensicCase(
            caseNumber: caseNumber,
            caseName: caseName,
            caseType: caseType,
            status: .inProgress,
            dateCreated: Date(),
            incidentDate: incidentDate,
            location: location,
            notes: notes,
            victimVehicle: victimVehicle.duplicatedWithFreshIDs(),
            suspectVehicle: nil,
            matchResult: nil,
            reportURL: nil,
            metadata: CaseMetadata(createdBy: metadata.createdBy),
            auditLog: [],
            isUnlocked: false,
            sourceCaseID: id
        )
        clone.recordAudit(
            .caseDuplicated,
            // `self.` is explicit throughout: the source case's own
            // identifiers, NOT the new case's `caseNumber`/`caseName`
            // parameters shadowing them.
            detail: "Victim vehicle evidence duplicated from case \(self.displayTitle) (\(self.caseNumber), id \(self.id.uuidString)). The victim photos in this case were captured for that case, not this one; no suspect data, match result, or report was carried over."
        )
        return clone
    }
}

// UIDevice import shim for non-UIKit previews
import UIKit
