# Vehicle Damage Investigation Assistant — Project State

**Maintained by**: Ledger (Product & Documentation Lead)
**Last updated**: 2026-09-06 · `main` at `3656b64`
**Audience**: the working team. For the reasoning behind any specific piece of
code, read `ios/README.md` — this document is state, that one is history.

> This replaces the original one-way handoff note. It is now a living
> state-of-the-project doc: whoever changes the facts below updates this file,
> per `docs/PROCESS.md` §3.

---

## 1. What this project is

An iOS app (SwiftUI + ARKit/LiDAR + Vision + StoreKit 2) that helps someone
document vehicle damage and correlate a victim vehicle against a suspect
vehicle in a hit-and-run. It guides a structured photo/scan capture flow, runs
several independent computer-vision and statistical comparisons, and generates
a PDF report for an insurance claim or investigation file.

**Scope discipline**: v1 is explicitly an *investigative documentation and
leads* tool, **not** a court-admissible forensic match. Every report carries
that disclaimer (`MatchResult.disclaimerText`). Keep it. It is the reason the
scoring work is allowed to be honest about uncertainty rather than pressured
into producing confident-looking numbers.

Two audiences: consumers building a case for an insurer, and adjusters / body
shops / investigators processing many cases.

Fully on-device — no backend, no cloud storage, no networking except StoreKit.
Case data is one JSON file per case via `FileManager` with
`.completeFileProtection`. For a forensic tool this is a feature: no
chain-of-custody question about data leaving the device, and it works with no
connectivity at a scene.

---

## 2. Where everything lives

**Source of truth**: `https://github.com/spierce26-Ems/Vehicle_Damage_Asst`,
branch `main` (the only branch). Owned by GitHub user `spierce26-Ems`.

**Agents cannot be GitHub collaborators — they have no GitHub accounts.** All
agent work reaches `main` through the tech lead's write access: hand over a
patch or the file content plus a commit message, and it is landed authored to
you. See `docs/PROCESS.md` §0.

A secondary `genspark` git remote received auto-pushed backups from the earlier
AI session. It is a safety net, not a place to work. GitHub is the only source
of truth.

**Repository layout** — see `ios/reference/COMPLETE_FILE_MANIFEST.md`, which is
generated from `git ls-files` and lists every tracked file with its size. In
short: `ios/` holds the entire Xcode project (`App/`, `Models/`, `ViewModels/`,
`Views/`, `Services/`, `Utilities/`, `ForensicEngine/`), `ios/reference/` holds
the original brief and specs plus the Python reference implementation, `docs/`
holds the privacy policy and terms pages, and `scripts/` holds the pbxproj
generator.

**`ios/README.md` is the authoritative changelog.** Every feature and fix is
logged there in order with what was built, why (often quoting the original
request), which files were touched, and what to test on-device. Non-trivial
functions carry inline `NOTE(...)` comments pointing back at it. Read it before
reading code.

**Reference material** in `ios/reference/`: `PROJECT_BRIEF.md`,
`iOS_TECHNICAL_SPECS.md`, `ALGORITHM_EXPLAINER.md`,
`APP_STORE_CONNECT_SETUP.md`, `PAINT_ANALYSIS_KIT_FUTURE_FEATURE.md`,
`HANDOFF_TO_AI_DEVELOPER.md` (superseded by this file),
`COMPLETE_FILE_MANIFEST.md`, and `forensic_analyzer.py` /
`enhanced_forensic_analyzer.py` — the Python implementation the Swift scoring
engine was validated against, and the right tool for sanity-checking a
suspicious Swift score.

---

## 3. Technical stack

| Layer | Technology |
|---|---|
| UI | SwiftUI (native, no third-party UI libraries) |
| Depth / 3D scanning | ARKit + RealityKit (LiDAR scene reconstruction, `sceneReconstruction = .mesh`) |
| Computer vision | Apple Vision (`VNDetectContoursRequest`) |
| Pixel-level analysis | Hand-rolled algorithms over raw `CGContext` pixel buffers (no CV/ML library) |
| Persistence | `FileManager` + `Codable` JSON — no database |
| In-app purchases | StoreKit 2 |
| Backend / cloud | None, by design |
| Min iOS | 17.0 |
| Swift | 5.0 language mode (not Swift 6 strict concurrency) |
| Bundle ID | `com.spearitnow.vehicledamageforensics` |
| Signing | Automatic; development team `U83TBM24XZ` set at `802e739` — see §5.1 |

The one acknowledged technical-debt area is the hand-rolled pixel and
statistics math in the matching engine. It is being hardened incrementally with
real statistical rigour rather than replaced — see plan item 3.

A Vite/Cloudflare web scaffold left over from an earlier prototype used to sit
at the repo root; Sean approved deleting it and it was removed at `34754e2`
after verifying nothing in `ios/` referenced it. The repo root is now the iOS
project, the docs, and the pbxproj scripts — nothing else.

---

## 4. Feature status

### 4.1 Implemented and on `main`

Case creation and dashboard; victim + suspect guided capture (fixed 10-shot
protocol, `PhotoType.requiredCaptureProtocol` as single source of truth, with
skip-a-shot logged to the audit trail); camera-roll import; LiDAR depth
scanning plus tap-to-measure height feeding Height Alignment; paint-transfer
colour analysis (CIEDE2000); scar-direction consistency; scar line comparison;
scar fingerprint matching (minutiae along the scar); tool-mark / striation
matching (across the scar width) with a null-model significance layer; PDF
report covering all of it; StoreKit 2 paywall and case credits.

**Caveat that applies to all of the above**: it is committed, reviewed, and
brace-balanced — it has **never been compiled**. See §5.3. Treat "implemented"
as "written and plausible", not "verified".

### 4.2 Plan and priorities

The live status table for the 5-item improvement plan and the P0 foundation
work is maintained in `ios/README.md` under "Improvement Plan & Work Status".
Headlines:

- **Item 5 is decided: Option B**, confirmed by Sean — a duplicate-case clone
  action (`sourceCaseID`, regenerated ids, suspect vehicle and match results
  cleared). Option A, refactoring `suspectVehicle` into an array across ~88
  references in 15 files on code that has never compiled, is not being done.
  Recorded so it comes back as a deliberate reopening if a single combined
  multi-suspect report is ever genuinely required, rather than being
  re-litigated from scratch.
- **Item 1 is 3-of-4 landed**; the reverted `ScarCaptureView` focus-region UI
  is the remaining piece, gated on a green build.
- **Item 2 was promoted ahead of item 1's UI** — per-shot capture guidance plus
  a close-focus quality gate is the cheaper root fix for the same tape-measure
  contamination bug. Its spec is accepted; the code is not written. Sean
  decided the gate **hard-blocks** auto-capture, with the manual shutter as the
  documented override — a forced shot is saved and recorded (`gateOverridden`)
  rather than being indistinguishable from a clean one. The warn-only variant
  is not being built.
  **One thing on the record so it is not re-derived**: item 2 is *not* a blanket
  "no rulers" rule. The protocol's height-reference shot is deliberately a
  ruler/tape-measure shot — wanted evidence. The bug is confined to the shots
  whose pixels feed the engine, where printed ticks read as striations. Guidance
  is per-shot, keyed on `PhotoType.isAnalysisShot`. Implemented as a blanket ban
  it would cost the height reference and with it all scale.
- **Sequencing on `ScarCaptureView.swift` is fixed**: item 1's reapply lands
  first, alone, verified in Xcode, before item 2's UI commit touches that file.
  It is the file blamed for the Xcode crash; two large diffs racing on it is how
  the crash repeats.
- **Item 3 is code-complete but unverified**; its on-device checklist has not
  been walked.
- **Item 4 carries a requirement worth restating**: excluding a cross-section
  must be audited, and exports must show both the full and the filtered score.
  A tool that lets a user silently delete the evidence that disagrees with them
  is worse than no tool.

The foundation work (signing, first green build, first end-to-end device run,
documentation process, and the "trust the number" version stamp / p-value
display) is tracked in the same table. Documentation process is done, and
**signing is done** — Team ID `U83TBM24XZ` landed at `802e739` in both the
project and the generator skeleton (§5.1). The one remaining hard input is now
**the first clean build**: Xcode, `Cmd+Shift+K`, `Cmd+B`, and the error list.
Nothing else can substitute for it, because no one on this team can compile.

---

## 5. Known issues and standing context

### 5.1 Signing — RESOLVED at `802e739`
**`DEVELOPMENT_TEAM = U83TBM24XZ`**, supplied by Sean, set in both the Debug and
Release configurations of `project.pbxproj` *and* in
`scripts/pbxproj_skeleton.txt`. `CODE_SIGN_STYLE = Automatic` and the bundle id
were already correct. Device builds and TestFlight are unblocked.

Kept here rather than deleted because the *reason* it needed two files is a
standing trap, not a closed ticket — see the rest of this section and §5.5. The
history below describes the state before `802e739`.

Setting it in the live pbxproj alone is not enough: `scripts/pbxproj_skeleton.txt`
carries the same two config blocks, and the generator would silently drop the
Team ID the next time anyone registered a new Swift file (§5.5). Both files.

Before `802e739`, Xcode reported "Signing for 'VehicleDamageForensics' requires
a development team" (Team: None), which blocked every device run and TestFlight
build. It never blocked a Simulator build, and the earlier
P0-1-gates-P0-2 ordering was wrong for that reason.

### 5.2 A large multi-file commit previously crashed Xcode
Adding the "Scar Focus Region" UI stage across six files caused Xcode itself to
crash whenever any changed file was opened. Root cause was Xcode's own
`IDEEditorCoordinator` reentrancy-guard assertion — an Xcode-side race, not a
bug in the Swift code — most likely triggered by stale local editor state
(`.xcuserstate` / `.xcuserdatad`, gitignored and device-local) colliding with
one file's large size jump in a single commit.

The commits were reverted (`9b6a67e`) and reapplied as four small incremental
ones so any recurrence isolates to a small diff. Three landed; the UI file is
outstanding, with content preserved at `3f6d7f4` — cherry-pick as a reference,
re-verify, commit small, open in Xcode immediately.

**If Xcode crashes on opening a recently changed file**: clear
`~/Library/Developer/Xcode/DerivedData/*` and any `*.xcuserstate` /
`*.xcuserdatad` in the checkout before suspecting the Swift code. That resolved
it here. This incident is why `docs/PROCESS.md` forbids large single-file jumps.

### 5.3 There is no Mac and no LiDAR device on this team — a standing constraint

Not a blocker to be cleared: a permanent shape of how this project verifies
anything. Sean's Mac is the only build machine and the only LiDAR-capable
device in the picture. Concretely:

- **The first green build is Sean's session.** He adds the collaborators,
  selects the development team, and runs the clean build. The engineer's job on
  that task is turning around the error list he reports back, not producing it.
- **Task-level device runs have exactly one possible operator.** Any protocol
  written for a device run should be written to be executed by Sean, with
  enough detail that he is not guessing at intent.
- **Nothing gets called working on anyone else's word.** See §5.4.

One correction to an earlier assumption, since it was costing time: **signing
does not gate compiling.** `Cmd+B` against a Simulator destination builds
without a development team selected. The Apple Developer team is needed to
*run on a device*, not to find compiler errors. So the first build check can
start as soon as someone has the repo, independent of signing setup.

### 5.4 Nothing in this repository has ever been compiled
All prior AI-developer work happened in a Linux sandbox with no Swift compiler
and no Xcode. Every change was verified only by brace/paren/bracket balance
checks and code review. Balance-checking catches syntax mismatches — it catches
nothing about types, logic, or the compiler's opinion. The first clean build
should be expected to produce a real error list, and that list is information,
not failure. Do a full clean build and walk the main flows before treating any
commit as working.

### 5.5 The pbxproj is generated — edit both files
An unregistered Swift file silently does not compile into the target, which has
already caused two confusing build failures (`bf3bc5a`, `3f56117`).
`scripts/build_pbxproj.py` regenerates `project.pbxproj` from
`scripts/pbxproj_skeleton.txt`.

The consequence that bites: **a build setting changed only in the live pbxproj
is discarded the next time the generator runs.** It disappears in a commit that
looks like it was about registering a new file, and presents as configuration
breaking itself for no reason. Change both files, every time. Signing was the
first place this would have bitten — see §5.1.

### 5.6 LiDAR requires a real device
Nothing in the LiDAR or depth path can be tested in Simulator. Same for camera
capture and StoreKit purchase flows.

### 5.7 Sean's local checkout
`/Users/seanpierce/Documents/Vehicle_Damage_Asst` is the live clone. A second,
stale clone at `/Users/seanpierce/Vehicle_Damage_Asst` was abandoned after
initial setup and never pulled again — not the one to use.

---

## 6. Open decisions

These need a product answer, not an engineering one. The full list, decided and
open, lives in `ios/README.md`'s status block.

**Decided by Sean:** item 5 is **Option B** (duplicate-case clone). The capture
quality gate **hard-blocks** auto-capture, with the manual shutter as the
documented override. The leftover web scaffold was deleted.

Still open:

1. **Distribution target** — TestFlight, or continue direct-to-device installs?
   Recommended: direct installs for now. This decides how urgent App Store
   Connect and IAP setup becomes
   (`ios/reference/APP_STORE_CONNECT_SETUP.md`).
2. **Paywall / monetization configuration** — whether an "excluded" result sits
   above or below the paywall. Design is proceeding on the assumption that it
   sits above; exposure is confined to one screen and marked on the design
   artefact.
3. **Whether the report prints when an exclusion was recorded** — before or
   after a similarity figure had been displayed
   (`docs/EVIDENCE_APPENDIX_CAPTURE_NOTES.md` §6). The *capture* of that
   ordering is not open and is not waiting on an answer: it can only be
   recorded as it happens, so it is specified as a requirement of the
   per-cross-section exclusion work. Only the printing is a product question.
   Recommended: print it, in the neutral three-state wording.

The **Apple Developer Team ID** was on that list too, and is now closed
(`U83TBM24XZ`, `802e739`) — it was never a decision, only an identifier.

**Two items, since the Team ID closed at `802e739`.** Work blocked on an *event* rather than an
answer is listed separately under "Queued behind the green build, not behind
Sean" in `ios/README.md` — the offline null run for the critical-value table and
the per-branch changelog entries both live there. Mixing them into this list
would grow it with items nobody can act on, which is the fastest way to make a
decision list stop being read.

**A recommendation is not a decision.** No box here gets ticked by agreement
among the people doing the work, however unanimous — only by Sean answering.
That distinction is the only reason this list is worth keeping.

---

## 7. Working agreements

Changelog prose is written by Ledger — hand over what changed, why, and which
files, and the entry plus the on-device checklist come back written. Report and
capture-screen copy is locked against drift into probabilistic or verdict
language; see `docs/EVIDENCE_APPENDIX_CAPTURE_NOTES.md` §4.

`docs/PROCESS.md` is the short version: one logical change per commit,
`[item-N]` message prefix with a `Compiled: yes|no` line, a changelog entry with
a walkable on-device test checklist for every functional commit, and a
definition of done that requires a real build and a real device run. Nothing is
reported as working until those are true.

Product decisions go to Sean with a recommendation and the cost of each option
attached. Status claims must be traceable to a commit; if the changelog and the
git log disagree, the git log wins and the changelog gets corrected.
