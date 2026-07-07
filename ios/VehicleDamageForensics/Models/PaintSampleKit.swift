// PaintSampleKit.swift
// Vehicle Damage Forensic Matcher
//
// NOTE(AI Developer): STUB / SCHEMA RESERVATION ONLY — 2026-07.
//
// Sean asked about a future feature: let a user physically collect a paint
// transfer sample from their vehicle, mail it to a partner lab for real
// chemical/spectroscopic analysis, and track that submission in-app via a
// unique code (23andMe/DNA-kit style: Requested -> Registered -> Mailed ->
// Received by Lab -> In Analysis -> Results Ready).
//
// We agreed to build this LATER — it needs real decisions first (which lab
// partner, payment processor, how much of a chain-of-custody promise we're
// willing to make to a non-professional collector). See
// `ios/reference/PAINT_ANALYSIS_KIT_FUTURE_FEATURE.md` for the full design
// questions and options.
//
// What THIS file does, right now: nothing functional. It only reserves the
// data-model shape so that `DamageZone.paintSampleKit` exists as an Optional
// field today. That matters because we just spent real effort undoing the
// pain of a field (`auditLog`) that was promised in the docs but missing
// from the model and had to be retrofitted with custom Codable shims. This
// stub avoids repeating that: when we build the real feature, we fill in
// behavior (kit creation, status transitions, lab webhook/portal, payment)
// without needing a JSON-migration dance, because the field already exists
// and is already Optional (so old + new case files both decode fine via the
// compiler-synthesized Codable — no custom init(from:) needed, since
// synthesized Decodable already treats Optional properties as
// decodeIfPresent).
//
// Nothing in the app currently creates, mutates, or displays a
// `PaintSampleKit`. It is unreachable dead code intentionally, until Sean
// greenlights the real feature.

import Foundation

// MARK: - Paint Sample Kit (future feature — not yet wired up)

/// Represents a single physical paint-sample submission tied to a
/// `DamageZone`, tracked end-to-end the way a consumer DNA test kit is:
/// pay -> get a code -> collect sample -> mail it -> watch status update ->
/// see results.
struct PaintSampleKit: Codable, Equatable, Identifiable {
    let id: UUID

    /// User-facing tracking code, e.g. "VDF-8K3M2Q". Written by the user
    /// onto the physical sample bag/tube per in-app instructions, and used
    /// to look up status later (in-app and, eventually, on a partner-lab
    /// portal if they have one).
    var kitCode: String

    var status: PaintSampleKitStatus

    /// Which damage zone this sample was collected from (denormalized copy
    /// of the parent zoneID for display/report purposes even if the zone
    /// list changes shape later).
    var sourceZoneID: String

    var requestedDate: Date
    var registeredDate: Date?
    var mailedDate: Date?
    var receivedByLabDate: Date?
    var resultsDate: Date?

    /// Name of the partner lab, once one is under contract. Left as a
    /// free-text field rather than an enum since we don't have a partner
    /// picked yet.
    var partnerLabName: String?

    /// Free-text summary + optional URL to a lab-provided PDF/report, once
    /// results come back. Deliberately NOT modeled as a numeric score here
    /// — how a lab reports paint composition results is unknown until a
    /// partner is chosen.
    var resultsSummary: String?
    var resultsReportURL: URL?

    /// Payment tracking — deliberately minimal (amount + processor
    /// reference) since we haven't picked a payment processor or pricing
    /// model yet.
    var feeAmountUSD: Double?
    var paymentReference: String?

    init(
        id: UUID = UUID(),
        kitCode: String,
        status: PaintSampleKitStatus = .requested,
        sourceZoneID: String,
        requestedDate: Date = Date(),
        registeredDate: Date? = nil,
        mailedDate: Date? = nil,
        receivedByLabDate: Date? = nil,
        resultsDate: Date? = nil,
        partnerLabName: String? = nil,
        resultsSummary: String? = nil,
        resultsReportURL: URL? = nil,
        feeAmountUSD: Double? = nil,
        paymentReference: String? = nil
    ) {
        self.id = id
        self.kitCode = kitCode
        self.status = status
        self.sourceZoneID = sourceZoneID
        self.requestedDate = requestedDate
        self.registeredDate = registeredDate
        self.mailedDate = mailedDate
        self.receivedByLabDate = receivedByLabDate
        self.resultsDate = resultsDate
        self.partnerLabName = partnerLabName
        self.resultsSummary = resultsSummary
        self.resultsReportURL = resultsReportURL
        self.feeAmountUSD = feeAmountUSD
        self.paymentReference = paymentReference
    }
}

/// NOTE(AI Developer): Status pipeline modeled on consumer DNA-kit apps
/// (23andMe/AncestryDNA style) per Sean's explicit suggestion. Exact steps
/// may change once a real lab partner's workflow is known (e.g. some labs
/// skip "registered" and go straight from "mailed" to "received").
enum PaintSampleKitStatus: String, Codable {
    case requested = "requested"                 // user paid, kit code generated
    case registered = "registered"               // user confirmed they have the kit / collected sample
    case mailed = "mailed"                       // user marked sample as shipped
    case receivedByLab = "received_by_lab"       // lab confirmed receipt (webhook or manual update)
    case inAnalysis = "in_analysis"              // lab is actively testing
    case resultsReady = "results_ready"          // results attached, viewable in-app
    case cancelled = "cancelled"

    var displayName: String {
        switch self {
        case .requested: return "Kit Requested"
        case .registered: return "Kit Registered"
        case .mailed: return "Sample Mailed"
        case .receivedByLab: return "Received by Lab"
        case .inAnalysis: return "In Analysis"
        case .resultsReady: return "Results Ready"
        case .cancelled: return "Cancelled"
        }
    }
}
