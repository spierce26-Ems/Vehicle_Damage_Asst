// EditCaseSheet.swift
// Vehicle Damage Investigation Assistant
// Edit form for an EXISTING case: case name/type, incident details/address,
// victim vehicle info, and — new per Sean's decision (2026-07) — suspect
// vehicle info (make/model/color/plate/VIN), since previously there was no
// way to record what a witness told you about the fleeing vehicle except
// by capturing photos of it.
//
// NOTE(AI Developer): Reachable from three places: the Dashboard case list
// (swipe action), the active Capture flow (toolbar button — the main entry
// point for entering suspect vehicle details as soon as you have them,
// even before/without photos), and the post-analysis Results screen
// (toolbar button — for updates after the fact, e.g. a witness calls back
// with a plate number). All three share this one sheet + a small
// `applyEdits(_:)` method on the relevant ViewModel, rather than three
// separate forms, so edit behavior can't drift out of sync.

import SwiftUI

struct EditCaseSheet: View {

    @Environment(\.dismiss) private var dismiss

    /// The case as it existed when the sheet was opened. Kept around so
    /// `save()` can start from a full, valid `ForensicCase` (preserving
    /// photos, damage zones, LiDAR data, matchResult, reportURL, metadata,
    /// and auditLog) and only overwrite the fields this form actually
    /// edits.
    private let original: ForensicCase
    var onSave: (ForensicCase) -> Void

    // Case info
    @State private var caseName: String
    @State private var caseType: CaseType
    @State private var notes: String

    // Incident details
    @State private var recordIncidentDate: Bool
    @State private var incidentDate: Date
    @State private var street: String
    @State private var city: String
    @State private var state: String
    @State private var zip: String

    // Victim vehicle
    @State private var victimMake: String
    @State private var victimModel: String
    @State private var victimYearText: String
    @State private var victimColor: String
    @State private var victimPlate: String
    @State private var victimVIN: String
    // NOTE(AI Developer), added 2026-07 per Sean's request for a simple
    // Car/Truck toggle that drives which top-down silhouette
    // `ImpactSilhouetteView` shows for this vehicle.
    @State private var victimBodyType: VehicleBodyType

    // Suspect vehicle
    @State private var recordSuspectInfo: Bool
    @State private var suspectMake: String
    @State private var suspectModel: String
    @State private var suspectYearText: String
    @State private var suspectColor: String
    @State private var suspectPlate: String
    @State private var suspectVIN: String
    @State private var suspectBodyType: VehicleBodyType

    init(forensicCase: ForensicCase, onSave: @escaping (ForensicCase) -> Void) {
        self.original = forensicCase
        self.onSave = onSave

        _caseName = State(initialValue: forensicCase.caseName)
        _caseType = State(initialValue: forensicCase.caseType)
        _notes = State(initialValue: forensicCase.notes)

        _recordIncidentDate = State(initialValue: forensicCase.incidentDate != nil)
        _incidentDate = State(initialValue: forensicCase.incidentDate ?? Date())
        _street = State(initialValue: forensicCase.location?.address ?? "")
        _city = State(initialValue: forensicCase.location?.city ?? "")
        _state = State(initialValue: forensicCase.location?.state ?? "")
        _zip = State(initialValue: forensicCase.location?.zip ?? "")

        let v = forensicCase.victimVehicle
        _victimMake = State(initialValue: v.make)
        _victimModel = State(initialValue: v.model)
        _victimYearText = State(initialValue: v.year.map(String.init) ?? "")
        _victimColor = State(initialValue: v.color)
        _victimPlate = State(initialValue: v.licensePlate ?? "")
        _victimVIN = State(initialValue: v.vin ?? "")
        _victimBodyType = State(initialValue: v.bodyType)

        let s = forensicCase.suspectVehicle
        // NOTE(AI Developer): "Suspect vehicle identified" starts on if we
        // already have ANY suspect data — an existing Vehicle object (even
        // with no make/model yet, e.g. one auto-created by the first
        // captured suspect photo) counts, so the fields aren't hidden the
        // moment you open this after starting suspect photo capture.
        _recordSuspectInfo = State(initialValue: s != nil)
        _suspectMake = State(initialValue: s?.make ?? "")
        _suspectModel = State(initialValue: s?.model ?? "")
        _suspectYearText = State(initialValue: s?.year.map(String.init) ?? "")
        _suspectColor = State(initialValue: s?.color ?? "")
        _suspectPlate = State(initialValue: s?.licensePlate ?? "")
        _suspectVIN = State(initialValue: s?.vin ?? "")
        _suspectBodyType = State(initialValue: s?.bodyType ?? .car)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Case Info") {
                    LabeledContent("Case Number", value: original.caseNumber.isEmpty ? "—" : original.caseNumber)
                        .foregroundStyle(.secondary)
                    TextField("Case name", text: $caseName)
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
                    TextField("Make (e.g. Toyota)", text: $victimMake)
                        .textInputAutocapitalization(.words)
                    TextField("Model (e.g. Camry)", text: $victimModel)
                        .textInputAutocapitalization(.words)
                    TextField("Year", text: $victimYearText)
                        .keyboardType(.numberPad)
                    TextField("Color", text: $victimColor)
                        .textInputAutocapitalization(.words)
                    TextField("License Plate", text: $victimPlate)
                        .textInputAutocapitalization(.characters)
                    TextField("VIN (optional)", text: $victimVIN)
                        .textInputAutocapitalization(.characters)
                    Picker("Vehicle Type", selection: $victimBodyType) {
                        ForEach(VehicleBodyType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    if !original.victimVehicle.photos.isEmpty {
                        Text("\(original.victimVehicle.photos.count) photo(s) captured — unaffected by this form.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Suspect Vehicle") {
                    Toggle("Suspect vehicle identified", isOn: $recordSuspectInfo.animation())
                    if recordSuspectInfo {
                        TextField("Make (e.g. Ford)", text: $suspectMake)
                            .textInputAutocapitalization(.words)
                        TextField("Model (e.g. F-150)", text: $suspectModel)
                            .textInputAutocapitalization(.words)
                        TextField("Year", text: $suspectYearText)
                            .keyboardType(.numberPad)
                        TextField("Color", text: $suspectColor)
                            .textInputAutocapitalization(.words)
                        TextField("License Plate", text: $suspectPlate)
                            .textInputAutocapitalization(.characters)
                        TextField("VIN (optional)", text: $suspectVIN)
                            .textInputAutocapitalization(.characters)
                        Picker("Vehicle Type", selection: $suspectBodyType) {
                            ForEach(VehicleBodyType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    if let photoCount = original.suspectVehicle?.photos.count, photoCount > 0 {
                        Text("\(photoCount) photo(s) captured — unaffected by this form, even if you turn the toggle off.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Edit Case")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    // MARK: Save

    private func save() {
        var updated = original
        updated.caseName = caseName
        updated.caseType = caseType
        updated.notes = notes
        updated.incidentDate = recordIncidentDate ? incidentDate : nil

        let location = IncidentLocation(
            address: street.isEmpty ? nil : street,
            city: city.isEmpty ? nil : city,
            state: state.isEmpty ? nil : state,
            zip: zip.isEmpty ? nil : zip,
            // Preserve any existing GPS fix from the original location —
            // this form only edits the text fields, never the coordinate.
            coordinate: original.location?.coordinate
        )
        updated.location = location.isEmpty ? nil : location

        updated.victimVehicle.make = victimMake
        updated.victimVehicle.model = victimModel
        updated.victimVehicle.year = Int(victimYearText)
        updated.victimVehicle.color = victimColor
        updated.victimVehicle.licensePlate = victimPlate.isEmpty ? nil : victimPlate
        updated.victimVehicle.vin = victimVIN.isEmpty ? nil : victimVIN
        updated.victimVehicle.bodyType = victimBodyType

        if recordSuspectInfo {
            // Start from the existing suspect Vehicle if one exists (so we
            // don't clobber its photos/damageZones/lidarScanData/id), or a
            // fresh one if this is the first time suspect info is entered.
            var suspect = original.suspectVehicle ?? Vehicle(role: .suspect)
            suspect.make = suspectMake
            suspect.model = suspectModel
            suspect.year = Int(suspectYearText)
            suspect.color = suspectColor
            suspect.licensePlate = suspectPlate.isEmpty ? nil : suspectPlate
            suspect.vin = suspectVIN.isEmpty ? nil : suspectVIN
            suspect.bodyType = suspectBodyType
            updated.suspectVehicle = suspect
        } else if var suspect = original.suspectVehicle,
                  !suspect.photos.isEmpty || !suspect.damageZones.isEmpty || suspect.lidarScanData != nil {
            // Toggle was turned off, but this suspect Vehicle already has
            // real evidence attached (photos/damage/LiDAR) — never delete
            // that. Just clear the identifying text fields.
            suspect.make = ""
            suspect.model = ""
            suspect.year = nil
            suspect.color = ""
            suspect.licensePlate = nil
            suspect.vin = nil
            updated.suspectVehicle = suspect
        } else {
            // No evidence attached yet and the toggle is off — safe to
            // drop the placeholder suspect Vehicle entirely.
            updated.suspectVehicle = nil
        }

        dismiss()
        onSave(updated)
    }
}
