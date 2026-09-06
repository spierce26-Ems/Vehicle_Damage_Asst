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

<!-- BEGIN: Improvement plan + work status (maintained by Ledger) -->
## Improvement Plan & Work Status

Last updated: 2026-09-06 · latest commit on `main`: `6cb476a`

Status values: Not started / In progress / Blocked / In review / Done.
`In review` means the author has finished everything in their control. `Done`
requires a real clean build, an on-device run where relevant, and a changelog
entry with a walked test checklist — see `docs/PROCESS.md` §4.

**Standing constraint: there is no Mac and no LiDAR device on this team.**
Every compile and every device run happens on Sean's machine. This is not a
temporary blocker to be cleared — it shapes every verification step from here.
See `HANDOFF_SUMMARY.md` §5.3.

### The 5-item improvement plan

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | ROI / focus-region crop (tape measure mistaken for damage) | Task #5 — 3 of 4 sub-commits on `main`; 4th in review on `reapply-focus-ui`, and **first in the landing order** | Model field `CapturedPhoto.scarFocusRegion` (`6cc8629`), extractor hard boundary (`caac5a8`), view-model threading (`89f5165`) are on `main`. The 4th sub-commit — the `ScarCaptureView` UI to draw the box — was reverted at `9b6a67e`; content preserved at `3f6d7f4`. Reapply as one isolated commit and open in Xcode immediately. Gated on a green build. |
| 2 | Per-shot capture guidance + close-focus quality gate | Task #4 — spec accepted at v3, code not written | Prioritised ahead of item 1's UI: cheaper root fix for the same tape-measure problem. **Recorded so it is not re-derived: this is NOT a blanket "no rulers" rule.** `CaptureProtocolStep.fullProtocol` id 4 is literally a ruler/tape-measure height-reference shot — wanted evidence. The bug is only that rulers land in the shots whose *pixels* feed the engine, where printed ticks read as striations and the ruler's colour reads as paint transfer. Guidance is per-shot, keyed on `PhotoType.isAnalysisShot`. A literal blanket ban would cost the height reference and with it all scale. Implementation gate: commit 3 touches `ScarCaptureView.swift`, so **item 1's reapply (task #5) lands first, alone, verified in Xcode** — two large diffs racing on that file is how the crash repeats. |
| 3 | Null-model / statistical-significance scoring for tool-mark match | Code on `main`, never compiled — **not Done** | `7391b73`. Adds `nullModelMeanPercent`, `nullModelStdDevPercent`, `zScore`, `isStatisticallySignificant` to `ToolMarkComparison`, all additive/optional. Seeded SplitMix64 PRNG so re-analysis is deterministic. Still needs the on-device checklist in the changelog entry walked before this is called Done. |
| 4 | Per-cross-section exclude in the results UI | Task #6 — in review on `cross-section-exclude` | Rebases onto task #8 once that lands: #8 changes what a headline is, so the filtered outcome routes through `headlineDisplay` and carries a p-value on the same terms as the full score. Excluded probes stay in the exported report — a report that silently drops set-aside data misleads the reader, and PDF length is a cosmetic cost against an evidentiary one. Exclusion reasons are mandatory (enforced in the view model, not the UI), restores are audited too, the full score stays the headline, and an exclusion that *raised* the score is called out — that asymmetry is deliberate. Demonstrated risk: two exclusions moved a comparison from not-significant to significant, which with 7 probes per photo is a few taps. The filtered null model is recomputed, not inherited: a shorter sequence is easier to align by chance, so reusing the full run's baseline would systematically overstate significance. |
| 5 | "Duplicate Case for Another Suspect" | Task #7 — in review on `duplicate-case`; **Option B decided by Sean** | **Option B**: a clone action creating a new case pre-filled with victim data (`sourceCaseID`, regenerated ids, suspect vehicle and match results cleared). **Why A is not recommended**: refactoring `ForensicCase.suspectVehicle` from an optional into an array touches ~88 references across 15 files, on a codebase that has never been compiled, and the file most likely to be dragged in is the one already blamed for an Xcode crash — the highest-risk change available, for no user-visible benefit today. A returns to the roadmap only if a single combined multi-suspect report is genuinely required. |

### Foundation work (must land before feature work is trustworthy)

**These are not strictly sequential.** P0-2 does *not* depend on P0-1: a
build-only check (`Cmd+B`) against a Simulator destination compiles without a
development team selected. Signing gates *running on a device*, not compiling.
An earlier P0-1-then-P0-2 ordering was wrong and is corrected here — nobody
should wait on Apple Developer team setup to start finding compiler errors.

| Priority | Item | Status | Depends on |
|---|---|---|---|
| P0-1 | Apple Developer team in Signing & Capabilities | In progress — needs one Team ID | Sean |
| P0-2 | First green clean build — nothing in this repo has ever been compiled | In progress | repo access only; **not** signing |
| P0-3 | End-to-end run on a LiDAR device: capture → analysis → PDF, logged in this changelog | In progress | P0-1 (signing) + P0-2 |
| P0-4 | Docs + process discipline (this block, `HANDOFF_SUMMARY.md`, file manifest, `docs/PROCESS.md`, `docs/EVIDENCE_APPENDIX_CAPTURE_NOTES.md`) | Done — landed `7966c5f`…`0f657db` | — |
| P1b | "Trust the number": algorithm version stamp in results and exports; no bare match % in the UI — always similarity plus the null-model p-value from `7391b73` | Task #8 — in review on `prism-task10-p1b` | P0-2 |

### Other open tasks

| # | Item | Owner | Status |
|---|---|---|---|
| #10 | Three scoring divergences against the Python reference, incl. the 6-inch height rule-out | Prism | (a) and (b) in review on `prism-task10-p1b`. The defect they fix: a height mismatch that should exclude a suspect scored 39/100 — quietly wrong in the direction of implicating someone. |
| #11 | Examiner identity — plus the `AuditEntry` actor field and the report attestation block, folded in | Vector | Open. Blocks the cover examiner line, the custody actor column and the attestation. All three omit cleanly until it lands (§5). |
| #12 | UI/UX design set: wireframes, report mocks, implementation specs | UI/UX Designer | Standing track, in review. Report page mocks reviewed; new strings on all four pages are under the copy lock. |
| #13 | Readiness bar + LiDAR set-point reticle | Vector | Open — touches no `ScarCaptureView.swift` and adds no new Swift files, so it is the one implementation item queuing behind signing alone. |

### Held out of the tree deliberately

**`main` carries zero Swift changes from this team.** Every commit on it is
documentation, process, or tooling. That is deliberate: Sean's first compiler
run must be against exactly the tree that was parse-verified, so a compiler
error cannot be ambiguous between new work and pre-existing state.

All Swift work is reviewed and pushed to real remote branches — nothing lives
in a chat attachment:

| Branch | Task | Notes |
|---|---|---|
| `reapply-focus-ui` | #5 | The `ScarCaptureView` focus-region UI reapply. Lands first and alone: it is the file blamed for the Xcode crash. |
| `prism-task10-p1b` | #10a, #10b, #8 | Scoring divergences plus the version stamp and headline rework. |
| `cross-section-exclude` | #6 | Conflicts with `prism-task10-p1b` on `ToolMarkAnalysis.swift`, so it rebases rather than applying. |
| `duplicate-case` | #7 | Applies cleanly on top. |

**Landing order, verified by testing the applications rather than assuming
independence:**

1. `reapply-focus-ui` (#5)
2. `prism-task10-p1b` (#10a, #10b, #8)
3. rebase `cross-section-exclude` (#6) — #8 changes what a headline is, so the
   filtered outcome must route through `headlineDisplay` and carry a p-value on
   the same terms as the full score
4. `duplicate-case` (#7)

Then item 2's commits, then #11 and #13. Changelog entries assume this order;
any change to it will be stated explicitly rather than left to be inferred from
the commit stream.

### Queued behind the green build, not behind Sean

Kept separate from the open decisions below on purpose. These are blocked on an
event, not on an answer, and listing them among the decisions would grow Sean's
list with items he cannot act on — which is the fastest way to make a
decision list stop being read.

- **The offline shopping-aware null run** that produces the critical-value table
  (`docs/EVIDENCE_APPENDIX_CAPTURE_NOTES.md` §6.1.1). Blocked on compute only:
  no Mac, no device, no answer from anyone. It is sequenced after the first
  clean build so it cannot land as committed data referenced by code that has
  never compiled. Per §6.1.1's per-cell rule this is an **incremental**
  milestone rather than a go/no-go gate — the well-resolved cells lift
  suppression at their own probe and exclusion counts while under-resolved
  corners stay suppressed, so a partial result is a usable result.
- **Changelog entries and on-device checklists** for each Swift branch as it
  lands, in the recorded order, each with `COMPLETE_FILE_MANIFEST.md`
  regenerated in the same patch.

Sean's list is three items and stays three items: the Team ID, the first-build
error list, and the distribution target.

### Open decisions

Every box here is Sean's to tick. A recommendation — however unanimous among
the people working on this — is not a decision and never becomes one by
agreement. The value of this list is precisely that it distinguishes what he
chose from what was suggested to him; a recommendation that quietly promotes
itself to a decision makes the list worthless for the decisions it exists to
track. Recommendations are recorded so the work can proceed on a default, not
so the question can be closed.

- [x] **Item 5: Option A or Option B** → **Option B**, decided by Sean. Duplicate-case clone; no `suspectVehicle` array refactor.
- [x] **Capture quality gate: hard-block or warn only?** → **hard-block**, decided by Sean, with the manual shutter as the documented override. The override is what makes hard-block safe — a forced shot is saved and recorded (`gateOverridden`) rather than being indistinguishable from a clean one. The warn-only variant is not being built.
- [x] **The leftover Vite/Cloudflare web scaffold** → **deleted** at `34754e2`, approved by Sean, after verifying nothing in `ios/` referenced it.
- [ ] **Distribution target: TestFlight or direct-to-device Xcode installs?** Recommended: **stay on direct installs for now**. This decides how urgent App Store Connect / IAP product setup becomes.
- [ ] **Paywall / monetization configuration** (design decision #1). Design work is proceeding on the stated assumption rather than holding; exposure is confined to one screen and marked on the design artefact.
- [ ] **Does the report show *when* an exclusion was recorded?** New, from `docs/EVIDENCE_APPENDIX_CAPTURE_NOTES.md` §6. The app captures whether each excluded cross-section was excluded before or after a similarity figure had been displayed — that capture is not a decision and is not waiting on anyone, because the ordering exists only at the moment it happens and is unrecoverable afterwards. What is open is whether the evidence appendix *prints* it for an insurer or a court. Recommended: **print it**, in the neutral three-state wording §6.3 locks (before / after / not recorded), with no colour, ranking, or adjudication. The argument for printing is that a reader assessing a filtered comparison cannot weigh it without knowing whether the filter preceded the number; the argument against is that "recorded after" invites an inference of bad faith the app cannot support, and §6.4 bans the nine words that would make that inference explicit but cannot stop a reader drawing it. Either answer is implementable at any time and no work is blocked on it — the data is recorded regardless.
- [ ] **Apple Developer Team ID** — `DEVELOPMENT_TEAM` is absent from both Debug and Release in `project.pbxproj` *and* from `scripts/pbxproj_skeleton.txt`. One 10-character Team ID (a public identifier, not a secret) closes it; the patch is written and waiting. `CODE_SIGN_STYLE = Automatic` and the bundle id are already correct. This blocks every device run.

### Conventions

- One logical change = one commit, prefixed `[item-N]` (or `[build]`/`[docs]`/`[fix]`/`[chore]`).
- Every functional commit gets a changelog entry here with an on-device test checklist.
- Changelog prose is written by Ledger only — hand over what/why/files.
- Report and capture-screen copy is locked: see `docs/EVIDENCE_APPENDIX_CAPTURE_NOTES.md` §4. No probabilistic or verdict language, ever.
- Full rules: `docs/PROCESS.md`.
<!-- END: Improvement plan + work status -->

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
  - **Paint Transfer factor actually wired up for the first time — reference-swatch capture +
    same-photo relative color comparison** (added 2026-07, per Sean's question — "on the color
    matching, wont we run into issues matching OEM if we have poor lighting conditions or bad
    images taken?"). Investigating that question uncovered something bigger than lighting
    sensitivity: **Paint Transfer (30% weight, the highest of the 7 factors) was permanently
    `dataQuality: .unavailable` in every real case**, confirmed via exhaustive grep — `DamageZone`,
    `PaintAnalysis`, and `Vehicle.colorRGB` had zero real writers anywhere in the app (only the
    free-text `Vehicle.color` field was ever settable, via `EditCaseSheet`), and the old
    whole-image `ColorAnalysis.averageColor(of:)` helper was unreferenced dead code. Fixed with a
    from-scratch capture-to-scoring pipeline, deliberately built lighting-aware from day one rather
    than patching the old (never-running) logic:
    - **Capture-time reference swatch** — `Views/Capture/PaintReferenceMarkerView.swift` (new
      file) is presented as a sheet immediately after each of the 2 required `.paintTransfer`
      shots per vehicle (`CaptureCameraView.captureNextShot()`), while the investigator is still at
      the vehicle. The user taps two points on the just-captured photo itself: the
      damaged/foreign-paint area, then a nearby clean/undamaged panel — modeled on
      `ImpactMarkerView`/`ImpactSilhouetteView`'s tap-to-mark pattern, but tapping the real
      `Image(uiImage:)` rather than a schematic outline. Both points are stored on the specific
      photo (`CapturedPhoto.paintDamagePoint`/`paintReferencePoint`, new backward-compatible
      fields) so re-opening the sheet later shows what was already tapped.
    - **Localized, highlight/shadow-rejecting extraction** — `ColorAnalysis.sampleColor(from:at:)`
      (new function) replaces the dead `averageColor(of:)` for this purpose: samples only a small
      radius (~2% of the image's shorter side, roughly 20–30px on a typical photo) around each
      exact tap point, discarding the brightest/darkest 15% of pixels within that patch (by
      luminance percentile, not a fixed brightness threshold) before averaging the rest — so a
      small specular highlight or shadow crease near the tap doesn't wash out or darken the sampled
      color.
    - **Same-photo-relative scoring** — `PaintTransferAnalyzer.analyze()` rewritten to drop the old
      `victimVehicleColor`/`suspectVehicleColor` parameters entirely and instead compare each
      vehicle's own `PaintAnalysis` (built from its two same-photo taps) against the other's: does
      the foreign paint found on vehicle A's damage sit closer to vehicle B's *own* clean-panel
      reference than to A's own reference? Because both samples in a comparison come from the same
      photo/lighting, this never has to assume absolute color values are comparable across two
      different photos taken in two different lighting conditions — the specific failure mode
      Sean's question identified.
    - **Confidence downgrade on bad captures** — `PaintAnalysis.sampleQualityIsGood` (new field)
      is set `false` when either tap's localized sample showed heavy outlier-pixel rejection or
      high residual luminance variance (signs of glare/shadow/edge contamination even after
      percentile clipping); `PaintTransferAnalyzer` downgrades the factor's `dataQuality` to
      `.partial` in that case rather than silently trusting a poorly-lit capture as `.full`
      confidence.
    - `MatchScoreCalculator`'s call site updated to the new `PaintTransferAnalyzer.analyze(victim:
      suspect:)` signature. `AuditAction.paintReferenceRecorded` (new case) logs the first time a
      vehicle's paint reference is completed, alongside every other chain-of-custody event.
      Free-tier, entirely on-device — no cloud dependency.
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
- **Last updated**: 2026-07-18 — three changes:
  1. **Guided auto-capture on the main 30-shot protocol camera** (`CameraService`,
     `CaptureCameraView`, `Vehicle.usesEvenLightingGate`): mirrors the standalone
     Scar-Direction camera's Steady/Focused/conditional-Lighting auto-capture gates so the main
     protocol camera can also fire the shutter automatically once framing is stable, in focus,
     and (where required) evenly lit.
  2. **"Analysis Evidence" PDF section — show that real analysis happened, not just uploaded
     photos** (Sean: "we need to show that we did something with the images in the report, not
     just show the pictures uploaded"). `DeformationMatcher.analyze()` now returns a
     `DeformationResult` that, alongside the existing Deformation Pattern factor score, also
     captures the actual Vision-detected damage-contour boundary (`VNDetectContoursRequest`,
     thinned to ≤200 points) for both vehicles. `MatchScoreCalculator.evaluate()` persists this
     once, at analysis time, as `MatchResult.victimContourOverlay`/`suspectContourOverlay`
     (paired with the exact source photo ID it was traced from) — `PDFReportGenerator` never
     re-runs Vision at report-render time (`AnalysisViewModel.generateReport()` calls it
     synchronously, so a Vision re-run there would risk the same main-thread hang/OOM issues
     already hit twice on this pipeline). The new `drawAnalysisEvidence` PDF page draws the
     Y-flipped contour outline directly over each vehicle's actual damage photo, with the
     Deformation Pattern factor's raw score/notes as a caption.
  3. **Scar-Direction Consistency surfaced in both the app and the PDF**: `MatchResultsView` now
     shows a dedicated section (status, scenario narrative, per-vehicle motion description,
     reciprocity deviation) reading the already-existing `AnalysisViewModel.scarDirectionCheck`/
     `.suspectExclusionReason`, with a prominent red exclusion-warning callout when the hard
     exclusion rule fires. `PDFReportGenerator.drawScarDirectionSection` mirrors this in the
     report.
- **2026-07-18 changes, part 2** (Sean's on-device bug report on the Scar-Direction capture
  screen — layout fit, drag, and library-import issues):
  1. **Status-chip overflow fixed** — `ScarCaptureView.statusChips` and `CaptureCameraView
     .autoCaptureStatusChips` each packed three `.fixedSize(horizontal: true, ...)` capsules
     (Steady/Focused/Lighting) into one `HStack` with no wrapping; the longest lighting message
     ("Uneven light across scar — even out shadows/glare") overflowed the screen width, clipping
     text at both edges — confirmed exactly via Sean's screenshot. Fixed identically in both
     files: Steady/Focused on one row, Lighting alone on a second row at full width with
     `.minimumScaleFactor` instead of being clipped.
  2. **Scar-capture screen not fitting the device / Ready button unreachable** — root cause was
     `CaptureFlowView` presenting `ScarCaptureView` via `.sheet` (which renders shorter than true
     device height) even though `ScarCaptureView`'s own layout (full-bleed camera preview +
     stacked bottom controls) assumed it owned the full screen. Switched to `.fullScreenCover`.
     Also reduced the stacked-control row count in `aimingStage` by merging the photo-library
     button into the same row as the shutter (library — shutter — centering spacer), matching
     `CaptureCameraView`'s existing library—shutter—skip layout, so the Ready button above it sits
     higher and stays on-screen.
  3. **"Only the red marker can be moved" / "cannot upload from the roll" — root cause was
     unpushed commits, not a code defect**: comparing local `main` against `github/main` showed
     local was 3 commits ahead (photo review/retake, the scar-capture nudge/import UX, the B2
     model layer) that had never actually been pushed — so Sean's on-device build was running
     code from before those fixes existed. The nearest-endpoint drag disambiguation and the
     `PhotosPicker` library-import button were already correctly implemented; they just hadn't
     reached the device. All pending commits plus this round's layout fixes were pushed to
     `github/main` in one push (the library button was also restyled to an icon-only circle to
     match `CaptureCameraView`'s look now that it shares a row with the shutter).
  4. **Fingerprint-style scar matching — answered, not built**: Sean asked whether scars are
     analyzed "similar to a fingerprint" (discrete, isolated markings matched between vehicles)
     and, if not, whether they should be. Confirmed the current pipeline (`ScarLineSuggester
     .suggestLine`, `ColorAnalysis.detectScarTaper`) only extracts a single dominant line plus a
     binary taper direction — it does **not** do multi-feature/landmark extraction-and-matching.
     A real fingerprint-style approach (isolating multiple discrete sub-marks along the scar,
     describing each by position/width/spacing, then nearest-neighbor matching feature sets
     between victim/suspect scars for a match count) was scoped as a substantial new capability
     and is **not yet built** — awaiting Sean's go-ahead before starting.
- **2026-07-18 changes, part 3** (Answer B2 UI/PDF wiring): the `ScarLineComparison` model-layer
  addition from the prior round (built but never consumed) is now wired into both surfaces Sean
  asked for:
  - `MatchResultsView.scarLineComparisonSection` — new section showing victim vs. suspect scar
    line length/angle/position side-by-side (via `ScarLineComparison.build(victim:suspect:
    check:)`), plus the reciprocity-deviation number reused from the existing Scar-Direction
    Consistency check. Shown only when at least one vehicle has a marked scar line.
  - `PDFReportGenerator.drawScarLineComparison` — same data, same two-column layout, in the PDF
    report, inserted right after the existing Scar-Direction Consistency page.
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
- **2026-07-17 changes, part 2** (paint-color reference-normalization fix — see the Paint Transfer
  bullet above for full detail): also written with no Xcode/Swift toolchain — every edited/new
  Swift file was checked for brace/paren/bracket balance via a Python one-liner, but none of this
  has been compiled or run. Double-check after pulling: (1) `PaintReferenceMarkerView.swift` (new
  file, manually registered in `project.pbxproj` under the `Capture` group the same way
  `OnboardingView.swift` was in the prior round — verify it appears there in Xcode), (2) the sheet
  actually presents after capturing a `.paintTransfer` shot and both taps register as expected
  markers on the photo, (3) `CaptureViewModel.recordPaintReferenceTaps`'s suspect-vehicle branch in
  particular (a `guard var suspect = forensicCase.suspectVehicle` local copy pattern, mutated then
  written back once) — this is new plumbing that has never been exercised on-device, and (4) a
  full two-vehicle run through to Results to confirm the Paint Transfer factor now actually shows
  `dataQuality: .full`/`.partial` instead of permanently `.unavailable` once both vehicles' paint
  references are recorded.
- **2026-07-17 changes, part 3** (dead-end regression fix, in response to Sean asking "are there
  any other features that actually lead to a dead end right now"): the paint-transfer fix above
  was itself the first code anywhere in the app to ever construct a real (non-nil) `DamageZone`
  (`CaptureViewModel.applyPaintAnalysis`). Before it, `Vehicle.damageZones` was *always* empty in
  every real case, so `MatchScoreCalculator.scoreDamageDimensions`/`scoreMaterialTransfer` and
  `HeightAlignmentAnalyzer`'s zone-height block always hit their `nil` guard and correctly reported
  `.unavailable`. Nothing in the app has ever populated `widthMM`/`heightMM`/`centerHeightInches`/
  `topEdgeHeightInches`/`bottomEdgeHeightInches` or the rubber/plastic-transfer flags on
  `PaintAnalysis` — so once a real zone exists (created only to carry paint data), those fields sit
  at their struct default (`0.0`/`false`), and without a guard, comparing two zeros/two `false`s
  would read as a false PERFECT match (`rawScore: 100, dataQuality: .full`) or a false confident
  negative, instead of the correct `.unavailable`. Added `DamageZone.hasDimensionData`/
  `.hasZoneHeightData` and `PaintAnalysis.materialTransferExamined` flags, and gated all three
  affected call sites on them. A broader sweep of the rest of the app (`AnalysisViewModel`,
  `CaseListViewModel`, `MatchResultsView`, `StorageService`, `PurchaseManager`, `PaywallView`,
  `LiDARScanView`) found no other dead-ends of this severity — see the chat log for the full list
  of lower-severity dead fields still outstanding (`DamageZone.impactAngleDegrees`/
  `transferDirection`, the `TransferDirection` enum, `LiDARScanData.meshFileURL`/`depthMapData`,
  `CameraSettings.whiteBalance`/etc., `Vehicle.colorRGB`) — none of these fabricate a false score,
  they just silently carry no signal, so they were left as-is pending Sean's prioritization.
  **Not yet compiled/run** — same no-Xcode-toolchain caveat as every other change in this file;
  only brace/paren/bracket balance was checked.
- **2026-07-18 changes, parts 2 & 3 — build/test state**: same no-Xcode-toolchain caveat — only
  brace/paren/bracket balance was checked (ScarCaptureView.swift, CaptureCameraView.swift,
  CaptureFlowView.swift, MatchResultsView.swift, PDFReportGenerator.swift), nothing has been
  compiled. Please rebuild/reinstall from main and re-test on-device: (1) the scar-capture
  screen now fits/fills the full display, (2) both scar-line endpoints (front/red and rear) can
  each be dragged independently by touching near that specific dot, (3) the photo-library import
  button appears next to the shutter and successfully imports a photo, (4) the Ready button is
  reachable once all gates are green, and (5) the new Scar Line Comparison section appears on the
  Results screen and in the generated PDF whenever at least one vehicle has a marked scar line.
- **2026-07-18 changes, part 4 (fingerprint-style Scar Matching, per Sean's explicit "let's start
  building this as well")**: added a genuine minutiae-style feature layer on top of the marked
  scar line, complementing (never replacing) the single-dominant-line (`ScarLineSuggester`) and
  binary-taper-direction (`ColorAnalysis.detectScarTaper`) analyses already in place. New
  `Utilities/ScarFingerprintAnalysis.swift`: samples two independent 1D profiles along the marked
  line — paint-transfer DENSITY (ΔE2000 vs. the clean-panel reference, reusing
  `ColorAnalysis.sampleColor`/`deltaE2000`/`rgbToLab`) and mark WIDTH (perpendicular-probe proxy) —
  then extracts local peaks in each as discrete `ScarMinutia` (a neighborhood-relative prominence
  filter rejects ordinary sample noise), and matches two vehicles' minutiae sets with a greedy
  nearest-neighbor algorithm (same type, within 15% of line length). Minutiae are extracted at
  capture time (`CaptureViewModel.recordScarDirection`, both victim/suspect branches) and persisted
  on `CapturedPhoto.scarMinutiae`; the match itself (`MatchResult.scarFingerprintMatch`) is computed
  in `MatchScoreCalculator.evaluate()` as a THIRD independent scar signal — like
  `ScarDirectionCheck` and the new Scar Line Comparison, it is deliberately never blended into
  `compositeScore`/`factors` (which must keep summing to 1.0). Zero/few minutiae is a valid,
  non-punitive outcome (`matchScorePercent` is `nil`, not 0, when either vehicle has no extractable
  markings) — same pattern as `DataQuality.unavailable`/`ScarDirectionCheck.notDeterminable`
  elsewhere in this app. Surfaced as a new "Scar Fingerprint Matching" section on the Results screen
  (`MatchResultsView.scarFingerprintSection`) and as its own PDF page
  (`PDFReportGenerator.drawScarFingerprintMatch`), both showing each vehicle's markings with
  matched/unmatched status. `project.pbxproj` updated to register the new source file (all 4
  required entries: PBXBuildFile, PBXFileReference, Utilities group, Sources build phase).
  **Not yet compiled/run** — same no-Xcode-toolchain caveat; only brace/paren/bracket balance was
  checked on all 8 touched files (7 Swift files all balanced + `project.pbxproj` brace/paren
  balanced with all 4 new-file registration IDs verified present in exactly the expected
  locations). Please rebuild/reinstall from main and re-test on-device: (1) marking a scar line
  with a paint reference already recorded runs without hanging or crashing, (2) the new "Scar
  Fingerprint Matching" section renders on the Results screen once a suspect vehicle also has a
  marked scar line, showing each vehicle's extracted markings, (3) the equivalent section appears
  as its own page in the generated PDF, and (4) a case where one or both vehicles have no scar
  line marked (or no clean-panel reference recorded) shows the "not enough distinct detail to
  compare" wording rather than a fabricated score.

- **2026-07-19 changes (existing-case-photo picker for scar marking, per Sean's explicit request
  "I want the option to pick from roll or take a picture right then for the scar picture. Scar
  picture may also be the same picture with paint transfer.")**: `ScarCaptureView` previously only
  accepted a BRAND NEW photo for scar marking (live auto-capture or a fresh camera-roll import) —
  there was no way to reuse an already-excellent `.closeupDamage`/`.paintTransfer` shot taken
  moments earlier in the main protocol camera, even when that exact photo already clearly showed
  both the scar and its paint-transfer taper. Added a third button (grid icon, next to the shutter
  and photo-library buttons) opening `ExistingPhotoForScarPicker` — a thumbnail grid (modeled on
  `PhotoReviewView.PhotoReviewCell`'s `LazyVGrid` layout) of this vehicle's already-captured
  `.closeupDamage`/`.paintTransfer` photos, with a non-punitive empty state
  (`ContentUnavailableView`) when none exist yet. Picking a photo reuses the existing
  `installFreshlyCapturedPhoto(_:)` hand-off, landing in the `.marking` stage identically to a
  fresh capture. No new files — both new views added as private structs at the bottom of
  `ScarCaptureView.swift`, so no `project.pbxproj` changes were needed.
- **2026-07-19 changes (Tool-Mark / Striation Matching, per Sean's explicit request: "we should be
  able to analyse both images and run them through an algorithm that looks closely at the lines
  and measure the distance between to see if the same fingerprint... change the light rays of the
  image or change the spectrum somehow to really bring out unique characteristics that can be
  matched at a high level of confidence just like finger prints. We are basically looking for
  tooling marks on each vehicle from the other.")**: a FOURTH, independent scar-based signal
  alongside Scar-Direction Consistency, Scar Line Comparison, and Scar Fingerprint Matching — this
  one is a genuine forensic tool-mark/striation examination analog. New
  `Utilities/ToolMarkAnalysis.swift` looks ACROSS the marked scar's width (not along its length,
  which is what `ScarFingerprintAnalysis` already does) for fine parallel scratch/gouge lines, and
  compares the SPACING RHYTHM between them, not their absolute size:
  - **Computational "raking light"** (answering "change the light rays/spectrum"): a high-pass
    filter subtracts a wide moving average from each cross-section's luminance profile, stripping
    broad shading/color gradients and leaving only the fine, fast-varying texture ripples a real
    raking (grazing) light would make visible.
  - **Scale/distance invariance** (answering "regardless of the height or size of the picture" /
    "match a close up... with an image that is not a closeup"): every gap between two detected
    striations is expressed as a ratio of that cross-section's own mean gap, never raw pixels — so
    a closeup and a wide shot of the same physical mark produce comparable "rhythm" sequences
    despite completely different absolute scales.
  - **Angle fan-out** (answering "analyse the scars from all angles"): probes several candidate
    angles at each of 7 evenly-spaced positions along the line and keeps whichever reveals the
    clearest periodic pattern, since the user only marks the scar's overall line, not the exact
    angle individual tool marks run at.
  - **"Stamp" pairing** (answering "granted it should be the opposite on the opposing vehicle
    similar to a stamp"): `ToolMarkMatcher.compare` tries the suspect's rhythm both forward and
    reversed against the victim's, and reports whichever orientation actually aligns
    (`ToolMarkComparison.orientationUsed`) — a genuine impression-pair comparison, not an
    identical-copy one.
  - Non-punitive: too little real texture detail (too blurry/distant/smooth) reports "not enough
    distinct striation detail to compare" (`matchScorePercent == nil`), never a fabricated
    low/negative score — same principle as `ScarFingerprintMatch`/`ScarDirectionCheck.notDeterminable`.

  Extraction (`ToolMarkExtractor.extractStriationProfile`) runs at capture time
  (`CaptureViewModel.recordScarDirection`, both victim/suspect branches) alongside the existing
  minutiae extraction, and is persisted on `CapturedPhoto.toolMarkStriationProfile`. The comparison
  itself (`MatchResult.toolMarkComparison`) is computed in `MatchScoreCalculator.evaluate()` as a
  read of that already-extracted data (no re-run of pixel sampling) — like every other scar-based
  check in this app, it is deliberately NEVER blended into `compositeScore`/`factors`. Surfaced as
  a new "Tool-Mark / Striation Matching" section on the Results screen
  (`MatchResultsView.toolMarkSection`) and as its own PDF page
  (`PDFReportGenerator.drawToolMarkComparison`), both showing each vehicle's per-position probe
  results and the best-aligned orientation. `project.pbxproj` updated to register the new source
  file (all 4 required entries: PBXBuildFile, PBXFileReference, Utilities group, Sources build
  phase) via a verified Python line-insertion method (occurrence counts checked before/after),
  not the file-editing tool.

  **Not yet compiled/run** — same no-Xcode-toolchain caveat as every other change in this file;
  only brace/paren/bracket balance was checked on all 9 touched files (`ToolMarkAnalysis.swift`,
  `CapturedPhoto.swift`, `CaptureViewModel.swift`, `MatchResult.swift`,
  `MatchScoreCalculator.swift`, `AnalysisViewModel.swift`, `MatchResultsView.swift`,
  `PDFReportGenerator.swift`, `ScarCaptureView.swift`) plus `project.pbxproj` (all balanced, with
  `ToolMarkAnalysis.swift` confirmed present exactly 4 times). Please rebuild/reinstall from main
  and re-test on-device: (1) the new grid-icon button on the scar aiming screen opens a thumbnail
  picker of this vehicle's existing closeup-damage/paint-transfer photos and picking one advances
  to line-marking on that photo, (2) marking a scar line on both vehicles runs without hanging or
  crashing, (3) the new "Tool-Mark / Striation Matching" section renders on the Results screen once
  both vehicles have a marked scar line, showing each vehicle's per-position striation counts and
  the best-aligned orientation (same-direction vs. reversed), (4) the equivalent section appears as
  its own page in the generated PDF, and (5) a case where one or both vehicles' scars are too
  smooth/blurry/distant to show real striations shows the "not enough distinct striation detail to
  compare" wording rather than a fabricated score.

- **Tool-mark score statistical significance — null-model/shuffle baseline.** Root cause of
  Sean's question "how do we get two different suspect vehicles with 69% and 78% tool
  mark/striation matching? How is that possible?": `ToolMarkMatcher.compare` tries every sliding
  offset in both orientations and keeps only the best-scoring result, and every gap is stored as a
  ratio to its own cross-section's mean gap — both of these compress most real-world, UNRELATED
  scrapes toward a "50-85% moderately similar" band purely by chance, with no way to tell that
  apart from a real match using the raw percentage alone. Fix: for the winning alignment, the exact
  same search (same offsets, same both-orientations check) is re-run 120 times against randomly
  shuffled copies of the suspect's own rhythm values (same numbers, real order destroyed;
  `ToolMarkMatcher.nullModelTrialCount`), building a baseline distribution of what an unrelated
  scrape would typically score from this same search by chance alone
  (`ToolMarkComparison.nullModelMeanPercent`/`nullModelStdDevPercent`). The real score is expressed
  as a z-score against that baseline (`ToolMarkComparison.zScore`), and only a score that clears 2.0
  standard deviations above the baseline is called statistically significant
  (`ToolMarkComparison.isStatisticallySignificant`, threshold in
  `ToolMarkMatcher.significanceZScoreThreshold`). `ToolMarkComparison.summary` now says so directly
  — e.g. "...however, unrelated/random spacing patterns of this same length typically score around
  X% with this same search purely by chance — this result is NOT statistically distinguishable from
  random..." — instead of presenting a raw percentage as if it were automatically meaningful. Uses a
  small deterministic seeded PRNG (`SeededGenerator`, SplitMix64) keyed off a stable hash of both
  rhythm sequences, not Swift's system RNG or `Hasher` (both are non-reproducible across
  runs/launches by design) — re-running analysis on the same two photos must always report the same
  verdict. Fully self-contained inside `ToolMarkAnalysis.swift`: `MatchResultsView.swift` and
  `PDFReportGenerator.swift` need NO changes since both only ever read `comparison.summary` and the
  pre-existing `matchScorePercent`/`orientationUsed` fields, which are unchanged in shape (3 new
  fields on `ToolMarkComparison` are purely additive/optional).

  **Not yet compiled/run** — same no-Xcode-toolchain caveat as every other change in this file; only
  brace/paren/bracket balance was checked on `ToolMarkAnalysis.swift` (the only file touched),
  confirmed balanced. Please rebuild/reinstall from main and re-test on-device: (1) the Tool-Mark /
  Striation Matching section on the Results screen and its PDF page both still render normally, (2)
  a comparison that previously showed a raw percentage now also shows either "...unlikely to be a
  coincidence" or "...NOT statistically distinguishable from random" appended to the summary
  sentence, (3) re-running analysis on the same two photos without changing anything reports the
  exact same percentage/verdict every time (determinism check), and (4) the "not enough distinct
  striation detail to compare" / "no consistent overlapping rhythm found" cases (no score at all)
  are unaffected and still show their original wording with no baseline/significance text appended.

- **Height Alignment: implement the documented 6-inch hard rule-out (task #10a).**
  `MeasurementHelpers.heightAlignmentScore` scored linearly to zero at 5x tolerance = 10 inches,
  contradicting `ios/reference/ALGORITHM_EXPLAINER.md` §2, which specifies banded scoring with a
  hard rule-out above 6 inches, and contradicting `_analyze_height_alignment` in the Python
  reference, which implements the bands. The consequence was the most consequential scoring defect
  found in this engine: a **6.1-inch height mismatch — a difference that should exclude a suspect
  outright — scored 39/100** and contributed a third of a 20%-weighted factor's credit toward
  implicating them. Wrong in the direction of implicating someone is the worst direction this app
  can be wrong in.

  | Δheight | was | now | Python reference |
  |---|---|---|---|
  | 1" | 90 | 100 | 100 |
  | 2" | 80 | 100 | 100 |
  | 4" | 60 | 75 | 75 |
  | 6" | 40 | 50 | 50 |
  | **6.1"** | **39** | **0** | **0** |
  | 8" | 20 | 0 | 0 |

  Now banded exactly as documented — verified to agree with the Python reference at every band
  boundary including 2.001", 4.001" and 6.001". Bands are deliberately absolute inches, not
  multiples of `toleranceInches`: the rule-out is a claim about vehicle geometry (strike heights on
  real vehicles do not differ by more than half a foot and still touch), so it must not move when
  someone tunes measurement precision — which is exactly how the old form drifted to 10 inches.
  `toleranceInches` now only widens the top "perfect" band. New `heightRuleOutInches` constant and
  `heightsRuleOut(_:_:)` predicate.

  **Also, per the tech lead's requirement that a rule-out surface as an exclusion rather than a low
  subscore:** `MatchScoreCalculator.evaluateExclusionRule` now fires on a height rule-out
  **standalone**, without requiring a scar-direction conflict. Previously the only path to an
  exclusion was "height mismatch AND scar conflict", so a physically impossible height difference
  on a case with no usable scar evidence — or with scars that happened to agree — produced no
  exclusion at all, just a 0 subscore multiplied by 0.20 and averaged into a composite that could
  still read "MODERATE CORRELATION". A geometric impossibility is not a weak signal to be outvoted
  by paint colour. Sean's original combined rule is unchanged and now runs only for the
  sub-rule-out mismatch band. Missing measurements are still never treated as a mismatch.

  **Not yet compiled** — no Xcode toolchain; brace/paren balance checked, and the new band curve
  was verified against a Python port of both the old and reference implementations at every
  boundary. On-device: confirm a deliberate >6" height-mismatch pair surfaces the exclusion banner
  on the results screen and in the PDF, and that a 3" mismatch does NOT (poor score, plausible
  collision).

## Reference Material
See `ios/reference/` for the original project brief, technical specs, algorithm explainer, and
the Python reference implementation the scoring engine was validated against.
