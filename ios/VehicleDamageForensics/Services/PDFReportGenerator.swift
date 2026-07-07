// PDFReportGenerator.swift
// Vehicle Damage Investigation Assistant
// Generates an investigative documentation PDF summary of a case using
// PDFKit + UIGraphicsPDFRenderer. Includes case header, vehicle details,
// per-factor breakdown, photos, and chain-of-custody trail.
//
// NOTE(AI Developer): Per Sean's decision (2026-07) to scope v1 as
// "best-in-class investigative documentation + leads tool", this report is
// explicitly NOT described as "court-admissible" or a forensic "match"
// verdict anywhere in its copy — see MatchResult.swift for the full
// rationale. Every generated report includes MatchResult.disclaimerText on
// its cover page.

import Foundation
import UIKit
import PDFKit

// MARK: - PDF Report Generator

struct PDFReportGenerator {

    enum ReportError: LocalizedError {
        case writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .writeFailed(let m): return "Could not write PDF: \(m)"
            }
        }
    }

    // MARK: Public API

    /// Render `forensicCase` to PDF and return the on-disk URL.
    @discardableResult
    func generate(for forensicCase: ForensicCase, into directory: URL) throws -> URL {
        let url = directory
            .appendingPathComponent("Report_\(forensicCase.caseNumber.isEmpty ? forensicCase.id.uuidString : forensicCase.caseNumber)")
            .appendingPathExtension("pdf")

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: pdfFormat())
        do {
            try renderer.writePDF(to: url) { ctx in
                drawCoverPage(ctx: ctx, rect: pageRect, case: forensicCase)
                drawSummaryPage(ctx: ctx, rect: pageRect, case: forensicCase)
                drawFactorBreakdown(ctx: ctx, rect: pageRect, case: forensicCase)
                drawPhotoEvidence(ctx: ctx, rect: pageRect, case: forensicCase)
                drawChainOfCustody(ctx: ctx, rect: pageRect, case: forensicCase)
            }
        } catch {
            throw ReportError.writeFailed(error.localizedDescription)
        }
        return url
    }

    // MARK: Pages

    private func drawCoverPage(ctx: UIGraphicsPDFRendererContext, rect: CGRect, case c: ForensicCase) {
        ctx.beginPage()
        // NOTE(AI Developer): Renamed from "Vehicle Damage Forensic Match
        // Report" / verdictString ("...MATCH") per Sean's decision — see
        // MatchResult.swift for rationale.
        let title = "Vehicle Damage Correlation Report"
        let subtitle = c.matchResult?.correlationLabel ?? "Analysis Pending"
        let caseNumber = c.caseNumber.isEmpty ? c.id.uuidString : c.caseNumber

        title.drawCenter(in: rect, y: 120, font: .boldSystemFont(ofSize: 24))
        subtitle.drawCenter(in: rect, y: 170, font: .systemFont(ofSize: 18))
        "Case Number: \(caseNumber)".drawCenter(in: rect, y: 220, font: .systemFont(ofSize: 14))
        "Generated: \(Self.dateFormatter.string(from: Date()))".drawCenter(in: rect, y: 244, font: .systemFont(ofSize: 12))

        if let score = c.matchResult?.compositeScore {
            let scoreText = String(format: "Composite Score: %.1f / 100", score)
            scoreText.drawCenter(in: rect, y: 320, font: .boldSystemFont(ofSize: 36))
            if let range = c.matchResult?.scoreRangeLabel {
                "Score Range: \(range)".drawCenter(in: rect, y: 368, font: .systemFont(ofSize: 13))
            }
        }

        // NOTE(AI Developer): Required disclaimer callout per Sean's
        // decision — placed on the cover page, boxed, so it cannot be missed
        // or separated from the report if pages are later split apart.
        drawDisclaimerBox(rect: rect, y: 430)
    }

    /// Draws `MatchResult.disclaimerText` inside a bordered box.
    private func drawDisclaimerBox(rect: CGRect, y: CGFloat) {
        let boxRect = CGRect(x: 50, y: y, width: rect.width - 100, height: 130)
        let path = UIBezierPath(roundedRect: boxRect, cornerRadius: 8)
        UIColor.systemGray5.setFill()
        path.fill()
        UIColor.systemGray2.setStroke()
        path.lineWidth = 1
        path.stroke()

        "IMPORTANT".draw(at: CGPoint(x: boxRect.minX + 16, y: boxRect.minY + 12),
                          font: .boldSystemFont(ofSize: 12), color: .darkGray)
        MatchResult.disclaimerText.draw(
            at: CGPoint(x: boxRect.minX + 16, y: boxRect.minY + 32),
            font: .systemFont(ofSize: 10),
            maxWidth: boxRect.width - 32,
            color: .darkGray
        )
    }

    private func drawSummaryPage(ctx: UIGraphicsPDFRendererContext, rect: CGRect, case c: ForensicCase) {
        ctx.beginPage()
        var y: CGFloat = 50
        "Case Summary".draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 20))
        y += 40

        // NOTE(AI Developer): Added Case Name + Incident Location lines
        // per Sean's decision (2026-07) to add structured case
        // naming/address capture — see Case.swift `caseName` /
        // `IncidentLocation` rework.
        let lines: [String] = [
            "Case Name: \(c.caseName.isEmpty ? "—" : c.caseName)",
            "Case Type: \(c.caseType.displayName)",
            "Status: \(c.statusLabel)",
            "Incident Date: \(c.incidentDate.map(Self.dateFormatter.string) ?? "n/a")",
            "Incident Location: \((c.location?.displayAddress.isEmpty ?? true) ? "—" : c.location!.displayAddress)",
            "Notes: \(c.notes.isEmpty ? "—" : c.notes)",
            "",
            "Victim Vehicle: \(c.victimVehicle.displayName)",
            "  Color: \(c.victimVehicle.color)",
            "  License: \(c.victimVehicle.licensePlate ?? "—")",
            "  VIN: \(c.victimVehicle.vin ?? "—")",
            "",
            "Suspect Vehicle: \(c.suspectVehicle?.displayName ?? "—")",
            "  Color: \(c.suspectVehicle?.color ?? "—")",
            "  License: \(c.suspectVehicle?.licensePlate ?? "—")"
        ]
        for line in lines {
            line.draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 12))
            y += 18
        }
    }

    private func drawFactorBreakdown(ctx: UIGraphicsPDFRendererContext, rect: CGRect, case c: ForensicCase) {
        ctx.beginPage()
        var y: CGFloat = 50
        "Per-Factor Breakdown".draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 20))
        y += 40

        guard let factors = c.matchResult?.factors, !factors.isEmpty else {
            "No analysis available.".draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 14))
            return
        }

        for f in factors.sorted(by: { $0.weight > $1.weight }) {
            let header = String(format: "%@   weight %.0f%%   raw %.1f   weighted %.1f",
                                f.factor.displayName, f.weight * 100, f.rawScore, f.weightedScore)
            header.draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 13))
            y += 18
            f.notes.draw(at: CGPoint(x: 60, y: y), font: .systemFont(ofSize: 11), maxWidth: rect.width - 120)
            y += 36
        }
    }

    private func drawPhotoEvidence(ctx: UIGraphicsPDFRendererContext, rect: CGRect, case c: ForensicCase) {
        let allPhotos = c.victimVehicle.photos + (c.suspectVehicle?.photos ?? [])
        let usable = allPhotos.filter { $0.isUsable }.prefix(8)
        guard !usable.isEmpty else { return }

        ctx.beginPage()
        var y: CGFloat = 50
        "Photo Evidence".draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 20))
        y += 30

        var x: CGFloat = 50
        let cellSize: CGFloat = 240
        for photo in usable {
            guard let img = UIImage(data: photo.imageData) else { continue }
            img.draw(in: CGRect(x: x, y: y, width: cellSize, height: cellSize * 0.75))
            let label = "\(photo.photoType.displayName) (Q: \(photo.qualityLabel.rawValue))"
            label.draw(at: CGPoint(x: x, y: y + cellSize * 0.75 + 4), font: .systemFont(ofSize: 10))
            x += cellSize + 20
            if x + cellSize > rect.width {
                x = 50
                y += cellSize * 0.75 + 40
                if y + cellSize * 0.75 > rect.height - 50 {
                    ctx.beginPage()
                    y = 50
                }
            }
        }
    }

    private func drawChainOfCustody(ctx: UIGraphicsPDFRendererContext, rect: CGRect, case c: ForensicCase) {
        ctx.beginPage()
        var y: CGFloat = 50
        "Chain of Custody".draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 20))
        y += 30

        // NOTE(AI Developer): Reworded per Sean's decision — "available for
        // forensic verification" implied a forensic-grade guarantee this
        // tool doesn't provide; reframed as documentation/audit language.
        let header = [
            "Case ID: \(c.id.uuidString)",
            "Case Created: \(Self.dateFormatter.string(from: c.dateCreated))",
            "Total Photos: \(c.victimVehicle.photos.count + (c.suspectVehicle?.photos.count ?? 0))",
            "Analysis ID: \(c.matchResult?.analysisID.uuidString ?? "—")",
            "",
            "This report was generated by the Vehicle Damage Investigation Assistant.",
            "All sensor data, GPS coordinates, and timestamps have been preserved",
            "in the source case file for documentation and audit purposes."
        ]
        for line in header {
            line.draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 12), maxWidth: rect.width - 100)
            y += 18
        }

        // NOTE(AI Developer): Chain-of-custody audit trail per Sean's
        // decision to add `ForensicCase.auditLog` (2026-07). This is the
        // whole reason the field exists — a printed, timestamped record of
        // every recorded event on the case (creation, each photo capture,
        // analysis run, report generation) for court admissibility. Prior
        // to this the page only had generic boilerplate text and no actual
        // per-event record.
        y += 12
        "Audit Trail".draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 14))
        y += 22
        for entry in c.auditLog.sorted(by: { $0.timestamp < $1.timestamp }) {
            if y > rect.height - 60 {
                ctx.beginPage()
                y = 50
            }
            let line = "\(Self.dateFormatter.string(from: entry.timestamp))  —  \(entry.action.displayName)"
                + (entry.detail.map { ": \($0)" } ?? "")
            line.draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 10), maxWidth: rect.width - 100)
            y += 15
        }
    }

    // MARK: Format

    private func pdfFormat() -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Vehicle Damage Investigation Assistant",
            kCGPDFContextAuthor  as String: "Correlation Analysis Engine"
        ]
        return format
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

// MARK: - String drawing helpers

private extension String {
    func draw(at point: CGPoint, font: UIFont, maxWidth: CGFloat = 500, color: UIColor = .black) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let rect = CGRect(x: point.x, y: point.y, width: maxWidth, height: .greatestFiniteMagnitude)
        (self as NSString).draw(with: rect, options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
    }

    func drawCenter(in rect: CGRect, y: CGFloat, font: UIFont, color: UIColor = .black) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let size = (self as NSString).size(withAttributes: attrs)
        let x = (rect.width - size.width) / 2
        (self as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
    }
}
