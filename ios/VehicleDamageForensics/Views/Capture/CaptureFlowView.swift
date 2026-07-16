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
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    // MARK: Footer

    private var footerControls: some View {
        VStack(spacing: 8) {
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
