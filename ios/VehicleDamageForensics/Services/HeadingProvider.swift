// HeadingProvider.swift
// Vehicle Damage Investigation Assistant
// Thin CLLocationManager wrapper exposing the device's live compass
// heading, used by ImpactMarkerView to auto-fill direction of travel
// when the investigator is physically on-scene with the vehicle.
//
// NOTE(AI Developer), added 2026-07 per Sean's request ("should we...
// always identify the direction of traveling at impact") and the design
// discussion that followed: a *live* compass reading only makes sense
// when the phone is physically near the vehicle at the moment of
// capture -- for the "uploaded after the fact" scenario Sean flagged as
// the common case for skipped shots, there is no live heading to read,
// so `ImpactMarkerView` also offers a manual dial (`DirectionDialView`)
// as the other entry path. This class deliberately does NOT touch
// `CaptureViewModel`'s or `CameraService`'s existing `CLLocationManager`
// instances -- see the dead-duplicate-CLLocationManager bug fixed
// earlier this session in `CaptureViewModel.init` for why a THIRD
// idle/duplicate manager would be exactly the kind of regression to
// avoid. This one is intentionally short-lived: created only while
// `ImpactMarkerView` is on screen, and stopped via `stop()` in
// `.onDisappear`, rather than living for the whole capture session.

import Foundation
import CoreLocation
import Combine

@MainActor
final class HeadingProvider: NSObject, ObservableObject {
    @Published private(set) var headingDegrees: Double?
    @Published private(set) var isAvailable: Bool = CLLocationManager.headingAvailable()

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func start() {
        guard isAvailable else { return }
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingHeading()
    }
}

extension HeadingProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        // Prefer true heading when available (magnetometer + location
        // fix), fall back to magnetic heading otherwise.
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.headingDegrees = value
        }
    }
}
