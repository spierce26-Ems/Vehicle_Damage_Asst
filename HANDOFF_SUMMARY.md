# Vehicle Damage Investigation Assistant — Project Handoff Summary

**Prepared for**: transfer to Genspark team
**Prepared by**: AI Developer (Genspark session), for Sean Pierce
**Date**: 2026-09-06 (session date; see git log for actual commit dates)

---

## 1. What This Project Is

An iOS app (SwiftUI + ARKit/LiDAR + Vision + StoreKit 2) that helps an
investigator document and forensically correlate vehicle damage between a
victim vehicle and a suspect vehicle in a hit-and-run case. It guides the
user through a structured photo/scan capture flow, runs several independent
computer-vision/statistical comparisons between the two vehicles, and
generates a PDF report suitable for an investigation file.

It is **fully on-device** — no backend server, no cloud storage, no
networking except Apple's own StoreKit for in-app purchases. All case data
is stored locally on the device as JSON via `FileManager`.

---

## 2. Where Everything Lives

### 2.1 Source of truth: GitHub repository

- **Repo**: `https://github.com/spierce26-Ems/Vehicle_Damage_Asst`
- **Branch**: `main` (the only branch; always use `main` for all work
  unless told otherwise)
- **Owner/access**: owned by GitHub user `spierce26-Ems` (Sean's account).
  **The new team will need Sean to add them as collaborators on this repo**
  — this AI session does not control GitHub permissions.
- **Latest commit at handoff**: `7391b73` — "Tool-mark score: null-model/
  shuffle statistical significance (item 3/5)"
- Working tree is clean; everything described in this document is
  committed and pushed. There is no uncommitted work sitting anywhere.

### 2.2 Secondary backup: Genspark SB-Git (auto-backup, not the main repo)

- A secondary git remote (`genspark`) also receives auto-pushed backups of
  this session's commits as a safety net. **This is not where the team
  should work from** — it's a Genspark-internal backup tied to this AI
  session, not a normal collaborative repo. Treat GitHub (`2.1` above) as
  the only real source of truth.

### 2.3 Local project folder structure (inside the repo)

```
Vehicle_Damage_Asst/                      <- repo root
├── HANDOFF_SUMMARY.md                    <- this file
├── .gitignore
└── ios/                                  <- the entire Xcode project lives here
    ├── README.md                         <- primary project documentation (READ THIS FIRST)
    ├── VehicleDamageForensics.xcodeproj/ <- Xcode project file
    ├── VehicleDamageForensics/           <- all Swift source
    │   ├── App/                          <- app entry point
    │   ├── Models/                       <- Codable data models (persisted structs)
    │   ├── ViewModels/                   <- @ObservableObject view models (MVVM)
    │   ├── Views/                        <- SwiftUI views, grouped by feature
    │   │   ├── Capture/                  <- camera/LiDAR/photo capture screens
    │   │   ├── Dashboard/                <- case list, onboarding, case editing
    │   │   ├── LiDAR/                    <- LiDAR scan UI
    │   │   ├── Paywall/                  <- StoreKit purchase UI
    │   │   ├── Reports/                  <- PDF report preview/share UI
    │   │   └── Results/                  <- match-results / comparison screen
    │   ├── Services/                     <- ARKit/camera/storage/PDF/StoreKit services
    │   ├── Utilities/                    <- pure-function analysis algorithms
    │   ├── ForensicEngine/               <- the scoring/matching orchestration layer
    │   └── Info.plist
    └── reference/                        <- original project brief + specs (see 2.4)
```

### 2.4 Reference material (original project brief — important context)

`ios/reference/` contains the documents this whole project was originally
built from:
- `PROJECT_BRIEF.md` — the original product brief
- `iOS_TECHNICAL_SPECS.md` — original technical spec
- `ALGORITHM_EXPLAINER.md` — explains the matching/scoring algorithms
- `HANDOFF_TO_AI_DEVELOPER.md` — an earlier handoff doc (predates this one)
- `COMPLETE_FILE_MANIFEST.md` — an earlier file manifest (may be stale —
  `ios/README.md`'s changelog and this document are more current)
- `APP_STORE_CONNECT_SETUP.md` — App Store Connect / IAP product setup notes
- `PAINT_ANALYSIS_KIT_FUTURE_FEATURE.md` — notes on a not-yet-built feature
- `forensic_analyzer.py`, `enhanced_forensic_analyzer.py` — a **Python
  reference implementation** the on-device Swift scoring engine was
  originally validated against (useful if the team wants to sanity-check
  the Swift math against an independent implementation)

### 2.5 The authoritative changelog: `ios/README.md`

**This is the single most important file for understanding what's been
built and why.** Every feature and bug fix made during AI-developer
sessions has been logged there in chronological order, each entry
explaining: what was built, why (often quoting Sean's exact original
request), which files were touched, and what to test on-device to confirm
it works. If the new team wants to understand the reasoning behind any
specific piece of code, start there before reading the code itself — most
non-trivial functions also have inline `NOTE(AI Developer)` comments
cross-referencing the same rationale.

---

## 3. Technical Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI (native, no third-party UI libraries) |
| Depth/3D scanning | ARKit + RealityKit (LiDAR scene reconstruction) |
| Computer vision | Apple Vision framework (`VNDetectContoursRequest`) |
| Pixel-level image analysis | Hand-rolled algorithms on raw `CGContext` pixel buffers (no CV/ML library) |
| Data persistence | `FileManager` + `Codable` JSON — **no database** |
| In-app purchases | StoreKit 2 |
| Backend/cloud | **None** — fully on-device by design |
| Min iOS version | 17.0 |
| Swift version | 5.0 |
| Bundle ID | `com.spearitnow.vehicledamageforensics` |
| Signing | "Automatically manage signing" — **no development team currently selected** (see Known Issues, 5.1) |

This stack was deliberately reviewed mid-session (see `ios/README.md` and
git history around the "are we using the best available tech stack"
question) — the on-device, no-backend architecture is considered a
*feature* for a forensic tool (no chain-of-custody question about data
leaving the device, works without connectivity at a scene), not a
limitation. The one acknowledged technical-debt area is the hand-rolled
(vs. library-based) pixel/statistics math in the tool-mark matching engine
— being incrementally hardened with proper statistical rigor (see item #3
below).

---

## 4. Feature Status

### 4.1 Fully implemented and working (pushed to `main`)
- Case creation/dashboard, victim + suspect vehicle capture flow
- LiDAR depth scanning + 3D scene reconstruction (impact geometry)
- Paint-transfer color analysis
- Scar-direction consistency check
- Scar Line Comparison (geometric)
- Scar Fingerprint Matching (minutiae-based, along scar length)
- Tool-Mark / Striation Matching (across scar width) — **plus a
  statistical significance layer added this session** (see 4.2, item #3)
- PDF report generation covering all of the above
- StoreKit 2 in-app purchase / paywall

### 4.2 A specific 5-item improvement plan is in progress

Sean asked for 5 specific improvements in one request; the plan was to do
each as small, isolated commits. Status at handoff:

1. **ROI/Focus-Region crop** (fixes a bug where a tape measure/ruler in
   frame was being mistaken for part of the vehicle damage) —
   **3 of 4 planned sub-commits done and pushed** (data model field,
   extractor hard-boundary logic, view-model threading). **The 4th
   sub-commit — the actual `ScarCaptureView` UI for the user to draw the
   focus-region box — was reverted and has NOT been reapplied yet.** See
   Known Issues 5.2 for why, and exactly what remains.
2. **No-ruler guidance + close-focus quality gate** — not started.
3. **Null-model/statistical-significance scoring** for the tool-mark match
   percentage — **done and pushed** (commit `7391b73`). This directly
   answers Sean's "how can two different suspects both score 60-80%?"
   question by telling the investigator whether a given score is actually
   distinguishable from random chance.
4. **Per-cross-section exclude** affordance in the results UI — not
   started.
5. **"Duplicate Case for Another Suspect"** — lets an investigator clone
   an existing case's victim-vehicle data to quickly set up a comparison
   against a different suspect vehicle, without re-entering everything.
   **Not started — and an open design question is still unanswered by
   Sean**: whether to (A) refactor `ForensicCase.suspectVehicle` from a
   single optional `Vehicle?` into an array (larger, riskier rewrite
   touching ~88 references across 15 files), or (B) add a simpler
   "duplicate case" clone action that just creates a new case pre-filled
   with the same victim data (small, additive, recommended). **The new
   team should get Sean's decision on A vs. B before starting this item.**

---

## 5. Known Issues / Important Context for the New Team

### 5.1 No Apple Developer Team configured for code signing
Xcode currently shows "Signing for 'VehicleDamageForensics' requires a
development team" (Team: None). The new team will need to set their own
Apple Developer account/team in Xcode's Signing & Capabilities tab before
they can build to a physical device or submit to TestFlight/App Store.
This has not blocked development so far because building/testing has been
happening via screen-sharing with Sean's own Xcode instance running
locally on his Mac (see 5.3).

### 5.2 An Xcode crash occurred and was root-caused — context for caution
Mid-session, a batch of file changes (adding a new "Scar Focus Region"
UI stage to `ScarCaptureView.swift`, among other files) caused Xcode
itself to crash immediately whenever Sean clicked on any of the 6 changed
files. Full investigation (see git history and the crash log's actual
backtrace) determined:
- **Root cause**: Xcode's own internal editor-tab "reentrancy guard"
  (`IDEEditorCoordinator`) assertion-failed — an Xcode-side bug/race, NOT
  a bug in the Swift/SwiftUI code itself. It was most likely triggered by
  *stale locally-cached Xcode editor state* (`.xcuserstate`/
  `.xcuserdatad`, which are gitignored and device-local, not part of the
  repo) colliding with one file's large size jump in a single commit.
- **Resolution taken**: the offending commits were reverted immediately
  (to unblock Sean), then reapplied as 4 much smaller, incremental commits
  instead of one large one, specifically so any future recurrence is easy
  to isolate to a single small commit rather than a large diff.
- **Practical guidance for the new team**: if Xcode ever crashes
  immediately upon opening a recently-changed file, first try clearing
  `~/Library/Developer/Xcode/DerivedData/*` and any `*.xcuserstate` /
  `*.xcuserdatad` in the local checkout before assuming the Swift code
  itself is at fault — that combination resolved it here.
- **Where this left off**: of the 4 planned incremental sub-commits for
  item #1 (see 4.2), only 3 are done/pushed. The 4th (the actual UI file,
  `ScarCaptureView.swift`, which was the file that grew the most and is
  the most likely to be implicated if the crash recurs) has **not yet
  been reapplied**. The content for it exists in this session's git
  history at commit `3f6d7f4` (before it was reverted at `9b6a67e`) if the
  new team wants to reference or cherry-pick it, but it should be
  re-verified carefully (small follow-up commit, test in Xcode
  immediately) rather than reapplied wholesale.

### 5.3 No Mac/Xcode toolchain in the AI sandbox — verification is limited
All AI-developer work in this session was done in a Linux sandbox with
**no Swift compiler or Xcode available**. Every code change was verified
only via brace/paren/bracket balance checks and manual code review — never
actually compiled by the AI. Sean has been doing the real
build/run/test/crash-reporting on his own Mac throughout. **The new team
should do a full clean build and run through the app's main flows before
assuming any given commit "works"** — balance-checking catches syntax
mismatches, not logic errors or compiler-level type errors.

### 5.4 Local Xcode project location on Sean's Mac (for reference)
Sean's local clone was found at
`/Users/seanpierce/Documents/Vehicle_Damage_Asst` (a second, stale,
never-updated clone also exists at `/Users/seanpierce/Vehicle_Damage_Asst`
— **not the one to use**, it was abandoned after initial setup on Jul 6
and never pulled again).

---

## 6. Recommended Next Steps for the New Team

1. Get added as collaborators on the GitHub repo (Sean needs to do this).
2. Clone `https://github.com/spierce26-Ems/Vehicle_Damage_Asst.git`,
   checkout `main`, open `ios/VehicleDamageForensics.xcodeproj` in Xcode.
3. Read `ios/README.md` top to bottom — it's the authoritative changelog
   and explains the reasoning behind nearly every non-trivial piece of
   code.
4. Set up code signing with the team's own Apple Developer account.
5. Do a full clean build (`Cmd+Shift+K` then `Cmd+B`) and run through the
   app's main capture → analysis → PDF report flow on a real LiDAR-capable
   device (LiDAR requires a real device; it won't work in Simulator).
6. Get Sean's decision on the Option A vs. B question for item #5 (5.2 in
   this document, item 4.2.5 above) before starting that work.
7. Continue the remaining items from the 5-item plan (4.2 above) at their
   own discretion, following the existing pattern in `ios/README.md` of
   small commits + changelog entries + on-device test checklists.

---

## 7. Contact / Continuity

Sean (nickname used throughout `ios/README.md`'s changelog: "Sean") is the
project owner and the person who should be consulted on product decisions
(the Option A/B question in 4.2 item 5, prioritization of remaining items,
etc.). All prior design rationale is preserved in git commit messages and
`ios/README.md` — there should be no need to guess at "why was it built
this way," as nearly every decision was documented at the time it was made.
