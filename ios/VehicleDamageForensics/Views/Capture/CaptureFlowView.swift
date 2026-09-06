// CaptureFlowView.swift
// Vehicle Damage Investigation Assistant
// Top-level capture screen. Coordinates the 30-shot protocol, role
// switching (victim → suspect), and the hand-off to LiDAR scanning.

import SwiftUI

struct CaptureFlowView: View {

    @StateObject private var viewModel: CaptureViewModel
    @State private var showLiDAR = false
    @State private var showAnalysis = false
    @State private var showEditCase = false
    // NOTE(AI Developer), added 2026-07 per Sean's request to identify
    // damage location + direction of travel per vehicle -- see
    // `ImpactMarkerView`. Presented as a sheet rather than a
    // `navigationDestination` since it's a required, focused sub-task
    // (record one profile, then return here), not a flow the user
    // navigates deeper from.
    @State private var showImpactMarker = false
    // NOTE(AI Developer), added 2026-07 for the Scar-Direction
    // Consistency feature (Sean's fix for the parallel-parking
    // direction-of-travel blind spot). Presented as a sheet, same
    // pattern as `showImpactMarker` -- see `ScarCaptureView`.
    // Deliberately OPTIONAL (unlike Impact Location/Direction above),
    // per Sean's explicit answer that a missing/inconclusive scar
    // reading should let the other 6 factors decide rather than block
    // analysis -- so there is no `hasScarDirection` gate on the
    // "Continue"/"Run Analysis" buttons below.
    @State private var showScarCapture = false
    // NOTE(AI Developer), added 2026-07 per Sean's "review of all the
    // thumbnails... before its submitted" request -- see
    // `PhotoReviewView`. Presented as a sheet, same pattern as
    // `showImpactMarker`/`showScarCapture` above.
    @State private var showPhotoReview = false

    init(forensicCase: ForensicCase) {
        _viewModel = StateObject(wrappedValue: CaptureViewModel(forensicCase: forensicCase))
    }

    var body: some View {
        VStack(spacing: 0) {
            roleHeader
            CaptureCameraView(viewModel: viewModel)
                .frame(maxHeight: .infinity)
            footerControls
        }
        .navigationTitle(viewModel.captureRole.displayName + " Vehicle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEditCase = true
                } label: {
                    Image(systemName: "pencil.circle")
                }
            }
        }
        .navigationDestination(isPresented: $showLiDAR) {
            LiDARScanView(viewModel: viewModel)
        }
        .navigationDestination(isPresented: $showAnalysis) {
            AnalysisRunnerView(forensicCase: viewModel.forensicCase)
        }
        .sheet(isPresented: $showEditCase) {
            EditCaseSheet(forensicCase: viewModel.forensicCase) { updated in
                Task { await viewModel.applyEdits(updated) }
            }
        }
        // NOTE(AI Developer), added 2026-07 per Sean's request ("should
        // we identify the location of the damage on each vehicle and
        // always identify the direction of traveling at impact") -- see
        // `ImpactMarkerView` and `impactMarkerButton` below.
        .sheet(isPresented: $showImpactMarker) {
            NavigationStack {
                ImpactMarkerView(viewModel: viewModel)
            }
        }
        // NOTE(AI Developer), added 2026-07 for the Scar-Direction
        // Consistency feature -- see `showScarCapture`/`scarCaptureButton`.
        // `ScarCaptureView` wraps its own `NavigationStack` internally
        // (it has two internal stages with their own toolbar), unlike
        // `ImpactMarkerView` above, so it isn't wrapped in a second one
        // here.
        //
        // NOTE(AI Developer), changed 2026-07 from `.sheet` to
        // `.fullScreenCover` per Sean's on-device report ("does not fit
        // well within the view of the app... [Ready button] is low on
        // the screen and can't activate it"). A `.sheet` on iOS renders
        // shorter than the true device height (card presentation, extra
        // top inset for the grab handle) -- fine for a static form like
        // `ImpactMarkerView`, but `ScarCaptureView`'s aiming stage is a
        // live full-bleed camera view whose own internal layout
        // (`.ignoresSafeArea()` preview + a bottom-anchored controls
        // stack) assumes it owns the full screen. On a `.sheet` that
        // assumption was false, silently eating into exactly the
        // vertical space the Ready/library/shutter controls needed.
        // `.fullScreenCover` gives it the full device height it was
        // already designed for, on top of the same screen's own layout
        // tightening (see `aimingStage`'s reworked bottom controls).
        .fullScreenCover(isPresented: $showScarCapture) {
            ScarCaptureView(viewModel: viewModel)
        }
        // NOTE(AI Developer), added 2026-07 -- see `showPhotoReview`
        // above. `onRetake` switches `captureRole` to match whichever
        // vehicle's slot was retaken (the review screen lets the user
        // browse either vehicle's thumbnails via its own segmented
        // control, independent of which vehicle is currently active
        // here) so the live camera that reappears underneath is asking
        // for the correct vehicle's freshly-cleared slot.
        .sheet(isPresented: $showPhotoReview) {
            PhotoReviewView(viewModel: viewModel) { role in
                viewModel.captureRole = role
            }
        }
    }

    // MARK: Header

    private var roleHeader: some View {
        HStack {
            Image(systemName: viewModel.captureRole == .victim
                  ? "shield.lefthalf.filled" : "exclamationmark.octagon.fill")
                .foregroundStyle(viewModel.captureRole == .victim ? .blue : .orange)
            Text(viewModel.captureRole.displayName + " Vehicle")
                .font(.headline)
            Spacer()
            Text("\(viewModel.currentShotIndex)/\(viewModel.protocolShots.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            // NOTE(AI Developer), added 2026-07 -- quick access to
            // `PhotoReviewView` from anywhere in the capture flow, not
            // just once the protocol is complete. Icon-only (vs. the
            // footer's own labeled entry point) since this lives in an
            // already-crowded header row.
            Button {
                showPhotoReview = true
            } label: {
                Image(systemName: "square.grid.2x2")
            }
            // NOTE(AI Developer): checks BOTH vehicles' progress (not
            // just the active role's `currentShotIndex`) since
            // `PhotoReviewView` lets the user switch between victim/
            // suspect internally -- a victim who's fully done shouldn't
            // see this disabled just because the suspect role (now
            // active) hasn't started yet.
            .disabled(viewModel.shotIndex(for: .victim) == 0 && viewModel.shotIndex(for: .suspect) == 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    // MARK: Footer — Case Readiness bar

    /// NOTE(AI Developer), rebuilt 2026-09 per the readiness-bar spec
    /// (Part A). This footer used to be five stacked bordered buttons
    /// plus two permanently-rendered explanatory captions, each carrying
    /// its own state inside its own label text ("Impact Location &
    /// Direction — Recorded"). Everything the old footer could reach is
    /// still reachable -- the five segments route to the SAME sheets the
    /// five buttons did -- but the state is now glanceable in one row
    /// instead of five rows of prose, and the data-quality cost of a
    /// skip is stated BEFORE analysis rather than turning up afterwards
    /// in `skippedShotsSummary` on the results screen.
    ///
    /// The two long captions are gone, and deliberately NOT re-added to
    /// their destination screens: both already say the same thing there.
    /// `ImpactMarkerView`'s header carries "required to correlate impact
    /// geometry between both vehicles" plus a why-note reading "confirm
    /// both vehicles were hit in a way that matches", and
    /// `ScarCaptureView`'s why-note explains the paint-taper reading of
    /// direction. Copying the footer wording alongside them would have
    /// produced two near-identical sentences on one screen, which is
    /// worse than the tall footer was. One clause IS lost -- the
    /// reversing / backing-out-of-a-parking-space example -- and that is
    /// flagged for the copy owner rather than fixed here, since
    /// `ScarCaptureView.swift` is being rewritten under a separate
    /// change and must not be touched from this one.
    ///
    /// What deliberately did NOT change: `Continue to Suspect` / `Run
    /// Analysis` keep the exact gate `isComplete && hasImpactProfile`.
    /// The bar changes what the user SEES, not what the app ALLOWS.
    private var footerControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Readiness — tap any segment")
                .font(.caption)
                .foregroundStyle(.secondary)

            readinessSegmentRow

            // Photo progress only, and deliberately secondary: the
            // segments are the primary cue. A single bar cannot express
            // five independent steps, which is the whole reason the
            // segments exist.
            ProgressView(value: viewModel.progress)
                .tint(.accentColor)

            readinessWarningLine
            nextStepBox
            primaryActions
        }
        .padding()
        .background(.thinMaterial)
    }

    /// Five fixed segments in one row, each an equal-width `Button`
    /// routing to the same destination its old footer button did.
    ///
    /// NOTE(AI Developer): the count is fixed at five, which is what
    /// makes a non-scrolling row viable. If a sixth is ever added, wrap
    /// to two rows of three -- do NOT let the text shrink, since these
    /// labels must stay legible at large Dynamic Type sizes on a
    /// roadside in sun.
    private var readinessSegmentRow: some View {
        HStack(spacing: 6) {
            ForEach(viewModel.readinessSegments) { segment in
                Button {
                    open(segment.destination)
                } label: {
                    VStack(spacing: 2) {
                        Text(segment.title)
                            .font(.caption.weight(.semibold))
                        Text(segment.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(tint(for: segment.state))
                .accessibilityLabel(accessibilityLabel(for: segment))
            }
        }
    }

    /// State severity is the ONLY thing colour encodes here, and it is
    /// never the only carrier: `segment.detail` and the accessibility
    /// label say the same thing in words. Semantic roles only -- no
    /// literal RGB -- so the deferred high-contrast field theme stays a
    /// token swap rather than a rewrite.
    private func tint(for state: ReadinessSegment.State) -> Color {
        switch state {
        case .done: return .green
        case .requiredMissing: return .orange
        case .optionalMissing: return .secondary
        }
    }

    /// NOTE(AI Developer): an optional gap must not be announced as a
    /// problem. "Optional" is read out as optional, and an inconclusive
    /// scar as inconclusive -- not as missing, which would send the user
    /// to re-shoot a frame that was fine.
    private func accessibilityLabel(for segment: ReadinessSegment) -> String {
        switch segment.state {
        case .done: return "\(segment.title), done, \(segment.detail)"
        case .requiredMissing: return "\(segment.title), required, \(segment.detail)"
        case .optionalMissing: return "\(segment.title), optional, \(segment.detail)"
        }
    }

    /// Generated from the real count of required-but-missing segments,
    /// and rendered ONLY when that count is at least one -- there is no
    /// reassuring variant, because a permanently-present line is a line
    /// users stop reading.
    ///
    /// The wording deliberately promises nothing specific about the
    /// score: it says confidence is reduced and the report will list the
    /// gaps, both of which are true and both of which the engine
    /// actually does. It must not be reworded into a numeric claim.
    @ViewBuilder
    private var readinessWarningLine: some View {
        let count = viewModel.readinessRequiredMissingCount
        if count > 0 {
            Label {
                Text("\(count) required \(count == 1 ? "item is" : "items are") missing. Analysis will run, but confidence will be reduced and the report will list these as limitations.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    /// One box naming the single highest-impact remaining item. Priority
    /// lives in the view model (`readinessNextStep`), not here.
    @ViewBuilder
    private var nextStepBox: some View {
        if let next = viewModel.readinessNextStep {
            Button {
                open(next.destination)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next step")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(nextStepTitle(for: next))
                        .font(.subheadline.weight(.semibold))
                    if let why = nextStepReason(for: next) {
                        Text(why)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            }
            .buttonStyle(.bordered)
        }
    }

    private func nextStepTitle(for segment: ReadinessSegment) -> String {
        switch segment.destination {
        case .impact: return "Impact location & direction"
        case .photos: return "Remaining protocol photos"
        case .height: return "Height reference photo"
        case .scar: return segment.detail == "retry" ? "Scar photo — direction not yet read" : "Scar photo & direction"
        case .lidar: return "LiDAR height measurement"
        }
    }

    /// Only the scar carries a reason line, and only because it is the
    /// step users skip most while it feeds four of the seven
    /// comparisons. Every other segment's title is self-explanatory, and
    /// a reason under each one would be the caption stack this bar
    /// replaced.
    private func nextStepReason(for segment: ReadinessSegment) -> String? {
        guard segment.destination == .scar else { return nil }
        return "Feeds 4 of the 7 comparisons. Highest impact of anything left."
    }

    private var primaryActions: some View {
        HStack(spacing: 16) {
            Button {
                showPhotoReview = true
            } label: {
                Label("Review Photos", systemImage: "square.grid.2x2")
            }
            .buttonStyle(.bordered)
            // NOTE(AI Developer): checks BOTH vehicles' progress -- see
            // the identical guard in `roleHeader`.
            .disabled(viewModel.shotIndex(for: .victim) == 0 && viewModel.shotIndex(for: .suspect) == 0)

            Spacer()

            // NOTE(AI Developer), unchanged since 2026-07 and must stay
            // unchanged: both buttons require `isComplete &&
            // hasImpactProfile`. Per Sean's decision that impact
            // location/direction is required, this gate is what enforces
            // it at the UI level (alongside
            // `ForensicCase.isReadyForAnalysis` guarding the engine).
            // The readiness bar above is informational; it does not
            // introduce a bypass.
            if viewModel.captureRole == .victim {
                Button {
                    viewModel.switchToSuspect()
                } label: {
                    Label("Continue to Suspect", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!(viewModel.isComplete && viewModel.hasImpactProfile))
            } else {
                Button {
                    showAnalysis = true
                } label: {
                    Label("Run Analysis", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!(viewModel.isComplete && viewModel.hasImpactProfile))
            }
        }
    }

    /// Segment routing. Every case opens an EXISTING presentation flag --
    /// no new navigation was added for the bar, so a segment cannot lead
    /// somewhere the old footer could not.
    private func open(_ destination: ReadinessSegment.Destination) {
        switch destination {
        case .photos: showPhotoReview = true
        case .impact: showImpactMarker = true
        case .scar: showScarCapture = true
        // The protocol's height slots are captured in the main camera
        // flow, so the actionable destination is the photo review grid --
        // the one screen that shows which slots are filled, skipped, or
        // pending and lets the user fix them.
        case .height: showPhotoReview = true
        case .lidar: showLiDAR = true
        }
    }
}

// MARK: - Analysis Runner (small wrapper for navigation hand-off)

struct AnalysisRunnerView: View {
    @StateObject private var viewModel: AnalysisViewModel

    init(forensicCase: ForensicCase) {
        _viewModel = StateObject(wrappedValue: AnalysisViewModel(forensicCase: forensicCase))
    }

    var body: some View {
        VStack(spacing: 24) {
            if viewModel.isRunning {
                ProgressView("Running correlation analysis…")
                    .progressViewStyle(.circular)
            } else if viewModel.matchResult != nil {
                MatchResultsView(forensicCase: viewModel.forensicCase)
            } else {
                Button {
                    Task { await viewModel.runAnalysis() }
                } label: {
                    Label("Start Analysis", systemImage: "wand.and.stars")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
    }
}
