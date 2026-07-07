// DashboardView.swift
// Vehicle Damage Investigation Assistant
// Main case-list dashboard. NavigationStack-based so each row pushes
// into either a capture flow (in-progress) or a results view (analyzed).

import SwiftUI

struct DashboardView: View {

    @StateObject private var viewModel = CaseListViewModel()
    @State private var showingNewCase = false
    @State private var newCaseRoute: ForensicCase?
    @State private var editingCase: ForensicCase?

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
                NewCaseSheet { draft in
                    showingNewCase = false
                    Task {
                        let new = await viewModel.createNewCase(
                            caseName: draft.caseName,
                            caseType: draft.caseType,
                            incidentDate: draft.incidentDate,
                            location: draft.location,
                            victimVehicle: draft.victimVehicle,
                            notes: draft.notes
                        )
                        newCaseRoute = new
                    }
                }
            }
            .navigationDestination(item: $newCaseRoute) { c in
                CaptureFlowView(forensicCase: c)
            }
            .sheet(item: $editingCase) { c in
                EditCaseSheet(forensicCase: c) { updated in
                    Task { await viewModel.updateCase(updated) }
                }
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
                .swipeActions(edge: .leading) {
                    Button {
                        editingCase = c
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
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
                Text(forensicCase.displayTitle)
                    .font(.headline)
                if !forensicCase.caseName.isEmpty {
                    // Case has a custom name, so also surface the serial
                    // number as a secondary line (it's the primary title
                    // above when no name was given, so no duplication).
                    Text(forensicCase.caseNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(forensicCase.victimVehicle.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let loc = forensicCase.location, !loc.displayAddress.isEmpty {
                    Text(loc.displayAddress)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
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

/// NOTE(AI Developer): Bundles everything the "New Case" form collects so
/// `DashboardView` only has one thing to pass to `createNewCase(...)`.
/// Not `Codable`/persisted itself — it's a transient form draft, converted
/// into a real `ForensicCase` (with an auto-assigned `caseNumber`) only
/// when the user taps "Create".
struct NewCaseDraft {
    var caseName: String
    var caseType: CaseType
    var incidentDate: Date?
    var location: IncidentLocation?
    var victimVehicle: Vehicle
    var notes: String
}

/// Case-creation form per Sean's decision (2026-07): lets the investigator
/// name the case, record detailed incident info (type/date/address), and
/// capture the victim vehicle's make/model/etc. up front. The case's
/// serial number (`caseNumber`) is intentionally NOT editable here — it's
/// always auto-assigned by `CaseListViewModel.createNewCase` so every case
/// is guaranteed a unique serial.
struct NewCaseSheet: View {

    @Environment(\.dismiss) private var dismiss

    // Case info
    @State private var caseName: String = ""
    @State private var caseType: CaseType = .hitAndRun
    @State private var notes: String = ""

    // Incident details
    @State private var recordIncidentDate = false
    @State private var incidentDate: Date = Date()
    @State private var street: String = ""
    @State private var city: String = ""
    @State private var state: String = ""
    @State private var zip: String = ""

    // Victim vehicle
    @State private var make: String = ""
    @State private var model: String = ""
    @State private var yearText: String = ""
    @State private var color: String = ""
    @State private var licensePlate: String = ""
    @State private var vin: String = ""

    var onCreate: (NewCaseDraft) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Case Info") {
                    TextField("Case name (e.g. \"Driveway Hit & Run\")", text: $caseName)
                    Picker("Case Type", selection: $caseType) {
                        ForEach(CaseType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                }

                Section("Incident Details") {
                    Toggle("Record incident date", isOn: $recordIncidentDate.animation())
                    if recordIncidentDate {
                        DatePicker("Date & Time", selection: $incidentDate, displayedComponents: [.date, .hourAndMinute])
                    }
                    TextField("Street address", text: $street)
                        .textContentType(.streetAddressLine1)
                    TextField("City", text: $city)
                        .textContentType(.addressCity)
                    HStack {
                        TextField("State", text: $state)
                            .textContentType(.addressState)
                        TextField("ZIP", text: $zip)
                            .keyboardType(.numberPad)
                            .textContentType(.postalCode)
                    }
                }

                Section("Victim Vehicle") {
                    TextField("Make (e.g. Toyota)", text: $make)
                        .textInputAutocapitalization(.words)
                    TextField("Model (e.g. Camry)", text: $model)
                        .textInputAutocapitalization(.words)
                    TextField("Year", text: $yearText)
                        .keyboardType(.numberPad)
                    TextField("Color", text: $color)
                        .textInputAutocapitalization(.words)
                    TextField("License Plate", text: $licensePlate)
                        .textInputAutocapitalization(.characters)
                    TextField("VIN (optional)", text: $vin)
                        .textInputAutocapitalization(.characters)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }

                // A case number is auto-assigned on creation — surfaced
                // here only as an informational note, not an editable field.
                Section {
                    Label("A case serial number will be assigned automatically when you tap Create.", systemImage: "number")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Case")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { onCreate(currentDraft()) }
                }
            }
        }
    }

    private func currentDraft() -> NewCaseDraft {
        let location = IncidentLocation(
            address: street.isEmpty ? nil : street,
            city: city.isEmpty ? nil : city,
            state: state.isEmpty ? nil : state,
            zip: zip.isEmpty ? nil : zip
        )
        let vehicle = Vehicle(
            role: .victim,
            make: make,
            model: model,
            year: Int(yearText),
            color: color,
            licensePlate: licensePlate.isEmpty ? nil : licensePlate,
            vin: vin.isEmpty ? nil : vin
        )
        return NewCaseDraft(
            caseName: caseName,
            caseType: caseType,
            incidentDate: recordIncidentDate ? incidentDate : nil,
            location: location.isEmpty ? nil : location,
            victimVehicle: vehicle,
            notes: notes
        )
    }
}
