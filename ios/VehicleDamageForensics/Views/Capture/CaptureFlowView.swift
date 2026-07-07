// CaptureFlowView.swift
// Vehicle Damage Investigation Assistant
// Top-level capture screen. Coordinates the 30-shot protocol, role
// switching (victim → suspect), and the hand-off to LiDAR scanning.

import SwiftUI

struct CaptureFlowView: View {

    @StateObject private var viewModel: CaptureViewModel
    @State private var showLiDAR = false
    @State private var showAnalysis = false

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
        .navigationDestination(isPresented: $showLiDAR) {
            LiDARScanView(viewModel: viewModel)
        }
        .navigationDestination(isPresented: $showAnalysis) {
            AnalysisRunnerView(forensicCase: viewModel.forensicCase)
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
        HStack(spacing: 16) {
            Button {
                showLiDAR = true
            } label: {
                Label("LiDAR Scan", systemImage: "scanner.fill")
            }
            .buttonStyle(.bordered)

            Spacer()

            if viewModel.captureRole == .victim {
                Button {
                    viewModel.switchToSuspect()
                } label: {
                    Label("Continue to Suspect", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isComplete == false)
            } else {
                Button {
                    showAnalysis = true
                } label: {
                    Label("Run Analysis", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isComplete == false)
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
