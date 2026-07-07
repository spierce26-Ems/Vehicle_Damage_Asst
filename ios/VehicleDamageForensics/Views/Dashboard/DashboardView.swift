// DashboardView.swift
// Vehicle Damage Investigation Assistant
// Main case-list dashboard. NavigationStack-based so each row pushes
// into either a capture flow (in-progress) or a results view (analyzed).

import SwiftUI

struct DashboardView: View {

    @StateObject private var viewModel = CaseListViewModel()
    @State private var showingNewCase = false
    @State private var newCaseRoute: ForensicCase?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading cases…")
                } else if viewModel.filteredCases.isEmpty {
                    emptyState
                } else {
                    caseList
                }
            }
            .navigationTitle("Cases")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewCase = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search cases")
            .task { await viewModel.load() }
            .sheet(isPresented: $showingNewCase) {
                NewCaseSheet { notes in
                    showingNewCase = false
                    Task {
                        let new = await viewModel.createNewCase(notes: notes)
                        newCaseRoute = new
                    }
                }
            }
            .navigationDestination(item: $newCaseRoute) { c in
                CaptureFlowView(forensicCase: c)
            }
        }
    }

    // MARK: Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "car.front.waves.up.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No cases yet")
                .font(.title2.bold())
            Text("Tap + to start a new case.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var caseList: some View {
        List {
            ForEach(viewModel.filteredCases) { c in
                NavigationLink(value: c) {
                    CaseRow(forensicCase: c)
                }
            }
            .onDelete { idx in
                for i in idx { viewModel.deleteCase(viewModel.filteredCases[i].id) }
            }
        }
        .navigationDestination(for: ForensicCase.self) { c in
            destination(for: c)
        }
    }

    @ViewBuilder
    private func destination(for c: ForensicCase) -> some View {
        switch c.status {
        case .analyzed, .reported, .closed:
            MatchResultsView(forensicCase: c)
        case .inProgress:
            CaptureFlowView(forensicCase: c)
        }
    }
}

// MARK: - Case Row

struct CaseRow: View {
    let forensicCase: ForensicCase

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(forensicCase.caseNumber.isEmpty
                     ? "Untitled Case" : forensicCase.caseNumber)
                    .font(.headline)
                Text(forensicCase.victimVehicle.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(forensicCase.dateCreated, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if let score = forensicCase.matchResult?.compositeScore {
                Text(String(format: "%.0f", score))
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: some View {
        Image(systemName: iconName)
            .foregroundStyle(iconColor)
            .font(.system(size: 28))
    }

    private var iconName: String {
        switch forensicCase.status {
        case .inProgress: return "camera.viewfinder"
        case .analyzed:   return "checkmark.seal"
        case .reported:   return "doc.text.fill"
        case .closed:     return "archivebox.fill"
        }
    }

    private var iconColor: Color {
        switch forensicCase.status {
        case .inProgress: return .orange
        case .analyzed:   return .green
        case .reported:   return .blue
        case .closed:     return .gray
        }
    }
}

// MARK: - New Case Sheet

struct NewCaseSheet: View {
    @State private var notes: String = ""
    var onCreate: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("New Case")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { onCreate(notes) }
                }
            }
        }
    }
}
