// PhotoReviewView.swift
// Vehicle Damage Investigation Assistant
// Thumbnail grid review of everything captured so far for a case,
// with the ability to replace a wrong shot from the photo library or
// retake the most recent one -- before the user commits to "Run
// Analysis".
//
// NOTE(AI Developer), added 2026-07 per Sean's explicit request: "we
// need the ability to go back and change the images once it is
// submitted. I chose the wrong image from my roll and i could not go
// back and fix. lets see a review of the all the thumbnails of the
// images beofre its sumitted to be anaylised." This is the UI layer on
// top of `CaptureViewModel.reviewSlots(for:)` / `replacePhoto(atSlot:
// for:with:)` / `clearSlot(atSlot:for:)` (see those functions' doc
// comments for the underlying architecture -- in particular why
// "retake" is only offered for the LAST filled slot, while "replace
// from library" works for ANY slot regardless of position).

import SwiftUI
import PhotosUI

// MARK: - Photo Review View

struct PhotoReviewView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRole: VehicleRole
    @State private var enlargedSlot: ReviewSlot?
    // NOTE(AI Developer): set (and the sheet dismissed) only when the
    // user confirms "Retake" on the last-filled slot -- `CaptureFlowView`
    // reads this via the `onRetake` callback to both switch
    // `captureRole` to match and pop back to the live camera, already
    // pointed at the freshly-cleared slot (see `clearSlot`'s doc
    // comment: `nextShotType` naturally becomes that slot again once
    // it's cleared).
    let onRetake: (VehicleRole) -> Void

    init(viewModel: CaptureViewModel, onRetake: @escaping (VehicleRole) -> Void) {
        self.viewModel = viewModel
        self.onRetake = onRetake
        _selectedRole = State(initialValue: viewModel.captureRole)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.forensicCase.suspectVehicle != nil {
                    Picker("Vehicle", selection: $selectedRole) {
                        Text("Victim").tag(VehicleRole.victim)
                        Text("Suspect").tag(VehicleRole.suspect)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                }

                legend

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 14)], spacing: 18) {
                        ForEach(viewModel.reviewSlots(for: selectedRole)) { slot in
                            PhotoReviewCell(
                                slot: slot,
                                // Only the LAST occupied slot is eligible
                                // for "Retake" -- see `clearSlot`'s safety
                                // guard doc comment for exactly why a
                                // mid-sequence slot can't be safely
                                // reopened to the live camera the same way.
                                canRetake: slot.photo != nil
                                    && slot.index == viewModel.shotIndex(for: selectedRole) - 1,
                                onReplace: { image in
                                    Task { await viewModel.replacePhoto(atSlot: slot.index, for: selectedRole, with: image) }
                                },
                                onRetake: {
                                    Task {
                                        await viewModel.clearSlot(atSlot: slot.index, for: selectedRole)
                                        onRetake(selectedRole)
                                        dismiss()
                                    }
                                },
                                onTapPhoto: {
                                    if slot.photo != nil { enlargedSlot = slot }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Review Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $enlargedSlot) { slot in
            EnlargedReviewPhotoView(slot: slot)
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: .green, label: "Captured")
            legendItem(color: .orange, label: "Skipped")
            legendItem(color: .secondary, label: "Not yet taken")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.bottom, 6)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}

// MARK: - Single Review Cell

/// One thumbnail tile in the review grid, with its own `PhotosPickerItem`
/// state so each cell's "replace" picker is independent of every other
/// cell's (a `LazyVGrid`/`ForEach` can't share one `@State` across rows
/// the way `CaptureCameraView`'s single always-next-slot picker could).
private struct PhotoReviewCell: View {
    let slot: ReviewSlot
    let canRetake: Bool
    let onReplace: (UIImage) -> Void
    let onRetake: () -> Void
    let onTapPhoto: () -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var isLoading = false
    @State private var loadError: String?
    // NOTE(AI Developer): a real, separate `@State Bool` (rather than
    // `.constant(loadError != nil)`) since `.alert`'s `isPresented`
    // binding is written back to `false` on dismiss -- a `.constant(...)`
    // binding silently discards that write, so the alert would
    // immediately reappear while `loadError` is still non-nil after the
    // user taps OK. Set alongside `loadError` and cleared in the alert's
    // own action button.
    @State private var showLoadError = false
    @State private var showRetakeConfirmation = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                thumbnail
                if isLoading {
                    Color.black.opacity(0.35)
                    ProgressView().tint(.white)
                }
            }
            .frame(width: 108, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(borderColor, lineWidth: 2)
            )
            .onTapGesture(perform: onTapPhoto)

            Text(slot.photoType.displayName)
                .font(.caption2.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 28)

            HStack(spacing: 14) {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                }
                .disabled(isLoading)

                if canRetake {
                    Button {
                        showRetakeConfirmation = true
                    } label: {
                        Image(systemName: "camera.rotate")
                    }
                    .disabled(isLoading)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.blue)
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadAndApply(newItem) }
        }
        .confirmationDialog(
            "Retake this photo?",
            isPresented: $showRetakeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Retake", role: .destructive, action: onRetake)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear \(slot.photoType.displayName) and return you to the camera to shoot it again.")
        }
        .alert("Couldn't load photo", isPresented: $showLoadError, actions: {
            Button("OK") { loadError = nil }
        }, message: {
            Text(loadError ?? "")
        })
    }

    private func loadAndApply(_ item: PhotosPickerItem) async {
        isLoading = true
        defer {
            isLoading = false
            selectedItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                loadError = "Could not load the selected photo."
                showLoadError = true
                return
            }
            onReplace(image)
        } catch {
            loadError = error.localizedDescription
            showLoadError = true
        }
    }

    private var borderColor: Color {
        if slot.photo != nil { return .green }
        if slot.wasSkipped { return .orange }
        return .secondary.opacity(0.4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        // NOTE(AI Developer): `photo.imageData` is non-optional `Data`, so
        // `thumbnailData ?? imageData` itself is already non-optional --
        // only the FINAL `UIImage(data:)` step can fail/be nil here, so
        // that's the only one of these three that belongs in the `if let`
        // chain (Xcode build error: "Initializer for conditional binding
        // must have Optional type, not 'Data'" on the old 3-clause form).
        if let photo = slot.photo,
           let uiImage = UIImage(data: photo.thumbnailData ?? photo.imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .overlay(alignment: .bottomTrailing) {
                    if photo.wasImported {
                        Image(systemName: "square.and.arrow.down")
                            .font(.caption2)
                            .padding(4)
                            .background(.black.opacity(0.55), in: Circle())
                            .foregroundStyle(.white)
                            .padding(4)
                    }
                }
        } else if slot.wasSkipped {
            ZStack {
                Color.orange.opacity(0.12)
                VStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.forward.circle")
                        .foregroundStyle(.orange)
                    Text("Skipped")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            ZStack {
                Color.secondary.opacity(0.08)
                Image(systemName: "camera")
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
    }
}

// MARK: - Enlarged Photo Viewer

/// Full-screen zoomable-ish view of a single review slot's photo, with
/// its basic capture metadata -- lets the user confirm "yes, this really
/// is the wrong photo" before committing to replace/retake it, without
/// having to squint at a 108x108 thumbnail.
private struct EnlargedReviewPhotoView: View {
    let slot: ReviewSlot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                if let photo = slot.photo, let uiImage = UIImage(data: photo.imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                }
            }
            .background(Color.black)
            .navigationTitle(slot.photoType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let photo = slot.photo {
                    metadataStrip(photo)
                }
            }
        }
    }

    private func metadataStrip(_ photo: CapturedPhoto) -> some View {
        HStack(spacing: 16) {
            Label(photo.wasImported ? "From Library" : "Live Capture", systemImage: photo.wasImported ? "square.and.arrow.down" : "camera.fill")
            if !photo.wasImported {
                Label(String(format: "%.0f%%", photo.qualityScore * 100), systemImage: "checkmark.seal")
            }
            Spacer()
            Text("#\(slot.index + 1)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding()
        .background(.thinMaterial)
    }
}
