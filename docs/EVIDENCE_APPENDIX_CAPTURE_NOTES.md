# Report Spec — Capture-Quality Notes in the Evidence Appendix

Owner: Ledger. Implements §3 of the Item 2 no-ruler / focus-gate UX spec.
Applies to `Services/PDFReportGenerator.swift` and the evidence appendix only.
Ledger owns this wording; changes to it go through the copy lock in §4 below.

Principle: **a flagged photo in the file beats a missing one.** Nothing is
silently dropped, nothing is silently promoted. The report records what the
capture conditions were and lets the reader weigh it. That is the whole job.

---

## 1. Which photos get a note

A per-photo note is emitted for an **analysis shot** (`PhotoType.isAnalysisShot`)
when any of:

| Condition | Meaning |
|---|---|
| `gateOverridden == true` | captured with the sharpness/framing gate failing, via the manual shutter |
| `frameConfirmedClear == false` | the examiner was asked and did not attest the frame was free of a ruler or foreign object |
| `qualityFlags.isBlurry` or `.isTooFar` | set from live gate state at capture time |
| `sharpnessScore == nil && frameConfirmedClear != nil` | sharpness was not measured for this photo (see §1.1 for why the second clause) |

Reference/measurement shots get **no** note for any of these. A tape measure in
a measurement shot is wanted evidence, not a defect — this is the core insight
of the Item 2 spec and the report must not contradict it.

### 1.1 Unmeasurable is not the same claim as unconfirmed

`frameConfirmedClear` is `Bool?`, three-state, per the Item 2 spec v2:

| Value | Meaning | Appendix behaviour |
|---|---|---|
| `true` | examiner explicitly confirmed the frame was clear | no note |
| `false` | examiner was asked and declined | note, per §2.2 |
| `nil` | never asked — pre-Item-2 photo, or a library import | **no note at all** |

`nil` **is** "unmeasurable", and that is a different claim from "unconfirmed".
The appendix must not conflate them: emitting the unconfirmed note on `nil`
would make every historical photo in every existing case read as deficient for
a reason no examiner can act on — a defect-shaped note about a photograph with
nothing wrong with it.

No extra field is needed to distinguish the cases. Swift's optional comparison
excludes `nil` on its own, so the §1 condition is literally
`frameConfirmedClear == false` and is unconditionally correct as written.

**`frameConfirmedClear` also dates the photo.** A photo that was asked the
confirmation question is necessarily a post-Item-2 capture, so
`frameConfirmedClear != nil` is the test for "this photo postdates the
sharpness field" — which is why the sharpness row reads
`sharpnessScore == nil && frameConfirmedClear != nil`. No second field there
either.

Library imports land at `nil` / `nil` and correctly emit nothing: no live
camera frame ever existed to measure, so silence is the honest output rather
than a note about missing data.

**The general rule: never infer a defect from a field's absence.**

---

## 2. Exact wording

### 2.1 Appendix section header

> **Capture Conditions**
>
> The analysis photographs below were captured under conditions the app records
> automatically. Notes in this section describe how a photograph was taken. They
> are not findings about the vehicles.

That second sentence is not optional. Without it a reader can mistake a capture
note for an analytical conclusion.

### 2.2 Per-photo notes

One line per photo, prefixed with the shot label and photo index.

| Trigger | Note |
|---|---|
| `gateOverridden == true` | Captured manually while the app's sharpness and framing checks were not met. The examiner chose to record the shot rather than lose it. Detail read from this photograph may be limited. |
| `frameConfirmedClear == false` (recorded) | The examiner did not confirm that the frame was clear of a ruler, tape measure, or other foreign object before capture. |
| `qualityFlags.isBlurry` | The app measured this photograph as not sharp at the point of capture. |
| `qualityFlags.isTooFar` | The app measured the damage area as not filling the guide frame — the subject may be too distant for fine surface detail. |
| `sharpnessScore == nil && frameConfirmedClear != nil` | Sharpness was not measured for this photograph. |

Multiple triggers on one photo produce multiple lines under one photo heading,
in the table's order. Do not merge them into a summary sentence — each one is a
separate fact about the capture.

### 2.3 When no analysis photo carries a flag

> All analysis photographs met the app's capture-quality checks at the time of
> capture.

Emit this rather than omitting the section. A silent section is
indistinguishable from a section that was never generated.

### 2.4 Cross-reference from the findings section

Where a factor's score was computed from photographs that carry any note above,
the factor's row in the main report gains a single reference, no adjective:

> See Capture Conditions in the evidence appendix.

The score itself is not annotated, discounted, or hedged in the findings
section. The reader is pointed at the facts; the report does not editorialise
about its own inputs.

---

## 3. Language constraints

These hold everywhere in this section, and they are the same constraints the
whole report already operates under (`MatchResult.disclaimerText`):

- **No verdict or probabilistic language.** Not "likely", "probably",
  "consistent with a match", "suggests", "indicates", "cannot be excluded".
  A capture note describes a photograph, never a conclusion about a vehicle.
- **No quality adjectives standing alone.** "Poor photograph" is a judgement;
  "the app measured this photograph as not sharp at the point of capture" is a
  record. Use the record.
- **Attribute every claim.** Either the app measured it or the examiner
  attested it. Never leave the reader guessing which.
- **Never imply the examiner did something wrong.** `gateOverridden` documents a
  deliberate, reasonable choice made at a roadside. The wording in §2.2 says so
  on purpose.
- **No missing-data implications.** An unmeasured value is unmeasured, not
  failed.

---

## 4. Copy lock

§4 of the Item 2 UX spec (the 16-string copy inventory) and §2 of this document
are **locked copy**. They are the strings a future edit is most likely to
casually "improve" back into probabilistic phrasing, which is exactly the thing
v1's scope forbids.

Under `docs/PROCESS.md`:

- Any commit that changes a string in either inventory must carry
  `Copy: changed` in its message body and list the affected keys.
- The changelog entry for that commit must quote the before and after text.
- Ledger reviews copy changes before they land. This is not a gate on velocity
  — it is a gate on one specific failure mode: the report drifting from
  "documentation tool" language toward "forensic identification" language one
  well-meaning word at a time.
- The full string inventory lives with the changelog, not only in a spec
  attachment, so it survives the spec being superseded.

### 4.1 Copy change ledger

Every change to a locked string is recorded here, oldest first, whether or not
it arrived through a commit. The rationale column is the point — it is what
stops a future editor from "restoring" wording that was deliberately changed.

| Date | Key | Was | Now | Why |
|---|---|---|---|---|
| 2026-09-06 | `review.flag` | Analysis photo — frame not confirmed clear | Analysis photo — examiner did not confirm the frame was clear | The old wording described the photograph as deficient; the new one describes what a person did or did not do. Same principle as the `frameConfirmedClear` tri-state — a photo is not at fault for a question nobody asked. Changed in Item 2 spec v2, before this lock existed; recorded retroactively. |

The current value of `review.flag` is therefore **"Analysis photo — examiner
did not confirm the frame was clear"**, and the §2.2 note wording for
`frameConfirmedClear == false` is consistent with it by construction.

---

## 5. Test checklist (for the changelog entry when this lands)

- [ ] A case where every analysis photo passed the gates renders the §2.3 line, not an empty section.
- [ ] A photo captured via manual-shutter override renders the `gateOverridden` note, and the photo is present in the appendix.
- [ ] A measurement/reference shot with a tape measure clearly in frame produces **no** capture note anywhere.
- [ ] A case created before these fields existed (`frameConfirmedClear == nil`, `sharpnessScore == nil`) renders **no** capture notes at all on its historical photos — not an "examiner did not confirm" note, not an "unmeasured" note.
- [ ] A photo imported from the camera roll (`nil` / `nil`) renders no capture note.
- [ ] A photo where the examiner was asked and declined (`frameConfirmedClear == false`) does render the note — confirming `nil` and `false` are not collapsed anywhere in the render path.
- [ ] A factor whose inputs include a flagged photo shows the §2.4 cross-reference, and its numeric score is unchanged from the same analysis run without the appendix.
- [ ] Search the rendered PDF text for: likely, probably, consistent with, suggests, indicates, match confirmed — zero hits in the Capture Conditions section.
