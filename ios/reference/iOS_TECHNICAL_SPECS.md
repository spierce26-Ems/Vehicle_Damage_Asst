# iOS Technical Specifications
**Version**: 1.0  
**Date**: May 2, 2026  
**Platform**: iOS 15.0+  
**Target Devices**: iPhone 12 Pro or newer (LiDAR required)

## Architecture Overview

```
┌─────────────────────────────────────────┐
│         SwiftUI Interface Layer          │
├─────────────────────────────────────────┤
│  Camera   │  AR       │  Gallery  │ PDF │
│  Capture  │  Height   │  Manager  │ Gen │
├─────────────────────────────────────────┤
│      Core Processing Layer               │
│  • Image Analysis (Vision/CoreML)        │
│  • Height Measurement (ARKit + LiDAR)    │
│  • Forensic Matching Algorithm           │
│  • Paint Color Detection                 │
├─────────────────────────────────────────┤
│         Data & Storage Layer             │
│  • Core Data (Cases/Photos)              │
│  • FileManager (Photo Storage)           │
│  • UserDefaults (Settings)               │
└─────────────────────────────────────────┘
```

## Core Features Implementation

### 1. Guided Photo Capture
**Framework**: AVFoundation + SwiftUI
**Components**:
- `CameraViewController`: Custom camera with overlay guides
- `PhotoGuideOverlay`: Visual guides for 16 required shots
- `PhotoQualityChecker`: Real-time blur/lighting detection

**Key Classes**:
```swift
class CameraViewController: UIViewController {
    var captureSession: AVCaptureSession
    var photoOutput: AVCapturePhotoOutput
    var previewLayer: AVCaptureVideoPreviewLayer
    
    func checkPhotoQuality(_ image: UIImage) -> QualityScore
    func capturePhotoWithMetadata() -> PhotoCapture
}

struct PhotoGuideOverlay: View {
    let currentStep: Int
    let totalSteps: Int = 16
    let guideType: GuideType // height, closeup, angle, etc.
}
```

### 2. AR Height Measurement
**Framework**: ARKit + RealityKit
**Requirements**: iPhone 12 Pro+ (LiDAR Scanner)

**Implementation**:
```swift
class ARHeightMeasurement: ObservableObject {
    var arView: ARView
    var lidarSession: ARSession
    
    func measureHeightFromGround(at point: CGPoint) -> Measurement<UnitLength>
    func placeVirtualTapeMeasure() -> ARMeasurementResult
    func captureARScreenshot() -> UIImage
}

struct MeasurementResult {
    let height: Measurement<UnitLength>
    let confidence: Double // 0.0-1.0
    let pointCloud: [SIMD3<Float>]
    let timestamp: Date
}
```

**Accuracy**: ±1cm (0.4 inches) with LiDAR

### 3. Paint Transfer Detection
**Framework**: Vision + Core ML
**Model**: Custom trained on 10,000+ paint transfer images

**Implementation**:
```swift
class PaintDetector {
    let visionModel: VNCoreMLModel
    
    func detectPaintTransfer(in image: UIImage) -> [PaintTransferRegion]
    func extractDominantColors() -> [UIColor]
    func analyzeColorMatch(victim: UIColor, suspect: UIColor) -> Double
}

struct PaintTransferRegion {
    let boundingBox: CGRect
    let confidence: Double
    let color: UIColor
    let pixelCount: Int
}
```

### 4. Forensic Matching Algorithm
**Language**: Swift (port from Python)
**Components**: 7-factor scoring system

```swift
class ForensicMatcher {
    func analyzeMatch(victim: VehicleData, suspect: VehicleData) -> MatchResult
    
    private func scorePaintTransfer() -> FactorScore
    private func scoreHeightAlignment() -> FactorScore
    private func scoreImpactGeometry() -> FactorScore
    private func scoreDeformationPattern() -> FactorScore
    private func scoreDamageDimensions() -> FactorScore
    private func scoreMaterialTransfer() -> FactorScore
    private func scoreTemporalConsistency() -> FactorScore
}

struct MatchResult {
    let compositeScore: Double // 0-100
    let probability: String // "60-75%"
    let confidence: ConfidenceLevel
    let factors: [FactorScore]
    let recommendations: [String]
}
```

### 5. PDF Report Generation
**Framework**: PDFKit + UIKit
**Output**: 8-page court-ready PDF

```swift
class PDFReportGenerator {
    func generateReport(for matchResult: MatchResult) -> PDFDocument
    
    private func createCoverPage() -> PDFPage
    private func createVehicleSummary() -> PDFPage
    private func createFactorAnalysis() -> PDFPage
    private func createPhotoEvidence() -> PDFPage
    private func createRecommendations() -> PDFPage
    private func createMethodology() -> PDFPage
    private func createDisclaimer() -> PDFPage
}
```

## Data Models

### Core Data Schema
```swift
@Model
class Case {
    var id: UUID
    var caseNumber: String
    var dateCreated: Date
    var victimVehicle: Vehicle
    var suspectVehicle: Vehicle?
    var matchResult: MatchResult?
    var status: CaseStatus
}

@Model
class Vehicle {
    var id: UUID
    var role: VehicleRole // victim or suspect
    var make: String?
    var model: String?
    var year: Int?
    var color: String
    var licensePlate: String?
    var photos: [Photo]
    var damageLocation: DamageLocation
}

@Model
class Photo {
    var id: UUID
    var imageData: Data
    var captureDate: Date
    var photoType: PhotoType
    var metadata: PhotoMetadata
    var qualityScore: Double
}
```

## UI/UX Flow

### Wireframe: Main Flow
```
[Home Screen]
    ↓
[New Case] → [Victim Vehicle Photos (8 shots)]
    ↓
[Suspect Vehicle Photos (8 shots)]
    ↓
[Processing & Analysis (30-60 seconds)]
    ↓
[Match Results Screen]
    ↓
[Generate PDF Report]
```

### Screen Specifications

#### 1. Home Screen
- Recent cases list
- "New Case" button (primary CTA)
- Settings gear icon
- Help/Tutorial access

#### 2. Photo Capture Screen
- Live camera preview (full screen)
- Semi-transparent guide overlay
- Progress indicator (1/16, 2/16, etc.)
- Quality indicator (green/yellow/red)
- Capture button (bottom center)
- Skip button (for optional shots)

#### 3. AR Height Measurement
- AR view with ground plane detection
- Virtual tape measure
- "Tap to measure" instruction
- Height display (real-time)
- Capture button

#### 4. Results Screen
- Match score gauge (0-100)
- Probability badge
- 7-factor breakdown (expandable)
- Photo carousel
- "Generate PDF" button
- "Share" button

## Development Phases

### Phase 1: Foundation (Week 1-2)
- [ ] Project setup (Xcode, SwiftUI)
- [ ] Core Data models
- [ ] Basic camera capture
- [ ] Photo storage system

### Phase 2: Core Features (Week 3-5)
- [ ] AR height measurement
- [ ] Paint detection (Vision)
- [ ] Forensic algorithm (Swift port)
- [ ] Photo quality checks

### Phase 3: Analysis & Reporting (Week 6-7)
- [ ] Match analysis engine
- [ ] PDF generation
- [ ] Results visualization
- [ ] Factor breakdown UI

### Phase 4: Polish & Testing (Week 8)
- [ ] UI refinements
- [ ] Error handling
- [ ] Performance optimization
- [ ] Beta testing

## Technical Requirements

### Minimum iOS Version
- iOS 15.0+ (for SwiftUI improvements)
- Recommend iOS 16.0+ for better AR features

### Device Requirements
**CRITICAL**: LiDAR Scanner required
- iPhone 12 Pro / Pro Max
- iPhone 13 Pro / Pro Max
- iPhone 14 Pro / Pro Max
- iPhone 15 Pro / Pro Max
- iPad Pro (2020 and later)

### Permissions Required
```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required to capture vehicle damage photos.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>Photo library access is needed to save and retrieve damage photos.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Location data helps document where the incident occurred.</string>

<key>ARKit</key>
<string>ARKit is required for accurate height measurements using LiDAR.</string>
```

## Dependencies

### Swift Packages
```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
    .package(url: "https://github.com/onevcat/Kingfisher", from: "7.0.0"), // Image caching
]
```

### Third-Party (Optional)
- **Amplitude**: Analytics
- **Sentry**: Crash reporting
- **RevenueCat**: Subscription management

## Performance Targets

| Metric | Target | Critical |
|--------|--------|----------|
| App Launch | < 2s | < 3s |
| Photo Capture | < 0.5s | < 1s |
| AR Measurement | < 1s | < 2s |
| Analysis Processing | < 60s | < 90s |
| PDF Generation | < 15s | < 30s |
| Memory Usage | < 150MB | < 200MB |

## Testing Strategy

### Unit Tests
- Forensic algorithm accuracy
- Color matching precision
- Height calculation validation
- PDF generation correctness

### Integration Tests
- Camera → Storage flow
- AR → Measurement flow
- Analysis → PDF flow
- Case management CRUD

### Beta Testing Checklist
- [ ] 10 real accident cases
- [ ] 5 different iPhone models
- [ ] iOS 15, 16, 17 versions
- [ ] Various lighting conditions
- [ ] Paint transfer edge cases

## API Documentation (for Backend - Future)

### Endpoints (Phase 2 Cloud Features)
```
POST /api/v1/analysis
- Upload photos
- Returns: match_id

GET /api/v1/analysis/{match_id}
- Returns: MatchResult JSON

POST /api/v1/report/pdf
- Generate PDF server-side
- Returns: PDF download URL
```

## Hiring Requirements

### iOS Developer Profile
**Required Skills**:
- 3+ years iOS development
- Expert in SwiftUI + UIKit
- ARKit experience (CRITICAL)
- Core ML / Vision framework
- PDF generation experience
- Git workflow

**Nice to Have**:
- Computer vision background
- Metal/GPU programming
- App Store submission experience
- TestFlight beta management

### Interview Questions
1. How would you implement real-time height measurement using LiDAR?
2. Explain your approach to optimizing image processing on-device
3. How do you handle low-light camera capture?
4. Describe PDF generation from scratch in iOS
5. What's your strategy for testing AR features?

### Code Challenge
"Build a simple ARKit demo that measures distance between two tapped points using LiDAR and displays result in inches."

## Launch Checklist

### Pre-Launch
- [ ] App Store Developer Account ($99/year)
- [ ] Privacy Policy page
- [ ] Terms of Service
- [ ] App Store screenshots (6.7", 6.5", 5.5")
- [ ] App Store description + keywords
- [ ] App icon (1024x1024)
- [ ] TestFlight beta (10 users)

### App Store Metadata
**Name**: Vehicle Damage Forensic Matcher
**Subtitle**: Hit-and-Run Evidence Analysis
**Category**: Utilities
**Keywords**: vehicle damage, forensic, accident, evidence, insurance, police report
**Description**: See APP_STORE_LISTING.md

## Cost Breakdown (Updated)

| Item | Cost | Timeline |
|------|------|----------|
| iOS Developer Account | $99 | One-time/year |
| Freelance iOS Dev | $3,000-8,000 | 4-6 weeks |
| Beta Testing | $500 | Week 8-12 |
| **Total Phase 2** | **$3,599-8,599** | **12 weeks** |

## Success Metrics (Post-Launch)

| Metric | Week 1 | Month 1 | Month 6 |
|--------|--------|---------|---------|
| Downloads | 100 | 500 | 5,000 |
| Active Users | 50 | 300 | 3,000 |
| PDF Reports Generated | 25 | 150 | 2,000 |
| Revenue | $500 | $3,000 | $30,000 |
| App Store Rating | 4.0+ | 4.2+ | 4.5+ |

## Next Steps

1. **This Weekend**: Review these specs, gather feedback
2. **Monday**: Post job listing on Upwork/Toptal
3. **Week 1**: Interview 3-5 iOS developers
4. **Week 2**: Hire developer, kick off Phase 1
5. **Week 8**: Begin beta testing
6. **Week 12**: App Store submission

---
**Document Status**: ✅ COMPLETE  
**Ready for**: Developer handoff, hiring process, budget approval
