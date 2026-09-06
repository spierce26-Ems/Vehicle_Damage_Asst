# Complete File Manifest — Vehicle_Damage_Asst

Generated from the actual tracked tree at commit `1e8f29e` (2026-09-06). Line counts are exact at that commit.

This file supersedes the earlier manifest, which described a one-off AI-session
workspace of PDFs/JSON/markdown artifacts that are NOT in this repository. If a
file is not listed below, it is not in the repo.

Totals: 72 tracked files, of which 42 Swift sources (17338 lines).

## iOS app — Xcode project

Single target, `com.spearitnow.vehicledamageforensics`, iOS 17.0 min, Swift 5.0 language mode.

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics.xcodeproj/project.pbxproj` | 613 |

## App entry point

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/App/VehicleDamageForensicsApp.swift` | 191 |

## Models — Codable structs, persisted as JSON

Changing any field here is a persistence-format change: keep it additive/optional or write a migration.

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/Models/CapturedPhoto.swift` | 509 |
| `ios/VehicleDamageForensics/Models/Case.swift` | 512 |
| `ios/VehicleDamageForensics/Models/MatchResult.swift` | 709 |
| `ios/VehicleDamageForensics/Models/PaintSampleKit.swift` | 140 |
| `ios/VehicleDamageForensics/Models/Vehicle.swift` | 775 |

## ViewModels — @ObservableObject (MVVM)

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/ViewModels/AnalysisViewModel.swift` | 302 |
| `ios/VehicleDamageForensics/ViewModels/CaptureViewModel.swift` | 1068 |
| `ios/VehicleDamageForensics/ViewModels/CaseListViewModel.swift` | 141 |

## Views — SwiftUI, grouped by feature

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/Views/Capture/CaptureCameraView.swift` | 534 |
| `ios/VehicleDamageForensics/Views/Capture/CaptureFlowView.swift` | 313 |
| `ios/VehicleDamageForensics/Views/Capture/ImpactMarkerView.swift` | 537 |
| `ios/VehicleDamageForensics/Views/Capture/PaintReferenceMarkerView.swift` | 212 |
| `ios/VehicleDamageForensics/Views/Capture/PhotoReviewView.swift` | 329 |
| `ios/VehicleDamageForensics/Views/Capture/ScarCaptureView.swift` | 1052 |
| `ios/VehicleDamageForensics/Views/Capture/SensorGuidanceOverlay.swift` | 189 |
| `ios/VehicleDamageForensics/Views/Dashboard/DashboardView.swift` | 466 |
| `ios/VehicleDamageForensics/Views/Dashboard/EditCaseSheet.swift` | 274 |
| `ios/VehicleDamageForensics/Views/Dashboard/OnboardingView.swift` | 132 |
| `ios/VehicleDamageForensics/Views/LiDAR/LiDARScanView.swift` | 365 |
| `ios/VehicleDamageForensics/Views/Paywall/PaywallView.swift` | 265 |
| `ios/VehicleDamageForensics/Views/Reports/PDFReportView.swift` | 41 |
| `ios/VehicleDamageForensics/Views/Results/MatchResultsView.swift` | 757 |

## Services — camera, ARKit/LiDAR, storage, PDF, StoreKit

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/Services/CameraService.swift` | 1000 |
| `ios/VehicleDamageForensics/Services/HeadingProvider.swift` | 60 |
| `ios/VehicleDamageForensics/Services/LiDARService.swift` | 316 |
| `ios/VehicleDamageForensics/Services/PDFReportGenerator.swift` | 787 |
| `ios/VehicleDamageForensics/Services/PurchaseManager.swift` | 283 |
| `ios/VehicleDamageForensics/Services/ScarCaptureCameraService.swift` | 461 |
| `ios/VehicleDamageForensics/Services/StorageService.swift` | 225 |

## Utilities — pure-function analysis algorithms

Hand-rolled pixel/statistics math; validated against the Python reference in `ios/reference/`.

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/Utilities/CameraLevelMath.swift` | 58 |
| `ios/VehicleDamageForensics/Utilities/ColorAnalysis.swift` | 471 |
| `ios/VehicleDamageForensics/Utilities/MeasurementHelpers.swift` | 166 |
| `ios/VehicleDamageForensics/Utilities/ModelExtensions.swift` | 53 |
| `ios/VehicleDamageForensics/Utilities/ScarFingerprintAnalysis.swift` | 570 |
| `ios/VehicleDamageForensics/Utilities/ScarLineSuggester.swift` | 153 |
| `ios/VehicleDamageForensics/Utilities/ToolMarkAnalysis.swift` | 989 |

## ForensicEngine — scoring/matching orchestration

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/ForensicEngine/AlgorithmVersion.swift` | 271 |
| `ios/VehicleDamageForensics/ForensicEngine/DeformationMatcher.swift` | 215 |
| `ios/VehicleDamageForensics/ForensicEngine/HeightAlignmentAnalyzer.swift` | 100 |
| `ios/VehicleDamageForensics/ForensicEngine/MatchScoreCalculator.swift` | 748 |
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
| `docs/EVIDENCE_APPENDIX_CAPTURE_NOTES.md` | 463 |
| `docs/PROCESS.md` | 409 |
| `HANDOFF_SUMMARY.md` | 315 |
| `README.md` | 21 |
| `ios/README.md` | 1177 |

## Reference material (`ios/reference/`)

Original brief and specs, plus `forensic_analyzer.py` / `enhanced_forensic_analyzer.py`, the Python reference implementation the Swift scoring engine is validated against.

| File | Lines |
|---|---:|
| `ios/reference/ALGORITHM_EXPLAINER.md` | 279 |
| `ios/reference/APP_STORE_CONNECT_SETUP.md` | 118 |
| `ios/reference/COMPLETE_FILE_MANIFEST.md` | 157 |
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
| `scripts/build_pbxproj.py` | 110 |
| `scripts/gen_pbxproj_ids.py` | 18 |
| `scripts/pbxproj_skeleton.txt` | 310 |
| `scripts/preflight.py` | 787 |
| `scripts/check_doc_drift.py` | 291 |
| `scripts/set_dev_team.sh` | 44 |

## Repo root

| File | Lines |
|---|---:|
| `.gitignore` | 46 |

## Regenerating this file

This manifest is generated from `git ls-files`, not hand-maintained. Regenerate it
whenever files are added, removed, or moved — see `docs/PROCESS.md`.

Two things a regenerator needs to know. **This file lists itself**, so its own
row is one edit stale the moment the file is rewritten; the row records the
count before the final write, which is why `preflight.py`'s manifest check
compares paths and the totals line rather than every row. And **binary files
carry `binary` rather than a line count** — a line count for a PNG would be a
number that looks meaningful and is not.

`preflight.py` checks this file two ways: the self-asserted totals line against
`git ls-files`, and every tracked path against the rows. The second is the one
that catches drift which already landed, since the Swift-add reminder only fires
on a staged change and landed drift is the only kind a reader ever meets.
