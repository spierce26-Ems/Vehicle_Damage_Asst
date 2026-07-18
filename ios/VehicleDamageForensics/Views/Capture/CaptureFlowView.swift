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

    // MARK: Footer

    private var footerControls: some View {
        VStack(spacing: 8) {
            // NOTE(AI Developer), added 2026-07 per Sean's "review of all
            // the thumbnails... before its submitted to be analysed"
            // request -- a second, labeled entry point to
            // `PhotoReviewView` alongside the icon-only one in
            // `roleHeader` above, placed first in the footer since
            // reviewing/fixing photos is naturally something a user
            // checks before dealing with the impact/scar/LiDAR steps
            // below it.
            Button {
                showPhotoReview = true
            } label: {
                Label("Review Photos", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.shotIndex(for: .victim) == 0 && viewModel.shotIndex(for: .suspect) == 0)

            // NOTE(AI Developer), added 2026-07 per Sean's decision that
            // impact location + direction of travel is a REQUIRED step
            // (unlike the skippable photo protocol) -- surfaced as its
            // own row so it's visible and actionable independent of shot
            // count, with a checkmark once `hasImpactProfile` is true so
            // it's clear at a glance whether this vehicle still needs it.
            Button {
                showImpactMarker = true
            } label: {
                Label(
                    viewModel.hasImpactProfile ? "Impact Location & Direction — Recorded" : "Impact Location & Direction — Required",
                    systemImage: viewModel.hasImpactProfile ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(viewModel.hasImpactProfile ? .green : .orange)

            // NOTE(AI Developer), added 2026-07 per Sean's request for
            // in-flow "why this matters" guidance -- this button is the
            // entry point to `ImpactMarkerView` (where the fuller
            // one-line explanation also lives), but a user deciding
            // whether to tap it here benefits from knowing why it's
            // required *before* opening the sheet, not just that it is.
            if !viewModel.hasImpactProfile {
                Text("Required because it's what lets the app confirm both vehicles were hit in a way that matches — not just photos of separate damage.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }

            // NOTE(AI Developer), added 2026-07 for the Scar-Direction
            // Consistency feature -- deliberately styled/worded as
            // OPTIONAL ("Recommended", not "Required"), unlike the
            // Impact Location row above, per Sean's explicit answer
            // that a missing/inconclusive scar reading should let the
            // other 6 correlation factors decide rather than block
            // analysis. Three visual states: not yet attempted (gray/
            // outline), photo taken but direction inconclusive (orange,
            // "Inconclusive" -- a real, expected outcome for a blunt
            // dent with no taper to read, not an error), and resolved
            // (green, checkmark).
            Button {
                showScarCapture = true
            } label: {
                Label(
                    viewModel.hasScarDirection ? "Scar Direction — Recorded"
                        : viewModel.hasScarPhoto ? "Scar Direction — Inconclusive (tap to retry)"
                        : "Scar Direction — Recommended",
                    systemImage: viewModel.hasScarDirection ? "checkmark.circle.fill"
                        : viewModel.hasScarPhoto ? "questionmark.circle"
                        : "camera.viewfinder"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(viewModel.hasScarDirection ? .green : viewModel.hasScarPhoto ? .orange : .secondary)

            if !viewModel.hasScarDirection {
                Text("Optional, but a physical scar's paint taper can reveal the true direction of motion — even when the vehicle was reversing (e.g. backing out of a parking space) in a way a guessed compass heading can't.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }

            HStack(spacing: 16) {
                Button {
                    showLiDAR = true
                } label: {
                    Label("LiDAR Scan", systemImage: "scanner.fill")
                }
                .buttonStyle(.bordered)

                Spacer()

                // NOTE(AI Developer), updated 2026-07: both buttons below
                // now also require `viewModel.hasImpactProfile` alongside
                // `isComplete` -- per Sean's decision that impact
                // location/direction is required, this gate is what
                // actually enforces that at the UI level (in addition to
                // `ForensicCase.isReadyForAnalysis` guarding the analysis
                // engine itself).
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
        .padding()
        .background(.thinMaterial)
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
