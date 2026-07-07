// ModelExtensions.swift
// Vehicle Damage Forensic Matcher
// Convenience conformances and helpers we need across views & view-models.
// These are kept separate from the canonical model files so the underlying
// data contracts in Models/ remain pure value-type definitions.

import Foundation

// MARK: - ForensicCase Hashable (for NavigationStack value-based routing)

extension ForensicCase: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Vehicle Hashable

extension Vehicle: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Convenience accessors

extension ForensicCase {
    /// Total number of usable photos across both vehicles.
    var totalPhotoCount: Int {
        victimVehicle.photos.count + (suspectVehicle?.photos.count ?? 0)
    }

    // NOTE(AI Developer): `isReadyForAnalysis` is defined on the primary
    // model in Case.swift. This file previously declared a second,
    // conflicting `isReadyForAnalysis` here (suspectVehicle != nil && >= 5
    // photos per side vs. Case.swift's >= 4), which is an invalid
    // redeclaration and does not compile — removed. RESOLVED (2026-07):
    // Sean confirmed the threshold should derive from the actual capture
    // protocol rather than either hardcoded number; Case.swift's
    // `isReadyForAnalysis` now reads `PhotoType.requiredCaptureProtocol.count`
    // (see Models/Vehicle.swift), which is also what
    // `CaptureViewModel.protocolShots` uses, so all three can't drift out
    // of sync again.
}

extension Vehicle {
    /// Pick the highest-quality damage closeup, if any.
    var bestDamagePhoto: CapturedPhoto? {
        photos
            .filter { $0.photoType == .closeupDamage || $0.photoType == .paintTransfer }
            .max(by: { $0.qualityScore < $1.qualityScore })
    }
}
