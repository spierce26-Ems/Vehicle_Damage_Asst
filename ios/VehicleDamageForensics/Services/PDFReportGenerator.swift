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
                drawAlgorithmProvenance(ctx: ctx, rect: pageRect, case: forensicCase)
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

        // NOTE(AI Developer), added 2026-09: algorithm version on the
        // cover, immediately under the score it produced. Placed here
        // for the same reason the disclaimer is boxed here -- if pages
        // are later split apart, the page carrying the headline number
        // must also carry the statement of which math produced it. The
        // full constant list goes on its own page (see
        // `drawAlgorithmProvenance`).
        if c.matchResult != nil {
            let versionLine = c.matchResult?.algorithmVersionDisplay ?? ""
            versionLine.drawCenter(in: rect, y: 396, font: .systemFont(ofSize: 11))
        }

        // NOTE(AI Developer): Required disclaimer callout per Sean's
        // decision — placed on the cover page, boxed, so it cannot be missed
        // or separated from the report if pages are later split apart.
        drawDisclaimerBox(rect: rect, y: 430)

        // NOTE(AI Developer), added 2026-09 for item #5 (duplicate case
        // for another suspect). Disclosed on the COVER, by the same
        // reasoning that puts the disclaimer here: the PDF is the
        // artifact that leaves the device and gets handed to an insurer,
        // an officer, or a court, and a reader comparing two reports for
        // two suspects must be able to see that they rest on one shared
        // set of victim-vehicle photographs. If this fact only lived in
        // the audit-log page it could be separated from the score it
        // qualifies.
        // NOTE(AI Developer), added 2026-09 for task #11. The examiner
        // on the cover, where the case number and generation date
        // already are -- a reader must not have to reach the custody
        // page to learn who documented the case. Omitted entirely when
        // unrecorded rather than printing an empty label: the explicit
        // "no attestation" statement lives in the Attestation block, so
        // stating it twice would read as an accusation rather than a
        // fact.
        if let attestation = c.attestationSummary {
            ("Documented by: " + attestation)
                .drawCenter(in: rect, y: 268, font: .systemFont(ofSize: 12))
        }

        if c.sourceCaseID != nil {
            "Note: the victim-vehicle photographs in this case were duplicated from another case documenting the same incident against a different suspect vehicle. Results across those cases are not independent — see the Chain of Custody page."
                .draw(at: CGPoint(x: 50, y: 574), font: .italicSystemFont(ofSize: 10),
                      maxWidth: rect.width - 100, color: .darkGray)
        }
    }

    /// Draws `MatchResult.disclaimerText` inside a bordered box.
    /// NOTE(AI Developer), measured 2026-09-07 (task #12 tail). This box was
    /// a literal `height: 130` with its body at +32 -- the second unmeasured
    /// frame in this file, found by Ledger while verifying the first. It fits
    /// `MatchResult.disclaimerText` today at 520 characters (about six lines
    /// at 10pt, ~72pt in ~86pt of body space), so it was not clipping; it was
    /// one edit of locked copy away from clipping, with nothing to say so.
    ///
    /// Measured rather than left as a near-miss, because a near-miss and an
    /// overrun are the same defect at different content lengths, and this is
    /// the one piece of report copy whose truncation is a liability rather
    /// than an inconvenience: it is what stops the document reading as a
    /// certified forensic identification. A clipped disclaimer is a report
    /// that claims more than the algorithm can support.
    ///
    /// The box now grows to its content, so a longer disclaimer moves the
    /// frame instead of falling out of it. Returns nothing -- the cover
    /// page's layout is absolute.
    ///
    /// ONE CONSEQUENCE, recorded because measuring changed the failure
    /// mode rather than removing it. The cover DOES draw below this box:
    /// the duplicated-case note sits at a literal `y: 574`, and this box
    /// is drawn at `y: 430`, so it has 144pt of headroom. Today's text
    /// renders in about 120pt, which is why nothing collides. But the box
    /// now GROWS where the literal used to clip, so a disclaimer past
    /// roughly 144pt would overlap that note instead of falling out of
    /// its own frame. That is the better failure -- an overlap is visible
    /// on the page and a truncation is not -- and it is deliberately not
    /// "fixed" here, because the honest fix is a flow layout for the
    /// cover's fixed y-offsets, which is a separate diff. The measurement
    /// converted a silent clip into a visible collision; it did not make
    /// the cover safe for arbitrary copy.
    private func drawDisclaimerBox(rect: CGRect, y: CGFloat) {
        let bodyFont = UIFont.systemFont(ofSize: 10)
        let bodyWidth = rect.width - 100 - 32
        let bodyHeight = ceil(
            (MatchResult.disclaimerText as NSString).boundingRect(
                with: CGSize(width: bodyWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: bodyFont],
                context: nil
            ).height
        )
        let boxRect = CGRect(x: 50, y: y, width: rect.width - 100,
                             height: 32 + bodyHeight + 16)
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
            font: bodyFont,
            maxWidth: bodyWidth,
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
            y += drawWrapping(line, at: CGPoint(x: 50, y: y),
                              font: .systemFont(ofSize: 12), maxWidth: rect.width - 100) + 3
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
            y += drawWrapping(f.notes, at: CGPoint(x: 60, y: y),
                              font: .systemFont(ofSize: 11), maxWidth: rect.width - 120) + 23
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

        // NOTE(AI Developer), 2026-09-07 (task #12 follow-up). This is the
        // THIRD render site of `suspectExclusionReason` -- the other two are
        // `MatchResultsView.exclusionBanner` and its `scarDirectionSection`
        // copy -- and it was the last one still asserting an exclusion the
        // string may deny. It drew a red-filled box headed "EXCLUSION
        // WARNING" over every one of the three strings
        // `evaluateExclusionRule()` can return, including the task #14
        // LiDAR path, whose text says the difference CANNOT be resolved
        // from these photographs and to re-measure with a tape. A red box
        // captioned EXCLUSION WARNING over "this cannot be resolved" is the
        // same false exclusion the rejected fixed heading would have
        // shipped, and here it is a heading AND a colour AND a fill.
        //
        // Worse than either screen render, because this one is the paid,
        // shareable, printable artefact -- the copy that leaves the app and
        // is read by someone who cannot scroll to the string's own graded
        // consequence for context.
        //
        // The rule this closes: a duplicated string is only an invariant if
        // every render carries the same claim. Two sites were audited this
        // round and fixed; the count was never two. When a value is read in
        // more than one place, enumerate its render sites FROM THE CODE --
        // `grep` the symbol, do not recall the list.
        //
        // Neutral treatment matching both screen renders: no fill, a hairline
        // rule, and a heading that describes the section rather than
        // asserting its outcome. The string supplies the finding.
        if let reason = c.matchResult?.suspectExclusionReason {
            // The box is MEASURED, not fixed. At 60pt tall with the body
            // starting 26pt down, this box held ~2 lines at 11pt; the three
            // strings `evaluateExclusionRule()` returns measure 249, 470
            // and 235 characters from their format templates -- roughly
            // three, six and three lines at this width, before the
            // measured heights and the reciprocity delta are substituted
            // in. The WORST case is the LiDAR-inconclusive path, not the
            // combined rule (which is the shortest of the three), and it
            // is the path that DENIES an exclusion -- so a clip there
            // leaves a correctly neutral box that still reads as a
            // finding, which is the defect the neutral treatment was
            // chosen to prevent, arriving by truncation instead of
            // colour.
            // Every one of them overran, and the longest by ~45pt into the
            // status line drawn below. The red fill hid it; a hairline
            // border does not, which is how it surfaced. A frame that
            // cannot fit the real string is a layout defect, never a
            // licence to shorten locked copy -- and here the string IS the
            // finding, so a clipped exclusion is a missing one.
            let bodyFont = UIFont.systemFont(ofSize: 11)
            let bodyWidth = rect.width - 100 - 24
            let bodyHeight = ceil(
                (reason as NSString).boundingRect(
                    with: CGSize(width: bodyWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: bodyFont],
                    context: nil
                ).height
            )
            let boxRect = CGRect(x: 50, y: y, width: rect.width - 100,
                                 height: 26 + bodyHeight + 12)
            let path = UIBezierPath(roundedRect: boxRect, cornerRadius: 8)
            UIColor.systemGray6.setFill()
            path.fill()
            UIColor.systemGray3.setStroke()
            path.lineWidth = 1
            path.stroke()
            "RULE-OUT ASSESSMENT".draw(at: CGPoint(x: boxRect.minX + 12, y: boxRect.minY + 8),
                                       font: .boldSystemFont(ofSize: 12), color: .darkGray)
            reason.draw(at: CGPoint(x: boxRect.minX + 12, y: boxRect.minY + 26),
                        font: bodyFont, maxWidth: bodyWidth, color: .darkGray)
            y += boxRect.height + 16
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
            y += drawWrapping(narrative, at: CGPoint(x: 50, y: y),
                              font: .systemFont(ofSize: 12), maxWidth: rect.width - 100) + 25
        }
        if let vDesc = check.victimMotionDescription {
            y += drawWrapping("Victim: \(vDesc)", at: CGPoint(x: 50, y: y),
                              font: .systemFont(ofSize: 11), maxWidth: rect.width - 100) + 5
        }
        if let sDesc = check.suspectMotionDescription {
            y += drawWrapping("Suspect: \(sDesc)", at: CGPoint(x: 50, y: y),
                              font: .systemFont(ofSize: 11), maxWidth: rect.width - 100) + 5
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
                    // NOTE(AI Developer), 2026-09-07 (task #12 tail). The one
                    // LIVE overrun in the pairing residue. These are the same
                    // two sentences `scoreScarDirectionConsistency` puts in
                    // `victimMotionDescription`/`suspectMotionDescription`,
                    // which were converted on the wide single-column page --
                    // but here they render in a HALF-WIDTH column, where 99
                    // and 94 characters at 10pt take about three lines and
                    // two against an advance of 28. The FORWARD form overran;
                    // REVERSING did not. The sentence is fixed; the COLUMN is
                    // what makes it wrap, which is why following the string
                    // rather than the pairing missed it.
                    cy += drawWrapping(motion, at: CGPoint(x: x, y: cy),
                                       font: .systemFont(ofSize: 10),
                                       maxWidth: columnWidth, color: .darkGray) + 8
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

        // NOTE(AI Developer), rewritten 2026-09 for the "no bare match
        // %" rule -- PDF counterpart to `MatchResultsView
        // .scarFingerprintSection`'s change. A bold "83% Marking Match"
        // line in an exported document is worse than the same thing
        // on screen: the PDF outlives the app session, gets attached to
        // an investigation file, and gets read by people who never saw
        // the qualifying sentence underneath. The headline now always
        // carries the p-value and the chance verdict.
        // NOTE(AI Developer), 2026-09-07 (task #12 tail): literal `y += 30`
        // on a headline whose length moves with `pValueDisplay` and a trial
        // count nobody has run. Not overrunning today, which is exactly the
        // near-miss case -- a margin nobody measures is not a margin anyone
        // is maintaining.
        if let headline = match.headlineDisplay {
            y += drawWrapping(headline, at: CGPoint(x: 50, y: y),
                              font: .boldSystemFont(ofSize: 14),
                              maxWidth: rect.width - 100) + 10
        }
        y += drawWrapping(match.summary, at: CGPoint(x: 50, y: y),
                          font: .systemFont(ofSize: 12), maxWidth: rect.width - 100) + 19

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

        // NOTE(AI Developer), rewritten 2026-09 -- same change and
        // same reasoning as `drawScarFingerprintMatch` above.
        // Same pairing and same reason as `drawScarFingerprintMatch` above.
        if let headline = comparison.headlineDisplay {
            y += drawWrapping(headline, at: CGPoint(x: 50, y: y),
                              font: .boldSystemFont(ofSize: 14),
                              maxWidth: rect.width - 100) + 10
        }
        if let orientation = comparison.orientationUsed {
            let orientationLine = orientation == .reversed
                ? "Best alignment found in reverse order (stamp/impression pair)"
                : "Best alignment found in the same order on both vehicles"
            orientationLine.draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 10), color: .darkGray)
            y += 18
        }
        y += drawWrapping(comparison.summary, at: CGPoint(x: 50, y: y),
                          font: .systemFont(ofSize: 12), maxWidth: rect.width - 100) + 19

        let columnWidth = (rect.width - 100 - 30) / 2
        let leftX: CGFloat = 50
        let rightX: CGFloat = 50 + columnWidth + 30
        let startY = y

        // NOTE(AI Developer), reworked 2026-09 for item #4 of Sean's
        // 5-item plan: an excluded probe is still PRINTED, marked as
        // excluded with its stated reason, rather than omitted. A report
        // that silently dropped the data an examiner chose to ignore
        // would be actively misleading -- the reader must be able to see
        // what was set aside and judge that decision for themselves.
        func drawProfileColumn(title: String, role: VehicleRole, profile: StriationProfile, x: CGFloat) -> CGFloat {
            var cy = startY
            let excluded = comparison.excludedIDs(for: role)
            let keptCount = profile.crossSections.filter { !excluded.contains($0.id) }.count
            let header = excluded.isEmpty
                ? "\(title) (\(profile.crossSections.count) probes)"
                : "\(title) (\(keptCount) of \(profile.crossSections.count) probes used)"
            header.draw(at: CGPoint(x: x, y: cy), font: .boldSystemFont(ofSize: 12))
            cy += 16
            if !profile.isDeterminable {
                "Not enough striation detail found".draw(at: CGPoint(x: x, y: cy), font: .systemFont(ofSize: 10), color: .darkGray)
                cy += 14
            } else {
                for cs in profile.crossSections {
                    let isExcluded = excluded.contains(cs.id)
                    let base = String(format: "%.0f%%: %d marks found", cs.positionAlongLine * 100, cs.peakCount)
                    let line = isExcluded ? "[EXCLUDED] " + base : base
                    line.draw(at: CGPoint(x: x, y: cy), font: .systemFont(ofSize: 10),
                              maxWidth: columnWidth, color: isExcluded ? .orange : .darkGray)
                    cy += 14
                    if isExcluded,
                       let reason = comparison.exclusions.first(where: {
                           $0.crossSectionID == cs.id && $0.vehicleRole == role
                       })?.reason {
                        // NOTE(AI Developer), 2026-09-07 (task #12 tail).
                        // `StriationExclusion.reason` is FREE EXAMINER TEXT
                        // -- the sheet's field is `axis: .vertical`,
                        // `lineLimit(2...4)`, validated only for
                        // non-emptiness -- so no arithmetic of ours can
                        // settle this pair's fit, and a literal 12pt
                        // advance is wrong at some length whatever estimate
                        // you use. Measuring is the FLOOR, not the fix: a
                        // real bound belongs at the input, which is Sean's
                        // call. Worth the floor regardless, because this is
                        // the page read by opposing counsel and an
                        // examiner's stated reason for excluding evidence
                        // must not silently overlap the next probe row.
                        cy += drawWrapping("    Reason: " + reason,
                                           at: CGPoint(x: x, y: cy),
                                           font: .italicSystemFont(ofSize: 9),
                                           maxWidth: columnWidth, color: .orange) + 3
                    }
                }
            }
            return cy
        }

        let leftEndY2 = drawProfileColumn(title: "Victim", role: .victim, profile: comparison.victimProfile, x: leftX)
        let rightEndY2 = drawProfileColumn(title: "Suspect", role: .suspect, profile: comparison.suspectProfile, x: rightX)
        y = max(leftEndY2, rightEndY2) + 18

        // NOTE(AI Developer), added 2026-09 for item #4: Sean's brief
        // required exports to show BOTH the full and the filtered score.
        // The filtered block is rendered AFTER (and visually subordinate
        // to) the full score above, with its own recomputed chance
        // baseline -- see `ToolMarkFilteredOutcome`'s doc comment for
        // why the baseline must be recomputed rather than inherited.
        guard comparison.hasExclusions else { return }

        "Filtered Result — Investigator Exclusions Applied"
            .draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 14), color: .orange)
        y += 20
        if let outcome = comparison.filteredOutcome, let score = outcome.matchScorePercent {
            String(format: "%.0f%% filtered striation rhythm match (full, unfiltered score above remains the primary result)", score)
                .draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 12),
                      maxWidth: rect.width - 100, color: .orange)
            y += 20
        }
        if let filteredSummary = comparison.filteredSummary {
            y += drawWrapping(filteredSummary, at: CGPoint(x: 50, y: y),
                              font: .systemFont(ofSize: 11), maxWidth: rect.width - 100) + 35
        }
        "Exclusions recorded for this comparison:".draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 11))
        y += 16
        // NOTE(AI Developer), 2026-09: each row prints the exclusion,
        // its stated reason, and the DERIVED decision ordering -- all
        // in the same neutral colour. Per Ledger's EVIDENCE_APPENDIX
        // sec.6.3 the report states the ordering and stops: no warning
        // icon, no colour, no ranking of the three states.
        for exclusion in comparison.exclusions {
            let stamp = DateFormatter.localizedString(from: exclusion.timestamp, dateStyle: .short, timeStyle: .short)
            // NOTE(AI Developer), 2026-09-07. `displaySummary`
            // (`ToolMarkAnalysis:665`) INTERPOLATES the same unbounded
            // `StriationExclusion.reason` as the per-probe draw on the
            // tool-mark page, and here it also carries a `(recorded <stamp>)`
            // suffix -- so an 80-character reason is already two lines
            // against a literal 14pt advance, destroying the ordering line
            // drawn directly below it.
            //
            // This is the accessor route, not the value route: grepping
            // `reason` finds the tool-mark draw and none of these. The
            // ordering line beneath it is fixed copy but shares the same `y`,
            // so it is measured too -- an overlap needs only one of the two
            // to be wrong.
            y += drawWrapping("• " + exclusion.displaySummary + " (recorded \(stamp))",
                              at: CGPoint(x: 50, y: y),
                              font: .systemFont(ofSize: 10),
                              maxWidth: rect.width - 100, color: .darkGray) + 2
            y += drawWrapping("    " + exclusion.orderingSummary(
                                  firstScoreDisplayedAt: comparison.firstScoreDisplayedAt),
                              at: CGPoint(x: 50, y: y),
                              font: .italicSystemFont(ofSize: 9),
                              maxWidth: rect.width - 100, color: .darkGray) + 2
        }
        y += 6
        "Each exclusion above was made by the investigator after reviewing the photographs, and is also recorded in this case's chain-of-custody audit log. Because the excluded probes were chosen after the full similarity figure was available, statistical significance is not established for a filtered subset; the unfiltered figure above was computed without any selection and is the more defensible of the two. Both are reported here so this result can be assessed independently."
            .draw(at: CGPoint(x: 50, y: y), font: .italicSystemFont(ofSize: 9),
                  maxWidth: rect.width - 100, color: .darkGray)
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
                y += drawWrapping(line, at: CGPoint(x: 50, y: y),
                                  font: .systemFont(ofSize: 11), maxWidth: rect.width - 100) + 3
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
            y += drawWrapping(line, at: CGPoint(x: 50, y: y),
                              font: .systemFont(ofSize: 12), maxWidth: rect.width - 100) + 3
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
            y += drawWrapping(line, at: CGPoint(x: 50, y: y),
                              font: .systemFont(ofSize: 10), maxWidth: rect.width - 100) + 3
            // NOTE(AI Developer), added 2026-09 for task #11 per the
            // Tech Lead: "an audit trail that records what happened but
            // not who did it is barely an audit trail." Printed for
            // EVERY entry, including the unattributed ones -- an
            // omitted attribution line would let a reader assume the
            // examiner named at the top of the page recorded every
            // event, which is precisely the inference this field exists
            // to stop being guesswork.
            // NOTE(AI Developer), 2026-09-07. THIRD member of the unbounded
            // free-text class, and the one not reachable from
            // `StriationExclusion.reason`: `attributionSummary` returns
            // `examinerName`, typed into `EditCaseSheet`'s "Examiner name"
            // TextField, which has no length bound either -- `.textContentType`
            // is a keyboard hint, not a limit. At a literal 13pt advance on
            // the custody page, a long name destroys the audit line below it.
            //
            // It was missed by every pass so far because the searches followed
            // ONE free-text value through its accessors. There are two
            // unbounded fields, not one, and the second reaches the page under
            // a name that shares no substring with it. The rule generalises:
            // enumerate the FREE-TEXT INPUTS, then find their draws -- going
            // the other way finds only the value you already knew about.
            //
            // Measured as the floor. The fix is a bound at the input, for both
            // fields, and that is Sean's call.
            y += drawWrapping("      Recorded by: " + entry.attributionSummary,
                              at: CGPoint(x: 50, y: y),
                              font: .systemFont(ofSize: 9),
                              maxWidth: rect.width - 100, color: .darkGray) + 2
        }

        drawAttestationBlock(ctx: ctx, rect: rect, case: c, y: &y)
    }

    // NOTE(AI Developer), added 2026-09 for task #11. The attestation
    // block, per the Tech Lead's ruling that it be built for the same
    // reason as the examiner identity fields: Ledger's evidence appendix
    // already renders capture notes as "the examiner attested", and an
    // unattributed attestation is weaker than none.
    //
    // Renders an explicit statement in BOTH directions. Per the
    // Designer's rule (adopted as general): specify omission rather
    // than leaving blank lines, because a blank examiner line reads as
    // an unsigned report -- a worse artefact than an obviously
    // incomplete one. So an unrecorded examiner prints a sentence
    // saying so, never an empty signature rule.
    private func drawAttestationBlock(
        ctx: UIGraphicsPDFRendererContext,
        rect: CGRect,
        case c: ForensicCase,
        y: inout CGFloat
    ) {
        if y > rect.height - 200 {
            ctx.beginPage()
            y = 50
        }
        y += 20
        "Attestation".draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 14))
        y += 22

        if let examiner = c.examiner, examiner.hasAnyDetail {
            "The person named below documented this case using this application and attested to the capture conditions recorded in it."
                .draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 11), maxWidth: rect.width - 100)
            y += 32
            // Only the fields that exist are printed. A placeholder in
            // an attestation is a statement the app cannot support.
            if let name = examiner.name {
                ("Examiner: " + name).draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 12))
                y += 18
            }
            if let agency = examiner.agency {
                ("Agency: " + agency).draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 11))
                y += 16
            }
            if let badge = examiner.badgeNumber {
                ("Badge / ID: " + badge).draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 11))
                y += 16
            }
        } else {
            // The omission is stated outright rather than left as a
            // blank line -- see this method's header note.
            "No examiner identity was recorded for this case, so this report carries no attestation. The capture conditions recorded in it cannot be attributed to a named person."
                .draw(at: CGPoint(x: 50, y: y), font: .italicSystemFont(ofSize: 11),
                      maxWidth: rect.width - 100, color: .darkGray)
            y += 34
        }
    }

    // NOTE(AI Developer), added 2026-09 for the "trust the number" work
    // item. A dedicated provenance page listing the algorithm version
    // and every constant that produced this report's numbers.
    //
    // Why a whole page and not a footer line: the constants ARE the
    // meaning of the scores. A report read a year from now, after the
    // thresholds have moved, is uninterpretable without them, and
    // "check the git history of the app build the investigator happened
    // to have installed" is not a real answer for a document that may
    // be challenged. Printing them makes the artifact self-describing.
    //
    // Placed last, after chain of custody, because it is reference
    // material rather than findings. Rendered even for a legacy
    // unstamped result, where it states plainly that the version was
    // not recorded -- an investigator must be able to tell "produced
    // before stamping existed" apart from "stamp omitted".
    private func drawAlgorithmProvenance(ctx: UIGraphicsPDFRendererContext, rect: CGRect, case c: ForensicCase) {
        guard let result = c.matchResult else { return }

        ctx.beginPage()
        var y: CGFloat = 50
        "Analysis Provenance".draw(at: CGPoint(x: 50, y: y), font: .boldSystemFont(ofSize: 20))
        y += 28

        y += drawWrapping(result.algorithmVersionDisplay, at: CGPoint(x: 50, y: y),
                          font: .boldSystemFont(ofSize: 13), maxWidth: rect.width - 100) + 8

        y += drawWrapping("Analysis run: \(Self.dateFormatter.string(from: result.analysisDate))", at: CGPoint(x: 50, y: y),
                          font: .systemFont(ofSize: 11), maxWidth: rect.width - 100) + 5
        y += drawWrapping("Analysis ID: \(result.analysisID.uuidString)", at: CGPoint(x: 50, y: y),
                          font: .systemFont(ofSize: 10), maxWidth: rect.width - 100, color: .darkGray) + 14

        guard let version = result.algorithmVersion else {
            ("This result was produced before analysis version stamping was introduced, so the "
             + "thresholds and tolerances behind its scores are not recorded and cannot be "
             + "reconstructed from this document. Re-run the analysis on the current version of "
             + "the app to obtain a fully documented result.")
                .draw(at: CGPoint(x: 50, y: y), font: .systemFont(ofSize: 11), maxWidth: rect.width - 100)
            return
        }

        y += drawWrapping(("The values below were in force when this analysis ran and determine what its scores " + "mean. They are printed here so this report remains interpretable if the algorithm " + "changes later."), at: CGPoint(x: 50, y: y),
                          font: .italicSystemFont(ofSize: 10), maxWidth: rect.width - 100, color: .darkGray) + 22

        for constant in version.constants {
            if y > rect.height - 80 {
                ctx.beginPage()
                y = 50
            }
            y += drawWrapping("\(constant.name): \(constant.value)", at: CGPoint(x: 50, y: y),
                              font: .boldSystemFont(ofSize: 11), maxWidth: rect.width - 100) + 3
            y += drawWrapping(constant.explanation, at: CGPoint(x: 62, y: y),
                              font: .systemFont(ofSize: 10), maxWidth: rect.width - 124, color: .darkGray) + 14
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

/// Draws wrapping text and returns the height it actually consumed, so the
/// caller advances `y` by what was drawn rather than by a guessed line count.
///
/// NOTE(AI Developer), added 2026-09-07 (task #12 tail). `91c9d1c` measured
/// the rule-out callout box, which had assumed its content was two lines when
/// the three engine strings run 99, 235 and 715 characters. The defect was
/// never that box: it is a PAIRING -- a wrapping draw
/// (`String.draw(at:font:maxWidth:color:)`, which wraps to as many lines as
/// the content needs and reports nothing back) followed by a LITERAL `y +=`,
/// which encodes a line count the author guessed.
///
/// Grepping the PAIRING rather than the symbol found 17 more live instances
/// in this file, every one on content whose length the caller does not
/// control: engine narratives and motion descriptions, per-factor notes,
/// impact-profile lines, fingerprint and tool-mark summaries, audit-trail
/// lines, examiner text, and the algorithm-constant explanations. All predate
/// this round.
///
/// An under-guess overlaps the element below; an over-guess leaves a gap.
/// Neither is visible in a diff and neither is reachable by any check we own
/// -- and in this generator the overlap silently destroys the element it
/// lands on, which is why the callout's overrun went unnoticed from 2026-07
/// until a hairline border drew the boundary it crossed.
///
/// The rule this closes, which is the counting clause applied to layout: when
/// a defect is a pairing of two constructs, fixing the instance you were
/// shown leaves every other instance live. Grep the pairing, not the symbol.
///
/// Use this for any string whose length the caller does not fix. A frame or
/// an advance that cannot fit the real string is a layout defect, never a
/// licence to shorten locked copy.
private func drawWrapping(
    _ text: String,
    at point: CGPoint,
    font: UIFont,
    maxWidth: CGFloat,
    color: UIColor = .black
) -> CGFloat {
    text.draw(at: point, font: font, maxWidth: maxWidth, color: color)
    return ceil(
        (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height
    )
}

private extension String {
    func draw(at point: CGPoint, font: UIFont, maxWidth: CGFloat = 500, color: UIColor = .black) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let rect = CGRect(x: point.x, y: point.y, width: maxWidth, height: .greatestFiniteMagnitude)
        (self as NSString).draw(with: rect, options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
    }

    /// NOTE(AI Developer), 2026-09-07 (task #12 tail). The OTHER
    /// unmeasured-frame shape in this file, and the pairing grep cannot
    /// reach it: this is not a wrapping draw at all. It takes no
    /// `maxWidth`, so it never wraps and never clips vertically. It
    /// centres by MEASURING the string and subtracting:
    /// `x = (rect.width - size.width) / 2`. For a string wider than the
    /// page that arithmetic goes NEGATIVE and the text runs off BOTH
    /// edges with its middle intact -- a value that loses its beginning
    /// AND its end while looking deliberately centred.
    ///
    /// Two of the eight call sites take user text of unbounded length:
    /// the case number (`ForensicCase.caseNumber`) and the cover
    /// attestation (`Examiner.displayLine`, three free-text fields joined
    /// with em-dashes). Neither is length-limited in `EditCaseSheet`. At
    /// 12pt a 122-character attestation is about 717pt wide on a 612pt
    /// page. The attestation is the serious one: losing the ends of
    /// "Documented by: <name> - Badge <n> - <agency>" leaves a
    /// plausible-looking fragment, so the failure is a MISATTRIBUTION
    /// rather than a missing line -- and not implying an attribution the
    /// app cannot support is the whole point of the examiner work.
    ///
    /// Clamped, not wrapped-and-grown: these are single-line cover
    /// elements at fixed y-offsets, so growing downward is the collision
    /// this page cannot absorb. `x` is floored at the 50pt margin and the
    /// draw is bounded by the margins, so an over-long value stays on the
    /// page and may overlap the element below it. Visible failure over
    /// silent failure, the same trade the measured boxes made.
    func drawCenter(in rect: CGRect, y: CGFloat, font: UIFont, color: UIColor = .black) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let size = (self as NSString).size(withAttributes: attrs)
        let margin: CGFloat = 50
        let maxWidth = rect.width - margin * 2
        let x = max(margin, (rect.width - size.width) / 2)
        let bounds = CGRect(x: x, y: y,
                            width: min(size.width, maxWidth),
                            height: .greatestFiniteMagnitude)
        (self as NSString).draw(with: bounds, options: .usesLineFragmentOrigin,
                                attributes: attrs, context: nil)
    }
}
