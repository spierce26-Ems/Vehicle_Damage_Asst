// Case.swift
// Vehicle Damage Forensic Matcher
// Core case data model

import Foundation
import CoreLocation

// MARK: - Forensic Case

/// Top-level model representing a single forensic investigation case
struct ForensicCase: Identifiable, Codable, Equatable {
    let id: UUID
    var caseNumber: String
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

    // MARK: Init

    init(
        id: UUID = UUID(),
        caseNumber: String = "",
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
        metadata: CaseMetadata = CaseMetadata()
    ) {
        self.id = id
        self.caseNumber = caseNumber
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
    }

    // MARK: Computed Properties

    /// True if both vehicles have been photographed
    var isReadyForAnalysis: Bool {
        victimVehicle.photos.count >= 4 &&
        (suspectVehicle?.photos.count ?? 0) >= 4
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

struct IncidentLocation: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var address: String?
    var city: String?
    var state: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayAddress: String {
        [address, city, state].compactMap { $0 }.joined(separator: ", ")
    }

    init(coordinate: CLLocationCoordinate2D, address: String? = nil, city: String? = nil, state: String? = nil) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.address = address
        self.city = city
        self.state = state
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

// UIDevice import shim for non-UIKit previews
import UIKit
