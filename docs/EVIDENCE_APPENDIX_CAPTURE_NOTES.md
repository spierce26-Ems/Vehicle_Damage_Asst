# Report Spec — Capture-Quality Notes in the Evidence Appendix

Owner: Ledger. Implements §3 of the Item 2 no-ruler / focus-gate UX spec,
which is `docs/ITEM2_NORULER_FOCUSGATE_UX_SPEC.md` in this repository. **Every
"Item 2 spec" citation below means that file.** It was absent from the tree
until it landed, so all six citations here were unfollowable — this line is
what makes them resolve, and a citation is only provenance while its
destination can be opened.
Applies to `Services/PDFReportGenerator.swift` and the evidence appendix only.
Ledger owns this wording; changes to it go through the copy lock in §4 below.
The split of authority: this document is the authority on **wording**, the
spec on **behaviour** — the tri-state semantics, the per-shot rule and the gate
composition. §1.1's table restates those and is not their source.

> **How that citation came to be unfollowable, kept as the history — the
> current state is the header above, and this block is not it.** This document
> cited *the Item 2 UX spec* six times as the authority for its field semantics
> while that spec was **not in the tree**: `git ls-files '*.md'` returned twelve
> files and none of them was it. The chain was **spec → spec → decision tick,
> with the tree at neither end**, and it survived two months because the
> documents agreed with each other. **A citation that cannot be followed is
> indistinguishable from one that can until someone tries.**
>
> Resolved in two steps, and the second was not implied by the first: the spec
> landed at `docs/ITEM2_NORULER_FOCUSGATE_UX_SPEC.md`, and then the citations
> here were made to name it. **Landing a destination and pointing at it are
> different commits.**
>
> I had proposed the alternative — promote this document to the authority,
> since the implementation landed first. **Withdrawn: this document is locked
> *copy*, and promoting a restatement to the source would leave the original
> claims uncheckable and make it answer for decisions it never made.** The
> split in the header is the settled form.

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
| `qualityFlags.isBlurry` or `.isTooFar` | set at capture time from the MEASURED sharpness and fill terms — not from the gate booleans; see the spec's §2.4 correction, and §1.1 below for why the distinction is this table's problem too |
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

**The word "measured" in rows three and four is load-bearing copy, not
style.** It makes each sentence a claim about a measurement, which is what
forbids driving the trigger from a gate: **a gate may say "not yet"; a recorded
finding may only say what was measured** (`docs/PROCESS.md` §4c). `isBlurry`
and `isTooFar` were first wired from `!isFocused` / `!isCloseEnough` — gates
that read `false` before anything is measured — and fixed in `a9deebb`.

**The rows are not independent, and that is the maintenance rule this table
was missing.** Row five, *"Sharpness was not measured for this photograph"*,
fires on exactly the photo rows three and four described as
measured-and-failing under the old wiring: **one photograph, two notes, one
saying the measurement did not happen and one reporting its result**, rendered
into the same bullet list. So **row five is the negative case for rows three
and four, and an edit to any of the three must be checked against the others.**

**Rows one and two are gate-driven and correctly so — the difference is what
their sentences claim.** Row one is written from `!allGatesGood` at the moment
of capture, and says *"the app's sharpness and framing checks were not met"*:
a statement about **checks**, which is exactly what a gate can support. Row
two is an examiner attestation. **Neither says "measured", and that is why
neither has rows three and four's problem** — the audit is not "is this driven
by a gate?" but "does the sentence claim more than its input can support?"
Read the trigger column and the note column as one unit.

Row two additionally got the `nil` case right from the start because
`frameConfirmedClear` is `Bool?` and "never asked" is visible in the type. `Bool` cannot hold "unmeasured", so
for these two the distinction has to be held at the source — which is why four
careful readers passed over it. **If a future edit softens "measured" out of
row three or four, the constraint on their inputs disappears with it**: the
sentence becomes satisfiable by a gate, and the contradiction returns with
nothing in this document able to catch it.

### 2.3 When no analysis photo carries a flag

> All analysis photographs met the app's capture-quality checks at the time of
> capture.

Emit this rather than omitting the section. A silent section is
indistinguishable from a section that was never generated.

**The all-clear's precondition is the INPUT SET, not the note logic, and that
is where it failed.** This sentence is only true if the set it was computed
over contains every photograph that could have carried a note. The first
implementation built the set from `Vehicle.photos` alone — and `scarPhoto`
lives in its own field, is never appended to `photos`, and is the **only**
photograph in the app that ever carries `gateOverridden`,
`frameConfirmedClear`, `sharpnessScore`, or a measured `isBlurry`/`isTooFar`.
Every photograph that *was* in the set comes from the 30-shot path or a
library import, and none of those pass any of those fields. So no note could
ever be produced, `anyNotes` could never become true, and this all-clear
printed unconditionally — including on a case whose scar photo was captured
through the manual override with every gate failing.

**An all-clear computed over a set that excludes the only photograph that can
fail is an absence asserting the clean case** (§5), and here it asserted it
about the shot the analysis actually runs on.

The rule, for this section and any other all-clear: **state the population,
then the predicate.** An all-clear is a claim about a set, so the set is half
the claim, and a reader cannot see the set from the sentence. §1's condition
table is the predicate; the population is *every analysis shot on both
vehicles, including each vehicle's `scarPhoto`*.

### 2.4 Cross-reference from the findings section

Where a factor's score was computed from photographs that carry any note above,
the factor's row in the main report gains a single reference, no adjective:

> See Capture Conditions in the evidence appendix.

The score itself is not annotated, discounted, or hedged in the findings
section. The reader is pointed at the facts; the report does not editorialise
about its own inputs.

**Ratified deviation, 2026-09-07 — my call, declared `Copy: changed` in
`b0968f3` and left to me there.** The reference ships **section-level**, once
per findings section, preceded by one subject sentence:

> Some photographs used in this analysis carry capture notes. See Capture
> Conditions in the evidence appendix.

**Approved on the failure-direction rule.** `FactorScore` carries no photo
linkage — no id, no set — so per-factor attribution is not derivable, and
emitting the bare locked sentence under a factor row would let its *position*
assert which photographs fed that factor. **A locked string is locked against
silent rewording, not against a maintainer noticing that placing it would
assert something the data cannot support** — the same ground on which the
`.insufficient` cause suffix was ratified conditional in 2026-09.

The added sentence does the work the per-factor placement was supposed to do:
it names its own scope, so the reference cannot be read as a claim about one
factor, and `"photographs used in this analysis"` is deliberately the widest
true subject available.

**The requirement above is recorded as UNMET, not rewritten to match what
shipped.** Restore the bare §2.4 wording, per factor, in the diff that gives
`FactorScore` source photo ids — at that point the subject sentence becomes
the imprecise one and should go. The struck on-device item in §7 is re-enabled
by *that* diff, not by `b0968f3`.

---

## 3. Language constraints

These hold everywhere in this section, and they are the same constraints the
whole report already operates under (`MatchResult.disclaimerText`):

- **No verdict or probabilistic language.** Not "likely", "probably",
  "consistent with a match", "suggests", "indicates", "cannot be excluded".
  A capture note describes a photograph, never a conclusion about a vehicle.
- **No quality adjectives standing alone.** "Poor photograph" is a judgement;
  "the app measured this photograph as not sharp at the point of capture" is a
  record. Use the record. **`CapturedPhoto.issueDescriptions` is the in-tree
  counter-example and it is not report copy — it yields bare adjectives
  ("Out of focus", "Too far away", "Motion blur detected") from the same
  flags §2.2 renders as records.** It has zero readers today, which is the
  only reason it is a latent problem rather than a live one. **If anything
  ever surfaces it to a user or a report, it needs §2.2's wording, not its
  own** — and note the second defect in it: an empty result reads as "no
  problems found" when it can equally mean "not measured", because
  `isTooClose` and `hasMotionBlur` are written on no path. **A list of
  problems cannot express "unmeasured" by being short.**
- **Attribute every claim.** Either the app measured it or the examiner
  attested it. Never leave the reader guessing which.
- **Never imply the examiner did something wrong.** `gateOverridden` documents a
  deliberate, reasonable choice made at a roadside. The wording in §2.2 says so
  on purpose.
- **No missing-data implications.** An unmeasured value is unmeasured, not
  failed.
- **No distinction may be carried by colour alone.** Every state this report
  distinguishes — significant against not-distinguishable-from-chance, excluded
  against included, confirmed against not recorded — must be readable in the
  words or the layout. This is a requirement on the report, not a checklist
  item to be walked once. A forensic report is printed, photocopied and
  scanned; P1b exists precisely so a high-but-insignificant score cannot look
  like a good result, and a colour-only encoding of that reverts it on the
  first monochrome copy while every on-screen check passes. Colour may
  reinforce a distinction the text already makes; it may never be the thing
  that makes it.

  **This currently holds, and is written here as a property to preserve rather
  than work to do.** Verified in `PDFReportGenerator`: significance reaches the
  PDF through `headlineDisplay` with no colour argument, so it draws black, and
  the string itself carries the verdict — *"above chance"*, *"NOT
  distinguishable from chance"*, *"significance not testable"*. Colour does
  appear on the page — the exclusion box and the filtered section — and every
  instance has redundant literal text beside it (`EXCLUSION WARNING`,
  `[EXCLUDED] `, `Filtered Result — Investigator Exclusions Applied`), so
  colour is decorative there. The only colour-driven significance encoding is
  `significanceColor()` in `MatchResultsView`, which is on-screen, and even
  that labels a `headlineDisplay` string.

  So the failure mode is a refactor, not a gap: someone tidies
  `headlineDisplay` down to a bare percentage and moves the verdict into the
  colour, and **nothing fails** — the screen still reads correctly to the
  person making the change. Recorded as a regression guard because a spec item
  that reads as new work invites a second implementation of something already
  done.

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

### 4.0 A cited document is inside the lock

**Any document the app cites by name in a string a user reads is locked copy,
for the whole document.** Added 2026-09-06 after `ALGORITHM_EXPLAINER.md` was
found teaching the abandoned probability-and-verdict framing while being cited
into the report: `MatchScoreCalculator`'s height rule-out recommendation says
"see ALGORITHM_EXPLAINER §2", so a reader who followed the citation landed two
sections later on a table stating that 60-79 means a probable match at 60-85%
probability — a claim the report itself refuses to print.

The route matters more than the instance. The report contained no banned
language; it **pointed at** it, and a lock that inspects strings cannot see
one hop away. A citation is a promise that what it points to is as defensible
as what surrounds it, so the destination inherits the constraint — and the
whole document, not the cited section, because a reader who arrives at §2 does
not stop reading at §2.

Two obligations follow. Before adding a citation to a user-visible string,
read the cited document against §3's language constraints. And when this
document's framing changes, grep for cited reference documents rather than
assuming the lock's inventory covers them — the inventory lists strings, and a
citation's payload is not a string.

**Sweep for references mechanically, not by rereading what you just wrote.**
Prism applied this rule to his own code and found two breaches with a keyword
sweep over string literals on non-comment lines — one being the citation he
had added deliberately, the other a string he had read that same day while
rewriting the function around it. Aimed review found nothing; a sweep asking a
different question found both immediately. The sweep looks for person names,
section references, filenames, and commit identifiers. I ran the same sweep
across every user-facing string in the app afterwards and it is clean, with
two false positives that are the word "Compass" meaning the hardware sensor.

**A single-line literal sweep does not see `disclaimerText`, and that is the
string that matters most.** It is the app's only Swift multiline literal, so
any pattern excluding newlines skips it — and it is the legally load-bearing
text in the PDF's boxed cover callout, which makes it the string most likely to
attract a citation, because "see X for scoring detail" is a natural thing to
add to a disclaimer. A reference sweep covering every report string except the
disclaimer has exactly one hole, in exactly the wrong place.

I ran the single-line sweep across every user-facing string in the app and it
reported clean, with two false positives that are the word "Compass" meaning
the hardware sensor. That result was **narrower than it looked**: a citation
planted inside `disclaimerText` passes it silently, which I verified rather
than assumed once Prism found the same gap in the mechanical check. Any sweep
run against this rule must match multiline spans first and exclude them from
the single-line pass, or its clean result is partly luck.

This also assumes string literals live in source. If localisation ever lands,
the sweep has to follow the strings out of the file — otherwise it reports
clean on a codebase where none of the report copy is in the code at all.

### 4.0.1 The report attributes findings to evidence, never to a person

A named individual must not appear in any string a user reads, and
specifically not as the authority for a finding. The combined exclusion rule's
callout read *"both conditions of Sean's hard exclusion rule are met"* — a
person presented, in a prominent PDF exclusion callout, as the reason a
suspect vehicle should be ruled out. It now reads "the combined exclusion
rule".

Whose rule it is carries nothing an investigator can act on, and attributing
an exclusion to a person rather than to the measurements invites exactly the
question the report must not raise: whether this finding reflects the evidence
or somebody's preference. Design attribution belongs in the doc comment, where
it records intent for maintainers and reaches no reader of the report.

The general form, which also disposed of the `ALGORITHM_EXPLAINER` citation:
**a reference in report copy has to be something the reader can act on.** A
section number and a person's name are both unactionable, so both cost
everything a citation commits us to and return nothing.

**Provenance in a comment is the recommended form, and it must never trigger
the lock.** This rule tells people to move a citation out of report copy and
into a code comment. A check that then fires on the comment charges the full
price of a citation for complying -- and its own printed remedy, "move it into
a doc comment", would not have silenced it. `check_cited_doc_copy()` harvested
a document name from a *trailing* comment (`let x = 6  // see
ALGORITHM_EXPLAINER §2`), because it skipped a line only when its first token
was `//`. Corrected at `2f5dc32` by harvesting from string literals only:
multiline spans lifted first, then comments stripped, then single-line
literals. **A rule and the check enforcing it must agree about which artefact
is the compliant one**, or the check penalises the behaviour the rule asks for
-- and it does so most convincingly to the person who just complied.

One note on which artefact each of us tested, because the sequence is
instructive. My single-line sweep's blind spot above is real and is mine. The
same gap was then diagnosed in the *landed* check by reading its pattern text
-- and the landed check does not have it, since it scans line by line and so
reads lines inside a """ body like any other. The finding was accurate about a
superseded draft. Hence the habit worth keeping: **name the commit you verified
against.** "Verified the patch" is true, costs a round, and is exactly as
confident as the useful version.

### 4.0.3 An absent verdict is now a corruption disguise

Recorded here because it changes what the honest-absence wording means, and
that wording is locked copy.

Merging the per-cross-section exclusion work with the version-stamp work
produced a hand-written decoder that compiles perfectly and omits two
persisted fields. `encode(to:)` stays synthesized, so the values are still
*written* -- they simply never come back. `permutationPValue` and
`nullTrialCount` return `nil`, and the surfaces then render **"no
significance test was possible"**: the exact honest-absence state this
document specifies, produced by silent data loss instead of by an absent null
model.

So the wording we chose for integrity is also the wording data loss wears. That
does not make it the wrong wording -- there is no phrasing that distinguishes
"no baseline could be built" from "the baseline was dropped on load", because
the surface cannot tell -- but it does mean **the absence states in this
document cannot be the only thing standing between a case file and a wrong
report.** They are honest about what the app knows; they are not evidence that
the app knows it.

**And this absence fails toward silence that looks deliberate**, which is what
separates it from every other absence state in this document. The others fail
toward plain silence: a badge is not drawn, a note is not emitted, a verdict is
withheld. This one emits a sentence carrying the authority of a design
decision -- so the more carefully the wording was chosen, the better cover it
gives the data loss. That is an argument for the operational consequence below
rather than for weakening the wording. A well-written absence state is a better
disguise than a badly written one, and the answer is to verify the absence, not
to write it worse.

The check that catches it (`decoder-completeness`, `2d56a5d`) is a
**staged-mode** check, so `--all` cannot see it -- it needs `--since` or a real
commit. Anyone reviewing a merge that touches a hand-written decoder and
reading a clean `--all` has confirmed nothing about this hazard.

Standing consequence for copy review: when a persisted field is added or a
decoder is hand-written, an absence state appearing on screen is no longer
self-evidently correct. It has to be traced to a real absence. Provenance goes in
code comments and on the Analysis Provenance page, both of which are
reviewable and neither of which is the report's argument.

### 4.0.2 Copy owed on the readiness bar and the set-point reticle (task #13)

`Copy: changed` on three of four commits on `readiness-setpoint`. New and
reworded strings: the readiness header and five segment labels with details,
the limitations line in singular and plural, next-step titles, the scar reason
line, `Set ground point` / `Set damage point`, two missed-surface banner
variants, both aiming banners reworded from "tap" to aiming the circle, the
coverage caption with its proportion-only line, and the confirmation screen's
heading, why-it-matters line and two buttons. Reviewed: no verdict or
probabilistic drift, and the coverage caption's "proportion only — not which
part of the vehicle" is the strongest form available given the input.

Two items that are decisions rather than transcription.

**The parking-space example is currently nowhere in the app.** Replacing the
capture footer removed the caption reading "even when the vehicle was reversing
(e.g. backing out of a parking space)", which is the clearest statement of why
a scar reading beats a compass heading. `ScarCaptureView`'s own why-note
explains the paint-taper mechanism but not the reversing case, and the
mechanism is the *how* while the parking space is the *why*. **Decision: it
belongs in `ScarCaptureView` when task #5 lands**, not re-added now — that file
is under rewrite, and re-adding a caption to it guarantees a conflict for one
sentence. Tracked here so a caption removed for a good reason does not become a
caption permanently absent for no reason; the risk with "add it when #5 lands"
is that nobody owns the sentence in between, and this section is that owner.

**A confirmation-screen string asserted a consequence a scheduled change
removes — fixed at `78a9c8a`, not deferred.** It read "one of the two
conditions that can rule a vehicle out": true of the engine as shipped, false
once task #14's provenance gate makes a LiDAR height inconclusive. My first
call was to correct it alongside #14. That was wrong, because the provenance
half of #14 needs no calibration and can land without waiting on a device — so
the string would have been false from that moment, not from some later
threshold decision. It now reads:

> This is compared against the other vehicle's damage height. Getting it right
> here matters — a measurement taken at the scene cannot be re-taken from the
> report.

**Two rules come out of this, and the second is the reusable one.**

*UI copy must not assert an engine behaviour that is already scheduled to
change.* Not "must be updated when it changes" — must not assert it at all.
Copy that lags reality is a defect with a known fix; copy that was accurate
when written and is invalidated by a change already on the board is the §4c
failure with a countdown attached, and the interval belongs to nobody.

*Overstating consequence is how a measurement gets defended rather than
re-taken.* An examiner told their number can exclude a suspect acquires a stake
in it being right. An examiner told the number cannot be re-taken later has a
reason to check it now. Same information, opposite effect on behaviour — and
the replacement wording survives any future threshold decision, because
irreversibility is a property of being at the scene rather than of the engine.

### 4.1 Copy change ledger

**The rule: any surface that reproduces a locked string is bound by this lock.**

One rule, deliberately not a list of surfaces. The lock was first scoped to
commits, then extended to spec revisions, then to mocks — three times, each time
because a string escaped through a channel the enumeration had not named. An
enumerated list is a list of the ways drift has already happened; the rule has
to cover the ways it has not happened yet.

So: **if an artefact shows a locked string to a human who might type it into
the product, changing that string requires a ledger entry here.** Commit,
spec revision, wireframe, mock, prototype, slide, screenshot in a message —
the carrier is irrelevant. The obligation is on the string.

Additional obligations by carrier, on top of the ledger entry:

- **A commit** — `Copy: changed` in the message body plus the affected keys,
  and the changelog entry quotes before and after.
- **A layout artefact** (mock, wireframe, prototype) — either a ledger entry,
  or an explicit placeholder marking on the artefact naming this document as
  the authority.

Layout artefacts are the most dangerous carrier and the easiest to miss. A spec
revision at least announces itself as text somebody has to read; an implementer
working from a picture has no signal that the words in it are placeholder. They
build the screen, type what they see, and a paraphrase is in the product with no
diff anywhere that looks like a copy change. **Strings in a layout artefact are
layout placeholders with no authority** — the Item 2 spec §4 inventory and §2.2
of this document are the only sources. Where a frame cannot fit the real string,
that is a layout finding to raise, never a licence to shorten the copy.

A banner on the artefact is good practice and does not discharge the
obligation: a banner depends on its author remembering to write it every time,
which is a habit, not a mechanism. The ledger is the mechanism.

The rationale column is the load-bearing part — it is what stops a future
editor "restoring" wording that was deliberately changed.

| Date | Key | Was | Now | Why |
|---|---|---|---|---|
| 2026-09-06 | `review.flag` | Analysis photo — frame not confirmed clear | Analysis photo — examiner did not confirm the frame was clear | The old wording described the photograph as deficient; the new one describes what a person did or did not do. Same principle as the `frameConfirmedClear` tri-state — a photo is not at fault for a question nobody asked. Changed in Item 2 spec v2, before this lock existed; recorded retroactively. |

The current value of `review.flag` is therefore **"Analysis photo — examiner
did not confirm the frame was clear"**, and the §2.2 note wording for
`frameConfirmedClear == false` is consistent with it by construction.

Known outstanding: the eight-screen wireframe set reproduces four locked
strings, two of them shortened to fit a phone frame (screen 4's analysis band,
screen 7's legend). Those are placeholders, flagged as such on the artefact.
Neither shortened form is a copy change and neither may be implemented. The
design set is tracked as task #12; report page mocks arriving there come under
this lock on the same terms.

### 4.2 The override wording is a condition of the gate, not a courtesy

Sean's decision that the quality gate **hard-blocks** auto-capture rests on
three things holding together:

1. the manual shutter stays enabled unconditionally;
2. taking the override is recorded (`gateOverridden`) and surfaced;
3. **this document describes taking it as a reasonable roadside choice, not as
   a shortfall.**

Point 3 is not softer phrasing — it is what makes points 1 and 2 safe. An
affordance that gets you written up as deficient for using it is an affordance
people stop using, and they would lose evidence to avoid the note. The gate
would then be producing missing photographs instead of flagged ones, which is
strictly worse than not gating at all.

So the §2.2 `gateOverridden` wording is load-bearing. A future length-trim that
reduces it to "captured with quality checks not met" breaks the decision it
implements. If it ever needs to change, the gate design has to be revisited in
the same breath — not the sentence alone.

---

### 4.3 Attestation and actor wording (custody appendix)

Scope was ruled separately: the actor column and the attestation block are
built; a per-page source-file hash is not. What follows is the wording for the
two that are built.

#### 4.3.1 The attestation

> I generated this report from the case data described above. I make no claim
> of forensic identification.

Signed by the examiner, with name, unit, and badge or identifier beneath.

What the sentence deliberately does and does not say:

- It attests to an **act** — that this person generated this report from this
  data. That is a fact the examiner can know and be held to.
- It does **not** attest to a conclusion, a method's validity, or a chain of
  custody being unbroken. An examiner cannot truthfully attest to any of those
  from inside the app, and an attestation that overreaches is worth less than
  none, because the first challenge to any part of it discredits the whole.
- The second sentence is not boilerplate hedging. It is the one place in the
  document where the person signing says the limit out loud in the first
  person, which is materially different from the app printing a disclaimer
  about itself.

**Never render an unsigned attestation.** If examiner identity is not
available, omit the entire block — signature line, name line, and all. A blank
signature line reads as a report someone declined to sign, which is a claim
about a person; an absent block reads as a feature that is not there. Same rule
as the cover's examiner line, and the same house rule as everywhere else: an
absence must not assert something (`docs/PROCESS.md` §5).

#### 4.3.2 The actor column

Each audit event carries the actor that performed it. Two constraints on how it
reads:

- **`system` is a real actor, not a gap.** Automated events — analysis runs,
  generated reports — are attributed to `system`, never left blank and never
  attributed to whoever happened to be logged in. Conflating the two would make
  the trail assert a person did something the app did.
- **Where an event predates the actor field, the cell reads "not recorded"**,
  not blank and not inferred from the case owner. An event whose actor was
  never captured is unattributed, which is a different claim from unattended.

The audit trail prints **every** event in timestamp order, never a selection.
A filtered trail is not a trail. Where length is a concern the answer is
continuation pages, which the mock already does.

#### 4.3.3 What is deliberately not in the report

A per-page or per-file hash is **not** printed. It would look like
tamper-evidence and prove nothing: the app that wrote the case data can rewrite
it, so a digest computed by that same app attests only that the file matched
itself at print time. Rigour-shaped notation that does not support the claim it
implies is worse than its absence in a document that may be challenged — the
first person to test it finds it hollow, and everything near it inherits the
doubt.

If real tamper-evidence is ever required, it is a signed evidence bundle with
an external verifier, not a digest in a PDF. Recorded here so this is visibly a
decision rather than an oversight.

---

## 5. Test checklist (for the changelog entry when this lands)

- [ ] A case where every analysis photo passed the gates renders the §2.3 line, not an empty section.
- [ ] A photo captured via manual-shutter override renders the `gateOverridden` note, and the photo is present in the appendix.
- [ ] A measurement/reference shot with a tape measure clearly in frame produces **no** capture note anywhere.
- [ ] A case created before these fields existed (`frameConfirmedClear == nil`, `sharpnessScore == nil`) renders **no** capture notes at all on its historical photos — not an "examiner did not confirm" note, not an "unmeasured" note.
- [ ] A photo imported from the camera roll (`nil` / `nil`) renders no capture note.
- [ ] With examiner identity unavailable, the attestation block and the cover examiner line are **absent** — no blank signature line anywhere.
- [ ] An automated audit event shows actor `system`, not blank and not the case owner.
- [ ] An audit event predating the actor field reads "not recorded".
- [ ] No page prints a source-file hash.
- [ ] A photo where the examiner was asked and declined (`frameConfirmedClear == false`) does render the note — confirming `nil` and `false` are not collapsed anywhere in the render path.
- [ ] **A scar capture taken on the very first frame, before any measurement lands, renders row five and NOT rows three or four.** The negative case for `a9deebb`: enter the scar camera, tap the manual shutter immediately, export. One note — *"Sharpness was not measured for this photograph"* — with no *"The app measured…"* line beside it. **Two notes on that photo means the flags are reading gates again.** Walk it a second time with the lens hunting: `isFocused` is the conjunction of device focus and the sharpness measurement, so a hunting lens over a sharp frame is the other way a gate reads `false` with a good measurement in hand.
- [ ] ~~A factor whose inputs include a flagged photo shows the §2.4 cross-reference, and its numeric score is unchanged from the same analysis run without the appendix.~~ **NOT IMPLEMENTED — do not walk this item, it cannot pass.** `408a247` built §1, §2.1, §2.2 and §2.3 in full and verbatim, and did not build §2.4: *"See Capture Conditions in the evidence appendix."* has zero references in Swift, and `drawFactorBreakdown` renders `f.notes` and nothing else. **A checklist line for a clause nobody built would have been walked, found no cross-reference to look at, and read as a pass — or as a defect in the tester's method.** That is this document's own subject one artefact over. Re-enable it in the same diff that implements §2.4; the requirement stands.
- [ ] Search the rendered PDF text for: likely, probably, consistent with, suggests, indicates, match confirmed — zero hits in the Capture Conditions section.

---

## 6. Excluded cross-sections: wording and the ordering record (task #6)

Written on Prism's statistical review of per-cross-section exclusion
(2026-09-06). Two things belong to this spec rather than to the statistics: what
the report and the results screen are permitted to *say* when exclusions are
active, and what has to be recorded at capture time so that anything can be said
at all.

### 6.1 No significance verdict on a filtered subset

**Required.** When one or more cross-sections have been excluded from a
comparison, the significance verdict is **suppressed**, not recomputed. The
headline may state the filtered similarity figure; it may not state "above
chance" or "NOT distinguishable from chance" for the filtered subset.

Locked wording for `headlineDisplay` in the filtered case:

> Filtered comparison — NN% similarity across M of N cross-sections.
> Statistical significance is not established for a filtered subset. See the
> exclusion record in the appendix.

Rationale, and why this is not conservatism for its own sake: the p-value
recomputed on a filtered subset is not wrong by a small margin. Prism measured a
15.6× inflation of the false-positive rate at two exclusions, with the *typical*
unrelated pair landing on p = 0.05 once an investigator selects the filtered
view with the lowest p-value. A verdict computed against 0.05 in that state is a
number the report cannot defend, printed in the one place a reader trusts most.
This is the same case as the missing null baseline in the version-stamp work: the
figure stays, the claim about the figure goes.

A calibrated critical value may later replace suppression with a real verdict.
Until a fitted lookup table is in the tree and referenced by the code, the
verdict stays suppressed — an uncalibrated threshold is not an improvement on
saying nothing.

#### 6.1.1 What "fitted" has to mean before suppression lifts

Landing this table is the act that re-enables significance verdicts on filtered
subsets, so the conditions on it are release conditions, not review notes. All
of the following, or suppression stays:

1. **Each cell carries its confidence interval, and the code carries the
   interval too — not only the point estimate.** A critical value whose CI spans
   a full grid step is the same category of object as a percentage with no null
   model behind it: a number whose precision is typographic. This document
   already refuses the second one; refusing the first is the same rule applied
   one level up.
2. **A cell whose CI spans more than one p-grid step does not lift suppression
   for that cell.** Suppression is per-cell, so a table may be partially
   admissible — a well-resolved cell can enable verdicts at its own probe and
   exclusion count while an under-resolved neighbour stays suppressed. Nothing
   is gained by making the whole table wait for its worst cell, and nothing is
   risked by letting the worst cell keep saying nothing.
3. **Monotonicity across exclusion count within each probe count is a
   correctness check, not a smoothing step.** More shopping freedom cannot make
   a test stricter, so a rise in the critical value as exclusions increase is
   proof the cells are under-resolved. Raw estimates that violate it beyond
   noise reject the fit; they are not fitted around.
4. **The table lands as committed data with its generating script alongside
   it**, and the script's parameters — trial count, pairs per cell, seed — are
   recorded with the numbers. A constant nobody can regenerate cannot be
   re-verified when the algorithm changes underneath it, and the version stamp
   would then attest to a match computed against a threshold of unknown
   provenance.
5. **The null trial count under exclusion is a precondition, not a tuning
   parameter.** A permutation p-value from *t* trials is a discrete multiple of
   1/(1+t); at 400 trials the grid step is 0.0025 and a 0.0075 critical value is
   grid point 3. The table cannot be fitted at that resolution *at any sample
   size*, because the limit is the statistic's expressible precision, not the
   noise. Raising trials is therefore part of building the table rather than an
   optimisation to schedule afterwards.

The underlying test is the one this document applies everywhere: a figure never
travels without what makes it readable. A critical value's CI is what makes the
critical value readable, and a threshold quoted to four decimal places with a
one-grid-step interval behind it fails that test in the direction the report can
least afford — anti-conservative, in the number that decides whether a verdict
prints at all.

### 6.2 The exclusion record has to know what came first

A legitimate exclusion (a probe that wandered onto a ruler) and an exclusion
chosen because it improved the number are statistically identical. Nothing in
the score separates them. What separates them is whether the decision was taken
before or after a similarity figure for that comparison had been displayed.

That ordering exists only while it is happening. It cannot be reconstructed from
a saved case, a timestamp added later, or an investigator's recollection. So it
is recorded at capture time or it is permanently unavailable — which makes it a
data-model requirement for #6 rather than a later enhancement, and the reason
this section is being written before the feature lands rather than after.

**What to persist**, per exclusion and per comparison:

- the comparison's `firstScoreDisplayedAt` — set once, the first time any
  similarity figure for that pair is rendered to the screen; never overwritten.
- each exclusion's own `recordedAt`.
- each exclusion's investigator-stated `reason` (already in #6's shape).

Ordering is **derived** from the two timestamps, never stored as a
pre-judged boolean. Storing the label would freeze one interpretation of the
event; storing the two instants records only what is known and lets the
rendering rule change without invalidating saved cases.

All three are new fields on a persisted model, therefore optional — see
PROCESS.md §1. Cases created before these fields existed decode to `nil`.

### 6.3 Rendering the ordering — three states, never two

| state | appendix wording |
|---|---|
| `recordedAt` earlier than `firstScoreDisplayedAt` | Recorded before any similarity figure was displayed for this comparison. |
| `recordedAt` later than `firstScoreDisplayedAt` | Recorded after a similarity figure had been displayed for this comparison. |
| either timestamp `nil` | Ordering not recorded. |

The third row is not optional and must not be collapsed into the first. An
exclusion whose ordering was never captured is *unknown*, not *clean*; printing
the "before" line for a `nil` would make an absence assert the one property this
whole section exists to establish. House rule, PROCESS.md §5.

The report states the ordering and stops. It does not characterise an exclusion
as appropriate, inappropriate, legitimate, or selective; it does not rank the
three states; it prints no warning icon or colour on the "after" row. The
ordering is a fact about the procedure and the reader draws the inference — the
moment the report editorialises, the fact becomes an accusation the app cannot
support.

### 6.4 Copy constraints specific to this section

Forbidden in any exclusion-related string: *cherry-pick*, *shopping*, *p-hacking*,
*manipulated*, *gamed*, *suspicious*, *justified*, *valid exclusion*,
*invalid exclusion*. The first six accuse; the last three adjudicate. Both are
outside what the app knows.

Also forbidden: presenting the filtered figure more prominently than the
unfiltered one. Both are shown; the unfiltered figure is the one computed
without any selection and is never demoted.

### 6.5 Test checklist additions (task #6)

- [ ] With any exclusion active, the headline contains no "above chance" / "not distinguishable from chance" verdict, and does contain the §6.1 suppression sentence.
- [ ] Removing all exclusions restores the ordinary verdict on the unfiltered comparison, identical to a run where no exclusion was ever made.
- [ ] `firstScoreDisplayedAt` is written once and does not move when the score is re-rendered, re-entered, or recomputed.
- [ ] An exclusion made before the score was ever shown renders the "before" line; one made after renders the "after" line.
- [ ] A case saved before these fields existed renders "Ordering not recorded" — not the "before" line, not a blank row, not an omitted row.
- [ ] The unfiltered similarity figure appears in both the report and the results screen whenever a filtered figure does.
- [ ] Search the rendered PDF text for: cherry, shopping, manipulated, suspicious, justified, valid exclusion — zero hits.
- [ ] After the #6 rebase onto the version-stamp branch, the filtered outcome renders through `headlineDisplay` and emits no percentage string of its own.
- [ ] With a critical-value table present, a cell whose CI spans more than one p-grid step still suppresses the verdict at that probe/exclusion count — partial admissibility works per cell, and an under-resolved cell does not inherit a neighbour's verdict.
- [ ] The critical value in force is rendered with its confidence interval wherever it is shown, and the provenance page names the table's generating script and parameters.
