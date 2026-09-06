# Process Discipline — Vehicle_Damage_Asst

Owner of this document: Ledger (Product & Documentation Lead).
Scope: how work lands on `main`, and what documentation each change owes.

This exists because of one specific piece of project history: **nothing in this
repository has ever been compiled by the tooling that wrote it**, and one large
multi-file commit previously took Xcode down for the project owner. Both risks
are handled the same way — small commits, verified immediately, documented at
the time they land.

---

## 1. Branch and commit rules

- `main` is the only branch. Work directly on `main` unless the tech lead says
  otherwise.
- **One logical change = one commit.** If a change touches a data model, a
  view model, and a view, that is three commits, in that order (model →
  plumbing → UI), each one buildable on its own.
- **Never grow one file by hundreds of lines in a single commit.** Split it.
  This is the direct lesson from the `ScarCaptureView.swift` incident
  (reverted at `9b6a67e`; content preserved at `3f6d7f4`).
- **Open the changed file in Xcode immediately after committing** a UI file.
  If Xcode crashes on file open, clear `~/Library/Developer/Xcode/DerivedData/*`
  and any `*.xcuserstate` / `*.xcuserdatad` in the checkout before suspecting
  the Swift code.
- **Any new Swift file must be registered in `project.pbxproj`** or it silently
  does not compile into the target. This has already caused two "mystery"
  build failures (`bf3bc5a`, `3f56117`). `scripts/build_pbxproj.py` generates
  the pbxproj from `scripts/pbxproj_skeleton.txt`.

### Commit message format

```
[item-N] <imperative summary, <=72 chars>

<why this change exists — the problem, not the diff>

Files: <comma-separated paths>
Test: <what to do on-device to confirm it works>
Compiled: yes | no (no toolchain)
```

`[item-N]` refers to the 5-item improvement plan. Work outside the plan uses a
prefix of `[build]`, `[docs]`, `[fix]`, or `[chore]`.

The `Compiled:` line is not optional. A commit that says `Compiled: no` is a
commit nobody may treat as working.

---

## 2. What every change owes `ios/README.md`

`ios/README.md` is the authoritative changelog and the reason this project is
still understandable. Every functional commit gets an entry, appended in
chronological order, using this template:

```markdown
### <YYYY-MM-DD> — <short title> (item N/5)

**Why**: <the problem, in the requester's own words where available>

**What changed**: <behaviour, not line-by-line diff. Name the types and
functions a reader would grep for.>

**Files touched**: `Path/One.swift`, `Path/Two.swift`

**Commit(s)**: `abc1234`

**Compiled/run**: <yes, Xcode <version>, device <model> | NOT COMPILED — see below>

**On-device test checklist**:
- [ ] <step 1 — a thing a human does, with the expected result>
- [ ] <step 2 — including the negative case: what should NOT change>
- [ ] <step 3 — determinism/regression check where the change touches scoring>
```

Rules for the checklist: every item must be something a person can do on a
device and observe. "Verify the algorithm is correct" is not a checklist item;
"re-run analysis on the same two photos twice and confirm the same percentage
both times" is.

Non-trivial functions also get an inline `NOTE(<author>)` comment
cross-referencing the changelog entry, so a reader in the code finds the
rationale without leaving the file.

---

## 3. Documentation ownership — who updates what, when

| Trigger | File to update | Who |
|---|---|---|
| Any functional commit | `ios/README.md` changelog entry | the committer |
| A task closes | plan-status table in `ios/README.md` | Ledger |
| A file is added, removed, or moved | `ios/reference/COMPLETE_FILE_MANIFEST.md` (regenerate, don't hand-edit) | the committer |
| A product decision is made **by Sean** | tick the box in the open-decisions list, record it in `HANDOFF_SUMMARY.md` | Ledger |
| Signing / repo access / build config changes | `HANDOFF_SUMMARY.md` §3 and §5 | whoever changed it, or Ledger on report |
| A known issue is resolved | delete it from `HANDOFF_SUMMARY.md` §5 — do not leave stale warnings | Ledger |
| Scoring behaviour or thresholds change | `ios/reference/ALGORITHM_EXPLAINER.md` | the committer |
| Any user-visible or report string changes | changelog entry must quote before/after, commit body must carry `Copy: changed` + the affected keys | the committer; Ledger reviews |

Nobody writes changelog prose except Ledger: hand over what changed, why, and
which files, and the entry plus the on-device checklist come back written.
Ledger also owns locked copy — the report's evidence-appendix wording and the
capture-screen string inventory, per
`docs/EVIDENCE_APPENDIX_CAPTURE_NOTES.md` §4.

Ledger keeps the plan status and the decision log honest but writes no code.
Implementation detail in a changelog entry is the committer's to write — it
describes what they actually did.

---

## 4. Definition of done

Two distinct bars. Keep them distinct — collapsing them either hides real
progress or lets unverified work be called finished.

### `in_review` — the author has done everything they can

Move a task here as soon as all of this is true:

1. Everything within the author's control is finished: committed and pushed to
   `main` in small isolated commits, or — where the author cannot commit —
   delivered as the finished artefact in the task thread.
2. Anything that could **not** be verified is written down as unverified, in
   the changelog entry and in the task thread. Explicitly, not by omission.
3. What remains is named: which verification step, and who or what it waits on.

`in_review` means "author is finished, awaiting verification." It is the honest
resting state for work that is blocked on a Mac, a device, or repo access — not
`in_progress`, which would imply someone is still typing.

### `done` — verified

All of the `in_review` clauses, plus:

4. It **compiles** — an actual clean build (`Cmd+Shift+K`, `Cmd+B`), not a
   syntax or brace-balance check.
5. It has been run on a real device for anything touching camera, LiDAR,
   StoreKit, or PDF export. LiDAR does not work in Simulator.
6. `ios/README.md` has an entry with a filled-in on-device test checklist, and
   the checklist has actually been walked once.

"Balance-checked and looks right" is not done. It is not even started.

Nothing is described as working in a status report until clauses 4 and 5 hold,
whatever the task's status says.

---

## 5. Reporting up

- Blocked items and product decisions go to Sean explicitly, with a
  recommendation and the cost of each option — never a bare question.
- **A recommendation is not a decision.** Only Sean ticks a box on the
  open-decisions list. Agreement among the people doing the work — however
  unanimous, however obviously correct — does not close a question that was put
  to him. Record the recommendation, scope the work on it as a default, say so
  plainly, and leave the box open. The list is only worth keeping because it
  distinguishes what he chose from what he was advised; a recommendation that
  can quietly promote itself makes it worthless for exactly the decisions it
  exists to track.
- Status claims must be traceable to a commit. If the changelog and the git log
  disagree, the git log wins and the changelog gets corrected.
- Nothing is described as "working" in a status report unless clauses 4 and 5
  of §4 are satisfied.
