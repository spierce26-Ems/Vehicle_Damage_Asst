// MatchResultsView.swift
// Vehicle Damage Investigation Assistant
// Score breakdown screen with composite correlation score, per-factor bars,
// recommendations, and a "Generate PDF Report" action.
//
// NOTE(AI Developer): All user-facing copy in this file was reviewed and
// rewritten per Sean's decision (2026-07) to scope v1 as "best-in-class
// investigative documentation + leads tool" rather than a forensic
// identification system. See MatchResult.swift for the full rationale and
// MatchResult.disclaimerText for the standard disclaimer shown below.

import SwiftUI

struct MatchResultsView: View {
    @StateObject private var viewModel: AnalysisViewModel
    @State private var showShareSheet = false
    @State private var showEditCase = false
    /// NOTE(AI Developer), added 2026-07 per Sean's monetization decision:
    /// the composite score above stays free/instant (gives every user a
    /// reason to convert -- "you scored 78/100, unlock the full
    /// breakdown"), while the per-factor breakdown, recommendations, and
    /// PDF export are the actual actionable deliverable, gated behind
    /// `PaywallView`. See `AnalysisViewModel.isUnlocked`.
    @State private var showPaywall = false

    init(forensicCase: ForensicCase) {
        _viewModel = StateObject(wrappedValue: AnalysisViewModel(forensicCase: forensicCase))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                verdictCard
                disclaimerCard
                if viewModel.isUnlocked {
                    factorBreakdown
                    if !viewModel.skippedShotsSummary.isEmpty {
                        skippedShotsSection
                    }
                    if viewModel.scarDirectionCheck != nil {
                        scarDirectionSection
                    }
                    if let comparison = scarLineComparison, comparison.hasAnyData {
                        scarLineComparisonSection(comparison)
                    }
                    if let fpMatch = viewModel.scarFingerprintMatch {
                        scarFingerprintSection(fpMatch)
                    }
                    if let toolMarkMatch = viewModel.toolMarkComparison {
                        toolMarkSection(toolMarkMatch)
                    }
                    recommendations
                    reportSection
                    // NOTE(AI Developer), added 2026-09: the algorithm
                    // version + the constants that produced these
                    // numbers, placed last so it reads as provenance
                    // rather than competing with the results, but
                    // always present. See `AlgorithmVersion`.
                    algorithmVersionCard
                } else {
                    lockedSection
                }
            }
            .padding()
        }
        .navigationTitle("Correlation Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showEditCase = true
                } label: {
                    Image(systemName: "pencil.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if viewModel.isUnlocked {
                        viewModel.generateReport()
                        showShareSheet = viewModel.reportURL != nil
                    } else {
                        showPaywall = true
                    }
                } label: {
                    Image(systemName: viewModel.isUnlocked ? "square.and.arrow.up" : "lock.fill")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = viewModel.reportURL {
                ActivityShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showEditCase) {
            EditCaseSheet(forensicCase: viewModel.forensicCase) { updated in
                Task { await viewModel.applyEdits(updated) }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView {
                viewModel.markUnlockedFromPaywall()
            }
        }
        .task {
            if viewModel.forensicCase.matchResult == nil {
                await viewModel.runAnalysis()
            }
        }
    }

    // MARK: Locked section (pre-purchase)

    /// Shown in place of the factor breakdown / recommendations / report
    /// sections until this case is unlocked. Offers a fast path to spend
    /// an already-purchased case credit (common for a Pro user who bought
    /// a 5-pack and is unlocking case #2, say) before falling back to the
    /// full paywall for a new purchase.
    private var lockedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Full Report Locked", systemImage: "lock.fill")
                .font(.headline)
            Text("The per-factor breakdown, investigative recommendations, and shareable PDF report are part of the full report. Unlock this case to view them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if PurchaseManager.shared.caseCredits > 0 {
                Button {
                    Task {
                        if await viewModel.unlockWithCreditIfAvailable() == false {
                            showPaywall = true
                        }
                    }
                } label: {
                    Label("Use 1 Case Credit (\(PurchaseManager.shared.caseCredits) available)", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            // NOTE(AI Developer): Split into two branches rather than a
            // single Button with `condition ? .bordered : .borderedProminent`
            // -- SwiftUI's `.buttonStyle(_:)` is generic over a concrete
            // `PrimitiveButtonStyle` type, and the ternary's two branches
            // are different concrete types (`BorderedButtonStyle` vs.
            // `BorderedProminentButtonStyle`) that the compiler cannot
            // unify into one expression. This was a real Xcode 26.6 build
            // error ("Type 'ButtonStyle' has no member 'bordered'" /
            // "'borderedProminent'") surfaced by Sean, not a naming
            // collision -- see CHANGELOG note 2026-07-08.
            if PurchaseManager.shared.caseCredits > 0 {
                Button {
                    showPaywall = true
                } label: {
                    Label("Unlock Full Report", systemImage: "lock.open.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    showPaywall = true
                } label: {
                    Label("Unlock Full Report", systemImage: "lock.open.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Correlation card

    private var verdictCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.correlationLabel.uppercased())
                .font(.title3.bold())
                .foregroundStyle(.tint)
            Text(String(format: "%.1f / 100", viewModel.compositeScore))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("Score range: \(viewModel.scoreRangeLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let conf = viewModel.forensicCase.matchResult?.confidence {
                Label(conf.displayName, systemImage: conf.systemImageName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Disclaimer

    /// NOTE(AI Developer): Required per Sean's decision — shown immediately
    /// below the score so it can't be missed or scrolled past unnoticed.
    private var disclaimerCard: some View {
        Label {
            Text(viewModel.disclaimerText)
                .font(.caption)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Algorithm version / provenance

    /// NOTE(AI Developer), added 2026-09 for the "trust the number"
    /// work item. Answers "which version of the math produced this, and
    /// with what settings?" from the screen itself. Collapsed by
    /// default -- an investigator does not need the constants every
    /// time, but must be able to get at them without reading source
    /// code. Shown for legacy unstamped results too, where
    /// `algorithmVersionDisplay` says the version was not recorded.
    private var algorithmVersionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let version = viewModel.matchResult?.algorithmVersion {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(version.constants) { constant in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(constant.name): \(constant.value)")
                                    .font(.caption.bold())
                                Text(constant.explanation)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Label(version.displayLine, systemImage: "number.square")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            } else {
                Label(
                    viewModel.matchResult?.algorithmVersionDisplay
                        ?? "Analysis algorithm version not recorded",
                    systemImage: "questionmark.square"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Factor breakdown

    private var factorBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Per-Factor Breakdown").font(.headline)
            ForEach(viewModel.topFactors) { f in
                FactorBar(factor: f)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Skipped Shots

    /// NOTE(AI Developer), added 2026-07 per Sean's explicit answer on
    /// how a skipped shot should be presented ("Shot X was skipped: not
    /// available") -- see `AnalysisViewModel.skippedShotsSummary`. Shown
    /// only when at least one shot was actually skipped, so cases with a
    /// full capture never show an empty/pointless section.
    private var skippedShotsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Skipped Shots").font(.headline)
            ForEach(viewModel.skippedShotsSummary, id: \.self) { line in
                Label(line, systemImage: "minus.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Scar-Direction Consistency

    /// NOTE(AI Developer), added 2026-07 for Sean's Scar-Direction
    /// Consistency feature -- surfaces `MatchResult.scarDirectionCheck`
    /// (a SECOND, INDEPENDENT check, never blended into the composite
    /// score/factor breakdown above -- see `ScarDirectionCheck`'s doc
    /// comment) and, when it fires, `MatchResult.suspectExclusionReason`
    /// as a prominent, hard-to-miss warning. Both are already exposed by
    /// `AnalysisViewModel` (`scarDirectionCheck`/`suspectExclusionReason`)
    /// so no ViewModel changes were needed -- this is purely new UI.
    /// Only shown when `scarDirectionCheck` is non-nil (i.e. the analysis
    /// actually ran); within that, `.notDeterminable` still renders --
    /// showing "why not" is more useful to an investigator than silently
    /// omitting the section.
    private var scarDirectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scar-Direction Consistency").font(.headline)

            if let reason = viewModel.suspectExclusionReason {
                Label {
                    Text(reason)
                        .font(.subheadline.bold())
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            if let check = viewModel.scarDirectionCheck {
                Label(scarStatusLabel(check.status), systemImage: scarStatusIcon(check.status))
                    .font(.subheadline.bold())
                    .foregroundStyle(scarStatusColor(check.status))

                if let narrative = check.scenarioNarrative {
                    Text(narrative)
                        .font(.subheadline)
                }

                if let vDesc = check.victimMotionDescription {
                    Text("Victim: \(vDesc)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let sDesc = check.suspectMotionDescription {
                    Text("Suspect: \(sDesc)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let delta = check.reciprocityDeltaDegrees {
                    Text(String(format: "Reciprocity deviation: %.1f°", delta))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !check.notes.isEmpty {
                    Text(check.notes)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func scarStatusLabel(_ status: ScarDirectionCheck.Status) -> String {
        switch status {
        case .consistent: return "Consistent"
        case .inconsistent: return "Conflict Detected"
        case .notDeterminable: return "Not Determinable"
        }
    }

    private func scarStatusIcon(_ status: ScarDirectionCheck.Status) -> String {
        switch status {
        case .consistent: return "checkmark.seal.fill"
        case .inconsistent: return "xmark.seal.fill"
        case .notDeterminable: return "questionmark.circle.fill"
        }
    }

    private func scarStatusColor(_ status: ScarDirectionCheck.Status) -> Color {
        switch status {
        case .consistent: return .green
        case .inconsistent: return .red
        case .notDeterminable: return .secondary
        }
    }

    // MARK: Scar Line Comparison (Answer B2)

    /// NOTE(AI Developer), added 2026-07 for Sean's Answer B2 ("use
    /// already-recorded scar data... to show victim vs. suspect scar line
    /// length/angle/position side-by-side with a computed match/deviation
    /// number"). Built fresh from `viewModel.forensicCase` each time this
    /// view renders -- see `ScarLineComparison`'s doc comment for why this
    /// is deliberately NOT stored on `MatchResult`. `nil` when there's no
    /// suspect vehicle at all (can't compare against nothing).
    private var scarLineComparison: ScarLineComparison? {
        guard let suspect = viewModel.forensicCase.suspectVehicle else { return nil }
        return ScarLineComparison.build(
            victim: viewModel.forensicCase.victimVehicle,
            suspect: suspect,
            check: viewModel.scarDirectionCheck
        )
    }

    /// Side-by-side victim/suspect scar line length/angle/position, plus
    /// the single computed deviation number Sean asked for
    /// (`reciprocityDeltaDegrees`, reused from the Scar-Direction
    /// Consistency check rather than a second, less-grounded metric --
    /// see `ScarLineComparison.reciprocityDeltaDegrees`'s doc comment).
    /// Shown as its own section, separate from `scarDirectionSection`
    /// above, because that section is about the reciprocity VERDICT while
    /// this one is about the raw per-vehicle line data behind it.
    private func scarLineComparisonSection(_ comparison: ScarLineComparison) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scar Line Comparison").font(.headline)
            Text("In-photo line length/angle have no shared scale between the two photos and are shown for reference only. Position is the scar-verified compass bearing used for actual scoring.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack(alignment: .top, spacing: 16) {
                scarLineComparisonColumn(title: "Victim", side: comparison.victim)
                Divider()
                scarLineComparisonColumn(title: "Suspect", side: comparison.suspect)
            }

            if let delta = comparison.reciprocityDeltaDegrees {
                Divider()
                Label(String(format: "Deviation from a perfect reciprocal match: %.1f°", delta),
                      systemImage: "arrow.left.arrow.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(scarStatusColor(comparison.status))
            }

            if let narrative = comparison.scenarioNarrative {
                Text(narrative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func scarLineComparisonColumn(title: String, side: ScarLineComparison.VehicleSide) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            if side.hasLine {
                if let length = side.lengthNormalized {
                    Text(String(format: "Length: %.2f (normalized)", length))
                        .font(.caption)
                }
                if let angle = side.angleInPhotoDegrees {
                    Text(String(format: "In-photo angle: %.0f°", angle))
                        .font(.caption)
                }
                if let bearing = side.scarBearingDegrees {
                    Text(String(format: "Position (bearing): %.0f°", bearing))
                        .font(.caption)
                }
                if let motion = side.motionDescription {
                    Text(motion)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No scar line marked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Scar Fingerprint Matching

    /// NOTE(AI Developer), added 2026-07 for the fingerprint-style Scar
    /// Matching feature (Sean: "do we currently analyse the scar similar
    /// to a fingerprint? if not we should. we should identify and
    /// isolate clear markings and use those to match" -> "let's start
    /// building this as well"). A THIRD, INDEPENDENT scar-based section
    /// alongside Scar-Direction Consistency (overall direction of
    /// travel) and Scar Line Comparison (raw line geometry) above --
    /// this one is about the discrete, isolated markings within each
    /// scar (`ScarMinutia`) and how many of them line up between the
    /// two vehicles, the direct analog of comparing individual
    /// fingerprint ridge-ending/bifurcation points rather than the
    /// print's overall pattern. Always shown once analysis has run
    /// (`viewModel.scarFingerprintMatch != nil`) -- even the "not enough
    /// distinct detail to compare" case is shown, same "explain why not"
    /// principle as `scarDirectionSection`'s `.notDeterminable` case.
    private func scarFingerprintSection(_ match: ScarFingerprintMatch) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scar Fingerprint Matching").font(.headline)
            Text("Identifies isolated markings (paint-density or width peaks) along each vehicle's scar line -- like comparing individual fingerprint ridge points -- and matches them by position and type.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // NOTE(AI Developer), rewritten 2026-09 for the "no bare
            // match %" rule. This used to render "83% Marking Match" in
            // title3-bold with a traffic-light colour driven purely by
            // the percentage -- a green 83% on a comparison that had
            // never been tested against chance. Unrelated scars produce
            // percentages in that range routinely (see
            // `ScarFingerprintMatch`'s null-model note), so the raw
            // number alone was actively misleading and the colour made
            // it worse by conferring approval. The headline now comes
            // from `headlineDisplay`, which always carries the p-value
            // and the chance verdict alongside the percentage, and the
            // colour is driven by SIGNIFICANCE, not by score size.
            if let headline = match.headlineDisplay {
                Label(headline, systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                    .foregroundStyle(significanceColor(match.isStatisticallySignificant))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(match.summary)
                .font(.subheadline)

            HStack(alignment: .top, spacing: 16) {
                scarFingerprintColumn(title: "Victim", minutiae: match.victimMinutiae, matchedIDs: Set(match.matchedPairs.map { $0.victimMinutia.id }))
                Divider()
                scarFingerprintColumn(title: "Suspect", minutiae: match.suspectMinutiae, matchedIDs: Set(match.matchedPairs.map { $0.suspectMinutia.id }))
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func scarFingerprintColumn(title: String, minutiae: [ScarMinutia], matchedIDs: Set<UUID>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title) (\(minutiae.count))").font(.subheadline.bold())
            if minutiae.isEmpty {
                Text("No isolated markings found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(minutiae) { m in
                    Label(
                        String(format: "%@ @ %.0f%%", scarMinutiaTypeLabel(m.type), m.positionAlongLine * 100),
                        systemImage: matchedIDs.contains(m.id) ? "checkmark.circle.fill" : "circle.dashed"
                    )
                    .font(.caption)
                    .foregroundStyle(matchedIDs.contains(m.id) ? .green : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scarMinutiaTypeLabel(_ type: ScarMinutia.FeatureType) -> String {
        switch type {
        case .densityPeak: return "Density mark"
        case .widthPeak: return "Width mark"
        }
    }

    /// NOTE(AI Developer), added 2026-09, REPLACING the previous
    /// `scarFingerprintScoreColor(_:)` which coloured a comparison
    /// green/orange/red purely by how big its percentage was. That is
    /// the visual form of the same error the "no bare match %" rule
    /// exists to stop: a high score that is indistinguishable from
    /// chance was being painted green. Colour now reflects only whether
    /// the score survived its null model.
    ///   - green:  significant (unlikely to be coincidence)
    ///   - orange: tested and NOT distinguishable from chance
    ///   - gray:   no significance test was possible
    /// Note that "not significant" is orange rather than red on
    /// purpose: it means "this tells you nothing", not "this excludes
    /// the suspect", and red would read as an exclusion.
    private func significanceColor(_ significant: Bool?) -> Color {
        switch significant {
        case .some(true): return .green
        case .some(false): return .orange
        case .none: return .gray
        }
    }

    // MARK: Tool-Mark / Striation Section

    /// NOTE(AI Developer), added 2026-07 for the tool-mark/striation
    /// matching feature (Sean: "we are basically looking for tooling
    /// marks on each vehicle from the other"). A FOURTH, INDEPENDENT
    /// scar-based section alongside Scar-Direction Consistency, Scar
    /// Line Comparison, and Scar Fingerprint Matching above -- this one
    /// is about the fine parallel striation/scratch-spacing RHYTHM found
    /// ACROSS each scar's width (not along its length), the closest
    /// analog in this app to a real forensic tool-mark examiner's
    /// comparison. Always shown once analysis has run
    /// (`viewModel.toolMarkComparison != nil`) -- even the "not enough
    /// distinct detail to compare" case is shown, same "explain why not"
    /// principle as `scarFingerprintSection`'s empty case.
    private func toolMarkSection(_ comparison: ToolMarkComparison) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tool-Mark / Striation Matching").font(.headline)
            Text("Looks across each scar's width for fine parallel scratch/gouge lines (tooling marks) and compares the spacing rhythm between them -- independent of photo distance, angle, or zoom, and checked in both normal and mirrored order to account for a victim/suspect stamp-and-impression relationship.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // NOTE(AI Developer), rewritten 2026-09 for the "no bare
            // match %" rule -- same change and same reasoning as
            // `scarFingerprintSection` above. Note this section had the
            // sharper version of the bug: the null model from commit
            // 7391b73 already existed here, but when it could not be
            // built the view still printed a bold coloured percentage
            // with no qualifier at all. A uniform striation pattern
            // matches almost anything at near 100%, so that was the
            // most confidently-wrong number the app could display.
            if let headline = comparison.headlineDisplay {
                Label(headline, systemImage: "waveform.path")
                    .font(.headline)
                    .foregroundStyle(significanceColor(comparison.isStatisticallySignificant))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let orientation = comparison.orientationUsed {
                Label(
                    orientation == .reversed ? "Best alignment found in reverse order (stamp/impression pair)" : "Best alignment found in the same order on both vehicles",
                    systemImage: orientation == .reversed ? "arrow.left.arrow.right" : "arrow.right"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(comparison.summary)
                .font(.subheadline)

            HStack(alignment: .top, spacing: 16) {
                toolMarkColumn(title: "Victim", profile: comparison.victimProfile)
                Divider()
                toolMarkColumn(title: "Suspect", profile: comparison.suspectProfile)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func toolMarkColumn(title: String, profile: StriationProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title) (\(profile.crossSections.count) probes)").font(.subheadline.bold())
            if !profile.isDeterminable {
                Text("Not enough striation detail found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(profile.crossSections) { cs in
                    Label(
                        String(format: "%.0f%%: %d marks found", cs.positionAlongLine * 100, cs.peakCount),
                        systemImage: "line.3.horizontal.decrease"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Recommendations

    private var recommendations: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommendations").font(.headline)
            ForEach(viewModel.recommendations, id: \.self) { rec in
                Label(rec, systemImage: "lightbulb.fill")
                    .font(.subheadline)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Report Section

    /// NOTE(AI Developer), added 2026-07 per Sean's request: "after a
    /// match score shows, a one-line 'here's what to do with this'...
    /// so the payoff moment doesn't just end on a number." Previously,
    /// once a PDF was generated, this section just confirmed the
    /// filename and stopped -- no next step, so the flow's actual
    /// payoff moment (having a report) had no follow-through. Now shows
    /// a one-line next-step nudge plus a direct "Share Report" button
    /// right here (not just the toolbar share icon, which a user
    /// scrolled down this far might not think to look back up for),
    /// so acting on the report doesn't require hunting for the action
    /// that produced it.
    private var reportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Report").font(.headline)
            if let url = viewModel.reportURL {
                Label("Generated PDF: \(url.lastPathComponent)", systemImage: "doc.fill")
                    .font(.subheadline)
                Text("Save or share this report with your insurer, the police, or a body shop — it's your documentation of what happened.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    showShareSheet = true
                } label: {
                    Label("Share Report", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            } else {
                Text("Tap the share button above to generate a documentation report for investigators or insurers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Factor Bar

struct FactorBar: View {
    let factor: FactorScore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(factor.factor.displayName)
                    .font(.subheadline.bold())
                Spacer()
                Text(String(format: "%.0f", factor.rawScore))
                    .font(.subheadline.monospacedDigit())
            }
            ProgressView(value: factor.rawScore / 100.0)
                .tint(barColor)
            HStack {
                Text(factor.factor.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("weight \(Int(factor.weight * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var barColor: Color {
        switch factor.rawScore {
        case 80...:  return .green
        case 60..<80: return .blue
        case 40..<60: return .orange
        default:     return .red
        }
    }
}

// MARK: - Share Sheet wrapper

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
