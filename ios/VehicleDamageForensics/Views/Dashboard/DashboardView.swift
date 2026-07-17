// DashboardView.swift
// Vehicle Damage Investigation Assistant
// Main case-list dashboard. NavigationStack-based so each row pushes
// into either a capture flow (in-progress) or a results view (analyzed).

import SwiftUI
// NOTE(AI Developer), added 2026-07 alongside the CaseRow thumbnail
// feature -- `UIImage(data:)` (used in `leadingVisual` below to decode
// `CapturedPhoto.thumbnailData`) is a UIKit type; SwiftUI does not
// re-export it, so this file needs the explicit import (other views in
// this project that touch `UIImage` directly, e.g. `CaptureCameraView.swift`,
// already do the same).
import UIKit

struct DashboardView: View {

    @StateObject private var viewModel = CaseListViewModel()
    @State private var showingNewCase = false
    @State private var newCaseRoute: ForensicCase?
    @State private var editingCase: ForensicCase?
    @State private var caseToDelete: ForensicCase?

    // NOTE(AI Developer), added 2026-07 per Sean's request for a
    // first-time "how this works" intro. `@AppStorage` (not `AppState`,
    // which is dead/unused code -- see the NOTE in
    // `VehicleDamageForensicsApp.swift`) persists this flag across
    // launches so the intro only auto-shows once. `showingOnboarding` is
    // a separate `@State` (not derived directly from the flag) so the
    // "How does this work?" link in `emptyState` can re-open the same
    // intro on demand later without un-setting the "already seen it"
    // flag for the auto-show-on-first-launch behavior.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showingOnboarding = false

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
            .task {
                // Auto-show the intro exactly once, the very first time
                // the dashboard appears. Deliberately a separate `.task`
                // from the data `.load()` above so a slow load never
                // delays or blocks the onboarding check.
                if !hasSeenOnboarding {
                    showingOnboarding = true
                }
            }
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingView {
                    hasSeenOnboarding = true
                    showingOnboarding = false
                }
            }
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
            // NOTE(AI Developer): Delete confirmation added per Sean's
            // security-audit decision (2026-07). Deleting a case is
            // permanent -- it destroys all photos, LiDAR scans, and the
            // chain-of-custody audit log with no undo -- so it must not be
            // possible via a single accidental swipe-and-tap. `caseToDelete`
            // is set by the swipe action below; the actual delete only
            // happens if the user confirms here.
            .confirmationDialog(
                "Delete Case?",
                isPresented: Binding(
                    get: { caseToDelete != nil },
                    set: { if !$0 { caseToDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: caseToDelete
            ) { c in
                Button("Delete \(c.displayTitle)", role: .destructive) {
                    viewModel.deleteCase(c.id)
                    caseToDelete = nil
                }
                Button("Cancel", role: .cancel) { caseToDelete = nil }
            } message: { c in
                Text("This permanently deletes all photos, LiDAR scans, and the audit log for this case. This cannot be undone.")
            }
        }
    }

    // MARK: Subviews

    // NOTE(AI Developer), rewritten 2026-07 per Sean's request: the old
    // version was just "No cases yet" / "Tap + to start a new case." --
    // accurate, but gives a first-time (likely stressed, just-hit)
    // user zero context on what the app actually does before asking
    // them to act. Now explains the app's purpose in one line, gives a
    // full-width primary CTA button (not just the small toolbar "+",
    // which is easy to miss) that opens the same "New Case" sheet, and
    // a secondary link back into the 3-screen intro (`OnboardingView`)
    // for anyone who skipped/dismissed it too fast the first time.
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "car.front.waves.up.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("No cases yet")
                    .font(.title2.bold())
                Text("Document a hit-and-run in a few guided steps — photos, an optional LiDAR scan, and where each vehicle was hit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                showingNewCase = true
            } label: {
                Label("Start New Case", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)

            Button("How does this work?") {
                showingOnboarding = true
            }
            .font(.footnote)

            Spacer()
            Spacer()
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
                // NOTE(AI Developer): Replaced the old `.onDelete` full-swipe
                // (which deleted immediately on swipe-to-end, no confirmation)
                // with an explicit trailing swipe button that only stages
                // `caseToDelete` -- the actual delete happens in the
                // `.confirmationDialog` above, only after the user confirms.
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        caseToDelete = c
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
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
            leadingVisual
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

    // NOTE(AI Developer), added 2026-07 per Sean's request ("Case-list
    // thumbnail polish -- CaseRow currently shows an icon + text only, a
    // small photo thumbnail per case would make the list easier to scan
    // visually"). Renders `forensicCase.thumbnailPhoto` (the case's
    // first usable captured/imported photo, across either vehicle) as a
    // 44x44 rounded thumbnail with the same status-color ring the old
    // plain icon used, plus a small status-icon badge in the
    // bottom-trailing corner so the at-a-glance status signal isn't
    // lost by swapping the icon out for a photo. Falls back to the
    // original icon-only `statusIcon` for any case with no usable photo
    // yet (e.g. a case just created, before any shots are taken).
    @ViewBuilder
    private var leadingVisual: some View {
        if let photo = forensicCase.thumbnailPhoto, let data = photo.thumbnailData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(iconColor, lineWidth: 2)
                )
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: iconName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(iconColor, in: Circle())
                        .offset(x: 4, y: 4)
                }
        } else {
            statusIcon
                .frame(width: 44, height: 44)
        }
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
