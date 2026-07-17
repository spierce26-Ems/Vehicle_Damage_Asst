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
  - **Fixed: LiDAR mesh scan never visibly activating** (added 2026-07, per Sean's on-device
    report — "tap and measure worked but the lidar never activated during scan"):
    `ARViewContainer.makeUIView` (`Views/LiDAR/LiDARScanView.swift`) now sets
    `arView.automaticallyConfigureSession = false` before assigning `arView.session`. `ARView`
    defaults that flag to `true`, under which RealityKit can auto-generate and (re-)run its own
    `ARWorldTrackingConfiguration` on the session — one that, per Apple's own scene-reconstruction
    sample doc ("Visualizing and interacting with a reconstructed scene"), does not enable
    `.sceneReconstruction` by default, which could stomp on the custom `.sceneReconstruction =
    .mesh` configuration `LiDARService.startScan()` runs on the same session. This matches Sean's
    report exactly: tap-to-measure raycasts (`.estimatedPlane`, which can also hit plane-detection
    surfaces) still worked, while the mesh wireframe/coverage never engaged. `LiDARService`'s own
    `session.run(...)` in `startScan()` is now the only thing that ever configures/runs the
    session.
  - **LiDAR startup/interruption feedback** (added 2026-07, per Sean's follow-up report — "Lidar
    took a while to start and the lidar crashed/stop"): `LiDARService` now implements
    `sessionWasInterrupted`/`sessionInterruptionEnded`/`cameraDidChangeTrackingState`
    (`ARSessionDelegate`), none of which existed before. A slow-but-normal tracking start (ARKit
    needs a few seconds of camera motion before tracking quality reaches `.normal`) now shows a
    `trackingStateMessage` (e.g. "Initializing — hold the phone steady…") in `LiDARScanView`'s
    `topStatus` instead of silently doing nothing. A genuine system interruption (phone call,
    Control Center, multitasking) — which previously left `isScanning` stuck `true` with no mesh
    data arriving, indistinguishable from a crash — now shows "Scan interrupted…" immediately and
    automatically resets tracking and resumes once the interruption ends. `LiDARScanView` also
    now has an actual `.alert` reading `LiDARService.lastError` (previously nothing in the view
    read that property at all, so even a hard, unsupported-device failure was invisible).
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
  1. **Tap the point of impact** on a top-down silhouette (`ImpactSilhouetteView`) — free
     tap-anywhere, not a fixed zone picker.
  2. **Direction of travel at impact** — either read live from the device compass
     (`Services/HeadingProvider.swift`, a dedicated short-lived `CLLocationManager` scoped to this
     screen only) or set manually via a drag-to-set compass dial (`DirectionDialView`).
  This data (`Vehicle.impactTapPoint`, `directionOfTravelDegrees`, and the derived
  `impactBearingDegrees`) revives the previously-dead **Impact Geometry** factor (15% weight) in
  the correlation engine — `scoreImpactGeometry` now checks that the two vehicles' impact
  bearings are reciprocal (~180° apart) instead of always reporting `.unavailable`.
  - **Car/Truck silhouette toggle** (added 2026-07, per Sean's on-device feedback — "if its a
    truck we should be able to better identify the location of the impact instead of a generic
    square we tap"): `Vehicle.bodyType` (`VehicleBodyType`: `.car` / `.truck`, defaulting to
    `.car` so existing cases are unaffected) is set via a segmented Car/Truck `Picker` in
    `EditCaseSheet.swift`'s Victim/Suspect Vehicle sections; `ImpactSilhouetteView` reads it to
    pick which outline to draw. Both outlines keep the exact same normalized (0,0)-(1,1)
    tap-point contract that `Vehicle.impactRelativeAngleDegrees` depends on (front-center at
    (0.5, 0), rear-center at (0.5, 1)) — only the drawing changes, not the angle math.
  - **Fenders and bumpers added to both silhouettes** (added 2026-07, per Sean's follow-up
    feedback on the first version of the toggle — "I dont like the new truck silhouette. Still a
    little confusing on how to mark the spot of impact. need to see fenders and bumpers to
    clearing mark impact spots."): both `.car` and `.truck` outlines now draw a labeled **front
    bumper** bar and **rear bumper** bar (tailgate, for the truck), plus four **fender** bulges
    (one per wheel position) each with a darker wheel-well ellipse inside — the actual landmarks
    ("front bumper," "driver-side front fender") people use to describe where a vehicle was hit,
    replacing the plain unlabeled box corners from the first version. The truck's cab/bed body
    shape is kept but is now a secondary detail under the more prominent bumper/fender landmarks.
  Precise physical measurement (bumper height, paint chemistry, mm-level dimensions) is
  deferred to a later phase per Sean's decision — this step only captures location + direction.
- **Case management** (`ViewModels/CaseListViewModel`, `Views/Dashboard/`): create, edit, search,
  and delete cases; each case carries a full chain-of-custody `auditLog`
  (`Models/Case.swift` — `ForensicCase`, `AuditEntry`, `AuditAction`).
- **First-launch onboarding + enhanced empty state** (added 2026-07, per Sean's request — "right
  now a first-time user lands on an empty dashboard with no explanation of what to do"):
  - `Views/Dashboard/OnboardingView.swift` — a new 3-screen "how this works" intro (purpose →
    the 3-step flow → why the impact-marking step matters), shown automatically the first time
    `DashboardView` appears (gated by an `@AppStorage("hasSeenOnboarding")` flag — deliberately
    **not** routed through `AppState`, which is dead/unused code; see the NOTE in
    `VehicleDamageForensicsApp.swift`). Presented as a `.fullScreenCover` from `DashboardView`,
    not a nested `NavigationStack`.
  - `DashboardView.emptyState` rewritten: previously just "No cases yet / Tap + to start a new
    case." — now explains what the app does in one line, adds a full-width primary **"Start New
    Case"** button (the small toolbar "+" was easy to miss), and a **"How does this work?"** link
    that re-opens the same onboarding intro on demand (so dismissing/skipping it too fast the
    first time, plausible for a stressed user, isn't a dead end).
- **In-flow "why this matters" guidance** (added 2026-07, per Sean's request — "a one-line...
  would help a panicked/upset user understand why they're tapping a fender diagram instead of
  just taking photos"): short, low-key one-line explanations (lightbulb icon, secondary/caption
  styling — not competing for attention with the actual instructions) added at the three points
  in the capture flow that aren't self-evidently photo-like:
  - `ImpactMarkerView.swift` — under both the impact-tap step and the direction-of-travel step
    (the explicit example Sean gave), explaining that these steps confirm the two vehicles' damage
    actually matches, not just that damage exists.
  - `LiDARScanView.swift` — under the "tap the ground" prompt in the height-measurement banner,
    explaining what the height measurement is for.
  - `CaptureFlowView.swift` — under the "Impact Location & Direction — Required" button itself
    (shown only while still unrecorded), so the reasoning is visible *before* a user opens the
    sheet, not only after.
- **Results/PDF next-step nudge** (added 2026-07, per Sean's request — "after a match score
  shows, a one-line 'here's what to do with this'... so the payoff moment doesn't just end on a
  number"): `MatchResultsView.reportSection` (`Views/Results/MatchResultsView.swift`) now shows a
  one-line "save or share this with your insurer, the police, or a body shop" note plus a direct
  **"Share Report"** button once a PDF has been generated — previously this section only
  confirmed the filename and stopped, with no next-step affordance beyond scrolling back up to
  the toolbar share icon.
- **Case-list thumbnails** (added 2026-07, per Sean's request — "CaseRow currently shows an icon
  + text only, a small photo thumbnail per case would make the list easier to scan visually"):
  - `ForensicCase.thumbnailPhoto` (new computed property, `Models/Case.swift`) — the case's first
    usable captured/imported photo (victim vehicle first, sorted by `sequenceIndex`; falls back to
    the suspect vehicle if the victim has none yet), read from the photo's existing
    `thumbnailData` (already generated by `CameraService.generateThumbnail` on every
    capture/import — no new capture-time work needed).
  - `CaseRow.leadingVisual` (`Views/Dashboard/DashboardView.swift`) — replaces the old icon-only
    `statusIcon` with a 44x44 rounded photo thumbnail (status-colored border + a small
    status-icon badge in the corner, so the at-a-glance status signal isn't lost), falling back
    to the original icon-only look for any case with no usable photo yet.
- **App icon** (added 2026-07, per Sean's request — "app icon, Terms/Privacy Policy, Privacy
  Manifest"): `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` — a generated,
  flat/geometric 1024×1024 icon (car silhouette + shield + magnifying glass/damage-point accent on
  a deep-blue background), RGB with no alpha channel (verified — App Store icons must not have
  transparency) and no baked-in rounded corners (iOS applies the mask). `Contents.json` in that
  folder updated with the `"filename"` key referencing it. No `project.pbxproj` change was needed
  for this — the whole `Assets.xcassets` folder is already registered as a single folder
  reference, so new files placed inside an existing asset catalog don't need individual pbxproj
  entries (unlike a new loose Swift/resource file added directly under `Views/` or `Resources/`).
- **Privacy Manifest** (added 2026-07, same request as above): `Resources/PrivacyInfo.xcprivacy`
  — a new file, declaring exactly the required-reason APIs this codebase actually uses, found by
  exhaustively grepping every `.swift` file against Apple's 5 required-reason API categories:
  - **File Timestamp** (`NSPrivacyAccessedAPICategoryFileTimestamp`, reason `C617.1`) — for
    `StorageService.swift`'s use of `.contentModificationDateKey` when listing files inside the
    app's own `Documents/Cases` folder to sort the case list. `C617.1` is the "access
    timestamps/size/metadata of files inside your app's own container" reason — correct here since
    this only ever touches the app's own sandboxed storage, never a shared/App Group container.
  - **User Defaults** (`NSPrivacyAccessedAPICategoryUserDefaults`, reason `CA92.1`) — for
    `PurchaseManager.swift`'s `CaseCreditsStore`, which uses plain `UserDefaults.standard` (no App
    Group, no MDM) to persist the consumable case-credit balance. `CA92.1` is the
    "app-only UserDefaults, not shared" reason — correct here since credits are never shared with
    another app/extension.
  - System Boot Time, Disk Space, and Active Keyboards categories are confirmed **not** used
    anywhere in this codebase (targeted greps for their associated APIs returned zero matches), so
    no entries for those were added. `UIDevice.identifierForVendor` (used in `Case.swift`) was
    also checked and confirmed to **not** be one of Apple's 5 required-reason categories, so it
    needs no manifest entry either.
  - Top-level keys: `NSPrivacyTracking = false` and empty `NSPrivacyTrackingDomains` /
    `NSPrivacyCollectedDataTypes` arrays, reflecting that the app has no analytics/ad SDKs, does
    not track users across apps/sites, and collects no data off-device at all (100% local
    storage — see Data Architecture below).
  - Registered in `project.pbxproj` as a `PBXFileReference` + `PBXBuildFile` +
    `PBXResourcesBuildPhase` entry (a bundled resource, like `Info.plist`/`Assets.xcassets`, not
    compiled Swift source — so it does **not** go in the Sources build phase). New unique object
    IDs were generated and checked against the existing file for collisions before use.
- **Terms of Use / Privacy Policy** (added 2026-07, same request as above):
  - `docs/privacy-policy.html` and `docs/terms-of-use.html` — standalone static HTML pages,
    committed at the **repo root** `docs/` folder (not under `ios/`), specifically so GitHub
    Pages' "Deploy from a branch" option can serve them directly (that feature only supports the
    repo root or a root-level `/docs` folder, not an arbitrary nested path like `ios/docs`).
  - Privacy Policy content accurately reflects this app's real, on-device-only data practices: no
    backend, no analytics/ad SDKs/tracking, no data sold or shared, purchases handled entirely by
    Apple/StoreKit, and a plain-English explanation of the two required-reason API uses (file
    timestamps for case-list sorting, UserDefaults for the credit balance) alongside the four
    Info.plist-declared permissions (camera, photo library read/add, location-when-in-use).
  - Terms of Use content leans on Apple's standard EULA (linked) plus app-specific additions:
    what the app is/isn't (explicitly **not** a certified forensic/legal determination tool),
    ownership of user content, the required Guideline-3.1.2 auto-renewing-subscription disclosure
    (length, price, cancel-anytime), and standard warranty/liability disclaimers.
  - `Views/Paywall/PaywallView.swift` updated: added `privacyPolicyURL`/`termsOfUseURL` constants
    (currently pointed at the GitHub Pages URL pattern for this repo,
    `https://spierce26-ems.github.io/Vehicle_Damage_Asst/{privacy-policy,terms-of-use}.html`), and
    two new `Link`s ("Terms of Use", "Privacy Policy") added to `legalFooter`, next to the
    existing subscription-disclosure text.
  - **Action needed from Sean, not done here**: GitHub Pages is not automatically turned on by
    pushing these files — go to the repo's **Settings → Pages**, set Source to "Deploy from a
    branch", branch `main`, folder `/docs`, and save. Once that's live the two `Link`s in the
    paywall will resolve correctly. If Sean would rather host these somewhere else (his own
    site, or as a page on the Cloudflare Pages web app in this same sandbox), the two URL
    constants in `PaywallView.swift` are the only thing that needs to change.
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
   products. (Sean's own task in App Store Connect — not done here.)
2. Turn on GitHub Pages for the repo (Settings → Pages → Deploy from branch `main`, folder
   `/docs`) so the Terms of Use / Privacy Policy pages drafted in this session actually resolve at
   the URLs now linked from `PaywallView.swift`. Text is drafted and committed; only the hosting
   toggle is outstanding.
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
- **Last updated**: 2026-07-17
- **Note**: the 2026-07-16 changes (impact-profile capture, score renormalization, skip-a-shot,
  LiDAR tap-to-measure height wiring, the `automaticallyConfigureSession` mesh-scan fix, LiDAR
  startup/interruption feedback, the Car/Truck silhouette toggle with fender/bumper landmarks,
  first-launch onboarding + enhanced empty state, in-flow "why this matters" guidance, the
  Results/PDF next-step nudge, and case-list thumbnails) were written in the Genspark sandbox,
  which has no Xcode/Swift toolchain — only brace/paren/bracket balance was checked, not a real
  compile. Build and test on-device before relying on this, especially the new tap/drag UI
  (`ImpactMarkerView`), the live-compass path (`HeadingProvider`), the LiDAR tap-to-measure flow
  (`LiDARScanView`'s "Measure Height" button, `LiDARService.worldY`/`heightFromWorldPositions`,
  the `automaticallyConfigureSession = false` fix, and the new
  `sessionWasInterrupted`/`sessionInterruptionEnded`/`cameraDidChangeTrackingState` handlers) —
  none of these have ever been compiled or run; the LiDAR raycast/mesh-scan code in particular
  needs a physical LiDAR device (no simulator support) to verify at all — the Car/Truck body-type
  toggle (`Vehicle.bodyType`, the `Picker` in `EditCaseSheet.swift`, and
  `ImpactSilhouetteView`'s bumper/fender landmarks) — the new `OnboardingView.swift` (a new file,
  manually registered in `project.pbxproj` since there's no Xcode GUI available in this sandbox
  to add it the normal way — double-check it appears under the Dashboard group in Xcode after
  pulling) — and `CaseRow`'s new thumbnail (`ForensicCase.thumbnailPhoto`,
  `UIImage(data:)` decode in `leadingVisual`), which needs a case with at least one real captured
  photo to actually exercise (a brand-new/empty case will just show the old icon fallback).
- **2026-07-17 changes** (app icon, Privacy Manifest, Terms of Use/Privacy Policy — see the
  sections above for full detail): also written with no Xcode/Swift toolchain available.
  `PrivacyInfo.xcprivacy` was validated as syntactically-correct XML plist via Python's
  `plistlib`, and its `project.pbxproj` registration follows the exact same
  PBXFileReference/PBXBuildFile/PBXResourcesBuildPhase pattern already used for `Assets.xcassets`
  — but neither has been opened in actual Xcode yet, so double-check both after pulling: (1) the
  app icon should appear filled-in (not blank) in the AppIcon slot in the asset catalog editor,
  and (2) Xcode's build log should confirm `PrivacyInfo.xcprivacy` is being copied into the app
  bundle (Apple's App Store Connect upload step will also flag it if the manifest is missing or
  malformed). The Privacy Policy/Terms pages are drafted and committed, but are **not live yet** —
  see "Still needed" above; the two `Link`s in `PaywallView.swift` will 404 until Sean turns on
  GitHub Pages for this repo.

## Reference Material
See `ios/reference/` for the original project brief, technical specs, algorithm explainer, and
the Python reference implementation the scoring engine was validated against.
