# Handoff Brief — Vehicle Damage Forensic Matcher (iOS)

**Handoff from:** Genspark Claw (planning + docs + Python analyzer)
**Handoff to:** AI Developer (Xcode / iOS build surface)
**Owner:** Sean Pierce
**Date:** 2026-07-06
**Project root:** `/home/work/.openclaw/workspace/vehicle-damage-forensics/`
**iOS source root:** `/home/work/.openclaw/workspace/vehicle-damage-forensics/VehicleDamageForensics/`

---

## 1. What this project is (30 seconds)

A forensic-grade iOS app that compares damage on a victim vehicle vs. a suspect vehicle (hit-and-run investigations) and produces a court-admissible match score + PDF report. Uses:

- **SwiftUI** for UI
- **AVFoundation** for guided photo capture
- **ARKit + LiDAR** for depth scans (iPhone Pro / iPad Pro)
- **Vision framework** for contour / deformation matching
- **PDFKit** for report generation
- **Local file storage** (Codable JSON) for cases — no backend

The scoring engine runs 7 factors (paint transfer, deformation pattern, height alignment, dimensional analysis, damage location, material transfer, temporal indicators) and produces a weighted composite score 0–100 with confidence bands.

Reference algorithm already validated in Python on Sean's own hit-and-run case (`forensic_analyzer.py`, `enhanced_forensic_analyzer.py`) — result: **84.5/100 match**. The iOS scoring code mirrors that Python logic.

---

## 2. Current state (honest)

### ✅ Written (~3,107 lines of Swift across 25 files)

```
VehicleDamageForensics/
├── App/
│   └── VehicleDamageForensicsApp.swift        (141)  ← @main + AppDelegate + AppState + ContentView
├── Models/
│   ├── Case.swift                             (177)  ← ForensicCase, chain-of-custody
│   ├── Vehicle.swift                          (233)  ← Vehicle, DamageZone, ColorRGB
│   ├── CapturedPhoto.swift                    (218)  ← photo + EXIF + metadata
│   └── MatchResult.swift                      (233)  ← FactorScore, MatchResult, Confidence
├── ForensicEngine/
│   ├── MatchScoreCalculator.swift             (189)  ← 7-factor composite scorer
│   ├── PaintTransferAnalyzer.swift            (98)   ← CIEDE2000 color match
│   ├── DeformationMatcher.swift               (141)  ← VNDetectContoursRequest
│   └── HeightAlignmentAnalyzer.swift          (79)   ← ground-plane / bumper alignment
├── Services/
│   ├── CameraService.swift                    (429)  ← AVCaptureSession + guided capture
│   ├── LiDARService.swift                     (167)  ← ARKit scene reconstruction
│   ├── StorageService.swift                   (144)  ← Codable JSON on disk
│   └── PDFReportGenerator.swift               (206)  ← 8-page court-ready report
├── Utilities/
│   ├── ColorAnalysis.swift                    (162)
│   ├── MeasurementHelpers.swift               (102)
│   └── ModelExtensions.swift                  (48)
├── ViewModels/
│   ├── CaptureViewModel.swift                 (159)
│   ├── AnalysisViewModel.swift                (85)
│   └── CaseListViewModel.swift                (96)
└── Views/
    ├── Capture/         (CaptureFlowView, CaptureCameraView, SensorGuidanceOverlay)
    ├── Dashboard/       (DashboardView)
    ├── LiDAR/           (LiDARScanView)
    ├── Reports/         (PDFReportView)
    └── Results/         (MatchResultsView)
```

### ❌ Not yet done (this is what you're picking up)

1. **No `.xcodeproj` / `.xcworkspace`** — the Swift files exist as loose sources. Needs an Xcode project scaffolded around them.
2. **No `Info.plist`** — needs privacy usage strings (camera, photo library, location optional).
3. **No `Assets.xcassets`** — no app icon, no accent color, no launch screen.
4. **Not compiled once.** These files were written from spec, not iterated in a compiler. Expect real errors:
   - Possible signature mismatches between ViewModels and Services
   - `@MainActor` isolation issues on some singletons
   - `NavigationView` is deprecated → will need `NavigationStack` on iOS 16+ target
   - `ARMeshAnchor` API surface may need minor updates for current ARKit
5. **No unit tests.** No `XCTest` target.
6. **No provisioning / signing.** Needs Sean's Apple Developer team ID configured.
7. **No entitlements.** iCloud (optional), Camera, PhotoLibrary, ARKit.

### 🎯 Minimum-viable target

**Compiling app that runs on device, walks a user through capturing victim + suspect photos, runs the scoring engine, and shows a match result screen.** Everything else (LiDAR polish, PDF export, cloud sync) is v1.1+.

---

## 3. Concrete task list for AI Developer

### Phase 1 — Get it compiling (day 1)

1. Create `VehicleDamageForensics.xcodeproj` with:
   - iOS 16.0 minimum deployment target (needed for `NavigationStack`, Charts, etc.)
   - Swift 5.9+
   - Bundle ID: `com.spearitnow.vehicledamageforensics` (confirm with Sean)
   - Team: **ask Sean for Apple Developer team ID before signing**
2. Add all existing `.swift` files under `VehicleDamageForensics/` as project sources, preserving group structure.
3. Add `Info.plist` with:
   - `NSCameraUsageDescription` = "Capture damage photos for forensic analysis"
   - `NSPhotoLibraryUsageDescription` = "Import existing damage photos for analysis"
   - `NSPhotoLibraryAddUsageDescription` = "Save forensic reports to your photo library"
   - Optional: `NSLocationWhenInUseUsageDescription` if geo-tagging capture location
4. Add capabilities:
   - Camera
   - ARKit (with `arkit` in `UIRequiredDeviceCapabilities`)
5. **First compile.** Fix errors iteratively. Do NOT rewrite architecture — the design is intentional. Fix minimum surface to compile.
6. Replace deprecated `NavigationView` → `NavigationStack` where it fails.

### Phase 2 — First runnable app (day 2–3)

7. Boot on simulator. Confirm Dashboard renders.
8. Boot on real device (LiDAR device preferred). Confirm camera permission flow.
9. Walk the CaptureFlowView end-to-end: victim photos → suspect photos → analysis trigger.
10. Confirm `MatchScoreCalculator.evaluate(case:)` runs without crashing (even with degraded/stub inputs).
11. Wire MatchResultsView to display the returned `MatchResult`.

### Phase 3 — Polish for internal use (week 1)

12. Add app icon (Sean can generate via `gsk img` if needed — ping Claw).
13. Add launch screen.
14. Add basic unit tests for `MatchScoreCalculator` using bundled fixture images from `demo/images/` and `photos/victim/` `photos/suspect/`.
15. Confirm `PDFReportGenerator` produces a valid PDF and it opens in Preview / Files.app.
16. Add StoreKit setup **only if Sean approves TestFlight distribution**.

### Phase 4 — Beta-ready (weeks 2–4)

17. Fix all runtime crashes surfaced by dogfooding on Sean's real case photos.
18. Tune scoring thresholds vs. Python reference (see `forensic_analyzer.py` / `enhanced_forensic_analyzer.py`). Match Python's 84.5 result on the reference case within ±5 points.
19. LiDAR scan polish (coverage indicator, retry flow).
20. TestFlight build.

---

## 4. Architecture guardrails (don't break these)

- **State flow:** `AppState` (env object) owns cases + active case; `StorageService.shared` persists. Views read via `@EnvironmentObject`. ViewModels are per-screen.
- **Scoring is pure & async:** `MatchScoreCalculator.evaluate(case:) async -> MatchResult`. Do not call it from the main thread synchronously.
- **Services are `@MainActor` singletons or instance-owned.** Do not spawn parallel LiDAR sessions.
- **Chain-of-custody matters.** Every mutation to `ForensicCase` should preserve `createdAt` and append to `auditLog` (see `Case.swift`). This is a court-evidence app — audit trail is a feature, not overhead.
- **No PII to cloud without explicit opt-in.** Storage is local-first by design.
- **Don't rewrite the ForensicEngine.** The 7-factor weights and scoring math mirror the validated Python reference. If you find a bug, flag it — don't silently "improve" the math.

---

## 5. Reference material inside the repo

- `iOS_TECHNICAL_SPECS.md` — full architecture spec (350+ lines)
- `ALGORITHM_EXPLAINER.md` — plain-English walkthrough of the 7 factors
- `FORENSIC_MATCH_ANALYSIS.md` + `FORENSIC_COMPARISON_REPORT.md` — Sean's real case output from the Python analyzer (ground truth for iOS parity)
- `forensic_analyzer.py` / `enhanced_forensic_analyzer.py` — the reference implementation
- `photos/victim/` and `photos/suspect/` — real image fixtures usable for testing
- `demo/images/` — smaller demo pair
- `PROJECT_BRIEF.md` — original goal doc
- `COMPLETE_FILE_MANIFEST.md` — line-by-line file inventory

---

## 6. When to hand back to Claw

**Bring it back to Genspark Claw (this assistant) for:**

| Need | Why Claw is better |
|---|---|
| **Python analyzer changes** (`forensic_analyzer.py`, `enhanced_forensic_analyzer.py`) | Runs natively in this VM; Claw can execute + iterate live. |
| **Regenerating forensic reports** on Sean's real case | Python + PDF pipeline already wired here. |
| **Updating any `.md` doc** (status, plans, App Store listing, police report template, algorithm explainer) | 40+ docs are the "operations layer" of this project — Claw's zone. |
| **App icon / launch screen art** | `gsk img` for generation, `gsk analyze` for review. |
| **Marketing copy** (App Store listing, TestFlight welcome email, beta invite) | Claw has full user context (`USER.md`) and can tie it to Sean's brand voice. |
| **Emails to counterparties** (police, insurance, beta testers, potential investors) | Claw has Sean's email + contact network + can send via `gsk vm_email`. |
| **Scheduling reminders / follow-ups** | Claw has `cron` — e.g., "remind me Monday to file the police report." |
| **Cross-project coordination** with Freedom Beverage / PD Bev / Ramona's / etc. | Claw is Sean's main assistant across all workstreams. |
| **Sanity-checking scoring math** vs. the Python reference | Claw can run both and diff outputs numerically. |
| **New forensic factors / R&D** on the algorithm before it hits iOS | Prototype in Python first, then hand the spec to AI Developer. |
| **Business docs**: pricing, TAM refresh, competitive scan, investor deck outline | Documentation + web research zone. |
| **Reading & summarizing** AI Developer's progress reports | Keep BUILD_LOG.md, PROJECT_STATUS.md current. |

**Stay with AI Developer for:**

| Need | Why AI Developer is better |
|---|---|
| **All Xcode work** — project file, targets, schemes, capabilities, signing | Real IDE integration. |
| **Compile / run / debug cycles** on the Swift code | Actual iOS toolchain. |
| **SwiftUI view iteration** (previews, layout tweaks, animations) | Xcode Previews. |
| **Instruments profiling** (memory, CPU, ARKit performance) | Requires Xcode. |
| **Unit / UI tests** (XCTest, XCUITest) | Build + run tests. |
| **Simulator + on-device testing** | Simulator / provisioning. |
| **TestFlight builds & App Store submission** | Xcode Cloud / archive / upload. |
| **CocoaPods / SPM dependency management** if any get added | Package resolution needs Xcode. |
| **ARKit / RealityKit / Vision runtime debugging** | Needs real device + Xcode logs. |

---

## 7. Suggested workflow

1. **AI Developer** completes Phase 1 (compile) → pings Sean.
2. Sean drops a short status back into Claw ("compiled, 3 warnings, screenshot attached").
3. **Claw** updates `BUILD_LOG.md` and `PROJECT_STATUS.md` to reflect reality.
4. Repeat per phase.
5. When AI Developer hits a scoring-math question or wants a new fixture, Sean brings it to Claw → Claw runs the Python reference → hands back a numeric answer or fixture pair.
6. Before TestFlight, Claw drafts the beta invite email + tester recruitment message.
7. Before App Store submission, Claw finalizes App Store listing copy + screenshots (art via `gsk img`, review via `gsk analyze`).

---

## 8. Open questions AI Developer should ask Sean before starting

1. **Apple Developer team ID** (for signing).
2. **Bundle identifier** — confirm `com.spearitnow.vehicledamageforensics` or preferred alternative.
3. **Minimum iOS version** — brief assumes iOS 16.0 (recommended). Sean may want iOS 17 to unlock Swift Charts polish and newer ARKit APIs.
4. **App name for App Store** — "Vehicle Damage Forensic Matcher" or a shorter consumer-facing name?
5. **Beta distribution channel** — TestFlight only, or ad-hoc first?
6. **iCloud sync** — v1 local-only OK, or does Sean want CloudKit from the start?
7. **Analytics / crash reporting** — off, Firebase, Sentry, or Apple-native only?

---

## 9. Success criteria for this handoff

**Phase 1 done when:** app compiles + launches to Dashboard in simulator, no crashes on cold start.

**Phase 2 done when:** end-to-end flow (create case → capture 2 photos each side → analyze → view score) works on a real device without crashes.

**Phase 3 done when:** Sean can run the app on his own case photos and get a match result numerically consistent (±5 points) with the Python reference (84.5).

**Ship-ready when:** TestFlight build exists, 3 external beta testers can install and complete a full case flow.

---

## 10. Contact

**Sean Pierce** — Owner
- Email: info@spearitnow.com / spierce26@gmail.com
- Phone: (949) 400-6592
- Timezone: America/Los_Angeles

**Claw (Genspark)** — Ops & Python side
- Ping via the main Genspark Chat any time you want the Python reference run, docs updated, or a fixture pair generated.

---

*Written by Genspark Claw, 2026-07-06. Update this doc as reality changes — don't let it drift.*
