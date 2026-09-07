# Item 2 — No-ruler guidance + close-focus quality gate
UX spec for implementation. CV thresholds flagged for Prism.
Scope: capture flow only. No scoring-math changes.

> **Landed in the repository 2026-09-07, and the reason is part of the record.**
> This document existed only outside the tree while
> `docs/EVIDENCE_APPENDIX_CAPTURE_NOTES.md` cited it **six times as its
> authority** and `ios/README.md` recorded a ticked decision resting on it. Its
> §1.1 tri-state table was the only in-tree statement of that semantics, and it
> presented itself as a restatement of a document nobody could read. Three
> artefacts agreed with each other and none of them was checkable.
>
> **The intended ordering was spec-then-wiring, and it did not hold.** The
> implementation landed first (`408a247`), in arrival order, so this document
> reaches the tree *after* the code it describes. Ledger and Vector called the
> ordering and the Tech Lead recorded the inversion rather than papering over
> it, which is what makes it correctable.
>
> **The open question was "land this, or accept the appendix as the authority
> and say so." Landing it is the answer, and the reason is which artefact can
> be checked.** The appendix is locked *copy* — it is the authority on wording
> and it says so. It is not an authority on the tri-state semantics, the
> per-shot rule, or the gate composition: its §1.1 table restates those and
> presents itself as a restatement. Promoting a restatement to the source
> leaves the original claims uncheckable and makes the appendix answer for
> decisions it never made. So the split stands as it was designed —
> **wording is the appendix's, behaviour is this document's** — and the
> citation now resolves.
>
> The consequence is concrete and this spec has to answer for it: a spec that
> arrives after its implementation is **reconciled against shipped code, not
> guiding it**, and for the interval between the two commits the
> implementation was its own authority. So §8 below is not a summary of intent
> — it is a section-by-section reconciliation written by reading the landed
> tree, and every divergence in it was found that way rather than remembered.
>
> **This spec is not a claim about the tree.** Every section describes intended
> behaviour. Where a section is unbuilt the implementation commit says so, and
> §8 below records what was built and what deliberately diverged.

---

## 0. The design insight that drives everything

The ruler is **not** contraband. `CaptureProtocolStep.fullProtocol` id 4 is literally
"Height reference: ruler or tape measure at damage center" — and that shot is
legitimate, wanted evidence. The bug is that a ruler ends up in the shots that
**feed pixel analysis**, where `ColorAnalysis` / `ToolMarkAnalysis` /
`ScarFingerprintAnalysis` read its printed ticks and painted edge as scar
striations and paint transfer.

So the rule is **per-shot, not global**. Never tell the user "no rulers" as a blanket
instruction — they'll drop the height reference and we lose scale entirely.

Two shot classes, made explicit in the UI:

| Class | Shots | Ruler | Framing goal |
|---|---|---|---|
| **Reference** | `.heightMeasurement`, `.contextShot`, `.wideAngle`, `.licenseDetail`, `.lidarReference` | **Required / fine** | scale + context in frame |
| **Analysis** | `.closeupDamage`, `.paintTransfer`, scar photo (`ScarCaptureView`) | **Must be out of frame** | damaged paint edge-to-edge, nothing else |

Add a computed property so this is one source of truth, not scattered `if`s:

```
// Models/Vehicle.swift, alongside PhotoType.isRequired
extension PhotoType {
    /// True when this shot's pixels are read by the analysis engine, so
    /// anything non-vehicle in frame (ruler ticks, trim, another panel)
    /// becomes false signal. See Item 2 UX spec.
    var isAnalysisShot: Bool {
        switch self {
        case .closeupDamage, .paintTransfer: return true
        case .heightMeasurement, .wideAngle, .contextShot,
             .licenseDetail, .lidarReference: return false
        }
    }
}
```
Exhaustive `switch`, not `==` — a future `PhotoType` case must fail to compile
here rather than silently defaulting to "safe to have a ruler in it."

**The scar photo (correction, per Tech Lead's condition 1).** The prose and the
table above both say the scar photo is an analysis shot, and it is. It is also
already covered by that property — but only by accident, and that accident is
worth naming: `ScarCaptureView.performCapture` constructs its `CapturedPhoto`
with `photoType: .paintTransfer`. So `isAnalysisShot` returns `true` for it today
with no extra case needed.

Do **not** rely on that. It's an incidental type reuse, not a statement of
intent, and the day someone gives the scar shot its own `PhotoType` case (or
routes it through `.closeupDamage`) the guidance silently changes behavior. Two
requirements:

1. Add a `NOTE(AI Developer)` at the `photoType: .paintTransfer` line in
   `performCapture` recording that Item 2's analysis-shot guidance depends on
   this value, so it is not "cleaned up" without updating `isAnalysisShot`.
2. In `ScarCaptureView`, drive the guidance band from a local constant `true`
   rather than reading `photo.photoType.isAnalysisShot` — this screen is
   unconditionally an analysis surface regardless of what type its output
   carries. The property is for the multi-shot camera, where the type genuinely
   varies shot to shot.

---

## 1. No-ruler guidance — three layers, escalating

### 1.1 One-time explainer card (first analysis shot of the first case)
Full-screen sheet before the camera opens, dismissible, `@AppStorage` flag
`hasSeenAnalysisShotExplainer`. Two side-by-side illustrations, same scar:

- Left, green check: scrape filling the frame, nothing else.
- Right, red X: same scrape with a tape measure laid alongside it.

Copy, verbatim:

> **Two kinds of photos**
>
> **Measurement photos** — keep your tape measure in frame. That's how the report
> shows how big the damage is and how high off the ground it sits.
>
> **Analysis photos** — move the tape measure out of frame. The app reads the paint
> and the scratch marks in these photos pixel by pixel. A ruler's printed lines
> look like scratch marks to it, and its color looks like transferred paint.
>
> We'll tell you which kind each shot is.
>
> [ Got it ]

Reachable again from the case's help/info button. Never auto-shown twice.

### 1.2 Persistent per-shot band (every analysis shot, live camera)
`CaptureCameraView` — replaces nothing; sits directly under the existing
instruction text. Two variants only.

Analysis shot:
> 🔬 **Analysis shot** — damaged paint only. Move the tape measure out of frame.

Reference shot:
> 📏 **Measurement shot** — keep the tape measure in frame.

Styling: same `.black.opacity(0.45)` rounded capsule as `topInstruction`,
`.caption` weight semibold, full width, one line, `.minimumScaleFactor(0.8)`.
It's the same two strings all day — that's the point, it becomes furniture the
user stops reading and starts obeying.

`ScarCaptureView.topInstruction` gets the analysis variant appended as its own
third line (the scar shot is the single worst offender for this bug):

> Fill the box with the scar/scrape
> Hold steady — it captures automatically when ready.
> 🔬 Damaged paint only — tape measure out of frame.

### 1.3 Arm-time confirmation (analysis shots only, once per shot)
The Ready button already exists (`isArmed`). For analysis shots only, first tap
of Ready in a given capture session swaps the button label for one beat:

> **Tape measure out of frame?**  [ Yes — capture ]

Second tap arms as normal. Subsequent shots in the same session skip this — one
confirmation per camera session, not per shot, or it becomes a mash-through.
Record the answer in `CapturedPhoto.frameConfirmedClear` — see §3 for why that
field is a tri-state optional and not a `Bool`.

Rationale for confirmation over detection: a real ruler detector is CV work
(long straight high-contrast edge + regular perpendicular tick periodicity) and
belongs to Prism, not to this item. A confirmed-by-examiner boolean is cheap,
shippable now, and is the thing that actually holds up in a report — "the
examiner attested the frame was clear" beats "an algorithm guessed."

### 1.4 Review-stage flag
`PhotoReviewView` — an analysis-shot thumbnail gets an amber corner badge,
`exclamationmark.triangle.fill`, only when `frameConfirmedClear == false`
(explicitly declined). `nil` — a photo taken before this feature existed, or
imported from the library — gets **no badge**, because we have no evidence
either way and a warning triangle on every historical photo trains users to
ignore the badge. Legend row:
> ⚠️ Analysis photo — examiner did not confirm the frame was clear

Tapping the enlarged view shows:
> This photo is read pixel by pixel. If a tape measure or ruler is visible in it,
> replace it — the marks on it can be read as scratches on the vehicle.
> [ Replace from library ]  [ Keep anyway ]

Not blocking. This is the last cheap catch before analysis.

---

## 2. Close-focus quality gate

The existing gates are Steady / Focused / Even Lighting, and `isFocused` is
`!isAdjustingFocus && !isAdjustingExposure` — that only says the lens finished
hunting, **not** that the result is sharp, and not that the phone is close
enough for the striations to be resolvable at all. Two additions.

### 2.1 Fill gate — "close enough"
The scar must occupy the guide box, not sit in the middle of it. Signal:
edge-energy density inside `ScarCaptureCameraService.guideRect` vs. the frame
margin outside it. If the interesting content isn't concentrated inside the box,
the user is too far away.

Cheaper alternative if Prism prefers it: `AVCaptureDevice.lensPosition` +
`idealDistanceMeters` from the step (0.3 m for paint transfer, 0.5–0.6 m for
closeups) against the AF depth hint already feeding
`SensorData.distanceEstimateMeters`. Either is fine for UX; I need one number
0–1 and a boolean.

New published state, matching the existing pattern exactly:
```
@Published private(set) var isCloseEnough: Bool = false
@Published private(set) var framingMessage: String = "Checking framing…"
```
Messages (one line, mutually exclusive, same voice as `lightingMessage`):
- `"Move closer — fill the box with the scar"`
- `"Too close — the lens can't focus this near"`  (lensPosition pinned at minimum)
- `"Framing looks good"`

### 2.2 Sharpness gate — "actually in focus"
Replace the meaning of `isFocused` rather than adding a fourth chip. Mean
absolute Laplacian response over `guideRect` (see §3's correction — the spec
originally said variance; the shipped measure is the mean absolute response), on the same throttled
`analyzeEveryNthFrame` path that already does the 2×2 luma quadrants — reuse that
loop, don't add a second one.

```
isFocused = !dev.isAdjustingFocus && !dev.isAdjustingExposure && sharpness >= sharpnessThreshold
```
Threshold is Prism's to calibrate on real device frames. Chip label changes from
"Focused" to **"Sharp"** — "Focused" reads as "the lens is done", "Sharp" reads
as a quality claim, which is what it now is.

Sharpness message when failing:
- `"Not sharp yet — hold steadier or back off slightly"`

### 2.3 Gate wiring
`allGatesGood` becomes:
```
isSteady && isFocused && isWellLit && isCloseEnough
```
This means **auto-capture will not fire** until the shot is close enough and
genuinely sharp. That is the root fix Item 2 is for: the tape-measure bug was
partly a framing bug — a too-far shot has room in frame for a ruler and not
enough resolution for real striations.

Chip layout, four gates, keeping the existing two-row fix that solved the
clipping report:
- Row 1: `Steady` · `Sharp` · `Close enough` (all short, fixed width)
- Row 2: lighting message (full width, `minimumScaleFactor`)
- Row 3: framing message, **only when `!isCloseEnough`** (full width) — appears
  only while it's the blocker, so the column doesn't grow permanently taller.
  The bottom-content-overflow regression is a known past bug on this screen; do
  not add a permanently-visible fourth row.

### 2.4 Manual shutter override
The manual shutter stays enabled regardless of gates — a scene is a scene and
sometimes the light is what it is. But when tapped with gates failing:

> **Capture anyway?**
> This shot isn't sharp/close enough for reliable scratch analysis. It'll be saved
> and flagged in the report.
> [ Capture anyway ]  [ Cancel ]

Set `QualityFlags.isBlurry` / `.isTooFar` at capture time — those flags already
exist and already surface in `PhotoReviewView` and `issueDescriptions`; they're
currently never set on this path. Wire them.

**Corrected 2026-09-07, and the correction is the load-bearing part: from the
MEASURED terms, not from the gate booleans.** This clause originally said "from
the live gate state", the first implementation followed it literally, and that
is wrong for a reason the gates cannot express. `isFocused` and `isCloseEnough`
default `false` and stay `false` until a frame has been analysed — correct for
a gate, because auto-capture must not fire on an unmeasured frame — and
`isFocused` is additionally the *conjunction* of the device's focus state with
the sharpness measurement, so it reads `false` on a hunting lens over a frame
that measured perfectly sharp. Meanwhile these two flags are persisted into
evidence and §1's appendix renders them as **"The app measured this photograph
as not sharp"** and **"The app measured the damage area as not filling the
guide frame"**.

The contradiction is inside one bullet list: the fifth note condition,
*"Sharpness was not measured for this photograph"*, is guarded on
`sharpnessScore == nil` — true on exactly the photo the gate-derived flags
just described as measured-and-failing. Wire them from
`ScarCaptureCameraService.measuredNotSharp` (`sharpnessScore != nil &&
!sharpnessSatisfied`) and `.measuredNotCloseEnough` (`framingMeasured &&
!isCloseEnough`) instead.

**General form, for any future clause of this shape: a gate may say "not yet";
a recorded finding may only say what was measured.** §3's tri-state is the same
rule where the type can express it; `Bool` cannot hold "unmeasured", so it has
to be held at the source.

---

## 3. New model fields

```
// CapturedPhoto
/// Examiner's attestation that no ruler/tape measure/foreign object was in
/// frame for this analysis shot. TRI-STATE, deliberately optional:
///   true  = examiner explicitly confirmed the frame was clear
///   false = examiner was asked and declined to confirm
///   nil   = never asked — pre-Item-2 photo, or a library import
/// `nil` is NOT "unconfirmed" and must never be rendered as a warning; we
/// have no evidence either way for those photos. See Item 2 UX spec §1.4.
var frameConfirmedClear: Bool?

/// True when captured with one or more capture gates failing, via the
/// manual-shutter override. `false` for pre-Item-2 photos is honest —
/// there were no gates to override.
var gateOverridden: Bool = false

/// Sharpness proxy measured over `guideRect` at capture time. `nil` when
/// unmeasured (pre-Item-2 photo, or a library import with no live frame).
///
/// CORRECTED 2026-09-07 at implementation: this section originally said
/// "variance of Laplacian". The shipped measurement is the MEAN ABSOLUTE
/// Laplacian response, which is the same monotone sharpness proxy and is
/// what `CIAreaAverage` can produce in one pass on the existing throttled
/// frame path. The distinction is recorded rather than quietly kept
/// because this value is persisted into evidence, and a doc comment must
/// not describe a statistic the code does not compute.
var sharpnessScore: Double?
```

Back-compat, same `decodeIfPresent` pattern as `scarFocusRegion`:

```
frameConfirmedClear = try c.decodeIfPresent(Bool.self, forKey: .frameConfirmedClear)
gateOverridden      = try c.decodeIfPresent(Bool.self, forKey: .gateOverridden) ?? false
sharpnessScore      = try c.decodeIfPresent(Double.self, forKey: .sharpnessScore)
```

**Why the tri-state (Tech Lead's condition 2, accepted).** A plain
`Bool = false` would have every photo in every existing case decode as
"examiner declined to confirm the frame was clear" — a false negative
attestation written into evidence about work the examiner was never asked to
do. For a tool whose output goes in an investigation file that is worse than a
missing field. `gateOverridden` stays a plain `Bool` because `false` is
truthful for old photos; `frameConfirmedClear` cannot make that claim.

Library imports stay `nil` too: the user is picking a photo of unknown
provenance, and there is no honest moment to ask "was the frame clear" about a
shot they may not have taken.

Report treatment (Ledger's to word finally): analysis photos with
`gateOverridden == true` or `frameConfirmedClear == false` get a per-photo note
in the evidence appendix. Photos with `frameConfirmedClear == nil` get **no
note** — absence of an attestation is not an adverse finding. Do not silently
drop any of them; a flagged photo in the file is better than a missing one.

---

## 4. Copy inventory (all new strings, for review in one place)

| Key | String |
|---|---|
| explainer.title | Two kinds of photos |
| explainer.measurement | Measurement photos — keep your tape measure in frame. That's how the report shows how big the damage is and how high off the ground it sits. |
| explainer.analysis | Analysis photos — move the tape measure out of frame. The app reads the paint and the scratch marks in these photos pixel by pixel. A ruler's printed lines look like scratch marks to it, and its color looks like transferred paint. |
| band.analysis | Analysis shot — damaged paint only. Move the tape measure out of frame. |
| band.reference | Measurement shot — keep the tape measure in frame. |
| confirm.arm | Tape measure out of frame? |
| chip.sharp | Sharp |
| chip.close | Close enough |
| framing.tooFar | Move closer — fill the box with the scar |
| framing.tooClose | Too close — the lens can't focus this near |
| framing.good | Framing looks good |
| sharp.fail | Not sharp yet — hold steadier or back off slightly |
| override.title | Capture anyway? |
| override.body | This shot isn't sharp/close enough for reliable scratch analysis. It'll be saved and flagged in the report. |
| review.flag | Analysis photo — examiner did not confirm the frame was clear |

No probabilistic or verdict language anywhere — consistent with the v1 framing
that this is an investigative documentation tool, not forensic identification.

---

## 5. Commit split (small, isolated — per the Xcode-crash lesson)

1. `PhotoType.isAnalysisShot` + the three `CapturedPhoto` fields + decode
   defaults + the `NOTE` on `performCapture`'s `photoType: .paintTransfer`.
2. `isCloseEnough` / `framingMessage` / sharpness in `ScarCaptureCameraService`,
   `allGatesGood` updated. No UI.
3. Chip row + framing row + band in `ScarCaptureView`. **Open in Xcode
   immediately** — this is the file that grew and got blamed for the crash at
   `3f6d7f4`. **HARD PREREQUISITE: task #5 must be landed and Xcode-verified
   first** (Tech Lead's ordering, not negotiable here). Task #5 reapplies the
   reverted focus-region UI to this same file; two large diffs racing on the
   file that crashed Xcode is how the crash repeats. If #5 is not done, stop
   after commit 2 and wait.
4. Same band + arm confirmation in `CaptureCameraView`; wire `QualityFlags`.
5. One-time explainer card. **Adds a NEW Swift file** — it must be registered
   in `project.pbxproj` via `scripts/build_pbxproj.py`, never a hand-edit. An
   unregistered file silently does not compile into the target and has already
   caused two mystery build failures on this project.
6. `PhotoReviewView` flag + legend row.

Blocked on P0-2 (green clean build) for anything past commit 1 being
verifiable, and commit 3 additionally blocked on task #5.

---

## 6. Gate behaviour — DECIDED

**Sean confirmed: hard-block, with the manual shutter as the documented
override.** No longer an open question; this is the specified behaviour and
there is nothing to hedge.

What "documented" binds, since the word is doing work here:

- `allGatesGood` gates auto-capture only. The manual shutter stays enabled at
  all times — §2.4 is not a courtesy, it is the half of the decision that makes
  hard-block safe to ship. A gate with no escape hatch loses evidence at a
  roadside in bad light.
- Taking the override is recorded (`gateOverridden`), surfaced in review, and
  described in the report appendix as a reasonable choice rather than examiner
  error. An affordance that gets you noted as deficient for using it is an
  affordance people stop using — and they would lose the shot to avoid the note.
- The warn-only variant is not built. Should it ever be revisited it is one line
  in `allGatesGood` plus keeping the framing chip visible.

---

## 7. Revision log

**v2 (2026-09-06)** — accepted all four conditions from the Tech Lead's spec
review:
1. `isAnalysisShot` rewritten as an exhaustive `switch`; scar-photo coverage
   documented (it already resolves `true` because `performCapture` uses
   `photoType: .paintTransfer`, but that is incidental and now carries a `NOTE`
   plus a local-constant override in `ScarCaptureView`) — §0.
2. `frameConfirmedClear` changed from `Bool = false` to a tri-state `Bool?`, so
   pre-existing and imported photos decode as "never asked" rather than
   "examiner declined" — §3, with matching no-badge / no-report-note rules in
   §1.4.
3. Commit 3 marked hard-blocked on task #5 landing first — §5.
4. Warn-only variant explicitly not built pending Sean — §6.

**v3 (2026-09-06)** — §6 closed: Sean confirmed hard-block plus documented manual-shutter override. No open questions remain in this spec; it is implementation-ready pending task #5 and a green build.

Also folded in: the `project.pbxproj` registration trap for the new explainer
file in commit 5 (§5), from Ledger's P0-4 review.

Calibration ownership: the Laplacian sharpness threshold and the fill signal go
to Prism inside the task #3 device run — both can only be set honestly against
real frames. Evidence-appendix wording for overridden/unconfirmed photos and
the no-verdict copy discipline are Ledger's.

---

## 8. Implementation record (2026-09-07)

Written by the spec's author, against the tree rather than against this
document — the whole reason this section exists is that a spec agreeing with
another spec is not evidence.

### Built

| Section | Where |
|---|---|
| §0 `isAnalysisShot`, exhaustive, no `default` | `Vehicle.swift` |
| §0 property consumed by the report filter | `PDFReportGenerator.drawCaptureConditions` |
| §0 load-bearing `photoType: .paintTransfer` NOTE | `ScarCaptureView.performCapture` |
| §1.2 analysis band, from a local constant | `ScarCaptureView.topInstruction` |
| §1.2 both band variants, from `isAnalysisShot` | `CaptureCameraView.analysisShotBand` |
| §1.3 arm-time attestation, once per session | `ScarCaptureView.readyButton` |
| §1.3 same, analysis shots only, once per session | `CaptureCameraView.readyButton` |
| §1.4 review badge on `== false` only | `PhotoReviewView.thumbnail` |
| §2.1 fill gate `isCloseEnough` + `framingMessage` | `ScarCaptureCameraService` |
| §2.2 sharpness folded into `isFocused` | `ScarCaptureCameraService.recomputeFocusGate` |
| §2.3 four-gate `allGatesGood`, row 3 only when blocking | service + `statusChips` |
| §2.4 override confirm, flags set, never disabled | `ScarCaptureView` |
| §3 three fields + additive decode + duplication | `CapturedPhoto.swift` |
| Appendix §2 per-photo notes | `PDFReportGenerator.drawCaptureConditions` |
| Appendix §2.4 cross-reference | `drawFactorBreakdown` (section-level, see below) |

### The protocol camera's §1.2/§1.3 gap — closed 2026-09-07, second commit

**Current state: `CaptureCameraView` now carries both band variants and the
arm-time attestation.** `PhotoReviewView`'s badge needed no change — it keys on
`frameConfirmedClear == false`, which protocol-camera analysis shots can now
actually carry, so §1.4 covers this surface by construction the moment the
attestation writes.

One thing this diff deliberately does **not** wire, and it is a finding rather
than an omission: **`gateOverridden` stays unwritten on this camera.** Its
locked note reads "captured manually while the app's sharpness and framing
checks were not met" — and this camera runs Steady / lens-settled / Even
Lighting, with no sharpness statistic and no fill gate at all. Writing `true`
here would put a sentence in an evidence appendix naming two checks that never
ran on that photograph. Failure direction decides it: `true` is a **wrong**
claim, absent is a **missing** one. Re-enabled by whichever diff brings those
terms to this camera, or by per-camera wording in the lock — Ledger's call.

**And the attestation's arrival falsifies an inference the appendix draws.**
`docs/EVIDENCE_APPENDIX_CAPTURE_NOTES.md` §1.1 reasons that
`frameConfirmedClear != nil` means "this photo postdates the sharpness field",
which is why the unmeasured-sharpness note is guarded on
`sharpnessScore == nil && frameConfirmedClear != nil`. That held while the
attestation existed only on the scar screen, which measures sharpness. A
protocol-camera analysis shot now lands at `frameConfirmedClear != nil` **with
`sharpnessScore == nil` permanently**, so every such photo emits "Sharpness was
not measured for this photograph" — true, but on every analysis shot of every
case rather than on the exceptional one. Ledger's row five was a rarity note;
on this surface it becomes furniture. Recorded, not reworded: it is his copy.

**Verified with a real Swift frontend, which is new for this project.** A
swift.org 5.10.1 Linux tarball at `~/toolchains/swift` clears
`preflight.py`'s `swift-parse` advisory outright: **0 advisories whole-tree,
all 42 Swift files actually parsed** rather than reported as unparsed. Beyond
that, the new attestation state machine was reduced to a no-SwiftUI shape,
compiled, and **executed** against eight `precondition`s — unasked records
`nil`, the first tap on an analysis shot asks without arming, the second arms
and records `true`, a later shot in the same session does not re-ask, a
reference shot arms on the first tap and records `nil`, an attestation does not
leak onto a reference shot, `gateOverridden` stays `false`, and a completed
protocol is not an analysis shot. All hold. **Three mutations of the shape each
failed on a different one**, which is what makes the set evidence rather than
decoration. It is still not a build: no iOS SDK, and nothing here type-checks
a SwiftUI `body`.

*Below this line is history, correct when written and superseded by the
paragraphs above.*

**§1.2's per-shot band did not exist on the 30-shot camera.** This is the
divergence the reconciliation caught that nobody flagged in review, and it is
the one worth reading closely.

§1.2 specifies the band on `CaptureCameraView`, under the existing instruction
text, in two variants — analysis and reference. That is where the shot type
genuinely *varies*, and it is the only reason `PhotoType.isAnalysisShot` needs
to exist as a property rather than a local constant. What shipped is the scar
screen's line (§1.2's third-line addendum, driven by a local constant per §0)
and the report-side filter. So:

- the scar screen is covered, and it is the worst offender for the bug;
- `.closeupDamage` and `.paintTransfer` shots taken through the **30-shot
  protocol camera get no no-ruler guidance at all**;
- `isAnalysisShot`'s only consumer is `drawCaptureConditions`, which decides
  what to *report*, not what to *tell the user at capture time*.

**That inverts the item's purpose for those shots: the report will faithfully
note a contaminated photograph the app never warned the user about.** §1.3's
arm-time attestation and §1.4's review badge have the same gap — both are
wired on the scar path only, so a 30-shot analysis photo is never asked about
and can never carry `frameConfirmedClear == false`.

Recorded rather than fixed at the time, because it is a second screen's worth of work
and belongs in its own diff. **It is not a partial implementation of §1.2 — it
is §1.2 unbuilt on the surface §1.2 was written for.**

### Deliberate divergences from this spec

1. **Sharpness statistic renamed, not reinterpreted** — §3 above. Mean absolute
   Laplacian response, not variance. Recorded because the value is persisted
   into evidence.
2. **`isFocused` default flipped `true` → `false`.** Not in this spec at all.
   As "the lens is not hunting" `true` was honest — nothing was hunting yet. As
   "measurably sharp" it claims a quality nothing has checked, so it starts
   `false` and blocks auto-capture for the first frames. The manual shutter is
   available throughout, which is what makes that the safe direction.
3. **Thresholds are provisional and deliberately LOOSE**, pending Prism.
   `sharpnessThreshold = 0.035`, `fillRatioThreshold = 1.35`. A gate calibrated
   by guesswork that rejects good shots trains users onto the override, which
   discards the benefit of having a gate at all: erring loose fails toward
   capturing evidence, erring strict fails toward losing it.
4. **§1.1's one-time explainer card is NOT built.** (`hasSeenAnalysisShotExplainer`
   has zero references in the tree.) It is the one section
   needing a new file, and therefore the `project.pbxproj` registration trap.
   Deferred to its own diff rather than folded in — §1.2's permanent band is
   the layer that does the daily work, and shipping the card in the same commit
   as the gate wiring would put a build-system risk inside a camera-path
   change. **§1.1 remains unbuilt and this table is the record of that**, not a
   silence to be read as done.
5. **`QualityFlags.isTooClose` / `hasMotionBlur` remain unassigned.**
   `isBlurry` and `isTooFar` are now set at capture time from the MEASURED
   sharpness and fill terms rather than the gate booleans (§2.4, and see the
   correction recorded there — the gate-derived version made an unmeasured
   capture print two notes claiming a measurement). The other two have no signal behind them yet: this screen measures
   sharpness and fill, not distance-too-near or motion specifically. They are
   left declared and annotated rather than assigned from a proxy, because a
   flag set from something it does not measure is worse than one that is
   honestly absent. Their `false` default is still the always-false disguise
   Vector's sweep identified — that is now a narrower open item, not a
   closed one.
6. **`qualityScore` on the clean scar path is still `1.0`.** The override path
   no longer claims it (it records `0.5`, above `isUsable`'s `0.4`, so the shot
   is never dropped). What a scar capture *should* record is a persisted-model
   semantics question for Sean; the recommendation is `0.0` plus an explicit
   flag, following the in-file `wasImported` precedent — record less, flag
   explicitly, never claim more.

### §2.4's cross-reference, and why it is section-level

Ledger's copy review found the appendix's §2.4 reference unbuilt: the Capture
Conditions page existed and nothing in the findings section led a reader to it.
The asymmetry is the instructive part — §2.4's *other* half ("the score is
never annotated, discounted or hedged") was satisfied trivially by not
implementing the reference, so the constraining half was present and the
informing half absent, which reads as compliance.

It is now emitted, but **once per findings section rather than per factor**,
and that is narrower than §2.4 asks for. §2.4 wants it on factors whose score
was computed from flagged photographs; `FactorScore` records **no photo
linkage at all** — no id, no set — so per-factor attribution is not derivable,
and inventing one would be a claim about which photograph fed which factor
that the model cannot support. The wording says "photographs used in this
analysis" instead of implying this factor's inputs. Per-factor precision needs
`FactorScore` to carry source photo ids: a model change, its own diff.

The note conditions also moved into one `captureNotes(for:)` function that
both the renderer and the new predicate call. Two independent predicates for
"does this photo carry a note" is the duplicated-claim defect this round was
spent on: they would agree until someone edited one, and the disagreement
would be a cross-reference pointing at an empty page, or a page nothing
points to.

### Open items this record leaves behind

Stated as a list because a reconciliation that only reports successes is the
artefact this whole round was about.

1. §1.2 / §1.3 / §1.4 on the 30-shot camera — unbuilt, above.
2. §1.1's explainer card — unbuilt, needs a new file and its `project.pbxproj`
   registration.
3. `QualityFlags.isTooClose` and `hasMotionBlur` — assigned on no path.
4. `qualityScore` semantics for a scar capture — Sean's decision.
5. Both threshold calibrations — Prism, on real frames.
6. §2.4's reference is section-level, not per-factor, pending photo linkage on
   `FactorScore`. Ledger's struck-out checklist item for it should be
   re-enabled by the diff that adds that linkage, not by this one.
7. `CapturedPhoto.issueDescriptions` cannot distinguish "no issues" from "not
   measured", and wiring every flag would not change that: a 30-shot photo gets
   no sharpness or fill measurement at all, so its empty list means something
   different from a scar photo's. The distinction has to live at the call site.

### Verification status

`preflight --all` clear and `git am` clean on a **plain `git clone`** of the
remote — named rather than described, since a `--single-branch` clone inherits
a main-only refspec and reports one advisory where a plain clone reports zero.
"Clone by URL and measure" is under-specified. **NOT COMPILED**: no Swift frontend on this team parsed the
camera-path change when it was written, no page has been rendered, and both
thresholds are uncalibrated by anyone. Sean's build and a device are the only
instruments for §2 and for the appendix's layout.
