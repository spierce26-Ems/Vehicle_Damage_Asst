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
                drawAnalysisEvidence(ctx: ctx, rect: pageRect, case: forensicCase)
                drawScarDirectionSection(ctx: ctx, rect: pageRect, case: forensicCase)
                drawScarLineComparison(ctx: ctx, rect: pageRect, case: forensicCase)
                drawScarFingerprintMatch(ctx: ctx, rect: pageRect, case: forensicCase)
                drawToolMarkComparison(ctx: ctx, rect: pageRect, case: forensicCase)
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
            "  VIN: \(c.victimVehicle.vin ?? "—")"
        ] + impactProfileLines(for: c.victimVehicle) + [
            "",
            "Suspect Vehicle: \(c.suspectVehicle?.displayName ?? "—")",
            "  Color: \(c.suspectVehicle?.color ?? "—")",
            "  License: \(c.suspectVehicle?.licensePlate ?? "—")"
        ] + (c.suspectVehicle.map { impactProfileLines(for: $0) } ?? [])
        for line in lines {
            line.draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 12), maxWidth: rect.width - 100)
            y += 18
        }
    }

    // NOTE(AI Developer), added 2026-07 per Sean's approved "Option A"
    // (impact location + direction-of-travel capture): surfaces
    // `Vehicle.impactZoneDescription` / `directionOfTravelDegrees` /
    // `impactBearingDegrees` on the summary page so the report documents
    // the same required impact-profile data the app now gates analysis
    // readiness on. Returns an empty array (no extra lines) if the
    // profile was never recorded, rather than printing confusing "n/a"
    // rows for older/incomplete cases.
    private func impactProfileLines(for vehicle: Vehicle) -> [String] {
        guard vehicle.hasImpactProfile else { return [] }
        var lines = ["  Impact Location: \(vehicle.impactZoneDescription ?? "—")"]
        if let travel = vehicle.directionOfTravelDegrees {
            lines.append("  Direction of Travel: \(String(format: "%.0f", travel))°")
        }
        if let bearing = vehicle.impactBearingDegrees {
            lines.append("  Impact Bearing: \(String(format: "%.0f", bearing))°")
        }
        return lines
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

    // NOTE(AI Developer), added 2026-07 per Sean's explicit request ("can
    // we show analysed results in the PDF? We need to show that we did
    // something with the images in the report, not just show the
    // pictures uploaded"). Draws the actual Vision-detected damage
    // contour outline (persisted at analysis time as `MatchResult
    // .victimContourOverlay`/`suspectContourOverlay` -- see
    // `MatchScoreCalculator.evaluate()` and `DeformationMatcher
    // .DeformationResult`) directly over the real damage photo it was
    // traced from. This NEVER re-runs Vision here -- it only reads
    // already-persisted points -- because `AnalysisViewModel
    // .generateReport()` calls this generator synchronously, and
    // re-running `VNDetectContoursRequest` on the main thread at
    // PDF-render time would risk exactly the kind of hang/OOM incident
    // Sean has already hit twice on this pipeline (see that file's
    // other NOTEs). Silently skips a vehicle whose overlay/source photo
    // isn't available, and skips the whole page if neither vehicle has
    // one, rather than showing a blank/misleading page.
    private func drawAnalysisEvidence(ctx: UIGraphicsPDFRendererContext, rect: CGRect, case c: ForensicCase) {
        guard let result = c.matchResult else { return }
        let victimPair = overlayImagePair(overlay: result.victimContourOverlay, vehicle: c.victimVehicle)
        let suspectPair = c.suspectVehicle.flatMap { overlayImagePair(overlay: result.suspectContourOverlay, vehicle: $0) }
        guard victimPair != nil || suspectPair != nil else { return }

        ctx.beginPage()
        var y: CGFloat = 50
        "Analysis Evidence".draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 20))
        y += 22
        "Vision-detected damage boundary overlaid on the source photo it was traced from."
            .draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 11), maxWidth: rect.width - 100, color: .darkGray)
        y += 30

        let deformFactor = result.factors.first { $0.factor == .deformationPattern }
        let cellWidth: CGFloat = 240
        let cellHeight: CGFloat = 240
        var x: CGFloat = 50

        for (label, pair) in [("Victim Vehicle", victimPair), ("Suspect Vehicle", suspectPair)] {
            guard let (image, overlay) = pair else { continue }
            let imgRect = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
            image.draw(in: imgRect)
            drawContourOverlay(overlay, in: imgRect)
            label.draw(at: CGPoint(x: x, y: y + cellHeight + 6), font: .boldSystemFont(ofSize: 12))
            x += cellWidth + 24
        }
        y += cellHeight + 30

        if let f = deformFactor {
            "Deformation Pattern factor: raw \(String(format: "%.1f", f.rawScore)) / 100"
                .draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 12))
            y += 18
            f.notes.draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 11), maxWidth: rect.width - 100)
        }
    }

    /// Looks up the source `CapturedPhoto` an overlay was traced from and
    /// decodes it as a `UIImage` for drawing. Returns `nil` (never a
    /// fabricated placeholder) if the overlay is missing or its source
    /// photo can no longer be found/decoded.
    private func overlayImagePair(overlay: ContourOverlay?, vehicle: Vehicle) -> (UIImage, ContourOverlay)? {
        guard let overlay,
              let photo = vehicle.photos.first(where: { $0.id == overlay.sourcePhotoID }),
              let image = UIImage(data: photo.imageData) else { return nil }
        return (image, overlay)
    }

    /// Draws Vision's detected contour boundary as a highlighted outline
    /// on top of `imageRect`. NOTE(AI Developer): Vision's
    /// `normalizedPoints` are in a bottom-left-origin 0-1 coordinate
    /// space, but `UIGraphicsPDFRenderer`/`CGContext` here use a
    /// top-left-origin space (matching where `image.draw(in:)` places
    /// the pixel at y=0) — the Y axis MUST be flipped
    /// (`1 - normalizedPoint.y`) or the outline is drawn upside-down
    /// relative to the photo. See `ContourOverlay.normalizedPoints`'s
    /// doc comment for the same warning.
    private func drawContourOverlay(_ overlay: ContourOverlay, in imageRect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), overlay.normalizedPoints.count > 2 else { return }
        ctx.saveGState()
        let path = UIBezierPath()
        for (i, p) in overlay.normalizedPoints.enumerated() {
            let flippedY = 1 - p.y
            let pt = CGPoint(
                x: imageRect.minX + p.x * imageRect.width,
                y: imageRect.minY + flippedY * imageRect.height
            )
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.close()
        UIColor.systemRed.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 2.5
        path.stroke()
        ctx.restoreGState()
    }

    // NOTE(AI Developer), added 2026-07 for the Scar-Direction
    // Consistency feature -- PDF counterpart to `MatchResultsView
    // .scarDirectionSection`. Deliberately kept off the composite score
    // (mirrors `MatchScoreCalculator`'s "never blended into `factors`"
    // rule) — purely presents `MatchResult.scarDirectionCheck` plus a
    // prominent callout when `suspectExclusionReason` fires. Skipped
    // entirely (no blank page) when no scar-direction check exists.
    private func drawScarDirectionSection(ctx: UIGraphicsPDFRendererContext, rect: CGRect, case c: ForensicCase) {
        guard let check = c.matchResult?.scarDirectionCheck else { return }

        ctx.beginPage()
        var y: CGFloat = 50
        "Scar-Direction Consistency".draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 20))
        y += 34

        if let reason = c.matchResult?.suspectExclusionReason {
            let boxRect = CGRect(x: 50, y: y, width: rect.width - 100, height: 60)
            let path = UIBezierPath(roundedRect: boxRect, cornerRadius: 8)
            UIColor.systemRed.withAlphaComponent(0.12).setFill()
            path.fill()
            "EXCLUSION WARNING".draw(at: CGPoint(x: boxRect.minX + 12, y: boxRect.minY + 8),
                                       font: .boldSystemFont(ofSize: 12), color: .systemRed)
            reason.draw(at: CGPoint(x: boxRect.minX + 12, y: boxRect.minY + 26),
                        font: .systemFont(ofSize: 11), maxWidth: boxRect.width - 24, color: .darkGray)
            y += 76
        }

        let statusText: String
        switch check.status {
        case .consistent: statusText = "Status: Consistent"
        case .inconsistent: statusText = "Status: Conflict Detected"
        case .notDeterminable: statusText = "Status: Not Determinable"
        }
        statusText.draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 14))
        y += 22

        if let narrative = check.scenarioNarrative {
            narrative.draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 12), maxWidth: rect.width - 100)
            y += 40
        }
        if let vDesc = check.victimMotionDescription {
            "Victim: \(vDesc)".draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 11), maxWidth: rect.width - 100)
            y += 18
        }
        if let sDesc = check.suspectMotionDescription {
            "Suspect: \(sDesc)".draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 11), maxWidth: rect.width - 100)
            y += 18
        }
        if let delta = check.reciprocityDeltaDegrees {
            String(format: "Reciprocity deviation: %.1f°", delta)
                .draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 11), color: .darkGray)
            y += 18
        }
        if !check.notes.isEmpty {
            check.notes.draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 10), maxWidth: rect.width - 100, color: .darkGray)
        }
    }

    // NOTE(AI Developer), added 2026-07 for Sean's Answer B2 ("use
    // already-recorded scar data... to show victim vs. suspect scar line
    // length/angle/position side-by-side with a computed match/deviation
    // number, in both MatchResultsView and the PDF"). PDF counterpart to
    // `MatchResultsView.scarLineComparisonSection` -- builds the exact
    // same `ScarLineComparison` value the same way (via
    // `ScarLineComparison.build(victim:suspect:check:)`) so the on-screen
    // and PDF presentations of this data can't silently drift apart.
    // Skipped entirely (no blank page) when there's no suspect vehicle or
    // neither vehicle has a marked scar line.
    private func drawScarLineComparison(ctx: UIGraphicsPDFRendererContext, rect: CGRect, case c: ForensicCase) {
        guard let suspect = c.suspectVehicle else { return }
        let comparison = ScarLineComparison.build(victim: c.victimVehicle, suspect: suspect, check: c.matchResult?.scarDirectionCheck)
        guard comparison.hasAnyData else { return }

        ctx.beginPage()
        var y: CGFloat = 50
        "Scar Line Comparison".draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 20))
        y += 26
        "In-photo length/angle have no shared scale between the two photos and are shown for reference only. Position is the scar-verified compass bearing used for actual scoring."
            .draw(at: CGPoint(x: 50, y: y), font: .italicSystemFont(ofSize: 10), maxWidth: rect.width - 100, color: .darkGray)
        y += 32

        let columnWidth = (rect.width - 100 - 30) / 2
        let leftX: CGFloat = 50
        let rightX: CGFloat = 50 + columnWidth + 30
        let startY = y

        func drawColumn(title: String, side: ScarLineComparison.VehicleSide, x: CGFloat) -> CGFloat {
            var cy = startY
            title.draw(at: CGPoint(x: x, y: cy), font: .boldSystemFont(ofSize: 13))
            cy += 18
            if side.hasLine {
                if let length = side.lengthNormalized {
                    String(format: "Length: %.2f (normalized)", length)
                        .draw(at: CGPoint(x: x, y: cy), font: .systemFont(ofSize: 11), maxWidth: columnWidth)
                    cy += 16
                }
                if let angle = side.angleInPhotoDegrees {
                    String(format: "In-photo angle: %.0f°", angle)
                        .draw(at: CGPoint(x: x, y: cy), font: .systemFont(ofSize: 11), maxWidth: columnWidth)
                    cy += 16
                }
                if let bearing = side.scarBearingDegrees {
                    String(format: "Position (bearing): %.0f°", bearing)
                        .draw(at: CGPoint(x: x, y: cy), font: .systemFont(ofSize: 11), maxWidth: columnWidth)
                    cy += 16
                }
                if let motion = side.motionDescription {
                    motion.draw(at: CGPoint(x: x, y: cy), font: .systemFont(ofSize: 10), maxWidth: columnWidth, color: .darkGray)
                    cy += 28
                }
            } else {
                "No scar line marked".draw(at: CGPoint(x: x, y: cy), font: .systemFont(ofSize: 11), color: .darkGray)
                cy += 16
            }
            return cy
        }

        let leftEndY = drawColumn(title: "Victim", side: comparison.victim, x: leftX)
        let rightEndY = drawColumn(title: "Suspect", side: comparison.suspect, x: rightX)
        y = max(leftEndY, rightEndY) + 12

        if let delta = comparison.reciprocityDeltaDegrees {
            String(format: "Deviation from a perfect reciprocal match: %.1f°", delta)
                .draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 12))
            y += 20
        }
        if let narrative = comparison.scenarioNarrative {
            narrative.draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 11), maxWidth: rect.width - 100, color: .darkGray)
        }
    }

    // NOTE(AI Developer), added 2026-07 for the fingerprint-style Scar
    // Matching feature -- PDF counterpart to `MatchResultsView
    // .scarFingerprintSection`. Reads `MatchResult.scarFingerprintMatch`
    // directly (computed once at analysis time by `MatchScoreCalculator
    // .evaluate()`, never recomputed here) so the on-screen and PDF
    // presentations can't drift apart. Skipped entirely (no blank page)
    // when no fingerprint-match result exists at all (a `MatchResult`
    // from before this feature existed) -- but still renders a page for
    // the determinable-but-empty case, same "explain why not" principle
    // as `drawScarDirectionSection`.
    private func drawScarFingerprintMatch(ctx: UIGraphicsPDFRendererContext, rect: CGRect, case c: ForensicCase) {
        guard let match = c.matchResult?.scarFingerprintMatch else { return }

        ctx.beginPage()
        var y: CGFloat = 50
        "Scar Fingerprint Matching".draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 20))
        y += 26
        "Identifies isolated markings (paint-density or width peaks) along each vehicle's scar line -- like comparing individual fingerprint ridge points -- and matches them by position and type."
            .draw(at: CGPoint(x: 50, y: y), font: .italicSystemFont(ofSize: 10), maxWidth: rect.width - 100, color: .darkGray)
        y += 30

        if let score = match.matchScorePercent {
            String(format: "%.0f%% Marking Match", score)
                .draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 16))
            y += 24
        }
        match.summary.draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 12), maxWidth: rect.width - 100)
        y += 34

        let columnWidth = (rect.width - 100 - 30) / 2
        let leftX: CGFloat = 50
        let rightX: CGFloat = 50 + columnWidth + 30
        let startY = y

        func drawMinutiaeColumn(title: String, minutiae: [ScarMinutia], matchedIDs: Set<UUID>, x: CGFloat) -> CGFloat {
            var cy = startY
            "\(title) (\(minutiae.count))".draw(at: CGPoint(x: x, y: cy), font: .boldSystemFont(ofSize: 12))
            cy += 16
            if minutiae.isEmpty {
                "No isolated markings found".draw(at: CGPoint(x: x, y: cy), font: .systemFont(ofSize: 10), color: .darkGray)
                cy += 14
            } else {
                for m in minutiae {
                    let typeLabel = m.type == .densityPeak ? "Density mark" : "Width mark"
                    let marker = matchedIDs.contains(m.id) ? "[matched]" : "[unmatched]"
                    String(format: "%@ @ %.0f%% %@", typeLabel, m.positionAlongLine * 100, marker)
                        .draw(at: CGPoint(x: x, y: cy), font: .systemFont(ofSize: 10),
                              maxWidth: columnWidth, color: matchedIDs.contains(m.id) ? .systemGreen : .darkGray)
                    cy += 14
                }
            }
            return cy
        }

        let victimMatchedIDs = Set(match.matchedPairs.map { $0.victimMinutia.id })
        let suspectMatchedIDs = Set(match.matchedPairs.map { $0.suspectMinutia.id })
        let leftEndY = drawMinutiaeColumn(title: "Victim", minutiae: match.victimMinutiae, matchedIDs: victimMatchedIDs, x: leftX)
        let rightEndY = drawMinutiaeColumn(title: "Suspect", minutiae: match.suspectMinutiae, matchedIDs: suspectMatchedIDs, x: rightX)
        _ = max(leftEndY, rightEndY)
    }

    // NOTE(AI Developer), added 2026-07 for the tool-mark/striation
    // matching feature -- PDF counterpart to `MatchResultsView
    // .toolMarkSection`. Reads `MatchResult.toolMarkComparison` directly
    // (computed once at analysis time by `MatchScoreCalculator
    // .evaluate()`, never recomputed here) so the on-screen and PDF
    // presentations can't drift apart. Skipped entirely (no blank page)
    // when no tool-mark result exists at all (a `MatchResult` from
    // before this feature existed) -- but still renders a page for the
    // determinable-but-inconclusive case, same "explain why not"
    // principle as `drawScarFingerprintMatch`.
    private func drawToolMarkComparison(ctx: UIGraphicsPDFRendererContext, rect: CGRect, case c: ForensicCase) {
        guard let comparison = c.matchResult?.toolMarkComparison else { return }

        ctx.beginPage()
        var y: CGFloat = 50
        "Tool-Mark / Striation Matching".draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 20))
        y += 26
        "Looks across each scar's width for fine parallel scratch/gouge lines (tooling marks) and compares the spacing rhythm between them -- independent of photo distance, angle, or zoom, and checked in both normal and mirrored order to account for a victim/suspect stamp-and-impression relationship."
            .draw(at: CGPoint(x: 50, y: y), font: .italicSystemFont(ofSize: 10), maxWidth: rect.width - 100, color: .darkGray)
        y += 40

        if let score = comparison.matchScorePercent, let orientation = comparison.orientationUsed {
            String(format: "%.0f%% Striation Rhythm Match", score)
                .draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 16))
            y += 20
            let orientationLine = orientation == .reversed
                ? "Best alignment found in reverse order (stamp/impression pair)"
                : "Best alignment found in the same order on both vehicles"
            orientationLine.draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 10), color: .darkGray)
            y += 18
        }
        comparison.summary.draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 12), maxWidth: rect.width - 100)
        y += 34

        let columnWidth = (rect.width - 100 - 30) / 2
        let leftX: CGFloat = 50
        let rightX: CGFloat = 50 + columnWidth + 30
        let startY = y

        func drawProfileColumn(title: String, profile: StriationProfile, x: CGFloat) -> CGFloat {
            var cy = startY
            "\(title) (\(profile.crossSections.count) probes)".draw(at: CGPoint(x: x, y: cy), font: .boldSystemFont(ofSize: 12))
            cy += 16
            if !profile.isDeterminable {
                "Not enough striation detail found".draw(at: CGPoint(x: x, y: cy), font: .systemFont(ofSize: 10), color: .darkGray)
                cy += 14
            } else {
                for cs in profile.crossSections {
                    String(format: "%.0f%%: %d marks found", cs.positionAlongLine * 100, cs.peakCount)
                        .draw(at: CGPoint(x: x, y: cy), font: .systemFont(ofSize: 10), maxWidth: columnWidth, color: .darkGray)
                    cy += 14
                }
            }
            return cy
        }

        let leftEndY2 = drawProfileColumn(title: "Victim", profile: comparison.victimProfile, x: leftX)
        let rightEndY2 = drawProfileColumn(title: "Suspect", profile: comparison.suspectProfile, x: rightX)
        _ = max(leftEndY2, rightEndY2)
    }

    private func drawPhotoEvidence(ctx: UIGraphicsPDFRendererContext, rect: CGRect, case c: ForensicCase) {
        let allPhotos = c.victimVehicle.photos + (c.suspectVehicle?.photos ?? [])
        let usable = allPhotos.filter { $0.isUsable }.prefix(8)
        let skipped = skippedShotLines(for: c)
        guard !usable.isEmpty || !skipped.isEmpty else { return }

        ctx.beginPage()
        var y: CGFloat = 50
        "Photo Evidence".draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 20))
        y += 30

        var x: CGFloat = 50
        let cellSize: CGFloat = 240
        for photo in usable {
            guard let img = UIImage(data: photo.imageData) else { continue }
            img.draw(in: CGRect(x: x, y: y, width: cellSize, height: cellSize * 0.75))
            // NOTE(AI Developer), added 2026-07 alongside camera-roll
            // import (Sean's request): imported photos show "Imported"
            // instead of a quality label, since `qualityScore` is not a
            // real measurement for them (see `CapturedPhoto.wasImported`)
            // -- printing "(Q: Poor)" on a photo we never actually scored
            // would misrepresent the evidence.
            let qualitySuffix = photo.wasImported ? "Imported" : "Q: \(photo.qualityLabel.rawValue)"
            let label = "\(photo.photoType.displayName) (\(qualitySuffix))"
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

        // NOTE(AI Developer), added 2026-07 per Sean's explicit answer on
        // skipped-shot messaging ("Shot X was skipped: not available").
        // Mirrors `AnalysisViewModel.skippedShotsSummary`'s exact wording
        // so the PDF report and the in-app Results screen never disagree.
        // `PDFReportGenerator` works directly off `ForensicCase` rather
        // than through the view model, so the same derivation is
        // duplicated here against `Vehicle.skippedShotIndices`.
        if !skipped.isEmpty {
            if x != 50 { x = 50; y += cellSize * 0.75 + 40 }
            if y > rect.height - 100 {
                ctx.beginPage()
                y = 50
            }
            "Skipped Shots".draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 14))
            y += 22
            for line in skipped {
                if y > rect.height - 60 {
                    ctx.beginPage()
                    y = 50
                }
                line.draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 11), maxWidth: rect.width - 100)
                y += 16
            }
        }
    }

    /// Produces "Shot X was skipped: not available" lines for both
    /// vehicles, in the same format as `AnalysisViewModel.skippedShotsSummary`.
    private func skippedShotLines(for c: ForensicCase) -> [String] {
        let protocolShots = PhotoType.requiredCaptureProtocol
        func describe(_ vehicle: Vehicle, roleLabel: String) -> [String] {
            vehicle.skippedShotIndices.sorted().compactMap { index in
                guard index < protocolShots.count else { return nil }
                let type = protocolShots[index]
                return "\(roleLabel) — Shot \(index + 1) (\(type.displayName)) was skipped: not available"
            }
        }
        var lines = describe(c.victimVehicle, roleLabel: "Victim")
        if let suspect = c.suspectVehicle {
            lines += describe(suspect, roleLabel: "Suspect")
        }
        return lines
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
