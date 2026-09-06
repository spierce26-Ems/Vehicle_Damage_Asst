# Complete File Manifest — Vehicle_Damage_Asst

Generated from the actual tracked tree at commit `0f657db` (2026-09-06). Line counts are exact at that commit.

This file supersedes the earlier manifest, which described a one-off AI-session
workspace of PDFs/JSON/markdown artifacts that are NOT in this repository. If a
file is not listed below, it is not in the repo.

Totals: 68 tracked files, of which 41 Swift sources (15981 lines).

## iOS app — Xcode project

Single target, `com.spearitnow.vehicledamageforensics`, iOS 17.0 min, Swift 5.0 language mode.

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics.xcodeproj/project.pbxproj` | 607 |

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
| `ios/VehicleDamageForensics/Models/MatchResult.swift` | 675 |
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
| `ios/VehicleDamageForensics/Views/Results/MatchResultsView.swift` | 667 |

## Services — camera, ARKit/LiDAR, storage, PDF, StoreKit

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/Services/CameraService.swift` | 1000 |
| `ios/VehicleDamageForensics/Services/HeadingProvider.swift` | 60 |
| `ios/VehicleDamageForensics/Services/LiDARService.swift` | 316 |
| `ios/VehicleDamageForensics/Services/PDFReportGenerator.swift` | 698 |
| `ios/VehicleDamageForensics/Services/PurchaseManager.swift` | 283 |
| `ios/VehicleDamageForensics/Services/ScarCaptureCameraService.swift` | 461 |
| `ios/VehicleDamageForensics/Services/StorageService.swift` | 225 |

## Utilities — pure-function analysis algorithms

Hand-rolled pixel/statistics math; validated against the Python reference in `ios/reference/`.

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/Utilities/CameraLevelMath.swift` | 58 |
| `ios/VehicleDamageForensics/Utilities/ColorAnalysis.swift` | 471 |
| `ios/VehicleDamageForensics/Utilities/MeasurementHelpers.swift` | 102 |
| `ios/VehicleDamageForensics/Utilities/ModelExtensions.swift` | 53 |
| `ios/VehicleDamageForensics/Utilities/ScarFingerprintAnalysis.swift` | 385 |
| `ios/VehicleDamageForensics/Utilities/ScarLineSuggester.swift` | 153 |
| `ios/VehicleDamageForensics/Utilities/ToolMarkAnalysis.swift` | 897 |

## ForensicEngine — scoring/matching orchestration

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/ForensicEngine/DeformationMatcher.swift` | 215 |
| `ios/VehicleDamageForensics/ForensicEngine/HeightAlignmentAnalyzer.swift` | 100 |
| `ios/VehicleDamageForensics/ForensicEngine/MatchScoreCalculator.swift` | 667 |
| `ios/VehicleDamageForensics/ForensicEngine/PaintTransferAnalyzer.swift` | 148 |

## iOS app — other target files

| File | Lines |
|---|---:|
| `ios/VehicleDamageForensics/Info.plist` | 70 |

## Documentation

`ios/README.md` is the authoritative changelog. `HANDOFF_SUMMARY.md` is the team-facing state-of-the-project doc.

| File | Lines |
|---|---:|
| `HANDOFF_SUMMARY.md` | 320 |
| `README.md` | 21 |
| `ios/README.md` | 828 |

## Reference material (`ios/reference/`)

Original brief and specs, plus `forensic_analyzer.py` / `enhanced_forensic_analyzer.py`, the Python reference implementation the Swift scoring engine is validated against.

| File | Lines |
|---|---:|
| `ios/reference/ALGORITHM_EXPLAINER.md` | 331 |
| `ios/reference/APP_STORE_CONNECT_SETUP.md` | 118 |
| `ios/reference/COMPLETE_FILE_MANIFEST.md` | 295 |
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

## Repo root

| File | Lines |
|---|---:|
| `.gitignore` | 46 |

## Regenerating this file

This manifest is generated from `git ls-files`, not hand-maintained. Regenerate it
whenever files are added, removed, or moved — see `docs/PROCESS.md`.
