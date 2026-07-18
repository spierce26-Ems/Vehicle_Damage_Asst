// CaptureViewModel.swift
// Vehicle Damage Investigation Assistant
// Drives the 30-shot guided photo capture protocol. Tracks shot
// progress, exposes the next required photo type, and handles the
// hand-off to the camera + LiDAR services.

import Foundation
import UIKit
import Combine
import CoreMotion
import CoreLocation

// MARK: - Review Slot

/// One position in `CaptureViewModel.protocolShots` for a given vehicle,
/// paired with whatever currently occupies it (a real photo, an explicit
/// skip, or nothing yet).
///
/// NOTE(AI Developer), added 2026-07 alongside `CaptureViewModel.
/// reviewSlots(for:)` per Sean's "review of all the thumbnails... before
/// its submitted" request. Deliberately a plain top-level struct (not
/// nested in `CaptureViewModel`) so `PhotoReviewView` and any preview/
/// test code can reference `ReviewSlot` directly. `Identifiable` via
/// `index` (unique per role's slot list, stable for the lifetime of a
/// single `PhotoReviewView` presentation) so it can back a SwiftUI
/// `ForEach`/`LazyVGrid` with no extra wrapping.
struct ReviewSlot: Identifiable {
    var id: Int { index }
    /// 0-based position within `protocolShots`.
    let index: Int
    let photoType: PhotoType
    /// The photo currently filling this slot, if any. `nil` if the slot
    /// is empty (not yet reached) OR was explicitly skipped -- check
    /// `wasSkipped` to distinguish "not reached yet" from "skipped".
    let photo: CapturedPhoto?
    /// True if this slot was explicitly skipped via `skipCurrentShot`
    /// rather than simply not-yet-reached.
    let wasSkipped: Bool

    /// True if this slot is beyond the vehicle's current progress --
    /// neither filled nor skipped. Kept separate from `wasSkipped` so
    /// `PhotoReviewView` can render a third, distinct "not reached yet"
    /// state (vs. a photo thumbnail or a "Skipped" placeholder).
    var isPending: Bool { photo == nil && !wasSkipped }
}

@MainActor
final class CaptureViewModel: ObservableObject {

    // MARK: Published

    @Published var forensicCase: ForensicCase
    @Published var captureRole: VehicleRole = .victim
    @Published private(set) var currentSensorData: SensorData = SensorData()
    @Published private(set) var lastQualityFlags: QualityFlags = QualityFlags()
    @Published var statusMessage: String = "Position phone perpendicular to damage."
    @Published var isCapturing: Bool = false

    // MARK: Protocol definition

    /// Ordered list of shot types required for a complete capture.
    /// NOTE(AI Developer): Now sourced from `PhotoType.requiredCaptureProtocol`
    /// (Models/Vehicle.swift) — the single canonical v1 shot list — instead
    /// of a separately-maintained literal array, so this can't silently
    /// drift out of sync with `ForensicCase.isReadyForAnalysis` again.
    let protocolShots: [PhotoType] = PhotoType.requiredCaptureProtocol

    // NOTE(AI Developer), fixed 2026-07 per Sean's on-device report
    // ("terminated due to using too much memory", Xcode debug code 9,
    // recurring even after the CameraService-level fixes this same
    // round): this used to be `capturedPhotos.count`, backed by a
    // `@Published private(set) var capturedPhotos: [CapturedPhoto] = []`
    // that `record(photo:)`/`importPhoto(_:)` appended to on every shot
    // and `switchToSuspect()` cleared via `.removeAll()`. That array's
    // *only* real purpose was this shot count -- nothing ever read its
    // contents (confirmed via a full-codebase grep) -- but every photo
    // appended to it is *also* already stored in
    // `forensicCase.victimVehicle.photos`/`.suspectVehicle.photos` right
    // below in the same functions. That's the exact same dead-duplicate-
    // array bug fixed in `CameraService.capturedPhotos` two rounds ago,
    // just one level higher in the call stack, and it slipped through
    // that audit specifically because `.count` on it looked like a real
    // reader. A full two-vehicle, 30-shot protocol run was keeping a
    // *third* full-resolution copy of every photo's `imageData` in
    // memory for the entire capture session because of this. Removed
    // the array entirely; the shot count is derived directly from
    // whichever vehicle's photo list matches the active `captureRole`,
    // which is the actual source of truth and needs no separate
    // bookkeeping (it also naturally resets to 0 the moment
    // `switchToSuspect()` flips `captureRole`, since
    // `forensicCase.suspectVehicle?.photos` starts empty -- no explicit
    // `.removeAll()` call needed there anymore either).
    //
    // NOTE(AI Developer), updated 2026-07 per Sean's "skip a shot"
    // request: now counts explicitly-skipped slots (`Vehicle.
    // skippedShotIndices`) toward the pointer as well as actually
    // captured/imported photos, so skipping a slot correctly advances
    // to the next one instead of leaving `nextShotType` stuck asking for
    // the shot that was just skipped. Both `photos` and
    // `skippedShotIndices` are only ever appended to in protocol order,
    // so their combined count is still a correct pointer into
    // `protocolShots`.
    var currentShotIndex: Int { shotIndex(for: captureRole) }

    /// NOTE(AI Developer), added 2026-07 alongside `PhotoReviewView`: same
    /// derivation as `currentShotIndex` above, generalized to take an
    /// explicit `VehicleRole` instead of always reading the active
    /// `captureRole` -- needed so the review screen can compute "is this
    /// the one pending slot the user is actually allowed to act on right
    /// now" for a specific vehicle without depending on which vehicle
    /// happens to be currently selected.
    func shotIndex(for role: VehicleRole) -> Int {
        switch role {
        case .victim:
            return forensicCase.victimVehicle.photos.count
                + forensicCase.victimVehicle.skippedShotIndices.count
        case .suspect:
            return (forensicCase.suspectVehicle?.photos.count ?? 0)
                + (forensicCase.suspectVehicle?.skippedShotIndices.count ?? 0)
        }
    }

    var nextShotType: PhotoType? {
        guard currentShotIndex < protocolShots.count else { return nil }
        return protocolShots[currentShotIndex]
    }

    var progress: Double {
        Double(currentShotIndex) / Double(protocolShots.count)
    }

    var isComplete: Bool {
        currentShotIndex >= protocolShots.count
    }

    /// True once the active vehicle's impact location + direction of
    /// travel have both been recorded. NOTE(AI Developer), added 2026-07
    /// per Sean's decision that this step is REQUIRED (unlike the
    /// skippable photo protocol) -- drives the "Continue to Suspect" /
    /// "Run Analysis" button gating in `CaptureFlowView` alongside
    /// `isComplete`. See `Vehicle.hasImpactProfile`.
    var hasImpactProfile: Bool {
        switch captureRole {
        case .victim: return forensicCase.victimVehicle.hasImpactProfile
        case .suspect: return forensicCase.suspectVehicle?.hasImpactProfile ?? false
        }
    }

    /// True once the active vehicle's scar photo has been captured
    /// (`Vehicle.hasScarPhoto`). NOTE(AI Developer), added 2026-07 for
    /// `CaptureFlowView`'s optional Scar Direction button -- unlike
    /// `hasImpactProfile`, this deliberately does NOT gate
    /// "Continue"/"Run Analysis" (Sean's explicit answer: a missing/
    /// inconclusive scar reading should let the other 6 factors decide).
    var hasScarPhoto: Bool {
        switch captureRole {
        case .victim: return forensicCase.victimVehicle.hasScarPhoto
        case .suspect: return forensicCase.suspectVehicle?.hasScarPhoto ?? false
        }
    }

    /// True once the active vehicle's scar direction has actually
    /// resolved to a real value (not just "a photo was taken" -- see
    /// `hasScarPhoto` for that weaker check). Drives the checkmark vs.
    /// plain "optional" state on `CaptureFlowView`'s Scar Direction
    /// button.
    var hasScarDirection: Bool {
        switch captureRole {
        case .victim: return forensicCase.victimVehicle.hasScarDirection
        case .suspect: return forensicCase.suspectVehicle?.hasScarDirection ?? false
        }
    }

    // MARK: Review slots

    /// The full, ordered list of `protocolShots` slots for `role`, each
    /// paired with whatever actually occupies it right now (a captured/
    /// imported photo, an explicit skip, or nothing yet if it's beyond
    /// that vehicle's `currentShotIndex`).
    ///
    /// NOTE(AI Developer), added 2026-07 per Sean's explicit request
    /// ("lets see a review of all the thumbnails of the images before
    /// its submitted to be analysed... we need the ability to go back
    /// and change the images"). Before this, there was no single place
    /// that reconstructed "what's in slot N" -- `Vehicle.photos` and
    /// `Vehicle.skippedShotIndices` are two separate append-only lists
    /// with no shared ordering key other than the fact that, together,
    /// their *counts* sum to `currentShotIndex` (see that property's own
    /// NOTE). This walks `protocolShots` in order and, for each position,
    /// looks up whichever photo's `sequenceIndex` matches that slot
    /// (1-based, matching `record(photo:)`/`importPhoto(_:)`'s
    /// `sequenceIndex = currentShotIndex + 1`) or whether that index was
    /// recorded as skipped -- giving `PhotoReviewView` one ordered array
    /// it can render as a grid and act on directly.
    func reviewSlots(for role: VehicleRole) -> [ReviewSlot] {
        let vehicle: Vehicle? = {
            switch role {
            case .victim: return forensicCase.victimVehicle
            case .suspect: return forensicCase.suspectVehicle
            }
        }()
        guard let vehicle else {
            return protocolShots.enumerated().map { index, type in
                ReviewSlot(index: index, photoType: type, photo: nil, wasSkipped: false)
            }
        }
        let skippedSet = Set(vehicle.skippedShotIndices)
        return protocolShots.enumerated().map { index, type in
            // `sequenceIndex` is 1-based (see `record(photo:)`), slot
            // `index` here is 0-based -- +1 to compare correctly.
            let photo = vehicle.photos.first { $0.sequenceIndex == index + 1 }
            return ReviewSlot(index: index, photoType: type, photo: photo, wasSkipped: skippedSet.contains(index))
        }
    }

    /// Replace whatever currently occupies protocol slot `index` for
    /// `role` with a freshly-imported library photo -- the fix for
    /// Sean's "I chose the wrong image from my roll and could not go
    /// back and fix" report. Works whether the slot was previously
    /// filled by a real photo, previously skipped, or (defensively)
    /// still empty; in every case the end state is "slot `index` now
    /// holds this photo, and is no longer marked skipped."
    ///
    /// NOTE(AI Developer), added 2026-07. Deliberately a separate entry
    /// point from `importPhoto(_:)` (which only ever appends to
    /// `nextShotType`, the NEXT unfilled slot) -- this one targets an
    /// arbitrary, already-processed slot by its protocol index, which is
    /// the actual architectural gap Sean hit. Mirrors `importPhoto(_:)`'s
    /// own resize/thumbnail/`wasImported: true` handling exactly, so a
    /// slot fixed this way carries the identical honesty-about-provenance
    /// guarantee (see `CapturedPhoto.wasImported`'s doc comment) as a
    /// same-flow import.
    func replacePhoto(atSlot index: Int, for role: VehicleRole, with image: UIImage) async {
        guard index >= 0, index < protocolShots.count else { return }
        let type = protocolShots[index]
        let stored = resizedForStorage(image)
        let data = stored.jpegData(compressionQuality: 0.85) ?? Data()
        let thumb = stored.preparingThumbnail(of: CGSize(width: 240, height: 240))?
            .jpegData(compressionQuality: 0.6)
        let photo = CapturedPhoto(
            imageData: data,
            thumbnailData: thumb,
            captureDate: Date(),
            photoType: type,
            qualityScore: 0.0,
            qualityFlags: QualityFlags(),
            sensorData: SensorData(),
            gpsCoordinate: nil,
            cameraSettings: CameraSettings(),
            sequenceIndex: index + 1,
            annotationNotes: "Imported from photo library (replaces earlier slot content)",
            wasImported: true
        )

        func apply(to vehicle: inout Vehicle) {
            vehicle.skippedShotIndices.removeAll { $0 == index }
            if let existingPos = vehicle.photos.firstIndex(where: { $0.sequenceIndex == index + 1 }) {
                vehicle.photos[existingPos] = photo
            } else {
                vehicle.photos.append(photo)
            }
        }

        switch role {
        case .victim:
            apply(to: &forensicCase.victimVehicle)
        case .suspect:
            if forensicCase.suspectVehicle == nil {
                forensicCase.suspectVehicle = Vehicle(role: .suspect)
            }
            guard var suspect = forensicCase.suspectVehicle else { return }
            apply(to: &suspect)
            forensicCase.suspectVehicle = suspect
        }
        forensicCase.recordAudit(.photoReplaced, detail: "\(role.displayName): \(type.displayName) (#\(index + 1))")
        await storage.save(forensicCase)
        updateGuidance()
    }

    /// Clear protocol slot `index` for `role` back to empty (removing
    /// either its captured/imported photo or its skip flag) WITHOUT
    /// immediately supplying a replacement -- used by `PhotoReviewView`'s
    /// "Retake" action, which dismisses back to the live camera pointed
    /// at that same slot rather than going straight to the photo picker.
    /// NOTE(AI Developer), added 2026-07 alongside `replacePhoto(atSlot:)`
    /// for the same "go back and fix a specific shot" request.
    ///
    /// IMPORTANT SAFETY GUARD: unlike `replacePhoto(atSlot:for:with:)`
    /// (which overwrites IN PLACE and never changes `photos.count`, so
    /// it's safe for any slot regardless of position), this function
    /// only allows clearing `index` when it is the LAST occupied slot for
    /// `role` (`index == shotIndex(for: role) - 1`). Reason: `nextShotType`/
    /// `currentShotIndex` are derived purely from `photos.count +
    /// skippedShotIndices.count` -- a simple counter, not a real pointer
    /// into `protocolShots`. If a slot in the MIDDLE of an already-filled
    /// sequence were cleared, that counter would silently decrease by one
    /// while every later slot's `CapturedPhoto.sequenceIndex` stays
    /// exactly where it was -- `nextShotType` would then point at
    /// whichever later slot happens to match the new (wrong) count,
    /// while the actually-empty middle slot is never revisited by the
    /// live capture flow at all (only `reviewSlots(for:)`'s direct
    /// sequenceIndex lookup would still show it correctly as empty).
    /// Clearing only ever the last slot keeps that counter and the real
    /// "what's actually filled" state in agreement, so the live camera
    /// correctly re-asks for exactly the slot that was just cleared. For
    /// any slot that ISN'T the last one, `PhotoReviewView` only offers
    /// "Replace from Photo Library" (`replacePhoto`), never "Retake".
    func clearSlot(atSlot index: Int, for role: VehicleRole) async {
        guard index >= 0, index < protocolShots.count else { return }
        guard index == shotIndex(for: role) - 1 else { return }
        func apply(to vehicle: inout Vehicle) {
            vehicle.skippedShotIndices.removeAll { $0 == index }
            vehicle.photos.removeAll { $0.sequenceIndex == index + 1 }
        }
        switch role {
        case .victim:
            apply(to: &forensicCase.victimVehicle)
        case .suspect:
            guard var suspect = forensicCase.suspectVehicle else { return }
            apply(to: &suspect)
            forensicCase.suspectVehicle = suspect
        }
        await storage.save(forensicCase)
        updateGuidance()
    }

    // MARK: Dependencies

    private let storage: StorageService
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()

    /// NOTE(AI Developer): `storage` defaults to `nil` here (rather than
    /// `= .shared` directly in the parameter list) because default-argument
    /// expressions are evaluated in a non-isolated context under Swift 6
    /// strict concurrency, and `StorageService.shared` is `@MainActor`-
    /// isolated. Resolving the actual default inside the (MainActor-
    /// isolated) init body avoids the "Call to main actor-isolated ...
    /// from synchronous nonisolated context" error.
    ///
    /// NOTE(AI Developer), fixed 2026-07 per Sean's on-device report
    /// ("terminated due to using too much memory", Xcode debug code 9):
    /// this used to also accept/store a `cameraService: CameraService?`
    /// parameter, defaulting to a brand-new `CameraService()` -- but
    /// nothing on `self.cameraService` was ever called anywhere in this
    /// class (confirmed via grep) and no caller ever passed one in either
    /// (`CaptureFlowView` only ever calls `CaptureViewModel(forensicCase:)`).
    /// `CaptureCameraView` creates and drives its own, completely separate
    /// `CameraService` instance for the actual live preview/capture --
    /// this one was a second, fully-idle copy, whose own `init()` starts
    /// a second `CMMotionManager` (30Hz device-motion updates) and a
    /// second `CLLocationManager` (continuous location updates) that ran
    /// for the entire capture session for no purpose. Removed the
    /// property and parameter entirely.
    init(forensicCase: ForensicCase,
         storage: StorageService? = nil) {
        self.forensicCase = forensicCase
        self.storage = storage ?? .shared
        startSensors()
    }

    // MARK: Public API

    /// Record a live-captured photo into the case under the active vehicle role.
    ///
    /// NOTE(AI Developer), fixed 2026-07 per Sean's on-device report
    /// ("terminated due to using too much memory", Xcode debug code 9):
    /// this used to take a `UIImage` and *rebuild* a brand-new
    /// `CapturedPhoto` from scratch -- but the caller
    /// (`CaptureCameraView.captureNextShot()`) already has a fully-formed
    /// `CapturedPhoto` straight from `CameraService.capturePhoto(...)`,
    /// complete with the correct GPS coordinate, gravity-corrected sensor
    /// reading (`SensorReading`/`CameraLevelMath`), and a real
    /// roll/pitch/brightness-based quality score. To call this old
    /// signature, the caller had to decode that photo's `imageData` back
    /// into a full-resolution `UIImage` (~46.5MB bitmap) purely so this
    /// method could re-encode it to JPEG *again* and throw together a
    /// second, strictly worse `CapturedPhoto` (`estimateQuality(for:)`'s
    /// placeholder score instead of the camera's real one, no GPS via
    /// `currentLocation()` -- see NOTE below -- and `currentSensorData`/
    /// `lastQualityFlags`, which are just late CoreMotion snapshots on
    /// this view model, not necessarily the exact reading at the instant
    /// of capture). That decode+re-encode round trip was a third
    /// full-resolution image operation per shot, on top of the two fixed
    /// in `CameraService.generateThumbnail`/`estimateBrightness` this same
    /// round -- and it was strictly *lossy* for the forensic record.
    /// Fixed by accepting the camera's own `CapturedPhoto` directly: no
    /// image decode of any kind happens here anymore, and the persisted
    /// record now uses the camera's own accurate metadata unconditionally.
    func record(photo capturedPhoto: CapturedPhoto) async {
        guard nextShotType != nil else { return }
        var photo = capturedPhoto
        photo.sequenceIndex = currentShotIndex + 1
        switch captureRole {
        case .victim:
            forensicCase.victimVehicle.photos.append(photo)
        case .suspect:
            if forensicCase.suspectVehicle == nil {
                forensicCase.suspectVehicle = Vehicle(role: .suspect)
            }
            forensicCase.suspectVehicle?.photos.append(photo)
        }
        // NOTE(AI Developer): Chain-of-custody entry per Sean's decision to
        // add the audit log (2026-07). Recorded before save so the entry is
        // persisted atomically with the photo it describes.
        forensicCase.recordAudit(.photoCaptured, detail: "\(captureRole.displayName): \(photo.photoType.displayName) (#\(photo.sequenceIndex))")
        await storage.save(forensicCase)
        updateGuidance()
    }

    /// Import an existing photo (e.g. from the camera roll) into the case
    /// under the active vehicle role, counting it toward the current
    /// required shot slot just like a live capture.
    ///
    /// NOTE(AI Developer), added 2026-07 per Sean's request ("we also
    /// should have the ability to upload images from camera roll") --
    /// useful when e.g. a bystander already snapped a photo of the
    /// suspect vehicle before Sean arrived, or a photo was taken on a
    /// different device and AirDropped over. Deliberately mirrors
    /// `record(photo:)`'s structure (same audit-then-save ordering, same
    /// role-based routing) so the two capture paths can't silently drift
    /// apart, but marks the result `wasImported: true` and skips
    /// sensor/GPS/quality scoring -- there's no live sensor reading for a
    /// photo that wasn't just taken by this device, and fabricating one
    /// would misrepresent the evidence record. See `CapturedPhoto.wasImported`.
    func importPhoto(_ image: UIImage) async {
        guard let type = nextShotType else { return }
        // NOTE(AI Developer), fixed 2026-07 per Sean's on-device report
        // ("its been 'running correlation analysis' for a few minutes
        // again"): unlike the live-capture path (`record(photo:)`), whose
        // source photo comes from `CameraService.capturePhoto()` (already
        // capped via `photoOutput.maxPhotoDimensions`), this path's `image` comes
        // straight from `PhotosPicker`/`loadTransferable` with NO
        // resolution cap -- a picked photo can be the device's full
        // native resolution (e.g. a 48MP ProRAW-derived JPEG), which
        // bloats `CapturedPhoto.imageData`, in turn bloating the case's
        // JSON file, and reproduces the same class of slow encode/write
        // that `StorageService`'s background-task fix addressed for the
        // *live-capture* path -- just via this different (import) entry
        // point. `resizedForStorage` applies the same ~12MP cap already
        // used in `CameraService.swift` before we ever call `jpegData`.
        let stored = resizedForStorage(image)
        let data = stored.jpegData(compressionQuality: 0.85) ?? Data()
        let thumb = stored.preparingThumbnail(of: CGSize(width: 240, height: 240))?
            .jpegData(compressionQuality: 0.6)

        let photo = CapturedPhoto(
            imageData: data,
            thumbnailData: thumb,
            captureDate: Date(),
            photoType: type,
            qualityScore: 0.0,
            qualityFlags: QualityFlags(),
            sensorData: SensorData(),
            gpsCoordinate: nil,
            cameraSettings: CameraSettings(),
            sequenceIndex: currentShotIndex + 1,
            annotationNotes: "Imported from photo library",
            wasImported: true
        )
        switch captureRole {
        case .victim:
            forensicCase.victimVehicle.photos.append(photo)
        case .suspect:
            if forensicCase.suspectVehicle == nil {
                forensicCase.suspectVehicle = Vehicle(role: .suspect)
            }
            forensicCase.suspectVehicle?.photos.append(photo)
        }
        forensicCase.recordAudit(.photoImported, detail: "\(captureRole.displayName): \(type.displayName) (#\(photo.sequenceIndex))")
        await storage.save(forensicCase)
        updateGuidance()
    }

    /// Explicitly skip the current required shot slot without capturing
    /// or importing a photo for it, advancing to the next shot in the
    /// protocol.
    ///
    /// NOTE(AI Developer), added 2026-07 per Sean's explicit request
    /// ("we should be able to skip a certain image view if we dont have
    /// an image in the camera roll or are no longer near the vehicle...
    /// most times this will likely be images uploaded after the fact")
    /// and his follow-up answers: skipping counts a slot as "done" for
    /// completion purposes ("a skipped shot should account for done
    /// unless the image is absolutely necessary"), and no shot type is
    /// mandatory/unskippable ("let's not allow mandatory shots" — every
    /// entry in `protocolShots` can be skipped). Records the skip in the
    /// chain-of-custody audit log (distinct `.photoSkipped` action, see
    /// `AuditAction`) with the shot type and reason so the gap is
    /// transparent in the report rather than silently missing -- see
    /// Sean's decision on the results/PDF wording ("Shot X was skipped:
    /// not available"), rendered by `MatchResultsView`/`PDFReportGenerator`
    /// reading `Vehicle.skippedShotIndices` against `protocolShots`.
    ///
    /// `reason` is free text describing *why* (surfaced to the button's
    /// confirmation dialog in `CaptureCameraView` — e.g. "No matching
    /// photo in camera roll" or "No longer near vehicle") so the audit
    /// trail records intent, not just the fact that a slot was skipped.
    func skipCurrentShot(reason: String) async {
        guard let type = nextShotType else { return }
        let skippedIndex = currentShotIndex
        switch captureRole {
        case .victim:
            forensicCase.victimVehicle.skippedShotIndices.append(skippedIndex)
        case .suspect:
            if forensicCase.suspectVehicle == nil {
                forensicCase.suspectVehicle = Vehicle(role: .suspect)
            }
            forensicCase.suspectVehicle?.skippedShotIndices.append(skippedIndex)
        }
        forensicCase.recordAudit(.photoSkipped, detail: "\(captureRole.displayName): \(type.displayName) (#\(skippedIndex + 1)) — \(reason)")
        await storage.save(forensicCase)
        updateGuidance()
    }

    /// Record the active vehicle's impact location (tap point on the
    /// top-down silhouette, normalized 0-1/0-1) and direction of travel
    /// at impact (compass degrees, 0-360).
    ///
    /// NOTE(AI Developer), added 2026-07 per Sean's request ("should we
    /// identify the location of the damage on each vehicle and always
    /// identify the direction of traveling at impact... to help
    /// correlating data") and his follow-up decision that this step is
    /// REQUIRED (unlike photo skipping). Called from `ImpactMarkerView`
    /// once the user has both tapped a damage location and set a heading
    /// (live compass or manual dial — see that view for the two entry
    /// modes). Feeds `MatchScoreCalculator.scoreImpactGeometry` via
    /// `Vehicle.impactBearingDegrees` — see that property's doc comment
    /// for why this specific combination of inputs produces a real,
    /// usable impact-angle-reciprocity score where none existed before.
    func recordImpactProfile(tapPoint: CGPoint, directionDegrees: Double) async {
        let wasAlreadyRecorded: Bool
        switch captureRole {
        case .victim:
            wasAlreadyRecorded = forensicCase.victimVehicle.hasImpactProfile
            forensicCase.victimVehicle.impactTapPoint = tapPoint
            forensicCase.victimVehicle.directionOfTravelDegrees = directionDegrees
        case .suspect:
            if forensicCase.suspectVehicle == nil {
                forensicCase.suspectVehicle = Vehicle(role: .suspect)
            }
            wasAlreadyRecorded = forensicCase.suspectVehicle?.hasImpactProfile ?? false
            forensicCase.suspectVehicle?.impactTapPoint = tapPoint
            forensicCase.suspectVehicle?.directionOfTravelDegrees = directionDegrees
        }
        // Only log the audit entry the first time this vehicle's profile
        // is completed, not on every subsequent adjustment/re-tap.
        if !wasAlreadyRecorded {
            forensicCase.recordAudit(.impactProfileRecorded, detail: "\(captureRole.displayName) vehicle")
        }
        await storage.save(forensicCase)
    }

    /// Record a physical damage height (inches) measured directly off the
    /// LiDAR-reconstructed mesh, via `LiDARScanView`'s tap-to-measure step
    /// (tap the ground, then tap the damage point; the vertical distance
    /// between the two raycast hits is `inches`).
    ///
    /// NOTE(AI Developer), added 2026-07 per Sean's explicit request ("wire
    /// LiDAR data into the Height Alignment factor as a next step... we
    /// need the use of Lidar as an extra tool"). Mirrors
    /// `recordImpactProfile(tapPoint:directionDegrees:)`'s structure
    /// (role-based switch, `wasAlreadyRecorded` guard so re-measuring
    /// doesn't spam the audit log, then persist). Sets
    /// `Vehicle.lidarMeasuredHeightInches`, which
    /// `Vehicle.effectiveBumperHeightInches` prefers over the
    /// never-actually-populated manual-entry `bumperHeightInches` field --
    /// see that computed property and its use in
    /// `MatchScoreCalculator.evaluate()`.
    func recordLiDARMeasurement(inches: Double) async {
        let wasAlreadyRecorded: Bool
        switch captureRole {
        case .victim:
            wasAlreadyRecorded = forensicCase.victimVehicle.hasLiDARMeasurement
            forensicCase.victimVehicle.lidarMeasuredHeightInches = inches
        case .suspect:
            if forensicCase.suspectVehicle == nil {
                forensicCase.suspectVehicle = Vehicle(role: .suspect)
            }
            wasAlreadyRecorded = forensicCase.suspectVehicle?.hasLiDARMeasurement ?? false
            forensicCase.suspectVehicle?.lidarMeasuredHeightInches = inches
        }
        // Only log the audit entry the first time this vehicle gets a
        // measurement, not on every subsequent re-measure.
        if !wasAlreadyRecorded {
            forensicCase.recordAudit(.lidarMeasurementRecorded, detail: "\(captureRole.displayName) vehicle: \(String(format: "%.1f", inches))\"")
        }
        await storage.save(forensicCase)
    }

    /// Record the two reference-swatch tap points (damage/foreign-paint
    /// area + clean undamaged panel) against an already-captured
    /// `.paintTransfer` photo, extract localized colors at each point, and
    /// build/update a real `PaintAnalysis` on this vehicle's primary
    /// `DamageZone` -- creating that zone if this is the first time any
    /// paint reference has been recorded for this vehicle.
    ///
    /// NOTE(AI Developer), added 2026-07 as the centerpiece of the
    /// paint-color reference-normalization fix Sean approved ("yes please
    /// do that" → "yes build it now") after asking "on the color
    /// matching, wont we run into issues matching OEM if we have poor
    /// lighting conditions or bad images taken?". Root cause (confirmed
    /// via exhaustive grep before writing this): `DamageZone`/
    /// `PaintAnalysis`/`Vehicle.colorRGB` were never populated ANYWHERE in
    /// the real app -- `PaintTransferAnalyzer.analyze()` always hit its
    /// `.unavailable` guard, so paint transfer (30% weight, the highest of
    /// the 7 factors) never actually ran in any real case. This is the
    /// first real writer for those fields.
    ///
    /// Methodology (per the approved spec): both tap points are sampled
    /// from the SAME photo, so they share identical lighting/white-balance/
    /// exposure -- comparisons are relative to each vehicle's own
    /// same-photo reference rather than trusting absolute color values
    /// across different photos taken in different conditions. `foreignPaintRGB`
    /// is set from the damage-area tap (the paint transferred FROM the
    /// other vehicle), while `primaryColorRGB` is set from the clean-panel
    /// tap (this vehicle's own true color, sampled under the same
    /// lighting as the damage tap -- see `PaintTransferAnalyzer.analyze()`'s
    /// rewritten reciprocity check for how the two vehicles' zones are
    /// compared against each other).
    ///
    /// Confidence downgrade: if either localized sample shows high
    /// rejected-pixel fraction or high residual luminance variance (glare/
    /// shadow contamination even after outlier clipping -- see
    /// `ColorAnalysis.LocalSample`), the resulting `PaintAnalysis` isn't
    /// flagged `foreignPaintDetected` with full confidence; instead we
    /// mark the underlying `FactorScore` `.partial` downstream in
    /// `PaintTransferAnalyzer` by threading a `sampleQualityIsGood` bit
    /// through `PaintAnalysis` rather than silently trusting a bad
    /// capture as `.full` quality.
    func recordPaintReferenceTaps(
        photoID: UUID,
        damagePoint: CGPoint,
        referencePoint: CGPoint
    ) async {
        // Locate the photo within the active vehicle's photo list and the
        // UIImage backing it -- both taps were recorded against the same
        // already-captured photo, so we decode it once here rather than
        // asking the caller to pass the UIImage separately (avoids a
        // caller accidentally passing a stale/different image than the
        // one the points were actually tapped on).
        func photoAndImage(in photos: [CapturedPhoto]) -> (Int, UIImage)? {
            guard let index = photos.firstIndex(where: { $0.id == photoID }),
                  let image = UIImage(data: photos[index].imageData) else { return nil }
            return (index, image)
        }

        let vehicleHadPaintAnalysisAlready: Bool
        switch captureRole {
        case .victim:
            vehicleHadPaintAnalysisAlready = forensicCase.victimVehicle.primaryDamageZone?.paintAnalysis != nil
        case .suspect:
            vehicleHadPaintAnalysisAlready = forensicCase.suspectVehicle?.primaryDamageZone?.paintAnalysis != nil
        }

        switch captureRole {
        case .victim:
            guard let (index, image) = photoAndImage(in: forensicCase.victimVehicle.photos) else { return }
            forensicCase.victimVehicle.photos[index].paintDamagePoint = damagePoint
            forensicCase.victimVehicle.photos[index].paintReferencePoint = referencePoint
            guard let analysis = Self.buildPaintAnalysis(image: image, damagePoint: damagePoint, referencePoint: referencePoint) else { return }
            Self.applyPaintAnalysis(analysis, to: &forensicCase.victimVehicle)
        case .suspect:
            if forensicCase.suspectVehicle == nil {
                forensicCase.suspectVehicle = Vehicle(role: .suspect)
            }
            // `forensicCase.suspectVehicle` is guaranteed non-nil at this
            // point (just created above if it wasn't already) -- pull it
            // into a local `var` so `applyPaintAnalysis`'s `inout Vehicle`
            // parameter has a concrete, non-Optional target to mutate,
            // then write the whole vehicle back once at the end.
            guard var suspect = forensicCase.suspectVehicle,
                  let (index, image) = photoAndImage(in: suspect.photos) else { return }
            suspect.photos[index].paintDamagePoint = damagePoint
            suspect.photos[index].paintReferencePoint = referencePoint
            guard let analysis = Self.buildPaintAnalysis(image: image, damagePoint: damagePoint, referencePoint: referencePoint) else {
                forensicCase.suspectVehicle = suspect
                return
            }
            Self.applyPaintAnalysis(analysis, to: &suspect)
            forensicCase.suspectVehicle = suspect
        }

        if !vehicleHadPaintAnalysisAlready {
            forensicCase.recordAudit(.paintReferenceRecorded, detail: "\(captureRole.displayName) vehicle")
        }
        await storage.save(forensicCase)
    }

    /// Sample both tap points on `image` and turn them into a
    /// `PaintAnalysis`. `nil` if either sample fails to extract (e.g.
    /// degenerate image data).
    private static func buildPaintAnalysis(
        image: UIImage,
        damagePoint: CGPoint,
        referencePoint: CGPoint
    ) -> PaintAnalysis? {
        guard let damageSample = ColorAnalysis.sampleColor(from: image, at: damagePoint),
              let referenceSample = ColorAnalysis.sampleColor(from: image, at: referencePoint)
        else { return nil }

        // A sample is considered low-quality if either tap rejected an
        // unusually large fraction of its own pixels as glare/shadow, or
        // shows high residual luminance variance among the pixels that
        // did survive rejection -- both suggest the tap landed somewhere
        // inconsistent (an edge, a reflection, deep shadow) rather than a
        // clean, uniform patch of paint. Thresholds are deliberately
        // generous (not razor-sharp cutoffs) since this only downgrades
        // confidence rather than discarding the data outright.
        let sampleQualityIsGood =
            damageSample.rejectedFraction < 0.5
            && referenceSample.rejectedFraction < 0.5
            && damageSample.luminanceStdDev < 40
            && referenceSample.luminanceStdDev < 40

        // Whether the damage-area tap actually looks like a DIFFERENT
        // color than this vehicle's own clean-panel reference -- i.e.
        // there's a plausible foreign-paint signal here at all, as
        // opposed to the user having tapped two points on the same paint.
        let dE = ColorAnalysis.deltaE2000(
            ColorAnalysis.rgbToLab(damageSample.color),
            ColorAnalysis.rgbToLab(referenceSample.color)
        )
        let foreignPaintDetected = dE > 3.0 // ΔE ≤ ~2-3 reads as "same paint" to the eye

        return PaintAnalysis(
            primaryColorRGB: referenceSample.color,
            foreignPaintDetected: foreignPaintDetected,
            foreignPaintRGB: foreignPaintDetected ? damageSample.color : nil,
            layerCount: 0,
            hasRubberTransfer: false,
            hasPlasticFragment: false,
            surfaceCondition: .fresh,
            sampleQualityIsGood: sampleQualityIsGood
        )
    }

    /// Attach `analysis` to `vehicle`'s primary damage zone, creating that
    /// zone if this is the first paint reference recorded for the
    /// vehicle. Deliberately does not touch any of the OTHER fields on an
    /// existing zone (dimensions, height, impact angle) -- this only owns
    /// `paintAnalysis`.
    private static func applyPaintAnalysis(_ analysis: PaintAnalysis, to vehicle: inout Vehicle) {
        if vehicle.damageZones.isEmpty {
            vehicle.damageZones.append(DamageZone(paintAnalysis: analysis))
        } else {
            vehicle.damageZones[0].paintAnalysis = analysis
        }
    }

    /// Record a marked scar line (endpoints + which end is toward this
    /// vehicle's own front) against an already-captured `.paintTransfer`
    /// photo, sample paint-transfer density along that line, and -- if
    /// the resulting taper is conclusive -- set this vehicle's
    /// `scarSlideDirection`.
    ///
    /// NOTE(AI Developer), added 2026-07 as the ViewModel-layer entry
    /// point for the Scar-Direction Consistency feature, per Sean's "yes
    /// build it" direction and his three explicit answers: (1) when the
    /// taper isn't conclusive (or there's no reference color to compare
    /// against yet), this deliberately leaves `scarSlideDirection == nil`
    /// -- "not determinable," never a fabricated direction -- rather than
    /// guessing; (2) this is a fully independent, optional step from
    /// `recordImpactProfile`/Impact Geometry, callable any time after a
    /// paint reference has been recorded for this vehicle; (3) the actual
    /// keep/exclude formula this feeds lives in
    /// `MatchScoreCalculator.scoreScarDirectionConsistency` and
    /// `MatchResult.suspectShouldBeExcluded`, not here -- this function's
    /// only job is turning marked pixels into a `ScarSlideDirection`.
    ///
    /// Mirrors `recordPaintReferenceTaps`'s structure (role-based switch,
    /// `wasAlreadyRecorded` audit-dedup guard on `hasScarDirection`
    /// specifically -- not just "was a line marked" -- so re-marking an
    /// inconclusive line doesn't spam the audit log until it actually
    /// resolves to a real direction, then `storage.save`).
    ///
    /// Requires a clean-panel reference color to compare transfer density
    /// against -- reuses `Vehicle.primaryDamageZone?.paintAnalysis
    /// .primaryColorRGB`, the same clean-panel sample already captured by
    /// `recordPaintReferenceTaps` for the Paint Transfer factor, rather
    /// than asking the user to tap a third reference point. If that
    /// hasn't been recorded yet for this vehicle, the scar line's
    /// endpoints are still saved (so the marking UI shows them on
    /// re-open), but no direction can be derived yet -- the user should
    /// complete the paint reference step first.
    ///
    /// NOTE(AI Developer), reworked 2026-07 alongside the dedicated
    /// `ScarCaptureView`/`captureScarPhoto` flow: this used to search for
    /// `photoID` inside `vehicle.photos` (the array `CaptureCameraView`'s
    /// 30-shot -- v1: 10-shot -- protocol appends to and
    /// `currentShotIndex` counts). That was fine only because the scar
    /// line used to be marked on an ALREADY-required `.paintTransfer`
    /// protocol shot. Now that scar evidence has its own dedicated,
    /// non-protocol capture (`Vehicle.scarPhoto`, taken via
    /// `ScarCaptureView`'s guided auto-capture), this reads/writes that
    /// single slot directly instead of searching an array -- no
    /// `photoID` parameter needed anymore since there's only ever one
    /// candidate photo per vehicle.
    func recordScarDirection(
        lineStart: CGPoint,
        lineEnd: CGPoint,
        frontEndpoint: ScarEndpoint
    ) async {
        func resolvedDirection(image: UIImage, referenceColor: ColorRGB?) -> ScarSlideDirection? {
            guard let referenceColor,
                  let taper = ColorAnalysis.detectScarTaper(
                    in: image, lineStart: lineStart, lineEnd: lineEnd, referenceColor: referenceColor
                  ),
                  taper.isConclusive
            else { return nil }
            return taper.thickerEnd == frontEndpoint ? .towardFront : .towardRear
        }

        // NOTE(AI Developer), added 2026-07 for the fingerprint-style
        // Scar Matching feature -- extracts `ScarMinutia` alongside the
        // existing taper-direction resolution above, from the exact
        // same image/line/reference-color inputs already on hand here.
        // No new capture step or user input needed: this only adds a
        // second, independent READ of data the user already provided
        // (the marked line) plus data already captured for Paint
        // Transfer (the clean-panel reference color).
        func extractedMinutiae(image: UIImage, referenceColor: ColorRGB?) -> [ScarMinutia] {
            ScarFingerprintExtractor.extractMinutiae(
                in: image, lineStart: lineStart, lineEnd: lineEnd,
                frontEndpoint: frontEndpoint, referenceColor: referenceColor
            )
        }

        let wasAlreadyRecorded: Bool
        switch captureRole {
        case .victim:
            wasAlreadyRecorded = forensicCase.victimVehicle.hasScarDirection
            guard forensicCase.victimVehicle.scarPhoto != nil,
                  let image = UIImage(data: forensicCase.victimVehicle.scarPhoto!.imageData) else { return }
            forensicCase.victimVehicle.scarPhoto?.scarLineStart = lineStart
            forensicCase.victimVehicle.scarPhoto?.scarLineEnd = lineEnd
            forensicCase.victimVehicle.scarPhoto?.scarFrontEndpoint = frontEndpoint
            let referenceColor = forensicCase.victimVehicle.primaryDamageZone?.paintAnalysis?.primaryColorRGB
            forensicCase.victimVehicle.scarSlideDirection = resolvedDirection(image: image, referenceColor: referenceColor)
            forensicCase.victimVehicle.scarPhoto?.scarMinutiae = extractedMinutiae(image: image, referenceColor: referenceColor)
        case .suspect:
            if forensicCase.suspectVehicle == nil {
                forensicCase.suspectVehicle = Vehicle(role: .suspect)
            }
            wasAlreadyRecorded = forensicCase.suspectVehicle?.hasScarDirection ?? false
            // Same `guard var suspect ... write-back-once` pattern as
            // `recordPaintReferenceTaps`'s suspect branch -- see that
            // function's comment for why (`inout Vehicle` needs a
            // concrete, non-Optional local to mutate).
            guard var suspect = forensicCase.suspectVehicle,
                  let scarPhoto = suspect.scarPhoto,
                  let image = UIImage(data: scarPhoto.imageData) else { return }
            suspect.scarPhoto?.scarLineStart = lineStart
            suspect.scarPhoto?.scarLineEnd = lineEnd
            suspect.scarPhoto?.scarFrontEndpoint = frontEndpoint
            let referenceColor = suspect.primaryDamageZone?.paintAnalysis?.primaryColorRGB
            suspect.scarSlideDirection = resolvedDirection(image: image, referenceColor: referenceColor)
            suspect.scarPhoto?.scarMinutiae = extractedMinutiae(image: image, referenceColor: referenceColor)
            forensicCase.suspectVehicle = suspect
        }

        // Only log the audit entry the first time this vehicle's scar
        // direction actually resolves to a real value, not on every
        // re-mark attempt (including ones that stay inconclusive).
        let isNowRecorded: Bool
        switch captureRole {
        case .victim: isNowRecorded = forensicCase.victimVehicle.hasScarDirection
        case .suspect: isNowRecorded = forensicCase.suspectVehicle?.hasScarDirection ?? false
        }
        if !wasAlreadyRecorded && isNowRecorded {
            forensicCase.recordAudit(.scarDirectionRecorded, detail: "\(captureRole.displayName) vehicle")
        }
        await storage.save(forensicCase)
    }

    /// Record a freshly-captured, guided scar photo (from `ScarCaptureView`
    /// / `ScarCaptureCameraService`) as this vehicle's `scarPhoto`,
    /// replacing any previous one (a retake supersedes, it doesn't
    /// accumulate -- only the latest scar photo is ever meaningful).
    ///
    /// NOTE(AI Developer), added 2026-07 as the dedicated capture entry
    /// point for the guided scar-line camera (Sean: "can we have the
    /// hold the phone over the damage and automatically capture the
    /// image when the phone is in the correct position... like the auto
    /// capture when I remote deposit a check"). Deliberately separate
    /// from `record(photo:)`: that function feeds the fixed-length,
    /// counted 10-shot protocol (`nextShotType`/`currentShotIndex`) --
    /// this one does not touch protocol state at all, since the scar
    /// photo is optional/independent of it (see `Vehicle.scarPhoto`'s
    /// doc comment). Clears any previously-marked line/direction on a
    /// retake, since a brand-new photo has no marked line yet and any
    /// stale direction derived from the OLD photo would misrepresent
    /// evidence that no longer exists in the current photo.
    func captureScarPhoto(_ photo: CapturedPhoto) async {
        switch captureRole {
        case .victim:
            forensicCase.victimVehicle.scarPhoto = photo
            forensicCase.victimVehicle.scarSlideDirection = nil
        case .suspect:
            if forensicCase.suspectVehicle == nil {
                forensicCase.suspectVehicle = Vehicle(role: .suspect)
            }
            forensicCase.suspectVehicle?.scarPhoto = photo
            forensicCase.suspectVehicle?.scarSlideDirection = nil
        }
        forensicCase.recordAudit(.scarPhotoCaptured, detail: "\(captureRole.displayName) vehicle")
        await storage.save(forensicCase)
    }

    /// Switch to capturing the suspect vehicle after victim is complete.
    /// NOTE(AI Developer), simplified 2026-07 alongside the `capturedPhotos`
    /// removal above: no explicit reset needed here anymore --
    /// `currentShotIndex` now reads `forensicCase.suspectVehicle?.photos.count`
    /// for the `.suspect` role, which is naturally 0 until photos are
    /// actually appended to it.
    func switchToSuspect() {
        captureRole = .suspect
        statusMessage = "Capturing suspect vehicle. Maintain consistent angle and distance."
    }

    /// Apply case-level edits made via `EditCaseSheet` (case name/type,
    /// incident details, victim/suspect vehicle info) while a capture is
    /// in progress. NOTE(AI Developer): Added per Sean's decision
    /// (2026-07) so investigators can record suspect vehicle details
    /// (make/model/plate from a witness, say) as soon as they're known,
    /// without waiting for suspect photo capture to begin.
    func applyEdits(_ updated: ForensicCase) async {
        var updated = updated
        updated.recordAudit(.caseEdited)
        forensicCase = updated
        await storage.save(forensicCase)
    }

    // MARK: Sensor monitoring

    private func startSensors() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.1
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, let m = motion else { return }
                // NOTE(AI Developer), fixed 2026-07 per Sean's on-device
                // report ("why is the camera preferred to be pointing down
                // for everything?"): previously stored `m.attitude.pitch`/
                // `.roll` directly, but CMAttitude's zero-point is "phone
                // flat on a table" -- not "phone held up, aimed level at
                // the vehicle" (which is what `idealPitchDegrees: 0` in
                // CaptureProtocolStep actually means). That mismatch made
                // "pitch near 0" only achievable by flattening the phone
                // toward the ground. Fixed by deriving pitch/roll from the
                // raw gravity vector via `CameraLevelMath`, whose zero
                // point matches "phone held vertically, camera level" --
                // see CameraLevelMath.swift for the full derivation.
                let (pitchDeg, rollDeg) = CameraLevelMath.pitchRollDegrees(
                    fromGravity: (m.gravity.x, m.gravity.y, m.gravity.z)
                )
                self.currentSensorData = SensorData(
                    pitch: pitchDeg * .pi / 180.0,
                    roll: rollDeg * .pi / 180.0,
                    yaw: m.attitude.yaw,
                    accelerometer: SIMD3<Double>(m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z)
                )
                self.updateGuidance()
            }
        }
        locationManager.requestWhenInUseAuthorization()
    }

    /// NOTE(AI Developer), rewritten 2026-07 per Sean's feedback ("pitch
    /// and roll is tough to use, needs to be easier to follow and more
    /// intuitive... maybe add better directions or cues"). Previously this
    /// only printed the raw degree value with no indication of *which way*
    /// to move the phone. Now gives an explicit directional instruction
    /// ("tilt left/right", "aim up/down") derived from the sign of the
    /// (now correctly zeroed, see `startSensors`) pitch/roll. Also uses
    /// gentler thresholds (a "close" band before the hard warning) so the
    /// message doesn't flicker between two states right at the boundary.
    private func updateGuidance() {
        guard let next = nextShotType else {
            statusMessage = "Capture complete. Tap Analyze to proceed."
            return
        }
        let roll = currentSensorData.rollDegrees
        let pitch = currentSensorData.pitchDegrees

        if abs(roll) > 15 {
            let direction = roll > 0 ? "left" : "right"
            statusMessage = "Tilt \(direction) to level the horizon (\(Int(abs(roll)))° off)"
        } else if abs(pitch) > 25 {
            let direction = pitch > 0 ? "down" : "up"
            statusMessage = "Aim the camera more \(direction) — hold it level with the damage"
        } else {
            statusMessage = "Next: \(next.displayName) (\(currentShotIndex + 1)/\(protocolShots.count))"
        }
    }

    // NOTE(AI Developer), removed 2026-07: `estimateQuality(for:)` used to
    // live here -- a placeholder quality estimator (fixed 0.85 base
    // score, adjusted only by this view model's own late CoreMotion
    // snapshot) that `record(image:)` used to pass to a `CapturedPhoto`
    // it rebuilt from scratch. Now that `record(photo:)` takes the
    // camera's own already-scored `CapturedPhoto` directly (see NOTE on
    // `record(photo:)` above), this placeholder had no remaining caller
    // and would only ever have produced a *worse* score than
    // `CameraService.evaluateQuality` (which factors in real
    // roll/pitch-vs-step-target deltas and actual image brightness).
    // Removed rather than left dead, since it's strictly superseded, not
    // reserved for future use.

    /// Caps `image`'s pixel dimensions before it's ever handed to
    /// `jpegData(compressionQuality:)`, mirroring the ~12MP
    /// (4032x3024) ceiling `CameraService` already enforces on live
    /// captures via `photoOutput.maxPhotoDimensions`.
    ///
    /// NOTE(AI Developer), added 2026-07 as the fix for the recurred
    /// "Running correlation analysis" hang Sean reported after the
    /// original `StorageService`/`CameraService` fix: an imported
    /// camera-roll photo has no upstream cap the way a live capture
    /// does, so it can come in at the device's full native resolution
    /// (e.g. 48MP+). Embedding that directly into `CapturedPhoto.imageData`
    /// bloats the case's JSON file enough that even the *backgrounded*
    /// encode/write in `StorageService.save(_:)` can take minutes of
    /// real CPU+I/O time -- which surfaces to the user as a stuck
    /// "Running correlation analysis" spinner (analysis and the
    /// preceding save both compete for the same background executor).
    /// Downsampling here, once, before storage keeps every downstream
    /// consumer (JSON encode, Vision requests in `DeformationMatcher`,
    /// PDF export) working with a bounded-size image regardless of
    /// where the original bytes came from.
    private func resizedForStorage(_ image: UIImage) -> UIImage {
        let maxReasonablePixels = 4032.0 * 3024.0
        let pixelWidth = Double(image.size.width * image.scale)
        let pixelHeight = Double(image.size.height * image.scale)
        let pixelCount = pixelWidth * pixelHeight
        guard pixelCount > maxReasonablePixels, pixelWidth > 0, pixelHeight > 0 else {
            return image
        }
        let scaleFactor = (maxReasonablePixels / pixelCount).squareRoot()
        let targetSize = CGSize(
            width: max(1, (pixelWidth * scaleFactor).rounded(.down)),
            height: max(1, (pixelHeight * scaleFactor).rounded(.down))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // targetSize is already in pixel units
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
