// PaintReferenceMarkerView.swift
// Vehicle Damage Investigation Assistant
// Reference-swatch capture step: tap the damaged/foreign-paint area AND
// a clean undamaged panel on the just-captured paint-transfer photo, both
// in the same shot/lighting. Feeds `CaptureViewModel.recordPaintReferenceTaps`,
// which is what actually powers the "Paint Transfer" correlation factor
// (30% weight -- the highest of the 7 -- and, before this fix, permanently
// `.unavailable` in every real case; see the NOTE on that method).
//
// NOTE(AI Developer), added 2026-07 as part of the paint-color
// reference-normalization fix Sean approved ("yes please do that" → "yes
// build it now") after asking "on the color matching, wont we run into
// issues matching OEM if we have poor lighting conditions or bad images
// taken?". Modeled on `ImpactMarkerView`/`ImpactSilhouetteView`'s
// tap-to-mark-with-normalized-coordinates pattern -- the key difference
// is this taps on the ACTUAL just-captured photo (`Image(uiImage:)`)
// rather than a drawn schematic outline, since the whole point is to
// sample real pixel colors at the tapped points.

import SwiftUI

struct PaintReferenceMarkerView: View {
    @ObservedObject var viewModel: CaptureViewModel
    let photo: CapturedPhoto
    @Environment(\.dismiss) private var dismiss

    private enum TapTarget {
        case damage, reference
    }

    @State private var damagePoint: CGPoint?
    @State private var referencePoint: CGPoint?
    @State private var activeTarget: TapTarget = .damage
    @State private var isSaving = false
    @State private var uiImage: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Tap the damaged / transferred-paint area")
                        .font(.headline)
                    Text("Tap the exact spot where foreign paint or a paint transfer mark is visible.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    whyThisMattersNote("Sampling this spot lets the app compare the actual transferred paint color against the other vehicle's own color — not just a general photo average.")

                    photoTapArea
                        .frame(height: 280)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 8) {
                    Text("2. Tap a clean, undamaged panel")
                        .font(.headline)
                    Text("Tap a spot nearby with this vehicle's own original paint, in the SAME photo.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    whyThisMattersNote("Because it's the same photo, this reference is under the exact same lighting as the damage tap above — so the comparison isn't thrown off by shadows, glare, or a different photo's white balance.")

                    Picker("Now tapping", selection: $activeTarget) {
                        Text("Damage Area").tag(TapTarget.damage)
                        Text("Clean Panel").tag(TapTarget.reference)
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                Button {
                    Task { await save() }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Label("Save Paint Reference", systemImage: "checkmark.circle.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .disabled(damagePoint == nil || referencePoint == nil || isSaving)

                Button("Skip This Photo") { dismiss() }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Paint Reference Sample")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            uiImage = UIImage(data: photo.imageData)
            if let existingDamage = photo.paintDamagePoint { damagePoint = existingDamage }
            if let existingReference = photo.paintReferencePoint {
                referencePoint = existingReference
                activeTarget = .damage
            } else if photo.paintDamagePoint != nil {
                activeTarget = .reference
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("\(viewModel.captureRole.displayName) Vehicle — \(photo.photoType.displayName)")
                .font(.title3.bold())
            Text("Two taps on this same photo let the app compare paint color under identical lighting.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Why this matters

    /// Same understated in-flow guidance pattern as `ImpactMarkerView`'s
    /// `whyThisMattersNote` -- small font, lightbulb icon, secondary
    /// color, so it reads as a helpful aside rather than competing for
    /// attention with the actual tap instructions.
    @ViewBuilder
    private func whyThisMattersNote(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "lightbulb.fill")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom, 4)
    }

    // MARK: Photo tap area

    private var photoTapArea: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                    ProgressView()
                }

                if let damagePoint {
                    markerDot(color: .red, label: "D")
                        .position(x: damagePoint.x * w, y: damagePoint.y * h)
                }
                if let referencePoint {
                    markerDot(color: .green, label: "C")
                        .position(x: referencePoint.x * w, y: referencePoint.y * h)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .onTapGesture { location in
                let normalized = CGPoint(
                    x: min(max(location.x / w, 0), 1),
                    y: min(max(location.y / h, 0), 1)
                )
                switch activeTarget {
                case .damage:
                    damagePoint = normalized
                    if referencePoint == nil { activeTarget = .reference }
                case .reference:
                    referencePoint = normalized
                }
            }
        }
    }

    private func markerDot(color: Color, label: String) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    // MARK: Save

    private func save() async {
        guard let damagePoint, let referencePoint else { return }
        isSaving = true
        await viewModel.recordPaintReferenceTaps(
            photoID: photo.id,
            damagePoint: damagePoint,
            referencePoint: referencePoint
        )
        isSaving = false
        dismiss()
    }
}
