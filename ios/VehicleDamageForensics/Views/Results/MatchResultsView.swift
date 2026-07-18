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
                    recommendations
                    reportSection
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
