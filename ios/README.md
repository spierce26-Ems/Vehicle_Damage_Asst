# Vehicle Damage Investigation Assistant (iOS)

## Project Overview
- **Name**: Vehicle Damage Investigation Assistant
- **Owner**: Sean Pierce
- **Bundle ID**: `com.spearitnow.vehicledamageforensics`
- **Platform**: iOS 17.0+ (SwiftUI, StoreKit 2)
- **Goal**: A scaleable damage-correlation and documentation tool for two audiences —
  1. **Consumers** who experience a one-off fender bender or overnight hit-and-run and need to
     build a solid case to hand to an insurer, and
  2. **Insurance adjusters / body shops / investigators** who process many cases as part of their
     job and need a fast, repeatable workflow.
- **Not** a "court-admissible forensic match" tool — v1 is explicitly scoped as a best-in-class
  *investigative documentation + leads* tool. Every generated report carries a disclaimer to that
  effect (`MatchResult.disclaimerText`).

## Core Features (Completed)
- **Guided capture flow** (`Views/Capture/`): `CaptureFlowView` walks a user through a fixed
  10-shot protocol per vehicle (`PhotoType.requiredCaptureProtocol` is the single source of
  truth), with a live camera preview (`CaptureCameraView`) and a bubble-level HUD
  (`SensorGuidanceOverlay`, `CameraLevelMath`) for consistent angles.
- **LiDAR depth capture** (`Views/LiDAR/LiDARScanView`, `Services/LiDARService`) on supported
  devices, for height/alignment analysis.
- **Camera-roll photo import** as an alternative to live capture.
- **Skip-a-shot** (added 2026-07, per Sean's decision): every entry in the 10-shot protocol is
  skippable — no mandatory photos — via a dedicated skip button next to the shutter/photo-library
  buttons in `CaptureCameraView`. A confirmation dialog captures why ("No matching photo in camera
  roll" / "No longer near the vehicle"), logged to the chain-of-custody audit trail
  (`AuditAction.photoSkipped`). A skipped shot counts as "done" for completion purposes
  (`Vehicle.skippedShotIndices`, tracked separately from the real `photos` array so a skip can
  never be mistaken for — or silently rendered as — a blank/empty photo). Skipped shots are called
  out as "Shot X was skipped: not available" on both the in-app Results screen
  (`MatchResultsView`, via `AnalysisViewModel.skippedShotsSummary`) and the PDF report
  (`PDFReportGenerator`).
- **7-factor correlation engine** (`ForensicEngine/`): `MatchScoreCalculator` orchestrates
  `PaintTransferAnalyzer` (CIEDE2000 color-delta matching), `DeformationMatcher`
  (Vision `VNDetectContoursRequest`-based shape comparison), `HeightAlignmentAnalyzer`, plus
  synchronous heuristic scorers, producing a weighted composite score (0–100) with a
  correlation-strength label and confidence banding.
  - **LiDAR-measured height wired into Height Alignment** (added 2026-07, per Sean's decision —
    "we need the use of Lidar as an extra tool"): previously the LiDAR scan (`LiDARScanData`) was
    captured and saved but never actually read by any scoring factor — Height Alignment (20%
    weight) was permanently `dataQuality: .unavailable` in every real run, since neither
    `DamageZone` nor `Vehicle.bumperHeightInches` had any writer anywhere in the app. Now,
    `Views/LiDAR/LiDARScanView` has a **"Measure Height"** button (independent of "Save Scan")
    that starts a tap-to-measure flow: tap the ground beside the vehicle, then tap the damage
    point on the vehicle body; `LiDARService.worldY(from:at:)` raycasts each tap against the
    reconstructed mesh (`ARView.raycast(from:allowing:.estimatedPlane,alignment:)`, which — unlike
    a plane-only raycast — intersects the actual non-planar mesh geometry from
    `sceneReconstruction = .mesh`), and `heightFromWorldPositions(groundY:damageY:)` converts the
    vertical distance between the two hits into inches. Confirmed and saved via
    `CaptureViewModel.recordLiDARMeasurement(inches:)` into the new
    `Vehicle.lidarMeasuredHeightInches` field (`AuditAction.lidarMeasurementRecorded`).
    `Vehicle.effectiveBumperHeightInches` (`lidarMeasuredHeightInches ?? bumperHeightInches`) is
    what `MatchScoreCalculator` now passes to `HeightAlignmentAnalyzer`, so a completed LiDAR
    measurement gives Height Alignment real data for the first time.
  - **Composite score renormalization** (added 2026-07, per Sean's decision): a case where one or
    more factors are `dataQuality: .unavailable` (no real data captured for that factor) no
    longer permanently caps the max achievable score. The composite is now `weightedSum /
    usableWeightTotal` over only the *usable* factors, so a case with a flawless match on the
    factors it does have data for reads close to 100, not capped around 20–40.
- **Impact location + direction-of-travel capture** (added 2026-07, per Sean's decision — "Option
  A"): a new **required** step in the capture flow (`Views/Capture/ImpactMarkerView.swift`),
  gating `ForensicCase.isReadyForAnalysis` and the Continue/Run-Analysis buttons in
  `CaptureFlowView`, alongside the 10-shot photo protocol (photos themselves remain skippable —
  see below). For each vehicle:
  1. **Tap the point of impact** on a top-down car silhouette (`ImpactSilhouetteView`) — free
     tap-anywhere, not a fixed zone picker.
  2. **Direction of travel at impact** — either read live from the device compass
     (`Services/HeadingProvider.swift`, a dedicated short-lived `CLLocationManager` scoped to this
     screen only) or set manually via a drag-to-set compass dial (`DirectionDialView`).
  This data (`Vehicle.impactTapPoint`, `directionOfTravelDegrees`, and the derived
  `impactBearingDegrees`) revives the previously-dead **Impact Geometry** factor (15% weight) in
  the correlation engine — `scoreImpactGeometry` now checks that the two vehicles' impact
  bearings are reciprocal (~180° apart) instead of always reporting `.unavailable`.
  Precise physical measurement (bumper height, paint chemistry, mm-level dimensions) is
  deferred to a later phase per Sean's decision — this step only captures location + direction.
- **Case management** (`ViewModels/CaseListViewModel`, `Views/Dashboard/`): create, edit, search,
  and delete cases; each case carries a full chain-of-custody `auditLog`
  (`Models/Case.swift` — `ForensicCase`, `AuditEntry`, `AuditAction`).
- **PDF report export** (`Services/PDFReportGenerator`, `Views/Reports/PDFReportView`): an
  investigative-documentation PDF with case header, vehicle details, per-factor breakdown,
  photos, and the chain-of-custody trail.
- **Local-only persistence** (`Services/StorageService`): cases are stored as Codable JSON on
  disk, with encode/decode and file I/O run off the main actor (`Task.detached`) so large cases
  (multiple embedded photos) don't block the UI.
- **Monetization (StoreKit 2)** — added 2026-07, see below.

## Monetization Architecture (added 2026-07)
Two-tier pricing matching the two target audiences, confirmed with Sean:

| Segment | Model | Product IDs |
|---|---|---|
| One-time consumer (fender bender, hit-and-run victim) | Pay-per-case, consumable IAP | `com.spearitnow.vehicledamageforensics.unlock.single` (1 case), `...unlock.five` (5-case bundle) |
| Insurance adjuster / pro (many cases) | Auto-renewing subscription, unlimited unlocks | `com.spearitnow.vehicledamageforensics.pro.monthly`, `...pro.annual` |

**Gating point**: the composite score reveal is free and instant (conversion hook — "you scored
78/100, unlock the full report"). What's gated behind the paywall: the per-factor breakdown,
investigative recommendations, and PDF report export.

**Key files**:
- `Services/PurchaseManager.swift` — StoreKit 2 singleton (`@MainActor`). Loads product metadata,
  drives the purchase flow, listens for `Transaction.updates`, derives live subscription status
  from `Transaction.currentEntitlements` (never persisted locally — Apple's API already handles
  renewal/expiration/refunds/Family Sharing), and tracks the consumable case-credit balance in
  `UserDefaults` (`CaseCreditsStore`, since Apple does not track "this consumable is unspent").
  Idempotent transaction processing (`processedTransactionIDs`) guards against double-granting
  credits when the same transaction is seen via both the direct purchase result and the
  background listener.
- `Views/Paywall/PaywallView.swift` — presents the one-time options and Pro subscription options
  side by side, with the required App Store subscription-terms disclosure text (Guideline 3.1.2)
  and a Restore Purchases action.
- `Models/Case.swift` — `ForensicCase.isUnlocked: Bool` (persistent, backward-compatible decode —
  defaults to `false`/locked for any case saved before monetization existed). Stored *per case*
  rather than derived live from subscription status, so a case a subscriber unlocked stays
  unlocked even if their subscription later lapses. `AuditAction.caseUnlocked` records how each
  case was unlocked (credit vs. subscription) in the chain-of-custody log.
- `ViewModels/AnalysisViewModel.swift` — `isUnlocked` computed property (case flag OR live
  subscription), `unlockWithCreditIfAvailable()`, `markUnlockedFromPaywall()`; `generateReport()`
  is guarded behind `isUnlocked`.
- `Views/Results/MatchResultsView.swift` — conditionally renders the gated sections, or a
  locked-state call-to-action (spend an existing credit, or open the paywall) otherwise.

**Known v1 limitation (by design, per Sean's "local only" decision)**: `restorePurchases()`
correctly restores an active Pro subscription (Apple tracks entitlements), but **cannot** restore
unused consumable case credits after an uninstall/device change — there is no backend or iCloud
sync of that balance yet. This is documented in code (`PurchaseManager.restorePurchases()`) as a
known trade-off, not a silent gap. A future upgrade path without a full backend would be
`NSUbiquitousKeyValueStore` (free iCloud key-value sync).

**Still needed before this can be tested on-device / shipped**:
1. Create the 4 In-App Purchase / Subscription products in App Store Connect with IDs matching
   `PurchaseManager.ProductID` **exactly**, and set up a subscription group for the two `pro.*`
   products.
2. Publish a Terms of Use / Privacy Policy (not yet drafted).
3. Suggested pricing (not yet finalized with Sean): consumer $9.99–14.99 one-time per case;
   Pro ~$29.99/mo or ~$299/yr.

## Data Architecture
- **Data model**: `ForensicCase` (Codable struct) — case metadata, two `Vehicle`s (victim/suspect),
  `CapturedPhoto[]`, optional `MatchResult`, optional PDF `reportURL`, `auditLog: [AuditEntry]`,
  `isUnlocked: Bool`.
- **Storage**: 100% local, on-device file system — one JSON file per case
  (`StorageService`, `.completeFileProtection` on write). No backend, no cross-device sync in v1.
- **Purchases**: subscription status derived live from StoreKit (`Transaction.currentEntitlements`,
  not persisted); consumable case-credit balance persisted in `UserDefaults`.

## User Guide
1. **Dashboard** — view/search existing cases, start a new case.
2. **New Case** — enter case name, incident address, and known vehicle/suspect details.
3. **Capture** — walk the guided 10-shot protocol for the victim vehicle, then the suspect
   vehicle (or import existing photos from the camera roll). LiDAR scan optional on supported
   devices.
4. **Analysis** — runs automatically after capture; shows the composite correlation score
   immediately, free.
5. **Unlock** — tap "Unlock Full Report" (or use an existing case credit) to see the per-factor
   breakdown, recommendations, and export a PDF report to share with an insurer/investigator.
6. **Edit** — case details can be corrected any time after analysis/reporting via the edit sheet.

## Deployment
- **Platform**: Native iOS app (Xcode project), not a Cloudflare Pages web app.
- **Tech stack**: SwiftUI, AVFoundation, ARKit/LiDAR, Vision, PDFKit, StoreKit 2. Swift 5.0
  language mode (not Swift 6 strict concurrency). iOS 17.0 minimum deployment target.
- **Signing**: Sean holds an active Apple Developer Program account.
- **Distribution**: not yet on TestFlight — currently built and run directly on Sean's device via
  Xcode during development.
- **Version control**: GitHub repo `spierce26-Ems/Vehicle_Damage_Asst` (branch `main`). Native
  Genspark GitHub OAuth (`setup_github_environment`) has not succeeded for this project in any
  session — pushes require Sean to provide a fine-grained Personal Access Token each session, as
  the sandbox does not persist credentials across sessions.
- **Last updated**: 2026-07-16
- **Note**: the 2026-07-16 changes (impact-profile capture, score renormalization, skip-a-shot,
  LiDAR tap-to-measure height wiring) were written in the Genspark sandbox, which has no
  Xcode/Swift toolchain — only brace/paren/bracket balance was checked, not a real compile.
  Build and test on-device before relying on this, especially the new tap/drag UI
  (`ImpactMarkerView`), the live-compass path (`HeadingProvider`), and the new LiDAR
  tap-to-measure flow (`LiDARScanView`'s "Measure Height" button, `LiDARService.worldY`/
  `heightFromWorldPositions`) — none of these have ever been compiled or run; the LiDAR raycast
  code in particular needs a physical LiDAR device (no simulator support) to verify at all.

## Reference Material
See `ios/reference/` for the original project brief, technical specs, algorithm explainer, and
the Python reference implementation the scoring engine was validated against.
