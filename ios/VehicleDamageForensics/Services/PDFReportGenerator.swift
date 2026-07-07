// PDFReportGenerator.swift
// Vehicle Damage Forensic Matcher
// Generates a court-admissible PDF summary of a forensic case using
// PDFKit + UIGraphicsPDFRenderer. Includes case header, vehicle details,
// per-factor breakdown, photos, and chain-of-custody footer.

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
        let title = "Vehicle Damage Forensic Match Report"
        let subtitle = c.matchResult?.verdictString ?? "Analysis Pending"
        let caseNumber = c.caseNumber.isEmpty ? c.id.uuidString : c.caseNumber

        title.drawCenter(in: rect, y: 120, font: .boldSystemFont(ofSize: 24))
        subtitle.drawCenter(in: rect, y: 170, font: .systemFont(ofSize: 18))
        "Case Number: \(caseNumber)".drawCenter(in: rect, y: 220, font: .systemFont(ofSize: 14))
        "Generated: \(Self.dateFormatter.string(from: Date()))".drawCenter(in: rect, y: 244, font: .systemFont(ofSize: 12))

        if let score = c.matchResult?.compositeScore {
            let scoreText = String(format: "Composite Score: %.1f / 100", score)
            scoreText.drawCenter(in: rect, y: 320, font: .boldSystemFont(ofSize: 36))
        }
    }

    private func drawSummaryPage(ctx: UIGraphicsPDFRendererContext, rect: CGRect, case c: ForensicCase) {
        ctx.beginPage()
        var y: CGFloat = 50
        "Case Summary".draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 20))
        y += 40

        let lines: [String] = [
            "Case Type: \(c.caseType.rawValue)",
            "Status: \(c.status.rawValue)",
            "Incident Date: \(c.incidentDate.map(Self.dateFormatter.string) ?? "n/a")",
            "Notes: \(c.notes.isEmpty ? "—" : c.notes)",
            "",
            "Victim Vehicle: \(c.victimVehicle.displayName)",
            "  Color: \(c.victimVehicle.color)",
            "  License: \(c.victimVehicle.licensePlate ?? "—")",
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

        let entries = [
            "Case ID: \(c.id.uuidString)",
            "Case Created: \(Self.dateFormatter.string(from: c.dateCreated))",
            "Total Photos: \(c.victimVehicle.photos.count + (c.suspectVehicle?.photos.count ?? 0))",
            "Analysis ID: \(c.matchResult?.analysisID.uuidString ?? "—")",
            "",
            "This report was generated by the Vehicle Damage Forensic Matcher.",
            "All sensor data, GPS coordinates, and timestamps have been preserved",
            "in the source case file and are available for forensic verification."
        ]
        for line in entries {
            line.draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 12), maxWidth: rect.width - 100)
            y += 18
        }
    }

    // MARK: Format

    private func pdfFormat() -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Vehicle Damage Forensic Matcher",
            kCGPDFContextAuthor  as String: "Forensic Analysis Engine"
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
