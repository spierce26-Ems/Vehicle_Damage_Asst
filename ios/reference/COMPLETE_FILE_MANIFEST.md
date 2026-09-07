# Complete File Manifest — Vehicle_Damage_Asst

Generated from the tracked tree as of the commit that last modified this file (2026-09-06); regenerated in the same patch as the change that moved the counts, per `docs/PROCESS.md` §3. Line counts are exact for that tree, with the one exception this file's own row documents below.

No commit hash is named here on purpose. A regenerated file cannot state the hash of the commit that carries it — the hash does not exist until the commit is written, and a rebase or amend invalidates whatever was written. A named-but-wrong hash is worse than none: it reads as provenance and resolves to nothing.

This file supersedes the earlier manifest, which described a one-off AI-session
workspace of PDFs/JSON/markdown artifacts that are NOT in this repository. If a
file is not listed below, it is not in the repo.

Totals: 86 tracked files, of which 42 Swift sources (21973 lines). The `scripts/shapechecks/` instruments are deliberately NOT `.swift`: the Swift count is a signal quoted in review, and a reduced model that says nothing about the app must not move it. Stated without a file count on purpose -- the set grows, and a number here would go stale in the direction that reads as an oversight.

## iOS app — Xcode project

Single target, `com.spearitnow.vehicledamageforensics`, iOS 17.0 min, Swift 5.0 language mode.

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics.xcodeproj/project.pbxproj` | 615 |

## App entry point

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/App/VehicleDamageForensicsApp.swift` | 191 |

## Models — Codable structs, persisted as JSON

Changing any field here is a persistence-format change: keep it additive/optional or write a migration.

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/Models/CapturedPhoto.swift` | 853 |
| `ios/VehicleDamageForensics/Models/Case.swift` | 851 |
| `ios/VehicleDamageForensics/Models/MatchResult.swift` | 709 |
| `ios/VehicleDamageForensics/Models/PaintSampleKit.swift` | 140 |
| `ios/VehicleDamageForensics/Models/Vehicle.swift` | 952 |

## ViewModels — @ObservableObject (MVVM)

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/ViewModels/AnalysisViewModel.swift` | 426 |
| `ios/VehicleDamageForensics/ViewModels/CaptureViewModel.swift` | 1266 |
| `ios/VehicleDamageForensics/ViewModels/CaseListViewModel.swift` | 218 |

## Views — SwiftUI, grouped by feature

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/Views/Capture/CaptureCameraView.swift` | 779 |
| `ios/VehicleDamageForensics/Views/Capture/CaptureFlowView.swift` | 423 |
| `ios/VehicleDamageForensics/Views/Capture/ImpactMarkerView.swift` | 537 |
| `ios/VehicleDamageForensics/Views/Capture/PaintReferenceMarkerView.swift` | 212 |
| `ios/VehicleDamageForensics/Views/Capture/PhotoReviewView.swift` | 359 |
| `ios/VehicleDamageForensics/Views/Capture/ScarCaptureView.swift` | 1654 |
| `ios/VehicleDamageForensics/Views/Capture/SensorGuidanceOverlay.swift` | 189 |
| `ios/VehicleDamageForensics/Views/Dashboard/DashboardView.swift` | 596 |
| `ios/VehicleDamageForensics/Views/Dashboard/EditCaseSheet.swift` | 319 |
| `ios/VehicleDamageForensics/Views/Dashboard/OnboardingView.swift` | 132 |
| `ios/VehicleDamageForensics/Views/LiDAR/LiDARScanView.swift` | 809 |
| `ios/VehicleDamageForensics/Views/Paywall/PaywallView.swift` | 265 |
| `ios/VehicleDamageForensics/Views/Reports/PDFReportView.swift` | 41 |
| `ios/VehicleDamageForensics/Views/Results/MatchResultsView.swift` | 1230 |

## Services — camera, ARKit/LiDAR, storage, PDF, StoreKit

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/Services/CameraService.swift` | 1037 |
| `ios/VehicleDamageForensics/Services/HeadingProvider.swift` | 60 |
| `ios/VehicleDamageForensics/Services/LiDARService.swift` | 316 |
| `ios/VehicleDamageForensics/Services/PDFReportGenerator.swift` | 1498 |
| `ios/VehicleDamageForensics/Services/PurchaseManager.swift` | 283 |
| `ios/VehicleDamageForensics/Services/ScarCaptureCameraService.swift` | 736 |
| `ios/VehicleDamageForensics/Services/StorageService.swift` | 225 |

## Utilities — pure-function analysis algorithms

Hand-rolled pixel/statistics math; validated against the Python reference in `ios/reference/`.

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/Utilities/CameraLevelMath.swift` | 58 |
| `ios/VehicleDamageForensics/Utilities/ColorAnalysis.swift` | 471 |
| `ios/VehicleDamageForensics/Utilities/MeasurementHelpers.swift` | 166 |
| `ios/VehicleDamageForensics/Utilities/ModelExtensions.swift` | 53 |
| `ios/VehicleDamageForensics/Utilities/ScarFingerprintAnalysis.swift` | 584 |
| `ios/VehicleDamageForensics/Utilities/ScarLineSuggester.swift` | 153 |
| `ios/VehicleDamageForensics/Utilities/ToolMarkAnalysis.swift` | 1590 |

## ForensicEngine — scoring/matching orchestration

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/ForensicEngine/AlgorithmVersion.swift` | 282 |
| `ios/VehicleDamageForensics/ForensicEngine/DeformationMatcher.swift` | 215 |
| `ios/VehicleDamageForensics/ForensicEngine/HeightAlignmentAnalyzer.swift` | 100 |
| `ios/VehicleDamageForensics/ForensicEngine/MatchScoreCalculator.swift` | 847 |
| `ios/VehicleDamageForensics/ForensicEngine/PaintTransferAnalyzer.swift` | 148 |

## iOS app — other target files

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/Info.plist` | 70 |
| `ios/VehicleDamageForensics/Resources/PrivacyInfo.xcprivacy` | 31 |
| `ios/VehicleDamageForensics/Resources/Assets.xcassets/Contents.json` | 6 |
| `ios/VehicleDamageForensics/Resources/Assets.xcassets/AccentColor.colorset/Contents.json` | 11 |
| `ios/VehicleDamageForensics/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` | 14 |
| `ios/VehicleDamageForensics/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | binary |

## Documentation

`ios/README.md` is the authoritative changelog. `HANDOFF_SUMMARY.md` is the team-facing state-of-the-project doc.

| File | Lines |
|---|---:|
| `docs/EVIDENCE_APPENDIX_CAPTURE_NOTES.md` | 1673 |
| `docs/ITEM2_NORULER_FOCUSGATE_UX_SPEC.md` | 753 |
| `docs/PROCESS.md` | 4680 |
| `HANDOFF_SUMMARY.md` | 320 |
| `README.md` | 21 |
| `ios/README.md` | 1913 |

## Reference material (`ios/reference/`)

Original brief and specs, plus `forensic_analyzer.py` / `enhanced_forensic_analyzer.py`, the Python reference implementation the Swift scoring engine is validated against.

| File | Lines |
|---|---:|
| `ios/reference/ALGORITHM_EXPLAINER.md` | 331 |
| `ios/reference/APP_STORE_CONNECT_SETUP.md` | 118 |
| `ios/reference/COMPLETE_FILE_MANIFEST.md` | 200 |
| `ios/reference/HANDOFF_TO_AI_DEVELOPER.md` | 245 |
| `ios/reference/PAINT_ANALYSIS_KIT_FUTURE_FEATURE.md` | 146 |
| `ios/reference/PROJECT_BRIEF.md` | 31 |
| `ios/reference/enhanced_forensic_analyzer.py` | 689 |
| `ios/reference/forensic_analyzer.py` | 571 |
| `ios/reference/iOS_TECHNICAL_SPECS.md` | 427 |

## Legal / web pages

| File | Lines |
|---|---:|
| `docs/privacy-policy.html` | 143 |
| `docs/terms-of-use.html` | 101 |

## Build scripts

`build_pbxproj.py` / `gen_pbxproj_ids.py` generate `project.pbxproj` from `pbxproj_skeleton.txt`. Any NEW Swift file must be registered in the pbxproj or it silently does not compile into the target.

| File | Lines |
|---|---:|
| `scripts/build_pbxproj.py` | 143 |
| `scripts/gen_pbxproj_ids.py` | 18 |
| `scripts/pbxproj_skeleton.txt` | 312 |
| `scripts/preflight.py` | 4254 |
| `scripts/check_doc_drift.py` | 555 |
| `scripts/regen_manifest.py` | 144 |
| `scripts/check_remedies.py` | 311 |
| `scripts/set_dev_team.sh` | 44 |
| `scripts/shapechecks/README.md` | 144 |
| `scripts/shapechecks/decline-affordance.shapecheck` | 111 |
| `scripts/shapechecks/decoder-roundtrip.shapecheck` | 128 |
| `scripts/shapechecks/filtered-headline.shapecheck` | 176 |
| `scripts/shapechecks/filtered-headline-v1.shapecheck` | 144 |
| `scripts/shapechecks/item2-attestation.shapecheck` | 109 |
| `scripts/shapechecks/motionblur-window.shapecheck` | 112 |
| `scripts/shapechecks/motionmeasurable.shapecheck` | 124 |
| `scripts/shapechecks/rowfive-proxy.shapecheck` | 91 |
| `scripts/shapechecks/allclear-variant-selector.shapecheck` | 139 |
| `scripts/shapechecks/run.sh` | 200 |

## Repo root

| File | Lines |
|---|---:|
| `.gitignore` | 54 |

## Regenerating this file

This manifest is generated from `git ls-files`, not hand-maintained. Regenerate it
whenever files are added, removed, or moved — see `docs/PROCESS.md`.

Two things a regenerator needs to know. **This file lists itself**, so its own
row must be written with the count the file will have *after* the final write,
not the count it has while being written. A regenerator that records the
in-progress count leaves exactly one row wrong, and `manifest-lines` now says
so by name. And **binary files carry `binary` rather than a line count** — a
line count for a PNG would be a number that looks meaningful and is not.

`preflight.py` checks this file three ways: the self-asserted totals line
against `git ls-files`, every tracked path against the rows, and every row's
line count against the file it names. The path check is the one that catches
drift which already landed, since the Swift-add reminder only fires on a staged
change and landed drift is the only kind a reader ever meets. The line-count
check exists because the first two passed clean over a header claiming 17,338
Swift lines against a tree of 19,837 — a generated document is only as
trustworthy as the widest assertion anyone validates.
