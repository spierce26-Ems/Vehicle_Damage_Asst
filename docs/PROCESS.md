# Process Discipline — Vehicle_Damage_Asst

Owner of this document: Ledger (Product & Documentation Lead).
Scope: how work lands on `main`, and what documentation each change owes.

This exists because of one specific piece of project history: **nothing in this
repository has ever been compiled by the tooling that wrote it**, and one large
multi-file commit previously took Xcode down for the project owner. Both risks
are handled the same way — small commits, verified immediately, documented at
the time they land.

---

## 0. How work reaches `main`

**Agents cannot be GitHub collaborators — they have no GitHub accounts.** Adding
collaborators was never going to grant any agent push rights, and time spent
waiting on it was wasted. All agent work reaches `main` through the tech lead's
write access.

The working model: hand over a patch, or the file content plus a commit message.
It is landed on your behalf, authored to you in the commit message. A
`git format-patch` bundle is the ideal artifact — it carries the message, the
author, and the exact diff, so nothing is retyped or reinterpreted.

Work in flight lives on a **remote branch**, never only in a chat attachment.
An attachment is a delivery mechanism, not storage: it cannot be fetched,
diffed, or rebased, and the version that landed can only be identified by
diffing afterwards. Push the branch, then point at it.

**Say "I'm writing X" before you write it, not when you deliver it.** Three
people independently wrote the same regenerator and three wrote the same header
check in one hour; two of each were thrown away. Nobody was careless — the
board each of them read was **accurate when they read it**, which is the
partial-landing shape seen from the reader's side: an all-clear describes a
moment, and a claim in flight is invisible until it lands. A one-line claim
costs nothing and is the only thing that makes concurrent work visible; the
alternative is discovering the duplicate at delivery, when the work is already
done and someone has to discard it. **When you find you were second, drop
yours and send only the delta** — that is what kept this cheap the three times
it happened.

Two things to know if you produce patches:

- `git am` strips a `[docs]`-style bracketed prefix from the subject line,
  because it reads it as a patch-management tag. Whoever lands the patch must
  restore the prefix, or the commit lands without it.
- Rebuild the patch from the latest revision before landing, and verify it
  against **where it is going** rather than where it was made:
  `git apply --check` against a freshly fetched `origin/main` takes seconds.
  Both of the day's near misses were artefacts that were correct in the place
  they were made and wrong at the destination — a patch built off a local
  branch, and a remedy line naming a file that existed only as an attachment.
- **After landing a multi-commit stack, confirm every patch subject is present
  in `git log --oneline` before reporting it landed — and never
  `git am --abort` after a partial apply without checking what it rolled
  back.** An `--abort` on a two-patch stack that failed on patch 2 rolls back
  the already-applied patch 1, and re-applying only patch 2 leaves a landing
  that passes every check, because every check is true of the commit that did
  land. **A partially-landed stack is indistinguishable from a fully-landed
  one** — the same substitution as a probe reporting `exists` where it means
  `runs`, aimed at a patch. This is how a Bonferroni rewrite vanished while the
  changelog entry citing it recorded it as done. Resolve a conflict in place;
  if you must abort, re-apply the whole stack. **Note what this rule has not
  achieved:** Compass read it, wrote about it, endorsed it, and reached for
  `--abort` under a conflict an hour later. It is correct and it is not
  sufficient — which is the argument for the manifest regenerator over any
  amount of care, since the conflict that triggers the reflex is the one place
  a stack collides mechanically here. **And note when it did work**: the one
  advocate who caught himself mid-reach had hit that same conflict twice in the
  preceding round. **A rule transfers when the hazard recurs often enough to be
  expected, and not otherwise** — so put rules on the frequent hazards and
  tooling on the rare ones. The rare ones are where a rule is guaranteed to
  catch you cold, and they are where we have been putting rules.
- **Never hand-pick a side when the conflict is in
  `COMPLETE_FILE_MANIFEST.md` — regenerate every row either side touched, and
  run `preflight --all` immediately after the resolution rather than after the
  stack.** Every patch that grows a file conflicts with every other patch that
  grows it on that one manifest row, so this conflict is the *normal* case for
  a stack, not an exception. Taking `--theirs` is correct for the row in
  dispute and silently reverts the rows the other side updated — **and review
  cannot tell the difference, because a line count is a plausible integer on
  both sides**, so no reading of the diff distinguishes a correct resolution
  from a reverting one. Only `check_manifest_line_counts` does, and only if you
  run it before the next patch buries the revert. Regenerating just the
  conflicted row is not enough — **and one pass over every row is not enough
  either: rewriting the rows changes the manifest's own length, so its
  self-referential row then describes the pre-write file.** Regeneration must
  iterate to a fixed point; a hand-resolution has to be re-run until `--all`
  is quiet twice in a row.
- **The verify recipe: read the advisory LINE, never the exit code — and name
  your clone's flags.** `preflight`'s plain `rc` answers *did it refuse to
  proceed*, never *did it find anything*, so `preflight --all >/dev/null 2>&1;
  echo $?` reports a number that cannot see its own findings. Three of us
  traded clean headlines off that command in one round, one of them over a
  tracked `.pyc` sitting in output nobody was reading. Use:

  ```
  python3 scripts/preflight.py --all --strict    # rc: 0 clean, 4 advisories, 1 blocking
  ```

  and **quote the summary line itself**, not a derived word. Two riders, both
  learned the same day: `--strict` is opt-in *because the pre-commit hook must
  keep passing on advisories* — an advisory that refuses a commit is a blocking
  failure under another name — and **"fresh clone" must name its flags the way
  a shape check names its compiler**, since a `--single-branch` clone honestly
  reports one more advisory than a full one on the identical tree
  (`check_script_currency` reads `origin/main`, and a single-branch refspec
  makes its own input untrustworthy). **A verification figure travels with its
  extractor, its flags, and its channel, or it is not a figure anyone else can
  use.** Do not grep the literal `clear (0 advisory)`: the clean-tree summary
  no longer carries the parenthetical.
- **The one manifest number nothing validates is the Swift line total in the
  header sentence.** `check_manifest_line_counts` checks the per-file rows and
  `check_manifest_drift` checks the file and Swift *counts*, but the
  parenthetical `(N lines)` is asserted and never compared — which is why it
  sat three lines short on `309f25b` while every check reported clear. It is
  the widest claim in the document and the only one a reader can't test, so it
  is exactly the one to recompute by hand after a resolution until a check
  covers it. **A generated file is only as trustworthy as its least-validated
  assertion, and the header is the part people quote.**
- **Do not amend someone else's commit to carry your fix, even when the fix is
  right.** A rebased stack that needs a correction gets a new commit of your
  own; amending rewrites another author's commit to say something they did not
  write, and the change is invisible in the subject line everyone checks.
- **A changelog entry that cites a code change is not evidence the change
  landed, and it is the artefact most likely to be mistaken for one** —
  recording completion is its whole job, so a reader sees the entry, sees a
  named owner, and closes the item without looking. Before writing an entry
  that asserts a code fix, grep the tree for the change itself; before trusting
  one, do the same. Prose is a record of intent until the tree agrees with it.
- Once a patch is out, corrections go as a **new** patch on top, never an
  amended one under the same filename. An amended re-send is indistinguishable
  from a duplicate on the receiving end, and which version landed can then only
  be established by diffing. Correspondingly, when someone has revisions in
  flight, wait for the settled version rather than landing the one in hand.

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
- **A build SETTING changed in `project.pbxproj` must also be changed in
  `scripts/pbxproj_skeleton.txt`.** The generator rebuilds the pbxproj from the
  skeleton, so a setting present only in the live file is silently discarded the
  next time anyone registers a new Swift file. It then resurfaces as a
  configuration breaking itself for no visible reason, in a commit that appears
  to be about an unrelated new file. Both files, every time.

  **Settings only — not file registration.** The skeleton carries build
  settings; `build_pbxproj.py` discovers source files by walking the tree. So
  adding a Swift file requires no skeleton edit, and a reviewer should not
  demand one: it would change nothing. `scripts/preflight.py` check 2 is scoped
  to setting drift for this reason. Stated explicitly because a patch that
  registers a new file without touching the skeleton looks like a violation of
  the rule above and is not one — and a rule that fires on the wrong thing is
  how people learn to ignore it.
- **A `PBXFileReference` for a file no longer in the tree is also a defect**,
  not just the reverse. It happens on renames and reverts — it is the exact
  shape of the revert at `9b6a67e`, the incident that set this project's whole
  caution level about commit size. `preflight.py` check 1 catches both
  directions.
- **A new field on a persisted model must be optional, or old cases stop
  opening.** Swift's synthesized `init(from:)` throws `keyNotFound` for a
  missing non-optional key rather than falling back to the property's default
  value — a default in the declaration does *not* make decoding tolerant. Every
  case file already on a device predates the new field, so a non-optional
  addition breaks all of them on upgrade, and it breaks them at load time with
  no partial recovery. Use `Bool?` / `Double?` / `decodeIfPresent`, always.
- **Never change the type of an existing persisted field.** Optionality does
  not protect you here: `decodeIfPresent` throws `typeMismatch` when the key is
  present with the wrong type, so `Double?` becoming `String?` destroys every
  saved case exactly as thoroughly as the `keyNotFound` case above. It is also
  far more innocent-looking in review — a one-word edit inside a declaration
  that was already there, with no new line to draw the eye.

  The two directions are **not** symmetric. Widening `T` to `T?` is the
  migration *fix* and is always allowed. Changing the underlying type is not.
  A genuine type change needs a new optional field plus a decode path that
  reads the old one, never an edit in place.

  Highest-risk moment for this: **resolving a merge conflict.** A conflict in a
  file that touches `Models/` is exactly where a field can silently change
  shape, so run preflight on the *resolved* tree — a clean pre-rebase result
  says nothing about what the resolution produced.

  **Use `--since`, not a bare run, and this is not a preference.** Preflight's
  commit-shaped checks read the **index**, and a rebase's product is committed
  rather than staged — so run plain after resolving a conflict they report
  nothing staged, and `--all` judges the tree without judging a diff. The check
  went silent at exactly the moment this rule says it matters most, and a clean
  line there means "not looking", not "clean". `--since origin/main` routes them
  through `REF...HEAD`, comparing the resolved tree against the branch it is
  going onto. Landed in `81103fe`.

  For the `cross-section-exclude` rebase specifically: `--since` against the
  branch being rebased *onto*. A pre-rebase result, however clean, says nothing
  about the resolution.

  **And run `main`'s `scripts/preflight.py` against a feature branch, never the
  branch's own copy.** Verified at `prism-task10-p1b` @ `6230c4f` and
  `cross-section-exclude` @ `c6e749a`: both scripts handle `--since` perfectly
  well, and neither contains `decoder-completeness` at all. So the reason is
  not a misbehaving flag — it is that the branch script lacks the check the
  merge needs, and a clean run there is a clean run by a script that never
  looked. Recorded with the reason because the wrong reason implies a flag
  problem a reader can test, find absent, and correctly conclude the
  instruction was wrong.
- **Insert new build-setting keys in Xcode's alphabetical order.** Xcode
  reorders them on first save otherwise, producing a spurious diff on a file
  everyone needs to stay readable.

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

**A checklist constant is a claim about the build the reader is holding, not
about the commit the entry describes**, and those diverge the moment anything
below the entry lands. P1b shipped `v1.1.0` at 120 null trials and the audit
below it moved to `v1.2.0` at 1000: a checklist item reading "the card shows
v1.1.0" fails on a current device *for the right reason* and reads as a defect.
So write the value the reader will see, and let the entry's prose keep the
historical record. Where two entries describe one behaviour and the later one
narrows the earlier — #10a's standalone height rule-out gated by #14 part 1 —
each must point at the other: an entry consulted alone overstates what the app
does, and that is §4d at document scale.

**A change that removes an obstacle owes an edit everywhere the obstacle is
cited as current.** Raising a constant is a one-line diff whose blast radius is
every argument that rested on the old value. The audit that took the trial
count to 1000 dropped the p-value floor from 0.0083 to 0.000999 and thereby
made a Bonferroni-corrected alpha of 0.0017 expressible — while the comment
arguing Bonferroni was impossible still stated the old direction as live fact.
The conclusion there is unchanged for other reasons, which is exactly what
makes it dangerous: a true conclusion resting on arithmetic a reader can
recompute and find false. When you change a constant, grep for the number.

**Cite symbols, never line numbers, and never let an audit's all-clear stand in
for the audit.** The entry recording that grep listed the remaining sites by
line number and pronounced them historical — one of them was
`nullTrialCount`'s doc comment, a live claim about the old constant, cleared
because it sat between two deprecation notes. A line number is a phantom hash
in a different notation: it reads as a precise citation and resolves to
whatever is at that offset when read, with no way to fail loudly. And the
clearing is the worse half — **a wrong all-clear is more durable than no audit
at all**, because a site an audit has passed is a site nobody re-checks. Name
the symbol, and say what was checked so a later reader can redo it rather than
trust it.

**A changelog entry is written in the past tense, including about defects it
does not fix.** *"`compare`'s comment **still** states the old direction as
live fact"* was true when written and false three commits later, and it goes
stale in the direction nobody checks: it reports an **open** defect long after
someone closed it, so the next reader either re-fixes a fixed thing or loses
trust in the entry. This is the wrong-all-clear with its sign reversed — that
one vouches for a defect nobody re-checks, this one reports a defect nobody
re-checks. An entry records what was true at its commit; a **present-tense
claim about code outside that commit is a promise the entry cannot keep**. Say
what the state was, name the symbol, and when it is later fixed, name the sha
that fixed it.

**A requirement is not a checklist item.** If a property must hold for the
change to be worth anything, it belongs in the spec the implementation is
written against, not only in the walk-through — a checklist is walked once, and
a requirement has to survive the next person who does not walk it. Significance
must be distinguishable on the report without colour: P1b exists so a
high-but-insignificant score cannot look like a good result, and colour-only
encoding reverts that on the first photocopy, which is what happens to a
forensic report in practice.

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
| A file is added or deleted | the manifest's `Totals:` sentence — **by hand, it is prose** | the committer, in the same commit |
| A product decision is made **by Sean** | tick the box in the open-decisions list, record it in `HANDOFF_SUMMARY.md` | Ledger |
| Signing / repo access / build config changes | `HANDOFF_SUMMARY.md` §3 and §5 | whoever changed it, or Ledger on report |
| A known issue is resolved | delete it from `HANDOFF_SUMMARY.md` §5 — do not leave stale warnings | Ledger |
| Scoring behaviour or thresholds change | `ios/reference/ALGORITHM_EXPLAINER.md` | the committer |
| Any user-visible or report string changes | changelog entry must quote before/after, commit body must carry `Copy: changed` + the affected keys | the committer; Ledger reviews |

**A generator must not rewrite prose, and the seam that leaves is a row in the
table above rather than a rule nobody reads.** The manifest's `Totals:`
sentence is a sentence — `scripts/regen_manifest.py` deliberately will not
touch it, because a script with an opinion about the document's wording is how
a document loses its author. So the seam is real and permanent: **the rows are
mechanical, the header is editorial, and a patch that adds or deletes a file
has to do the header by hand in the same commit.** State the seam and let
`--all` catch the miss; do not close it by giving the tool the pen.

**A remedy line must name something that fixes the failure, and this seam
broke that.** `manifest-lines` caught a wrong header total (`312c8ae`,
correctly) and told the reader to run `regen_manifest.py` — which rewrites
rows and leaves the header exactly as it found it. Ledger measured it: inject
a wrong total, run the named remedy, re-run the check, **get the identical
failure.** That is worse than no remedy, because a reader who follows it
concludes the check is broken rather than that the header is wrong — the same
routing failure as `cited-commits` telling readers a reachable-but-unpublished
sha "does not resolve", which sent them to the one instrument guaranteed to
agree with the stale document. **Fixed: the message now names the hand-edit and
the exact number to write, and says outright that running the regenerator will
not clear it.** The general rule this earned: *a check that fires on prose must
name the edit, because the tool that fixes its neighbours cannot fix this one.*

**Correction to that test, and it is mine: *"does following it remove the
condition?"* is right for a drift check and wrong for a reminder.** Compass
wrote a correct three-step remedy for the Swift-file-added warning, performed
all three steps, and the warning still fired — it is keyed to the diff, not to
manifest state, so **no amount of correct work clears it.** A remedy that
implies it will is the routing failure one turn deeper: the reader has now
*done the work* and been told it did not take, which is worse than being sent
somewhere useless. **A reminder's remedy says so, and names the checks that do
verify the result.** Nothing in reading the diff distinguishes the two kinds;
only performing the steps does.

**The count is the artefact worth keeping, not the fault.** One string —
*"regenerate, never hand-edit"* — appeared at six remedy sites aimed at one
document, and exactly one was fixable by the step all six recommended. It was
written when nothing in the repo could regenerate anything and was never
revisited when something could: **text that was true about a world with no
regenerator.** Neither carelessness nor a landing defect, and the reason it
survived six sites is that a remedy is read as instruction and never as a
claim.

**And then that fix reproduced the defect it fixed, one clause away.** The
`Totals:` sentence carries three numbers under two different checks; the
remedy was corrected on the line total, which was the number that had fired,
while the file and Swift counts kept the unperformable one. Prism found it by
following the *other* warning's remedy. **The fix was applied to the number
that was reported rather than to the sentence that was wrong** — and the
untouched half then read as verified, because it sat inside a fix everyone had
just confirmed. Three of us verified that commit independently and all three
tested the half that had fired. So the audit rule generalises past
line numbers: **the unit an audit clears is the unit it actually exercised,
never the artefact it was aimed at.** When a fix lands on one symptom of a
shared cause, name the cause's whole surface and test each part of it
separately.

**The whole surface, swept: six remedies, and the tool's actual remit stated
once so the next one can be checked without a measurement.**
`scripts/regen_manifest.py` **fills integers into rows that already exist.** It
does not write prose, it does not add or remove rows, and it cannot recreate
the document. Every remedy that said *"regenerate the manifest"* for anything
outside that remit was unperformable: the line total, the file/Swift counts one
clause away, the missing-rows warning, the `docs_owed` reminder that fires on
exactly the add/delete patches needing the hand work, and the absent-manifest
warning — which named a capability that has never existed anywhere in this
repo. Each was verified by *following* it, and following the last one found a
defect in the script itself: it raised `FileNotFoundError` and exited on a
traceback while its docstring claimed it exits cleanly, the same shape as the
`ls-files` traceback fixed in `c9e2099`.

**Both sides of a generator/prose seam must state it.** The checks name the
hand-edit and the value; the generator prints on every run what it did not
touch. A bare *"fixed point after 1 pass(es)"* reads as *"the manifest is now
correct"*, and a silent generator reporting success is how a reader following
the old remedy concluded it had worked.

**When a sequencing or ownership decision changes, the record keeper is told
first, not last.** A record that accurately reflects a superseded decision is
worse than a visibly missing one, because it looks current and carries
authority — and the people acting on it are precisely those who were not in the
conversation where it changed. Telling the implementers and not the record
keeper leaves the written order contradicting the real one, with nothing
flagging the difference.

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

## 4c. The other recurring failure: correct where it was made, wrong where it went

Distinct from §5 and just as common. An artefact is written, it is accurate at
that moment in that place, and it is then used somewhere else — later, or
downstream — where it has quietly stopped being true. Nothing about reading it
reveals this. Four instances in a single day, all different surfaces:

| Artefact | Correct when made | Wrong at the destination |
|---|---|---|
| An enumerated list guarding against drift (watched build settings; the copy lock's surfaces) | matched every known case at the time | silent about the case that appeared next — and it does not decay visibly |
| A rule's prose description of a tool's behaviour (§1's skeleton wording) | described the intent accurately | had stopped matching what the generator actually does |
| A remedy line naming a fix script | the script existed, as an attachment | named a path nobody had, for the reader least able to work out why |
| "This patch is not on `main`" | true of the tree that had been fetched | the gap had closed minutes earlier |

The last one was a report *about* staleness that was itself stale, which is the
clearest available demonstration that this is structural rather than
carelessness.

Two habits catch all four, and they are cheap:

- **Verify against the destination, not the origin.** `git apply --check`
  against `origin/main` takes seconds. So does re-reading the code a rule
  describes, rather than the rule.
- **Fetch, then claim.** Any statement about the state of `main` — especially
  an absence — is made against a freshly fetched ref or not made at all.

And when a guard is a list, ask whether it can be a rule instead: a list covers
the ways something has already gone wrong, a rule covers the ways it has not
gone wrong yet.

**Four people swept the same defect and each sweep was correct about what it
enumerated.** The scopes were: the symptom that had fired, the function it
fired in, the document it named, and the string it was written with. Every one
of them was defensible, every one of them was complete on its own terms, and
each missed instances the next found — the string sweep missed the site
phrased *"regenerate it from `git ls-files`"* because that wording matched
neither search term. **A sweep clears the unit it enumerated, not the defect it
was aimed at**, and four independent sweeps do not compose into coverage: they
compose into four partial clears, each reading as complete.

So the only honest scope for a sweep is the **cause**, and where the cause has
no textual signature, the enumeration must be mechanical — which for a remedy
means executing it rather than reading it. Until such a harness exists, say
which unit a sweep enumerated when reporting it; **"I swept X" is a claim about
X, and reporting it as "closed" is the wrong-all-clear again, in the report
rather than in the artefact.**

**And such a harness cannot infer which remedies are reminders — it has to be
told.** *"The condition persists after the remedy"* is the signature of a
**correct reminder** and of a **broken drift-check remedy** at once: one
observation, two opposite verdicts, which is this document's own
predicate-one-short shape aimed at the fix for it. **The class is 2 of 39, and
its smallness is the argument.** `preflight.py` carries 39 remedy sites; being
diff-keyed is **necessary and not sufficient** for a reminder, because a
diff-keyed check whose finding concerns the *content* the diff introduced — a
non-optional field, an oversized commit — clears when that content is fixed.
Only the **presence-keyed** subset cannot clear: a file added or removed, which
no remedy retracts because performing it does not un-make the change. Both live
in `check_docs_owed`. **A class that small is proof no heuristic would ever
have found it** — a stronger argument for call-site declaration than any
percentage. **Declare the kind at the call site; do not derive it from
behaviour.**

**How this paragraph previously said "7, matching the `diff_args()` count
exactly" is the day's shape at its purest: two independent miscounts landing on
the same wrong number, and their agreement reading as verification.** `7` was a
grep over `diff_args` — two of those lines are its own `def` and a comment —
against 5 call sites, one of which is the shared file selector rather than a
check. **Corroboration between two instruments is worth nothing when both share
a method**, and the parenthetical below warns about that exact method one
clause earlier. The harness's own output disagreed with the document before
anyone looked: it declared 2.
(Count the calls, not the greps: a bare `warn(`/`fail(` grep also matches the
two function definitions, which is how 37, 38 and 40 were all quoted for the
same file within one hour. And an AST walk keyed on the NAME `warn`/`fail`
misses a reporter bound to a variable first — `report = fail if key in critical
else warn` — which is how 38 survived a mechanical recount: **the walk asked
whether a call is NAMED warn or fail where the question is whether it REACHES
them.** `exists` for `runs` again, in the tool built to end it. A count is
itself a claim, so it needs a floor that fails on a DROP: an anchor assertion
catches a rename to zero and cannot catch 39 quietly becoming 38.)

**The denominator is the finding, and it is the last wrong all-clear of the
day.** Six sites were swept and four of us called the surface closed. **Six of
39 is 15%; the other 33 remedies have never been performed by anyone.** Nothing
suggests they are broken — but nothing establishes they are not, and "no
failures reported" from a sweep that never reached them is exactly what a dead
check looks like. **The honest word is *unexercised*: not suspect, not clear.**
"Bounded, non-blocking debt" is the phrase to avoid here — it is accurate about
the priority and it quietly implies the 32 are probably fine, which is the one
thing nobody has established. Same discipline as grading a missing
parenthetical *"could not be checked"* rather than passing it, applied to a
sweep report instead of to a check. **A documented gap beats a fifth sweep
declaring closure.**

**Then two of the 32 were exercised and both were defective**, which moves the
count to 8 of 39 and puts a number on what "unexercised" was protecting: the
`pbxproj` remedy names a regeneration that only ever ADDS sources, so a stale
entry survives a run **that reports success**; and the `skeleton-drift` remedy
names a script that refuses precisely when the check has fired. Two of two is a
small sample and not one that suggests the remaining thirty are clean.

**The second of those is a variety no reading catches, and it is worth naming:
a remedy whose precondition is the negation of its trigger.** `set_dev_team.sh`
is right for first-time signing setup — the key absent from both files — and
the check fires only on a *mismatch*, which is every case except that one. Read
against the situation it was written for, the remedy is true; read against the
situation it is offered in, it cannot run. Not stale text, not a missing tool,
and invisible to review, because review supplies the charitable case
automatically. **Ask what state the check guarantees at the moment it fires,
then ask whether the remedy is legal in that state.**

**Both of those sites had been declared `fixes` an hour earlier, by the author
of the declaration harness, and both declarations were false.** That is the
mechanism working rather than a case against it. An omission gives a reader
nothing to disagree with; **`fixes` beside a remedy that does not fix is a
mistake with an author's name on it**, and it was disproved within the hour by
someone who executed it. A declaration is a claim, not a proof — what it buys
is not correctness but *falsifiability*, which is the property an imperative
never had. That is the whole answer to why six careful readers missed six
instances of one string: **nobody audits an instruction; everybody audits a
claim.**

One caution attached to the harness that enforces this. Its declaration check
is structural, but its grading of a `reminder` — that the text says it will not
clear — matches **wording**, and a prose predicate goes stale in wording while
staying true in substance. That is this document's dead-check shape arriving
through the tool built to end it. It matches a disjunction of phrasings and
carries an opt-out for a correct paraphrase; **the stopping rule is that if the
opt-out is ever needed twice, the predicate is deleted rather than extended.**
A false positive there costs a correct remedy being reworded to satisfy a
regex, which is how a tool starts training the bypass habit `§5b` exists to
prevent.

**And the harness reads the annotation while the human reads the string, so a
site can pass it and still send the reader nowhere.** Correcting
`check_skeleton_drift`'s declaration to `state` was right and left the remedy
text naming `set_dev_team.sh` — a script that exits 1 in every case this check
fires on. **A true declaration beside prose that contradicts it** is not a
false claim, so the harness's bound does not reach it: the machine-readable
half is correct and the half a person acts on is not. **Repair follows what the
check reads.** Twice today the fix landed on the audited representation while
the used artefact stayed wrong — the reminder count corrected in this document
while the script already printed the right number, and this declaration
corrected while the sentence stayed unperformable. **Ask which artefact the
reader acts on, and fix that one first.**

Two gaps in the count machinery, **one now guarded and one still only named**.
A `MIN_SITES` floor catches 39 quietly becoming 38; it does not
catch **39 staying 39 while one of them stops being reachable** — a check
dropped from `main()` keeps its call site and its declaration and never runs,
which is `exists` for `runs` one level up from the alias and the same gap the
doc-drift bands had. **Walked by hand on 2026-09-06: 17 `check_` definitions, all
reachable, none orphaned — a measurement of that day and not a guard.**
*Measured empty today* is a different claim from *safe*, and writing the first
while meaning the second is how this section's other entries began. **The walk
is now in `check_remedies.py` and runs on every preflight, so the reading is
no longer load-bearing** — top-level `check_*` only, excluded by construction
rather than by a name exception, because an exception list is the
enumerated-list failure this repo has hit twice. The floor itself is still the
named-not-guarded half: a pinned integer a human bumps. And the annotation says
what a remedy *is*, never that it *works*.

**The harness enforcing all of this was, for its whole first day, not run by
the thing that reports on the tree.** `check_remedies.py` was standalone:
`preflight --all` printed `clear (0 advisory)` on `f3e585f` while the harness
exited 1 on the same tree. **A gate nobody invokes is a file** — this section's
subject arriving in this section's instrument, `exists` for `runs` one layer
above the alias it was built to catch. It survived three separate reports of
having landed — two from the agent who wrote the wiring and one repeating them
— because every one of them quoted the harness's own exit code and never
`preflight`'s. (Counted, not estimated: the claim first appeared in the report
of `8ae183b`, was repeated for `f3e585f`, and was carried forward once by a
second agent citing those. Two agents, three reports.) **A check's own exit code
cannot tell you whether anything invokes it**, so the measurement that closes
this is the one already in force for everything else: run `--all` and read what
it says. Wired as `check_remedy_declarations()`, advisory, reporting the
subprocess's own output, with an absent script reported **NOT CHECKED** rather
than passed — a silently missing gate reads exactly like a clean one.

**The wiring itself was the last instance.** `check_remedy_declarations()` was
reported landed twice and appeared zero times in `preflight.py`: the harness
ran, exited 1 on an undeclared site, and `preflight --all` reported clear. It
survived both reports because every report about it quoted **the script's own
exit code and never `preflight`'s** — the tool built to end `exists`-for-`runs`
became its own last instance, and the habit that caught a `RecursionError` in
the same file an hour earlier was the habit nobody applied to the gate.

**The layer that failure sits at is one above `exists` for `runs`: REPORTED for
EXISTS.** The wiring was described in enough detail to be checkable — a
function name, `rc=1` and `rc=0` in both directions, a negative test — and the
described artefact was in no commit in `git rev-list --all`. Every rule in this
section keys off a hazard in the artefact; **none of them covers the report
about the artefact**, and reading the report is the one step everyone always
does. The cheap defence is the one that caught it: `git log -S <identifier>`
against the claim, and re-verification from a fresh clone of the pushed sha
rather than the tree the work was done in.

**One number for the shape of this round, because it is the only measurement of
the duplicate rule anyone has — counted rather than estimated, since "roughly
fourteen" was the first version of this sentence.** 22 distinct patch
attachments arrived for one finding, carrying 23 commits between them; 10
commits landed. The remainder were duplicates, no-ops, supersessions, or
halves declined after someone diffed them first. The unit matters and it is
the section's own lesson: *patches sent*, *commits inside them*, and *commits
landed* are three different numbers, and a ratio quoting two of them without
saying which is the count-versus-grep error in a new costume. **All seven were caught at the landing and none at
the building** — the check-before-apply half was in force all day and the
announce-before-building half never was, so the cost fell entirely on work
already done. That is the asymmetry with a number attached: the half we keep
is the cheaper one to run and the more expensive one to rely on.

**The class this section has no instrument for: a true statement rendered on
the wrong surface.** Every entry above is a claim that was false in the tree.
Task #12's free-tier round produced six defects that were none of them false
anywhere — each was correct about something and wrong about where it landed.
`suspectExclusionReason` rendered only inside a section gated on `isUnlocked`,
so the strongest finding the engine produces was the only gated output. Three
engine strings ended by promising a factor breakdown the free tier gates, and
a fourth kept one positional word after three clauses were removed. A fixed
consequence line would have asserted *"can be ruled out"* above the one arm
whose own string says the opposite — re-asserting by copy the ~27.8% LiDAR
false positive task #14 removed from the engine, **through a layer that
touches no engine code.** A red border and an accent-tinted label asserted
urgency and interactivity that neither element had. A design audit checked
every string against the copy deck and never checked which side of
`isUnlocked` an element sat on.

**No check we own reaches any of it, and a cheap one does not exist.** Every
check in `preflight` reasons about the tree; these defects are properties of
the *composition* of two individually correct artefacts — a sentence and the
surface that renders it. A script would need a model of the paywall to tell a
true sentence on the right surface from the same sentence on the wrong one,
which is a second specification rather than a lint, and a lint that passed on
both versions would be worse than an honest gap. **Recorded as uninstrumented,
in the same form as the unexercised remedies above.**

**The instrument that did work, stated so it is not mistaken for luck:** a
named reader checking the string on the surface it will actually render on.
Six for six, caught by four readers, and by none of `preflight`,
`check_remedies.py`, or the parse gate. **The uninstrumented class includes
placement, not only wording** — reviewing the sentence is not reviewing the
surface, and gating is invisible in the artefact under review.

**The general form, which is tighter than enumerating the surfaces: a claim
names a subject, and the reader assumes the shared one.** Paywall, working
tree, local branch, stale attachment — four surfaces, one substitution, and
stating it this way covers the next one instead of waiting for it. Inside this
round: an advisory measured against a working tree
containing its author's own unlanded commit; a push reported for two days that
had only ever been local, because the sandbox holds no write credential; a
patch attached and described in detail that contained three unrelated landed
commits. Three people, three artefacts, **one failure — the measured subject
and the shared subject were not the same object.** A clone of your own
checkout inherits only what you fetched, so it is not a clone of the remote;
one of these produced `unable to read sha1` and a *blocking* preflight that
was pure artefact. The cheap checks are `git for-each-ref refs/remotes`,
`git cat-file -t <sha>`, and cloning the remote by URL — not re-reading your
own diff. **And this is why the instrument worked on the other defects at all:
they were caught because someone could fetch the artefact and re-run the
claim.** The one nobody could have caught was the local push, whose subject
was unreachable by construction.

**A fourth instance closed the loop: a teammate tested an attachment twice
after its replacement had already landed.** The subject was retrievable,
correct, and *no longer current* — so "fetch the artefact" is not sufficient;
the fetch has to be of the shared tip. `git log --oneline origin/main -6`
before testing an attachment, and it is the same substitution as the other
three.

**Which makes "read it more carefully" the wrong remedy, and this is the
operational form.** A reviewer looking at a mockup sees an element and a
sentence about it and has no way to know one contradicts the other, because
the fact that decides it is a Swift conditional in a different file. So the
check is not more care: it is **for any element, name which side of the gate
it renders on** — done against the code, every time. It cannot be done from a
picture, and it cannot be done by whoever is reviewing the picture.

**A fifth instance inverted the failure direction, and it is the one that
decides how a verification number should be read.** Every earlier instance
made something absent look fine. This one makes something fine look absent: a
per-commit check run from a clone of one's own checkout reported *1 BLOCKING*
and `unable to read sha1` on a file in a landed, valid commit, because a
partial clone inherits only the objects that had been fetched. The same
substitution, opposite sign — so **a local clone's result is not evidence in
either direction**, and the rule is to verify per-commit history from a clone
of the remote by URL, never from a clone of your own working checkout. The
matching hazard is at the other end of the same step: **a bare fresh clone of
this repository honestly reports 1 advisory, and it is the refspec one** —
`remote.origin.fetch` defaults to `main` only, which the guard checks as its
own precondition. Apply the remedy the advisory prints, re-fetch, *then*
measure. "0 advisories" is therefore a claim about a clone whose config has
been repaired; the surface being substituted is the clone's own configuration,
and the next person to verify from a fresh clone will see 1 and have to decide
whether it is a finding. It is not.

**The mechanism, because it is what makes the direction structural rather
than lucky.** A blob that was never fetched becomes a missing *file* on disk,
not a corrupt one: `git status` shows ` D`, and `swift-parse` treats an
unreadable input as a failure rather than a skip — a deliberate choice in its
doc comment. So a partial clone degrades toward *refusing*, and what you would
file off one is a phantom defect, never a phantom clean. Tip work from a local
clone is safe, because the tip's blobs are the ones you fetched; history work
is not.

**The three procedural steps, enumerated on purpose.** The class description
above is deliberately general — a list of surfaces invites checking the list
instead of the question. Remedies are the opposite: they are performed, not
matched, so they belong as a list.

1. Apply the refspec remedy and re-fetch **before** measuring advisories.
2. Clone the remote **by URL** for any per-commit or historical check.
3. `git log --oneline origin/main -6` **before** testing an attachment.

Three ways this was got wrong in one round, by three people, each covered by
one step.

**A remedy has to be chosen by failure direction, and the two directions want
opposite things.** A check that degrades toward *refusing* is loud by
construction: it costs an hour and what it needs is a note telling the next
person not to panic — which is why the refspec advisory and the partial clone
are documented above rather than instrumented. A defect that degrades toward
*looking fine* is silent by construction: it costs a shipped artefact, and the
only remedy is that someone goes and looks. **The third render site is the
proof.** `suspectExclusionReason` is read in three places — the free-tier
banner, its `scarDirectionSection` copy, and `PDFReportGenerator`'s callout —
and the third drew a red-filled box headed `EXCLUSION WARNING` over a string
that may deny an exclusion. Ten commits and three independent 0-advisory
verifications passed over it, because no check reads the composition of a
sentence and its frame. It was found by someone re-reading code they had
already signed off.

**So the rule, in its counted form: a duplicated string is only an invariant
if EVERY render carries the same claim — and the render count is whatever
`grep` says.** Two sites were audited this round because two were remembered.
When a value is read in more than one place, enumerate its render sites from
the code and write the count into a comment at each site, so the next reader
inherits the count instead of the recollection.

**And a de-styling diff is when to re-measure the frame, because removing a
decoration can reveal a layout fault rather than create one.** The PDF
callout's box was a literal 60pt tall with its body drawn 26pt down — about two
lines — while the three strings it renders measure 249, 470 and 235 characters
from their format templates, i.e. roughly three, six and three lines at that
width. Every path had overrun since 2026-07, the worst by around 45pt into the
line below — and that worst case is the LiDAR-inconclusive path, the one that
*denies* an exclusion, whose text an investigator most needs in full. It was invisible because a filled tinted band makes overflowing
text read as text on a band; a hairline border draws the boundary the overflow
crosses, so the neutral treatment exposed the fault it is now blamed on
introducing. **A frame that cannot fit the real string is a layout defect and
never a licence to shorten locked copy** — and where the string *is* the
finding, a clipped exclusion is a missing one. Measure the body and size the
frame to it; no check reads a box's height against its content, which puts this
squarely on the silent side above. **The count that fixed the frame was not the
count that described it:** four different figure-sets were quoted for these
three strings inside one exchange, including a total presented as a maximum,
which would have sent a tester to export the case least likely to overflow
while calling it the worst case. Measure from the format templates in the
source, and name which path is worst rather than a character count alone.

**And the box was never the defect — the defect is a pairing, which is the
counting clause applied to layout.** A wrapping `.draw(…maxWidth:)` followed by
a literal `y += N` encodes a line count its author guessed. Fixing the one
instance you were shown leaves every sibling live: grepping the *pairing*
rather than the symbol found seventeen more on `main`, all predating this
round — the scar narrative and both motion lines, per-factor notes,
impact-profile lines, the fingerprint and tool-mark summaries, audit-trail
lines, the examiner attestation, the algorithm-constant explanations. The scar
narrative's `.inconsistent` form runs about 268 characters against an advance
of 40 and has been overlapping the lines below it since 2026-07. **So: when a
defect is a pairing of two constructs, grep the pairing, not the symbol** — the
same failure as accepting the set of render sites you were handed.

**A near-miss is the same defect as an overrun.** The disclaimer box fit today,
about 520 characters in 86pt of a literal 130, and was one edit of locked copy
away from clipping with nothing to say so. A margin nobody measures is not a
margin anyone is maintaining, and that string is the one whose truncation is a
liability rather than an inconvenience: a clipped disclaimer is a report
claiming more than the algorithm can support.

**None of this is verified, in the strong sense.** `boundingRect` runs at draw
time, so the heights are real — but no page has been rendered by anyone, and
four people produced five figure-sets for three strings while arguing about
them. The defect does not depend on any of those numbers, because a literal
advance is wrong regardless of the number. **The fit does, and the only
instrument for it is exporting a PDF of all three paths.** That is what the
checklist item is for; it is not doing the arithmetic again.

**Quote a measurement with its method, or do not quote the number.** Five
figure-sets circulated for three strings in one exchange, and the outlier was
not a worse estimate — it was a *different quantity*: the three strings summed,
less the shortest, presented as a maximum. Two of the others differed only as
template length versus rendered length and agreed on the ranking. An unmethoded
figure cannot be checked without redoing the work, so the next reader treats
the most recent one as measured; that is the corrected-count substitution with
a helpful teammate as the surface. **The manifest total is the same class:
measure the landed total, never add a delta to a remembered base** — a correct
delta against a base that has moved is a wrong number arrived at carefully.

**Measuring a frame can change a failure mode rather than remove it, and the
comment has to say which.** The disclaimer box is drawn at a literal `y: 430`
on a cover whose duplicated-case note sits at a literal `y: 574` — 144pt of
headroom against roughly 120pt of current text, which is arithmetic on two
literals and depends on no estimate. A literal height clipped *inside* its own
frame; a measured one grows, so copy past that headroom now overlaps the note
instead of truncating. **That is the better failure — an overlap is visible on
the page and a truncation is not — but it is not safety**, and a comment that
implies otherwise is the round's own defect in miniature. Every measured frame
on a fixed-offset page has this property: the helper returns the height
consumed, which is exactly what a fixed-offset sibling cannot see. The honest
fix is a flow layout for the cover, in its own diff. On a second pass none of
`drawWrapping`'s seventeen call sites shares a function with an absolute
`y:` literal, so the cover is the only page where this applies today.

**A commit that closes a class must count its own residue, and this one did
not.** The pairing fix converted seventeen sites and stated that the twelve
remaining were fixed literals whose length the author could measure. Grepping
the pairing again against the landed tree returns **twenty**, and four are
content-dependent — including one live overrun: the same motion sentences that
had been converted on the wide page, redrawn in a half-width column where 99
characters at 10pt take three lines against an advance of 28. **The sentence is
fixed; the column is what makes it wrap.** So the enumeration failed the same
way it failed for render sites, one level in: the fix followed the *string*
rather than the pairing. **Recount the residue from the landed tree, and state
the count as a measurement rather than as the complement of what you changed.**

**And one pair cannot be settled by any measurement we make.** A striation
exclusion's `reason` is free examiner text with no length bound anywhere — the
input is a vertical `TextField` validated only for non-emptiness — drawn at an
advance of 12pt in a 241pt column on the page written to be read by opposing
counsel. **An unbounded string against a fixed advance is wrong at some length
regardless of whose arithmetic you use**, which makes it a bound at the input,
not a measurement at the frame: a product decision, not a layout fix.

**A decision list is a worse place for this failure than a checklist, and it
has now happened there.** A ticked decision recorded that a hard-block gate is
safe *because* taking the override is recorded and surfaced, and cited the
field by name; that field has zero references in Swift on the landed tree, and
the spec clause requiring it lives in a document the same author owns. **A spec
and a decision citing it read as complete by agreeing with each other, and
neither of them is the tree.** So the rule generalises past symbols: **grep the
pairing of a spec clause and its implementation, not the clause.** A checklist
is ours to walk and can be re-walked; a decision list is the record of what the
customer chose, so a tick there that was never earned is a wrong all-clear with
provenance attached. When a decision's stated safety condition is a named
field, the tick is only honest while that name resolves in the tree — say so
beside the tick rather than leaving the reader to check.

**And a corollary to the duplication rule, because it cuts the other way.**
Two renders disagreeing is not automatically the invariant failure: **two
verdicts, each rendered by the surface that owns it, is correct design.** The
30-shot service gates even lighting per shot type and the scar service requires
it unconditionally; each chip row matches its own service, and deduplicating
them would erase a real distinction. Check whether the two sites read the same
*value* before concluding they render the same *claim*.

**A grep for a pairing finds the shape you named, and the file held a second
one the grep cannot reach.** `drawCenter` is not a wrapping draw at all: it
takes no `maxWidth`, so it never wraps and never clips. It centres by measuring
the string and subtracting — `x = (rect.width - size.width) / 2` — which goes
**negative** for a string wider than the page, running the text off *both*
edges with its middle intact. **A value that loses its beginning and its end
while looking deliberately centred is the worst failure in this family**, and
two of its call sites take unbounded user text: the case number and the cover
attestation. Losing the ends of "Documented by: <name> — Badge <n> — <agency>"
leaves a plausible fragment, so that failure is a *misattribution*, not a
missing line — and not implying an attribution the app cannot support is the
entire point of the examiner work. **So a pairing grep is a lower bound on its
class, not a census of it:** it enumerates the shape you already understood.
Ask what *else* consumes the same unbounded input, in the other direction.

**Which is why the remedy for unbounded text is a bound at the input.** The
same free examiner `reason` reaches two draws in two files — the tool-mark
column and, through `displaySummary`, the audit page — and the same
unlength-limited case and examiner fields reach eight `drawCenter` sites. A
measurement at each frame fixes none of them properly: it converts each into a
different visible failure, one site at a time, forever. **One validated bound
at the field fixes every consumer, including the ones nobody has enumerated
yet.**

**And the search direction was the flaw in every pass, including the ones that
found things.** Each started from a *draw* and followed the value it already
knew about. That reaches a field's own draw, and with effort the derived one,
but it cannot reach a *second* unbounded field at all — a search seeded with
`reason` never finds `examinerName`, because they share no substring.
**Enumerate the free-text inputs and find their draws, not the reverse:**
thirty-six `TextField`s in `Views/`, of which two are unbounded and reach the
report — `reason` on the tool-mark page and, via `displaySummary`, the audit
page; `examinerName` on the custody page through `attributionSummary`.
`.textContentType` is a keyboard hint, not a limit. Going draw-first only ever
re-finds the value you started with, which is why several passes produced a
growing count of the same field.

**A related disguise, from the same rule applied to a whole spec rather than
its named fields: all four of the appendix's per-photo note conditions are
unbuilt, not the one the ticked decision cited.** `gateOverridden`,
`sharpnessScore` and `PhotoType.isAnalysisShot` have zero references;
`isBlurry`, `isTooFar`, `isTooClose` and `hasMotionBlur` are *declared* on
`QualityFlags` with `false` defaults and never assigned anywhere, while
`issueDescriptions` and `hasIssues` have no readers. `buildQualityFlags` sets
exposure and roll only. **A field that exists, decodes, and always reads
`false` is a worse disguise than an absent one** — grep finds it, the type
checks, and every consumer silently takes the clean branch. So checking a spec
against the tree means checking that each condition is *assigned*, not that its
name resolves.

**Swept past the spec's own list, exactly four properties in the app are never
written** — `isBlurry`, `isTooFar`, `isTooClose`, `hasMotionBlur`. The
consequence is the house rule from §5 arriving through dead state:
`issueDescriptions` is the user-visible claim, and with those four dead it
reports a photo as having no blur, no motion blur and no framing problem.
**An absence asserting the clean case.** They are audited at the declaration
rather than deleted, because the work that wires them needs the spec's
vocabulary.

**A sweep for never-written properties must check initialiser arguments, not
just assignments.** `isHighlighted` in `PaywallView` looks like a fifth
instance to a naive grep and is not: it is set at the call site from an
expression. A sweep that reads only `x = ` reports a false positive beside the
real ones — the same disguise pointed the other way, and a census that includes
a phantom is not a census.

**Widened, because the initialiser-argument form was one of several and the
error scales.** Swept over every `var x: T = default` in the tree, a sweep
modelling only `name =` returns thirty-three; adding initialiser arguments
brings it to nine; adding compound assignment (`total += …`), `inout` (`&pixel`
handed to a data pointer), mutating-method sinks (`.store(in: &cancellables)`)
and `$name` bindings collapses it to exactly the four. **So "never assigned" is
not `name =` plus one exception — it is every form that writes the storage, and
a sweep that models fewer reports phantoms in proportion.** Five phantoms
beside four findings is not a census with noise in it; it is a census a reader
cannot use, because the true rows are indistinguishable from the false ones.
Same failure as reading `exists` for `runs`, one level down: the walk asks
whether an assignment appears where the question is whether the storage is ever
written.

**And the verification recipe in this section needs one more sentence, or it
misfires for the next person who follows it.** A `git clone --single-branch`
inherits a `main`-only refspec and therefore reports **one** advisory — the
`script-currency` one — while a plain `git clone` of this repository reports
zero, because it gets the full refspec by default. Both were measured. Following
the printed remedy clears the single-branch case to zero. So "clone by URL and
measure" is under-specified: **name which clone, because the flag that makes a
clone cheap is also the flag that makes the guard fire.** A recipe that is
correct where it was run and wrong where it is repeated is this section's own
subject aimed at its own instructions.

**A partly-implemented clause can read as compliance when its halves pull in
opposite directions.** Spec §2.4 of the capture-notes work says two things: a
score is never annotated or hedged, and the findings section carries a
cross-reference to the appendix page. The cross-reference has zero references
in Swift — so **the constraining half is satisfied and the informing half is
missing, and the constraining half is satisfied *by* the omission.** A reviewer
checking "is any score hedged?" gets a clean answer from a tree that never
implemented the clause at all. **When a requirement both forbids and requires,
check the requiring half first: the forbidding half cannot distinguish
compliance from absence.**

**And the checklist item written for it would have hidden it, in the worst way
available.** "A factor whose inputs include a flagged photo shows the §2.4
cross-reference" is walkable by a human on a device — who would find no
cross-reference to look at and record either a pass or a defect in their own
method. **That is worse than the unearned tick**, because a tick nobody acts on
merely misinforms, while an item a human performs converts their effort into
false evidence. An item must be falsifiable against the tree it will be walked
on; when the mechanism it tests is absent, strike it with the reason and
re-enable it in the diff that implements the mechanism — never leave it live and
unpassable.

**A specification that arrives after its implementation is a different
artefact, and the inversion is worth exploiting rather than merely regretting.**
Written as a guide it records intent; written after the code it must be
reconciled against the landed tree, and a reconciliation is falsifiable in a
way intent is not. Doing it by reading the tree rather than by remembering the
patch is what found §1.2 unbuilt on the surface it was written for: the
guidance band, the arm-time attestation and the review badge all shipped on the
scar path and none on the 30-shot protocol camera, so those shots carry no
guidance and can never record a declined attestation. **The property meant to
drive capture-time guidance has exactly one consumer, the report filter — so
the report will faithfully note a contaminated photograph the app never warned
the user about.** Deciding what to *report* is not deciding what to *tell the
user*, and one property serving both reads as coverage.

**Which sets the standard for the closing section of any such reconciliation: it
ends in open items, not a summary.** A reconciliation reporting only its
successes is precisely the artefact this section is about. And **a citation is
provenance only while its destination can be opened** — six references to a
spec absent from the repository read as authority for a month, so landing the
document is not enough: the citing artefact has to name the path.

**And a row that is amended each time it is checked accretes into its own
failure.** The task #4 entry was correct at every edit and ended as one
paragraph asserting both that §2.4 had zero references and that §2.4 was built
— two accurate edits landing minutes apart, producing a row a reader cannot
act on. **Append-only is not a safe default for a status row**; separate what
is true now from how it was found, and put the current state first. The same
applies to a decision tick whose safety condition changes state: the tick
records what was chosen, a sentence beside it records what the tree does, and
they are different claims that must be updated independently.

**A copy decision recorded only in the document that made it is misplaced, by
the same test as a finding recorded only in §4c.** The reader of a copy
deviation is whoever next edits a locked string, and they look at the lock —
so the ratification belongs there, not in the spec section that reasoned about
it. **Ask which artefact the reader opens, then write it there.**
**And a count of commits on a moving branch cannot be written down.** A row
documenting the lapsed isolation guarantee recorded 99 Swift commits and
measured 100 one commit later — the very failure the row exists to describe,
inside the sentence describing it. Where a number moves with the tree, record
the command and not the figure.

**And a count that SCOPES something is a worse case than a count that reports
it, because staleness changes what the sentence authorises rather than what it
says.** The copy lock read "the 16-string copy inventory" while the table had
grown to 17 rows, so **the lock had silently stopped covering exactly the two
strings that round added** — a stale report merely misinforms; a stale scope
withdraws protection from the newest members, which are the ones most likely
to be casually reworded. Same proxy shape as row five, in the sentence that
defines the lock's own scope.

Which distinguishes the two cases in review: **when a figure appears, ask
whether anything is scoped BY it.** If it is, the repair is not a fresher
number — writing "17" is the identical defect with a later expiry — it is to
scope by the thing itself, whatever its length, and record the counting command
for any reader who needs the figure. Swept the tree for the pattern after
landing it: the remaining written counts (`42 tracked Swift files`, `all 43
remedy sites`, `Totals:`) are **reports at a commit, checked by tooling that
recomputes them**, and none of them scopes a rule. **A count under a check that
recomputes it is safe; a count in prose that authorises something is not.**
### 4c-vii. A boundary enforced at a control does not bind the paths that skip it

`hasMotionBlur` was rewritten to be written from a measured window rather than
a live gate, and the argument for the window was exactly right: a photograph is
blurred by movement during the exposure, so a peak from while the examiner
walked up to the vehicle is not a fact about the photograph. The window was
then opened at `armAutoCapture()` — which is a control, not a moment. The
manual shutter is deliberately never disabled on gate state (Item 2 §2.4, the
half of the hard-block decision that makes it shippable), so a manual capture
reaches `performCapture` with `armAutoCapture()` never called; and
`resetAutoCaptureStreak()` disarms after **every** capture without clearing the
peak, so a second manual shot inherits the first shot's. On both paths the flag
reported motion measured before the frame existed — **the same over-claim the
rewrite existed to remove, reintroduced by the mechanism of the fix.**

**When a rule is about an interval, enforce it with an interval.** A boundary
opened by a control binds only the paths that run the control, and the paths
that skip it are precisely the ones nobody reasons about while writing the
control. A trailing window ending at the event needs nothing to open it, so
there is no path that can skip opening it.

The general form, and it is the one to carry: **a correct argument constrains
what the fix must achieve, not where the fix may be installed.** Reviewing the
argument is not reviewing the installation, and here the argument was quoted in
three documents while the installation was wrong in two paths. Verify the
mechanism against the paths, not against the reason.

Two smaller findings from the same repair, both worth keeping:

- **Two guards that look redundant may each be load-bearing for a different
  property.** The rolling buffer's prune bounds memory; the read-time window
  filter decides correctness. Wall-clock advances with no gyro callback, so
  staleness is only detectable at read time; the filter alone frees nothing.
  A mutation run killed each only through the assertion the other cannot
  satisfy — so "these two do the same thing" would have deleted a real guard.
- **An assertion can pass for the wrong reason and still kill nothing.** The
  first stale-reading assertion used an under-threshold magnitude, so it held
  whether or not the window filter existed, and the mutant that deleted the
  filter survived it. A stale **high** reading was the case that discriminates.
  Choose assertion inputs that can only pass because of the thing under test —
  the set-membership form of §5's never-let-an-absence-assert rule.

### 4c-ix. A line number is a citation that rots without a diff

Swept every `File:NNN` citation in the docs at `64adfb2`. **Seven of nine were
wrong, and two of the seven were written by the two patches that were
themselves repairing citations.** Full table in
`EVIDENCE_APPENDIX_CAPTURE_NOTES.md` §4.2.2; the mechanism belongs here.

**A patch that adds explanatory comments above the code it cites pushes that
code down, so the act of documenting a site is what breaks the citation to
it.** The glyph fix added 41 net Swift lines across exactly the two files every
one of those citations pointed into. Each number was correct when its author
checked it and wrong when the same commit landed — the §4c shape with no
elapsed time at all.

**And a sweep for dead identifiers does not catch live identifiers at dead
addresses.** `64adfb2` correctly `git grep`-ed every `*.md` for a deleted field
name; the line numbers it wrote in the same patch already resolved to comment
prose. The identifier is checkable by grep and the address is not, so the two
failures need two different audits — and passing the first reads as having
audited the citations.

**A line number is a claim about a file's layout that nothing recomputes.**
Contrast the manifest counts: also numbers about the tree, but `preflight`
recomputes them and fails loudly, which is exactly why §4c concludes a count
under a recomputing check is safe. A line number is wrong silently while
*looking* like precision — **strictly worse than no citation**, because a
reader who follows it lands on unrelated code and concludes the claim is
confused rather than the pointer.

**Rule: cite by SYMBOL — type, member, or function — never by line.** Where a
range matters, name the enclosing member. Audit a locked literal by grepping
the string, never by jumping to a number.

**This is the presentation-channel class one level further out.** `confirm.no`
passed a lock that inspected only characters; these citations passed reviews
that checked whether the claim was *true* and never whether the pointer still
*resolved*. A reference is a channel too — the one no check here covers, and
the only class today found by following pointers rather than by reading or
running anything.

**And the reason to cite by symbol is not only that it survives edits — it is
that a symbol citation is CHECKABLE and a line number is not.** That is the
same property that makes a count under a recomputing check safe: `git grep` can
confirm a named type, member or function still exists, and nothing can confirm
a line still holds what it held. **So the rule earns a check rather than
discipline**, which is where every other rule in this section ended up:
extract the symbols cited in `*.md` and confirm each resolves in the tree.
Swept by hand after landing this — every remaining `File:NNN` in the tree sits
inside §4.2.2's evidence table, where the wrong numbers are the record and must
not be repaired.

**The one it does not catch is the one that caught us: a symbol that resolves
while the claim about it has gone stale.** Grep proves the address is live, not
that the sentence is still true — so symbol citations move the failure from
*silent and undetectable* to *silent and detectable*, which is the whole gain
and is worth being precise about. **A checkable pointer is not a verified
claim**, and the citation audit is a smaller thing than a review.

### 4c-x. "Count the rows and count the branches" is a check, not a habit

The sixth note row went two rounds unrendered: `hasMotionBlur` was persisted,
decoded, duplicated, locked and given a row in the appendix's condition table,
while `PDFReportGenerator.captureNotes(for:)` had five branches. **The
distinction existed, the copy existed, the field was persisted, and nothing
carried it to the artefact that makes the claim.**

The diagnosis landed as a rule — *a field that records a distinction is not
done until the artefact that would over-claim without it reads it, and "the
artefact" is the renderer, not the model* — with the audit stated as a
comparison anyone could run: count the rows in the lock, count the branches in
the renderer, and if they differ the lock describes a report nobody generates.

**That comparison is mechanical, so it should not be a habit.** Every other
rule in this section that could be checked ended up as a check, for the reason
§4c gives about counts: **a claim under something that recomputes it is safe,
and a claim under discipline is safe until the day someone is in a hurry.**
The rule was found three times today by three people reading carefully; that is
the signature of work a tool should be doing.

`check_note_rows_implemented` reads the copy table that OWNS the wording and
asserts each row's string appears in the renderer. Advisory, since a new row
legitimately lands before its code.

**Deliberately narrow, and the scope matters more than the check: it matches
the note STRING.** So it proves the copy is present and reachable in the file —
**not** that the predicate guarding it is correct. A row guarded by `if false`
passes. It closes "specified but never rendered" and nothing else. This is the
same limit the symbol-citation check has: **a checkable pointer is not a
verified claim**, and a check whose scope is not stated gets read as covering
the claim next to it.

**Two details from building it, both instances of rules already here.** Its
table anchor warns when it locates no table, because **an anchor that silently
finds nothing is an absence asserting a pass** (§5) — and that guard fired on
the first run, since the real header reads `| Trigger | Note |` and the check
looked for `Condition`. Without it the check would have reported a clean pass
over zero rows, which is the failure it exists to prevent, in itself. And it
was mutation-tested by replacing the motion note's string and confirming it
names that row: **a check written to catch a defect must be shown to fail on
it**, or it joins the class it closes.

### 4c-xi. A check scoped to the shape of its first instance reads as covering the class

`check_note_rows_implemented` compared the §2.2 note TABLE against the
renderer. §2.3's all-clear variants are BLOCK QUOTES, so with
`allclear.partial` specified and unrendered `preflight --all` reported clear
and silent. **A row with no branch and a VARIANT with no branch are the same
defect in two markdown shapes.**

I scoped it to a table because a table was the instance in hand, and the
population is every locked string the renderer is supposed to emit — so the
check committed the error §2.3 is itself about: **it answered a question about
a member and read as an answer about the set.** Rule: **name and scope a check
by the population, not by the artefact the defect turned up in.** This is
§4.1's three-times-widened lock scope arriving at a check.

**The widening is not a verbatim match, and this is the Tech Lead's caution
rather than a detail.** A locked TEMPLATE (`NN%`, `M of N`) and a locked
SENTENCE are different artefacts, so a naive sweep over "every locked string"
produces false absences. And **the widened check has to land WITH the doc
marking specified-not-built rows**, or immediate advisories normalise the
clear run it exists to protect. §2.3's held variant is therefore *declared* in
the check, so **an intentional hold reads as a hold and not as an oversight** —
lifting the declaration without building the branch is caught.

**Two bugs on the way in, both producing a WRONG reading rather than no
reading.** The blockquote parser flushed on the loop's tail instead of at the
first non-quote line, concatenating both variants into one string that matched
nothing — so **the check blamed the variant that IS rendered**, sending a
reader to correct working code. And renderer literals wrap across source
lines, so a naive substring test reports a present string as absent; the
comparison collapses whitespace on both sides.

### 4c-xii. Count how much of the population carries the default

Found by the Designer against a selector I wrote, and it is the sharpest
instance of §4c-vii on this board. §2.3's owed selector was
`captureConditionPhotos(in:).contains { !$0.motionMeasurable }`.
`motionMeasurable` is written on exactly ONE path
(`ScarCaptureView.performCapture`); `false` is the struct default; and
`CameraService`'s single `CapturedPhoto(...)` call passes it **not at all**
while constructing every protocol analysis shot. **So the predicate is true on
every real report, the qualified all-clear becomes the only reachable variant,
and the plain sentence is dead on arrival — the always-firing qualification the
lock forbids, arriving through the SELECTOR instead of the wording.**

**The reusable half is the sentence that was already there.** The section said
`motionMeasurable` "defaults `false` everywhere else" as *reassurance* that the
trigger reads the persisted model rather than a gate. **The same words say the
trigger is true for almost every photograph in the app. Same sentence,
opposite conclusion — and the reassuring reading is the one a reviewer reaches
for.** A population statement wearing a safety note's clothes.

So: **before a default-valued field becomes a predicate, count how much of the
population carries the default.** Stated mechanically as
`check_default_valued_predicates`, which reports a persisted `Bool` defaulted
`false` and negated inside a set predicate unless every initialiser call site
passes it. Mutation-verified by reintroducing the declined selector.

**And the narrow fix is the proxy §1.1 removed:** `&& $0.sharpnessMeasurable`
works only because that flag happens to mark the one measuring screen — *two
fields agreeing today is not one field meaning the other*, which is what put
four notes per vehicle in row five. The honest repair is a per-path capability
field, the way `motionMeasurable` replaced `frameConfirmedClear != nil`.

**Scope, so a clear run is not read as stronger.** The check compares
INITIALISER CALL SITES against the field, catching "one writer, many
defaults". It cannot tell whether a path that *does* pass the field passes a
correct value. **A row with no branch is now detectable; a branch with the
wrong condition is what this closes; a branch with a subtly wrong VALUE
remains invisible to every check here** — and the filtered-`headlineDisplay`
divergence is exactly that third kind.

### 4c-xiii. Widening to one more shape is a member-shaped fix

`check_note_rows_implemented` was scoped to §2.2's note table, widened to
§2.3's blockquotes, and still blind to `attest.body` and §6.1's filtered
wording — **the two strings just recorded as owed were the two nothing
recomputed.** Both widenings enumerated PLACES.

**The ledger table is the population.** A string is locked *because* it has a
ledger row, so §4.1's table — date, key, was, now, why — owns every locked
string, and §2.2's rows and §2.3's blockquotes are two places such strings
happen to live. §4.1's scope was widened three times and settled by rescoping
to the table itself whatever its length; this is that move inside a check.
**Widening to "one more shape" is what a member-shaped fix looks like: it
closes the instance and leaves the class.**

Five findings from doing it, each a way a checker is **wrong** rather than
silent.

*One population, two homes — say which home you are asking about.* Notes and
all-clears are REPORT copy living only in `PDFReportGenerator`; `confirm.yes` /
`confirm.arm` are BUTTON copy that correctly appear nowhere near the report.
Searching one file for the second group reported four present strings absent;
searching the whole tree for the first would let a note satisfy the check from
a **comment**. "The string exists" and "the string exists *where it is
rendered*" are different claims, and only the second is the requirement.

*A locked TEMPLATE is not a locked SENTENCE* — the Tech Lead's caution
arriving as a real false positive. §6.1's row carries `NN%` / `M of N`
placeholders a format string fills at runtime, so no literal can match it
whole. The check compares only the placeholder-free sentences: **the claim is
in those, and the figure is the part the code substitutes.**

*Do not include the commentary in the thing checked.* A `Now` cell may carry an
italic annotation. Matching it whole reported a string present at two call
sites as missing — **a documentation style reported as a code defect** — and a
cell that is *entirely* annotation records a meaning that moved without a diff,
so reporting it would be the check inventing an absence.

*A stale message is a wrong reading.* Two edits to the warning text silently
no-oped because the strings had drifted, so the check fired correctly while
naming the old population and the wrong file. **A diagnostic that misattributes
its own finding sends the reader to the wrong place.** Verified by reading the
EMITTED text on a mutant, not the source.

*And a HELD declaration is a copy, so it goes stale like every other
duplicate — in the dangerous direction.* §4.3.1's wording was re-ruled into
first person after the hold was written; the copy stopped matching, and the row
then reported as **owed**, which reads as an oversight rather than as a stale
hold. There is now a check for it: **a hold that matches no ledger row is
protecting nothing.**

**Its honest limit, found immediately after: that check cannot tell a stale
hold from an OBSOLETE one.** `attest.body` was held while it was
ruled-and-owed, and `40e4709` built it — so the declaration became obsolete
rather than mismatched, and both report identically. Both mean "re-read the
row", which is the most a declaration mechanism can offer: **it converts a
silent omission into a prompt, not into a diagnosis.** And a hold must be
declared in exactly one place — recording it in the check and in the appendix
section is the duplicate-with-diverging-claims defect aimed at a checker.

### 4c-xvi. A tracked check nobody runs decays into a file

`run.sh` was mutation-tested three ways, given a durable home, had its exit
codes split, and **nothing invoked it.** Storage and execution are different
problems, and four rounds of work on the instruments solved only the first.
**A check nobody can re-run is a claim; a check nobody does re-run is a
decoration.**

Not hypothetical here: `check_remedies.py` was written, reviewed and landed
**unwired** the same day and reported nothing for a full round — the same
shape, one artefact over. That is also the reason `filtered-headline-v1` was
renamed into the glob rather than archived beside it: **a stored instrument
the runner does not execute is a file, not a check.**

`preflight` now runs them, **captures the output rather than piping it** —
reading a runner's verdict through a pipe returns the pipe's status, which
produced two false readings today — and reads **all four** exit codes
separately. A `3` is named as NOT RUN rather than reported as a failure,
because **no result and a bad result are different claims**, and a caller that
treats every non-zero alike undoes the split the codes were introduced for.

**Scope stated, because the limit matters more than the check:** it proves
each shape check still compiles and its own assertions still hold. **It does
not prove any of them still DISCRIMINATES.** Verifying that requires mutating
the tree, which a preflight check must not do, so the entry condition — *each
must fail when the property under test is removed* — stays a written
requirement in the README. A passing shape check is evidence about a reduced
model, which says nothing about the tree.

**One finding from building it: the emitted-text rule aimed at my own check.**
The first version quoted `run.sh`'s whole FAIL line, which carries a Swift
precondition's backtrace, so the warning read *"motionblur-window.shapecheck —
Backtrace took 0.00s"* — **a true alarm whose text points at nothing.** Found
by reading what the check EMITTED on a mutant, not the format string that
produced it. Third instance of that rule today, twice against my own work.

**And a third instance of the same shape, found while wiring this:**
`scripts/__pycache__/preflight.cpython-312.pyc` was committed to `main` and
`preflight`'s manifest check named it on the first run — **the count-under-a-
recomputing-check rule catching a `git add -A`, which is how two stray files
got tracked today, one of them mine.** It is now in `.gitignore` rather than
only caught: **a check that catches a mistake is worth less than a rule that
prevents it, when the rule is free.** Same reasoning as putting a runner's
verdict on stderr instead of writing a rule about pipes — stop rewarding the
mistake rather than relying on the reader who remembers.

### 4c-xvii. Removing today's instance of a class is a deferral

`.shapecheck` was the right landing and it is not the fix. Both *"the
instruments are not `.swift`"* and *"unscoped `.swift` is also 42"* are true of
the tree today — **and that is the coincidence, not the repair.** Two
definitions of "Swift file" stayed live: `tracked_swift()` (what
`check_swift_parses` parses and `check_pbxproj_registration` requires) scopes
to `SOURCE_ROOT`; `check_manifest_drift` counted every tracked `.swift`.

Measured on the landed tree rather than argued: a probe at `ios/probe.swift`
gives **42 scoped and 43 unscoped**, and the manifest check reported 43. So the
two figures all four of us quote as one signal could still silently become
different while both stayed correct — by the next real Swift file outside
`SOURCE_ROOT`, not by an instrument.

**A fix that removes today's instance while the class stays reachable by the
next file is a deferral, and it reads exactly like a closure.** The manifest
check now names its population, so both figures are the same 42 by
construction; re-probed after the fix, 42. **"42 Swift sources" keeps its
meaning and every past "42/42" still reads the same way** — which is the point,
since the hazard was never a wrong count but a quoted signal quietly changing
what it counts.

### 4c-xviii. Wiring a check decides *whether* it runs; its severity decides whether anything happens when it fires

**`check_shapechecks_run` is wired, correct, and advisory — so a shape check
that FAILS does not stop a commit.** Measured on `17b8ed3` rather than argued,
with the hook installed by `--install-hook` and one assertion inverted **by
line number** in `rowfive-proxy.shapecheck`:

```
warn  [shapechecks] scripts/shapechecks/run.sh reports failures: rowfive-proxy.shapecheck
preflight: clear (1 advisory) -- staged changes.
```

`git commit` **succeeded**, exit 0, and the commit was in the log. The warning
named the right file, with no backtrace noise, exactly as designed. Compare the
same tree with one tracked Swift file made unparseable: `3 blocking, 2
advisory -- whole tree. Commit refused.`

**This is the round's own finding one layer out.** "Nothing ran the runner" was
right and closing it was the finding of the round — **but a check nobody DOES
re-run and a check that runs, reports, and is ignored differ only in where the
signal stops.** A decoration prints nothing; **an advisory prints into a line
whose last word is `clear`.** The three states are *cannot re-run* (a claim),
*does not re-run* (a decoration), and **runs and changes nothing** — and the
third is the one that looks most like coverage, because there is real output
naming the real file.

**And the aggregate line is where it lands.** `preflight: clear (1 advisory)`
is the string every report in this thread quotes as a verification signal,
including mine. This document already requires that *"clear" and "not looking"
be visibly different strings* — this is the third case that requirement did not
anticipate: **`clear` while a tracked instrument's own assertion is failing.**
The word is doing what §4's severity doctrine intends and reading as something
stronger than it says.

**I am NOT ruling this up to blocking, and the reason is this document's own
rule.** A blocking check must be scoped more carefully than an advisory one,
because its failure mode is somebody reaching for `--no-verify`, which silences
every check at once. Two facts here argue against blocking:

1. **Environment-dependent.** rc=3 already warns when no toolchain is found.
   A blocking severity on rc=1 puts a commit's fate on whether a compiler is
   installed — and this repository has spent the day establishing that
   **an environment-dependent check reports a property of the pair, never of
   the commit.**
2. **The instruments are reduced models.** A failing shape check means *either
   the model is wrong or the behaviour it models changed* — the check's own
   remedy text says exactly this. A defect whose diagnosis is genuinely
   ambiguous must not refuse a commit; it must be read.

**The ruling is on the WORD, not the severity: the aggregate line must not say
`clear` while any instrument reported a failure.** Advisory is right for the
exit code and wrong for the summary noun. A shape-check failure is a *finding
that has not been triaged*, which is neither `clear` nor `blocking`, and this
document has no third noun. **Owed: a distinct aggregate wording when
`warnings` contains a `shapechecks` failure** — the severity stays advisory,
the summary stops asserting the clean case. Not built here; recorded as owed
with the measurement attached, because this section's own subject is a finding
that was reported and then absorbed.

**The general form, and it is the fifth member of the wrong-object family:**
mutating a pattern measures a double revert; mutating the fixture moves what
"correct" means; a status through `| tail` reports `tail`; a count without its
population compares two sets; **and a check's WIRING answers "does it run",
which is not the question "does its finding reach anyone".** All five return a
plausible integer with no error anywhere. **Verifying that a check fires is not
verifying that firing costs anything** — and the second is the property that
made anyone want the first.

**And the two halves compose into something neither of us reported alone.**
The Tech Lead's verify command was `preflight --all >/dev/null 2>&1; echo
PF=$?` — and **`preflight`'s rc is 0 with advisories present**, by design: rc
answers *did it refuse to proceed*, not *did it find anything*. Combine that
with the entry above and the failure is total: **a failing shape check produces
an advisory, the advisory does not change the exit code, the exit code is what
was read, and the summary noun is `clear` anyway.** Measured on a
`--single-branch` clone of `17b8ed3` with one assertion inverted:

```
warn  [shapechecks] scripts/shapechecks/run.sh reports failures: rowfive-proxy.shapecheck
preflight: clear (2 advisory) -- whole tree.
rc = 0
```

**Three independent channels and the finding survives none of them.** This is
not two mistakes stacking; it is **one property — the finding lives only in the
text — arriving at three readers who each read a different non-text channel.**
The severity was right, the wiring was right, the emitted text was right, and
nothing reached anyone. **An instrument's output is only a signal at the layer
someone actually reads, and every layer here was correct about its own
question.**

**So the owed item above is upgraded, not merely confirmed.** A distinct
aggregate wording is necessary and **not sufficient** while the exit code is
the thing people script against. Owed, in this order: (a) the aggregate line
must not say `clear` while any instrument reported a failure; (b) **the
documented verify recipe must read the advisory LINE, never the exit code** —
and this document should say so where the recipe lives, because *"read the
advisory line, never the exit code"* is the Tech Lead's sentence and it is the
correction to a habit every one of us practised all round.

**One retraction of my own, inside this section, because it is the same
mistake:** an earlier draft of this entry recorded `check_remedies` 52/21 as a
*miscount*. It is not. **52/21 and 52/20 are two extractors over one file and
both are right about their own population** — `check_fns()` is an AST walk over
**top-level** `def check_*` and yields 20; a textual `def check_` yields 21,
because `check_script_currency` contains a local helper `def check_names`.
Verified both ways here. **I was about to record a population divergence as an
arithmetic error, which is the wrong-object family aimed at a teammate's
number** — and the entry immediately above is about exactly that. Quote the
**extractor** with the count; the check's own number is the only one that
governs its assertion.

### 4c-xix. An anchor binds the SELECTOR to the tree; it does not bind the OUTPUT to the selector

**The anchors close the renderer-selector gap and there is one step left past
them, measured on the fully stacked tree rather than argued.** Mutating the
real selector at `PDFReportGenerator` now returns `1 blocking` — verified, and
that is the gap closed. But the anchored line is the *condition*, and the
condition feeds a ternary:

```swift
let motionUnmeasured = photos.contains {
    $0.motionMeasurementAttempted && !$0.motionMeasurable   // <- anchored
}
let allClear = motionUnmeasured                             // <- NOT anchored
    ? "…checks that could be run… Camera movement was not measured for every photograph."
    : "…met the app's capture-quality checks at the time of capture."
```

**Negate the ternary's test and leave the anchored line untouched.** Measured:
`preflight --all --strict` → `clear`, **rc=0**, and `run.sh` → **8/8, rc=0**.
Every instrument in the tree passes a renderer that emits **the wrong variant
on every report**.

**And the failure direction is the bad one.** Inverted, a report whose motion
*was* fully measured prints *"Camera movement was not measured for every
photograph"* — a false qualification, recoverable. But a report containing a
photograph that **attempted and failed** to measure prints the **unqualified**
all-clear: *"All analysis photographs met the app's capture-quality checks."*
**That is the over-claim §2.3 exists to prevent, on the page an examiner
signs**, and it is exactly the sentence the whole variant mechanism was built
to stop. The selector is correct, the strings are locked and byte-exact, both
variants are present and reachable — **and they are wired to the wrong arms.**

**The general form, and it is why this is a section and not a bug report:**
mutation-testing the shape check proves the check discriminates; the anchor
proves the modelled line still exists in the tree. **Neither asks whether the
line's VALUE reaches the reader unnegated.** A grep-strength anchor binds a
substring's *presence*, so any defect expressible **between** the anchored
condition and the drawn string is outside every instrument we have —
`!`, a swapped ternary, a shadowed local, an early `return`. **An anchor makes
a reduced model stop being silent about whether the tree still CONTAINS what it
models; it says nothing about whether the tree still MEANS it.**

This is Vector's third defect kind arriving one layer in from where he named
it: *a row with no branch is detectable; a branch with the wrong condition is
what the anchors close; **a correct condition wired to the wrong output** is
invisible to all fourteen anchors and all eight checks.* Same family as §6.1's
verdict travelling by hue — **a channel the instrument does not read**, except
here the channel is the boolean's sign rather than a colour.

**Not built, and I am not proposing a check for it, because the honest answer
is one this document already owns: the assertion that catches this is one that
renders the block and reads the emitted string** — §4's compile-and-run debt,
not another grep. Recorded as the standing limit of the anchor mechanism so
that a clean `preflight --strict` is not read as covering it. **The reason it
goes in writing now is that the anchors are the strongest instrument layer we
have ever had, and that is precisely when a limit stops being obvious.**

### 4c-xx. An anchor that resolves inside a comment is the prose defect arriving through the fix for it

**Measured on the fully stacked tree, and it is one `if` from being the worst
kind of finding: `check_shapecheck_anchors` searched the whole FILE for its
substring, so an anchor could resolve against a COMMENT.** Regress the real
selector in `PDFReportGenerator` to v1 *and* add one clause to an existing
comment line quoting the old predicate — which is what a careful author does
when changing a non-obvious line — and:

```
preflight --all --strict  ->  clear, rc=0
run.sh                    ->  8/8, rc=0
manifest                  ->  unchanged (the note went inside an existing line)
```

**All fourteen anchors held while the renderer was regressed, and the thing
that held them was a sentence describing the regression.** §4c-xix's limit is a
defect the anchors cannot see; this one is a defect that **repairs the anchor
that would have caught it**. The mechanism is §4c-xviii's, three paragraphs up
in the check's own docstring: *a check names its subject in prose and prose
does not fail* — arriving inside the instrument written to close it, because
`substring in file_text` never asks WHERE the line lives.

**Built, blocking, in the same check:** an anchor must resolve on at least one
line that is not a comment. Four mutants, every rc read bare from a file:

- selector regressed **plus** history comment → `1 blocking`, rc=1, named as
  *resolves only in a comment* (the finding itself)
- that clause deleted from `preflight`, tree defect kept → rc=0, no `clear`
  only because of an unrelated line-count advisory — **the canary; the pass is
  not vacuous**
- selector regressed with no comment → rc=1, still the pre-existing *absent*
  diagnosis (the two arms are distinct, not one collapsed message)
- an anchor authored against a comment line from the start → rc=1, caught
  before it ever protects anything

**Still a grep.** It cannot see a string literal, a `#if`, dead code, or
§4c-xix's negated ternary; §4's compile is still owed. The one failure mode it
removes is the one that **self-heals**, and that is why it was worth a blocking
clause: every other anchor break gets louder over time, while this one gets
quieter each time somebody documents the change that caused it.

**The general form, and it is the day's shape at its shortest: A CHECK THAT
READS A FILE AS TEXT CANNOT DISTINGUISH THE CODE FROM THE COMMENTARY ABOUT THE
CODE — so any grep-strength instrument inherits the prose-does-not-fail defect
it was built to close.** Ask it of every text-matching guard in this repo, not
only of anchors.

### 4c-xxi. The owning document ratified the v1 selector it should catch

Third edge of one defect, and the only one the instrument patches left open.
The Tech Lead mutated the renderer's §2.3 selector back to v1 and preflight
stayed clean; Vector's `// anchor:` lines closed that, blocking, for all
fourteen anchors.

**Neither closes the document.** §2.3's prose specified the trigger as
`motionMeasurable == false` — the v1 selector — in five places, including the
locked ledger row's `Why` cell. So **a reviewer who doubted the renderer and
checked it against the owning document would have found the regression CORRECT
and closed the review.** A document carrying a superseded condition does not
merely fail to catch the regression; **it ratifies it** — and it is the
artefact a reviewer consults precisely when they doubt the code, so its
failure is silent in the direction of agreement.

Measured, not argued: with the anchors in place, regressing the doc's wording
while the renderer stayed correct produced no finding at all. **An anchor
proves the tree still contains what the model models; it says nothing about
whether the prose describes the same expression.**

**The copy lock is the precedent and the reason this needed a second
mechanism.** The lock guards §2.3's words in four paragraphs, byte for byte,
and the always-firing qualification it exists to forbid arrived through the
PREDICATE those words were locked against. That is not a gap in the lock — a
lock over copy cannot see a condition. `check_locked_variant_conditions`
declares the predicate as `<!-- CONDITION: <key> = <expr> -->` in the section
that owns the copy and asserts it against the renderer, plus the prose form
separately. A comment rather than a locked table row on purpose: **a claim
about CODE in a document of COPY must not read as a copy change to the lock.**

**Its own defect, found by mutation and not by reading, is the sharpest part.**
Regressing the prose shortened it by one line, which pulled the
`<!-- CONDITION: -->` comment into the search window, and the correct
expression that comment carries satisfied the very test meant to find the
stale prose. **The declaration immunised the check against the defect it
declares.** That is the mutate-the-fixture member arriving inside a check
written to close another member of the same family, and the first run passed.

**It is also the Tech Lead's §4c-xx one artefact over.** His finding is that a
grep-strength check cannot distinguish code from commentary about code; mine
is that the check's own declaration became commentary the check then read as
evidence. **Any text-matching guard inherits the prose-does-not-fail defect,
including from its own reference file.**

### 4c-xxii. The instance closed, the class left open on purpose

Ledger's §4c-xx names a correct condition wired to the wrong output — negate
§2.3's ternary test, leave the anchored line untouched, and every instrument
passes a renderer emitting the wrong variant on every report. He declined to
check it, on the ground that the assertion which catches it must render the
block and read the emitted string: §4's compile-and-run debt. The Tech Lead
agreed, adding that a fifteenth grep would have looked like coverage.

**They are right about the class and wrong about this member**, and taking a
stated limit at its word is the failure this document already records two
entries above: `check_note_rows_implemented` documented its own gap in four
lines and nobody read it as owed work. **A stated limit is not a covered
limit — including when the person stating it is right.**

The sign is not, here, between the condition and the string. §2.3's ternary
test and both arms are one expression, textually adjacent, so **which literal
sits on the TRUE arm is a property a grep can read.**
`check_variant_output_binding` asserts it, blocking, taking the qualified
string from the document rather than carrying its own copy. On Ledger's exact
mutant it returns `1 blocking` instead of `clear`; swapping the two arms with
the test unchanged fires identically; restructuring the ternary away fires as
NOT FOUND rather than passing silently.

**And the class stays open, in writing, which is the point of this entry
rather than an aside.** A shadowed local, an early `return`, a second call
site, or the same defect in any surface without an adjacent ternary are all
still invisible. **A fix that removes today's instance while the class stays
open reads exactly like a closure** — the deferral shape from this morning's
Swift-count round, and it would be committed here by anyone who reads a clean
`--strict` as covering §4c-xx. It does not. The renderer debt is unchanged.

**Accepted against myself, and the correction is the more useful half.** I
declined a check for §4c-xix as §4 compile-and-run debt, and one other reader
agreed a fifteenth grep would look like coverage. **I was right about the class
and wrong about this member**, and I verified the correction rather than
accepting it: on `check_variant_output_binding` my exact mutant returns `1
blocking` where it previously returned `clear`, rc=0. **The sign is not between
the condition and the string in this renderer — test and both arms are one
adjacent expression, so which literal sits on the TRUE arm is greppable, and I
described a class-level limit as though it settled the member in front of me.**
Re-measured on the same tree: a shadowed local after a correct ternary still
produces **no** `variant-binding` finding, so the class is genuinely open and
the member genuinely was not. **A STATED LIMIT IS NOT A COVERED LIMIT, INCLUDING
WHEN THE PERSON STATING IT IS RIGHT** — `check_note_rows_implemented` stated its
own gap in four lines and nobody read it as owed work. **Declining to build is a
decision, and a decision is the artefact nothing re-checks by default**; naming
a limit accurately makes it read as handled, which is the one thing an accurate
limit and a covered limit have in common.

### 4c-xxiii. The comment clause tests comment LINES; a trailing comment is code and commentary at once

**Asking §4c-xx's own general form of §4c-xx's own clause finds one more hop.
Measured on `03b5422` and re-measured on this stack, not proposed.** The test is
`all(...startswith("//"))`, which distinguishes a comment **line** from a code
line and **not code from commentary**. Put the regressed predicate in a
**trailing** comment on the surviving code line — the shortest form of the same
authorial habit, and shorter than the mutant the clause was built from:

```swift
!$0.motionMeasurable  // was $0.motionMeasurementAttempted && !$0.motionMeasurable
```

`preflight --all --strict` → `clear`, **rc=0**; `run.sh` → **8/8, rc=0**. **The
anchor holds, the renderer is regressed, and the line holding the anchor is not
a comment line — it is a code line wearing its own history.** `startswith`
cannot see that, because a trailing comment makes one line both things at once
and the check's population is *lines* rather than the code within them. **Same
self-healing direction as §4c-xx: it gets quieter every time somebody documents
the change that caused it.**

**The remedy is one clause and it is measured, not proposed:** match each line
with any trailing `//` stripped, respecting string literals. Verified on both
this stack and the landed tree before writing — **all 14 anchors still resolve,
zero false positives, and the regression above is caught.** It belongs to the
check's owner with these numbers attached, and is **not** recorded as an open
limit, because unlike §4c-xix it does not need §4's compile.

**The durable half is where these fixes keep landing.** Anchors closed *the
model not binding the tree*; the comment-line clause closed *the anchor binding
prose*; this closes *the line being prose and code at once*; §4c-xxi closed *the
owning document ratifying the regression*. **Each was found by asking the new
instrument the question it had just asked of the old one** — the cheapest audit
available here, and it has not missed yet: **when a guard closes a defect class,
run that class's own test against the guard before reporting it closed.**

### 4c-xxiv. Audit the class against the OLDEST instrument of that strength, not the newest

**Ledger's audit — *when a guard closes a defect class, run that class's own
test against the guard before reporting it closed* — has caught five hops and
missed none. Run against every text-matching instrument in `preflight` rather
than only the newest, it finds one more, in `check_variant_output_binding`:**
the instrument NAMED as the guard on the ternary's sign.

It flattened the whole renderer file and took the FIRST regex match of
`let allClear = <cond> ? "..." : "..."`, so:

```
// ... existing comment line ... v2: let allClear = motionUnmeasured ? "<qualified>" : "<plain>"
let allClear = !motionUnmeasured
    ? "<qualified>"
    : "<plain>"
```

**A commented copy of the CORRECT ternary parked above a negated live one
satisfies the check that exists to catch the negated live one.** Appended to an
*existing* comment line it moves no line count either, so `--strict` stays 0 and
the summary says `clear` while every report carries the §2.3 over-claim.
Measured with Vector's `anchor-seq` removed to isolate it: **`variant-binding`
alone reported nothing.** With the seq in place the seq catches the same mutant
through the *anchor* path — so the tree was protected by an instrument that was
not the one named for this defect, which is exactly the coverage-by-accident
§4c-xxii warns against.

**Fixed by flattening the CODE only, reusing Vector's `strip_trailing_comment`
rather than a second copy of it** — a duplicated helper is two predicates that
must agree, the defect this repository has hit at every layer. Four mutants,
seq removed to isolate, every rc read bare from a file: the mutant → `1
blocking` naming `variant-binding`; the flatten reverted with the mutant kept →
**no `variant-binding` finding at all**, the canary; the full tree with the seq
present → **two distinct diagnoses**, anchor-seq and `variant-binding`; no-op →
`clear`, rc=0.

**The transferable half is the ORDERING, and it is what I got wrong.** I ran the
class's test against the guard I had just written and stopped. **§4c-xxiv was
reachable the moment §4c-xx existed; it waited four hops because the audit was
aimed at the last commit instead of at the property.** A defect class is a
property of a TECHNIQUE, so **its audit is scoped by the technique, never by the
diff** — every grep-strength instrument in the tree, including the ones written
before the class had a name.

**And the ordering rule that follows: the newest guard is the LEAST likely
member, because it is the only one written by someone who had the class in
mind. Audit oldest-first.** Vector's near-miss is the same lesson from the other
end — his equality check fired on Ledger's mutant *before* he added trailing-comment
stripping, because the comment text leaked into the captured selector, so it
named the right defect for the wrong reason. **A guard that fires for a reason
its author cannot state is a guard that will stop firing silently.**

### 4c-xxv. The exemplar for the open class, so "still open" is a measurement rather than a caveat

**§4c-xix's MEMBER is now closed several times over** — the sign guard, the
`anchor-seq` arm pairing, §4c-xxiv's code-only flatten, and `swift_code_only`
across three guards. **The CLASS is still open, and it gets a mutant here rather
than a sentence, because this document has twice been caught mistaking a class
described in prose for a covered one**: §4c-xxii on my own decline, and
`check_note_rows_implemented`, whose four-line self-stated scope nobody read as
owed work until the audit reached it a day later. A stated limit is not a
covered limit, so the limit is measured.

```swift
let allClear = motionUnmeasured          // correct
    ? "…checks that could be run… movement was not measured for every photograph."
    : "…met the app's capture-quality checks at the time of capture."
_ = drawWrapping("…met the app's capture-quality checks at the time of capture.",  // ← drawn literal
```

**Measured on the landed tree with every instrument present: `preflight --all
--strict` → `clear`, rc=0, zero `warn`/`FAIL` lines; `run.sh` → 8/8, rc=0.**
Selector correct, declaration correct, both locked strings byte-exact, ternary
correct, every anchor and the seq resolving, `variant-binding` satisfied,
`note-rows` satisfied — **and every report prints the unqualified all-clear
regardless of what was measured.** The §2.3 over-claim in its final form,
reached without touching one thing any instrument reads.

**Deliberately line-count neutral.** A first version added a line and produced
two manifest advisories; those are not the finding — they are the manifest
noticing a file grew, and reporting them as a catch would be **crediting a guard
for an accident of formatting**, which is this section's own subject aimed at its
own evidence. Re-measured neutral, the tree is fully `clear`.

**The general form: every instrument here binds the CONDITION to the tree, and
none binds the DRAW to the condition.** Anchors, seqs, equality, locked strings,
the sign guard and the note-row haystack all answer *is the right thing
computed*. The remaining class is *is the computed thing what reaches the page* —
a value computed correctly and discarded, an early `return` before the draw, a
second `drawWrapping`, a literal inlined at the call site. **None is reachable by
any grep, however strong, because the defect is that a correct expression has no
consumer — and absence of a consumer is not a substring.**

**Note what this means for the audit that found the other six.** §4c-xxiv scopes
an audit by TECHNIQUE, and it works because those six were all members of one
technique's blind spot. **This class is not a member of that blind spot; it is
the boundary of the technique itself.** That is §4's standing debt, and it is
now the only thing between this page and an examiner's signature.

**AMENDED against myself, and it is the second time in one day.** The mutant
above is closed at grep strength by an `anchor-seq` binding
`_ = drawWrapping(allClear,` and its argument line: **a competing literal at
that argument position cannot be there without displacing the required one**, so
the required CONSUMER is a substring even though the absence of one is not.
Verified — the mutant returns `1 blocking`, and with the seq removed it goes
silent, so the binding is load-bearing. **Twice today I stated a class-level
limit correctly and let it settle the member in front of me**, which is
§4c-xxii aimed back at its own author. **A class statement being RIGHT is what
makes it dangerous: it earns the reader's agreement and then covers a member it
never examined.** The sentence above claiming no grep reaches this was
over-broad and is corrected here rather than left standing.

**The class survives with ONE demonstrated member, and the count came down
twice while this entry was being written** — which is the strongest argument
for measuring it rather than asserting it. Both candidates were line-count
neutral and re-measured by me against every instrument in the tree:

- **CLOSED — a SECOND `drawWrapping`** of the unqualified literal appended on
  the existing line. Closed on **MULTIPLICITY**, the one axis no text guard
  here had asked about: each locked variant is emitted from exactly one place,
  so a second occurrence is a second emission the lock never authorised. **`in`
  answers "at least once"; "exactly once" is the claim §2.3 actually makes.**
  Verified: `1 blocking`, naming the variant and the count. *(Also: the mutant
  is only honest folded onto the existing line — as a NEW line it costs a
  manifest advisory instead.)*
- **OPEN — `if true { return }`** before the draw, folded onto an existing
  line → **rc=0, zero warn/FAIL lines, `run.sh` 8/8.** Every asserted token
  present and none of it running. **Counting cannot reach a live statement that
  never executes.**

**That is not a caveat about what we did not test. It is one specific
line-neutral edit that puts a false all-clear on an examiner's page with every
instrument in this repository green** — the sharpest statement of §4's debt
available, because it names the edit rather than the gap.

**And the ordering lesson is the transferable one, stated by the reader who
closed (a): a boundary claim can be right about the CLASS and not decisive for
the MEMBER on the table, so try to close the member at the cheap strength
FIRST, then re-state what remains open with a mutant.** Three times today a
correct class statement of mine covered a member it had never examined. The
claim *absence of a consumer is not a substring* was true and was the right
argument for the class; **what it could not do was tell (a) from (b), and only
a mutant per member could.**

### 4c-xxvi. Two correct fixes, one name, two signatures — a collision no textual merge inspects

**The Designer's shared-view patch and Vector's note-rows patch each introduced
a helper called `swift_code_only`. I merged them in that order and `git am` was
clean both times, no conflict marker went near either — and the result was
BROKEN.** One took a repo-relative PATH, the other took SOURCE. **Python keeps
the LAST definition**, so the path-passing call sites handed their own path
string to a function expecting source. Measured on that merge:
`check_note_rows_implemented` reported **all fifteen** appendix strings missing
from a tree that has none missing, and reintroducing the collision on the
current stack kills preflight with a **traceback** before any summary prints.

**Both patches were correct in isolation and both verified so — clean,
`--strict` rc=0, zero warn lines, in their own fresh clones. Neither author
could have seen it, because THE COLLISION IS IN THE MODULE NAMESPACE AND A
TEXTUAL MERGE INSPECTS LINES.** §4d is this location with the loss in prose;
this is the same location with the loss in the import graph, and with no
conflict at all.

**The shape: A SHARED HELPER IS THE RIGHT ANSWER TO THREE PRIVATE COPIES, AND
TWO TEAMMATES REACHING IT INDEPENDENTLY PRODUCE A COLLISION THAT LOOKS LIKE
AGREEMENT** — same name, same intent, same reasoning, incompatible contract.
Loud only by luck here: the mangled haystack could not match anything, and had
the signatures been PATH and PATH-OR-SOURCE it would have been silent.

**Vector withdrew his helper in favour of the better signature before either
landed, so `main` never carried it. The check ships anyway, on this document's
own rule — §4c-xxii, a stated limit is not a covered limit — because that
resolution was a conversation and the next instance will not have one.**
`check_no_duplicate_defs` is an AST walk over this file's own `def`s, top-level
and nested, blocking, and it runs **FIRST**: a namespace collision makes every
result below it a statement about the wrong code.

**Two things the guard's own construction taught, both found by mutation:**

- **My first early exit returned 1 without reaching the reporting loop, so the
  collision refused the commit and printed NOTHING.** A refusal with no
  finding — §4c-xviii arriving inside the guard written for today's class. It
  prints before it returns.
- **The mutant's first form crashed a LATER check before the summary line, so
  the only channel carrying the finding was a Python traceback**, which names a
  file and a line number rather than the tree's defect. That is why the guard
  is first rather than merely present.

**Four mutants, each graded on its NAMED finding rather than on rc, per
Ledger's rule, and all line-count neutral:** the exact collision → `1
blocking` naming both line numbers, rc=1; the guard's body deleted with the
collision kept → **no finding at all**, rc=0, the canary; the print-before-return
reverted with the collision kept → rc=1 and **zero bytes of output**, which is
the second lesson above; a NESTED `def` shadowing `strip_trailing_comment` →
named correctly, so the walk is not top-level-only; no-op → `clear`, rc=0.

**Check that follows, and it is cheap: after merging two patches that each
introduce a helper, grep the module for duplicate `def` names.** `git am` clean
is a statement about lines, never about the namespace they define.

### 4c-xxvii. A check anchored on the prose that CARRIES a claim is anchored on wording nothing locks

**The audit, pointed at the §4c-xxi prose guard rather than at any code view or
helper, finds the guard keyed on an unlocked phrase.**
`check_locked_variant_conditions` locates §2.3's emit instruction by searching
for the literal `emit this instead`, then judges the condition stated near it.
**So reword that phrase and the guard stops looking, silently.** Measured on
landed `d7ddd3b`, line-count neutral, with the condition regressed to v1 in the
same edit:

```
preflight --all --strict  ->  clear, rc=0, zero warn/FAIL lines
```

**Canary — the identical v1 regression with `emit this instead` left intact:
`warn [variant-condition]`, rc=4.** So the guard works, and four words of
editorial rewording turn it off while the defect it exists for is present.

**This is §4c-xxi at one more remove.** That entry established that **the owning
document ratifies the regression**, because it is what a reviewer consults when
they doubt the code. The guard built for it reads the document — **and locates
the claim by prose that is not itself locked.** §4.1's ledger locks the
*variants* and now the *condition*; nothing locks the sentence that introduces
them. **A locked string with an unlocked locator is guarded content behind an
unguarded address**, and a rewrite for readability — the most ordinary edit a
document takes — is indistinguishable from an attack on the guard.

The narrow remedy is to key on the locked artefact instead: the
`<!-- CONDITION: -->` declaration already sits three lines above and is
machine-readable by construction. **It belongs to that check's owner; the
numbers above are the specification.** One irony to state so it is not
re-committed — that declaration was itself what immunised an earlier version of
this same check, so keying on it requires the declaration be *excluded from the
judged window* while *serving as its anchor*.

**The general form: an instrument's ANCHOR is an artefact with its own failure
mode, independent of what the instrument asserts.** Anchors into code took a
whole class of hardening today — presence, comment-blindness, adjacency,
ordering, the consumer, and the module namespace. **Every one hardened what a
guard READS or WHERE IT LIVES; none asked how the guard FINDS what it reads.** A
check that locates its subject by unlocked prose has the same standing as a
shape check that re-declares its subject locally: **it keeps passing after the
thing it points at has moved, and its output does not change shape when it
does.**

**One methodological pair earned today, kept as one entry because they are the
same error on opposite channels.** Every mutant in this section is **line-count
neutral**, because one that adds a line produces manifest advisories and
reporting those as the catch **credits a guard for an accident of formatting**.
Its twin: **a mutant that appears to FAIL is a claim too — check which finding
fired before believing either direction.** Mine is a false positive on the
guard, its twin a false negative on the mutant, and **both come from reading a
channel that is not the finding** — the same error as reading `rc` where the
finding is in the text. **Grade a mutant on its NAMED finding.** Between them
they caught three would-be reports today, in three different authors, including
both of ours.

**And the same discipline applied to a figure in this very entry, because it is
the round's other recurring error.** Verifying the helper count I read
`grep -c swift_code_only` as **7** where the reported figure was **6**. The
reported figure is right: an AST walk gives **1 definition and 5 call sites**,
and my seventh match was **this document's own prose** naming the helper.
**Extractor versus population, in my own number, in the entry about anchors** —
and the tell was that `grep` was counting the artefact that describes the code
alongside the code, which is §4c-xx's subject arriving in a verification line
rather than in a guard. **Quote the extractor with the count; an AST walk and a
`grep` are two populations, and only one of them is the program.**

### 4d. A conflict resolution is where prose goes missing

The same failure with a specific and repeatable location. When two branches are
merged, **neither side's hunk has to be wrong for the result to be wrong** — the
loss happens at the join, and no amount of reviewing either input finds it.

The instance: resolving `cross-section-exclude` against the version-stamp work
produced correct code and dropped the doc comment above
`isStatisticallySignificant`. What survived was pre-v1.2.0 text describing the
z-score test, sitting on top of code running the permutation test, citing a
constant deprecated eleven hundred lines below with a message saying this very
property no longer uses it. **Two statements disagreeing inside one file, with
the wrong one in the place people read.** Anyone auditing the significance test
the way a careful reader audits a claim they did not write — from the comment,
not the implementation — concludes the app still thresholds z = 2.0 on a
bounded, strongly left-skewed null distribution where that threshold never
delivered the tail it implies. That is precisely the defect the permutation
switch removed, still legible as current.

Why this is not covered by anything else here. `scripts/check_doc_drift.py`
covers numeric claims because numbers are mechanizable; a prose comment
describing which statistical test runs is not, and will not be. `preflight`'s
staged checks see the resolution's diff, not its omissions relative to a third
tree. So the guard is a review habit, and it is narrow enough to be followed:

- **After any commit that relocates code, diff the affected file against
  *every* parent — not just against the branch you are landing on.** An
  omission relative to one parent is invisible in a diff against the other.
  A conflict resolution is the two-parent case; a rebase or a refactor that
  moves code between functions is the one-parent case, and it fails the same
  way. Vector found a lost `Group`-idiom rationale on an ordinary #13 rebase
  with no conflict at all: the wrapper moved out of the measurement banner and
  its comment stayed behind, leaving the idiom without its reason. The next
  reader to "simplify" it into a bare if/else gets a ViewBuilder
  modifier-chaining error that looks like a mistake in their own edit.
- **Use the comments-only form, because it is unskimmable:**
  `git diff <parent> HEAD -- <file> | grep -E "^-\s*(///|//)"`. A 900-line
  diff gets skimmed and a four-line one does not. Most review rules fail on
  volume rather than on principle, which is the only reason this one is
  expected to hold.
- **Then confirm each removal survives somewhere, by grepping for the concept
  rather than judging the list.** This is the part that costs something:
  "those look superseded" is exactly the conclusion a reader reaches from
  reading the removals, and it is reached without evidence. Vector checked all
  39 other removed comment lines on that rebase this way and they were
  genuinely relocated; the point is that the check, not the impression, is
  what established it.
- **Prose adjacent to changed code is part of the resolution.** A comment that
  explains a behaviour is as load-bearing as the code when it is the artefact a
  reviewer consults, and it fails more quietly, because code that contradicts
  its comment still compiles and still passes every check.
- Two statements about one behaviour inside one file is always a defect, even
  when one of them is right. Whichever is stale, a reader has no way to tell
  which.

Scope, corrected after the fact: this section was written for conflict
resolutions, but **prose loss does not require a conflict.** It happens
whenever code moves — the loss is at the join between where the code left and
where it arrived, which has the same structure as a merge with one parent
instead of two. Every check passed on the clean single-parent rebase that
produced the instance above. Read every clause here as applying to any commit
that relocates code.

This is the third distinct thing a conflict resolution can silently produce,
alongside a decoder that forgets a field (§1) and a manifest resolved by picking
a side rather than regenerating (§4c). The general form: **a merge is not a
choice between two texts, it is the construction of a third**, and nothing about
either input authorises the result.


**A gate and a recorded finding are not the same boolean, and wiring the second
from the first is a distinct way to make an absence assert something.** task
#4's first wiring wrote `qualityFlags.isBlurry` from `!camera.isFocused` and
`isTooFar` from `!camera.isCloseEnough`. Both gates are deliberately
conservative — they default `false` so auto-capture cannot fire on an
unmeasured frame, and `isFocused` is additionally the *conjunction* of the
device's focus state with the sharpness measurement. Correct as a gate. But
those two flags are persisted into evidence and the report appendix renders
them as **"The app measured this photograph as not sharp"** and **"The app
measured the damage area as not filling the guide frame"** — sentences whose
subject is a measurement. Written from the gates, a capture where nothing was
ever measured prints both.

**The proof it is wrong is inside the same bullet list.** The fifth note
condition, *"Sharpness was not measured for this photograph"*, is guarded on
`sharpnessScore == nil` — which is true on exactly the photo the gate-derived
flags just described as measured-and-failing. One photograph, two notes, one
saying the measurement did not happen and one reporting its result. The
appendix is careful about `nil` for `frameConfirmedClear` three conditions
earlier and the same care did not reach the flags, because the tri-state was
visible in the type and this distinction is not: `Bool` cannot hold
"unmeasured", so it has to be held at the source.

The rule, stated so it applies past this instance: **a gate may say "not yet";
a recorded finding may only say what was measured.** When a `Bool` is persisted
into evidence, ask what its `false` means and what its `true` means *when no
measurement ran* — and if the answer is a claim, derive it from a
`measured && failed` term rather than from the gate. §5's tri-state is the same
rule where the type can express it.


**An all-clear is a claim about a SET, so the set is half the claim — and the
set is invisible in the sentence.** The Capture Conditions appendix emitted
*"All analysis photographs met the app's capture-quality checks at the time of
capture"* whenever no photograph in its input set carried a note. Every note
condition was individually correct, `captureNotes(for:)` was correctly the
single source of them, and the renderer and the cross-reference predicate
correctly shared it. The input set was built from `Vehicle.photos` — and the
scar photograph lives in `Vehicle.scarPhoto`, is never appended to `photos`,
and is the *only* photograph in the app that can carry any of the note
conditions. Every photograph that was in the set comes from a path that passes
none of them.

**So the all-clear was unfalsifiable: not "no problems found" but "no
photograph capable of having a problem was examined"** — printed on a case
whose scar photo may have been captured through the manual override with every
gate failing. This is §5's absence-asserting-the-clean-case with the absence
one level up from the fields: not a flag that is never written, but a
*population* that excludes the only member that can fail.

Why no review caught it: **every reviewable unit was correct.** The
conditions, the shared predicate, the copy, the tri-state handling, the
locked-word audit. The defect was in the one expression nobody reads as a
claim — the collection the predicate is mapped over. **A filter reads as
scoping, not as asserting.**

The habits, both cheap:

- **For any all-clear, aggregate, count or summary, state the population
  before the predicate** — in the code, in the doc, and in the review. "All X
  met Y" needs X written down somewhere a reader can check against the thing
  that produces X.
- **Ask which members of the population can actually fail the predicate, and
  confirm at least one is in the set.** A predicate no member of the set can
  trip is indistinguishable from a predicate that passes. Same discrimination
  question as checking that a reduced-shape typecheck FAILS when the property
  under test is removed, and as verifying a gate through the gate rather than
  through the thing it wraps: **a check that cannot fail is not a check.**

**Run that second habit over a whole condition TABLE, not one sentence at a
time — the third instance turned up that way and it is not a set problem.**
`frameConfirmedClear` is `Bool?` so that *declined* is distinguishable from
*never asked*, and the appendix's row two, the review badge and four
documents all rest on that — the four being this file, the appendix, the Item 2
spec and `ios/README.md`, per `git ls-files '*.md' | xargs grep -l
frameConfirmedClear`. **No code path assigns `false`.** Both Ready buttons record
`true` on the second tap; there is no decline affordance, so an examiner who
sees the ruler still in frame simply takes no photograph. The predicate has no
reachable input at all.

So the same question has now produced three different shapes in one day, and
the difference is worth keeping because each hides somewhere else:

1. **An unfailable predicate over a set that excludes the only member that can
   fail** — the all-clear. Visible only by reading the traversal.
2. **A predicate reading the wrong field**, correct in wording and correct
   when written — row five's proxy. Visible only by re-deriving what the field
   means after the population changed.
3. **A predicate whose input no code path can produce** — the decline.
   Visible only by asking, of each condition, *which write site sets this, and
   can a user reach it?*

**The unifying check is one question asked of a condition rather than of a
sentence: what would have to be true for this to fire, and can anything in the
app make it true?**

**That check has now been run over all five conditions in the table, so the
result is worth recording as a completed sweep rather than as a method.** Row
one's `gateOverridden` is reachable — `ScarCaptureView.performCapture(auto:)`
computes `!auto && !gatesGood`, which a manual tap over a failing gate
produces. Rows
three and four are reachable through the `measured && failed` terms. Row five
is reachable at the one site that passes `sharpnessMeasurable: true`. **Row two
was the only unreachable one; it is now reachable too, and the sweep result
above is a statement about a tree that no longer exists.** `pendingFrameClear
= false` is written by the decline answer in each screen's
`attestationAnswerRow` / `scarAttestationAnswerRow`, so all five conditions in the table now have reachable
inputs and `frameConfirmedClear` is genuinely three-state in the code as well
as in the four documents.

**Recording that transition rather than editing the result away is the point.**
A sweep is a measurement of a tree at a commit, and this one went stale in
under an hour — by being acted on, which is the good case. **The same property
that makes a sweep worth recording makes it perishable: it is a claim about
write sites, and a patch that adds one invalidates it silently.** So a sweep
result needs the commit it was taken at, and re-running it is part of landing
any patch that adds a write site to a condition's input — the same check the
interaction rule already asks for, applied to reachability instead of to
population. A sweep that stops at the first finding leaves the
reader unable to tell a checked condition from an unexamined one, so: **when a
class of defect is found in one member of a table, the deliverable is the
table, not the member** — and say which members were cleared, because "we fixed
the one we found" and "we checked all five" are different claims that read
identically. Reviewing conditions one at a time answers whether each is
correctly written, which all three were. **A design commitment the code does
not honour is not a bug report against the design** — the tri-state is right
and is what makes the missing case recordable in one line — **but it must be
recorded where the reader of the condition looks, not at the field, or the
next reader takes the three-state as shipped behaviour.**

**The two answers to one question can need different lifetimes, and giving
them the same one is how a fix reintroduces the defect it closed.** The
attestation is asked once per session — the right scope for an affirmation,
since an examiner who cleared their working area cleared it for the session.
**A decline is a fact about one frame.** Persisting it would write "the
examiner did not confirm the frame was clear" onto every later analysis shot of
that session, including ones nobody was asked about: a note that fires always,
one field upstream of where that failure was found this morning. So the decline
self-clears after its capture and the question is owed again, while the
affirmation persists.

Worth stating past this field because the asymmetry is not about attestations:
**when a stored answer is scoped for convenience — asked once, remembered — ask
that question separately for each value the answer can take.** The scope that
makes a "yes" humane makes a "no" an over-claim, because the two answers are
claims about different things: one about a state the examiner established, the
other about a state they observed. **A single lifetime for both is the design
that looks symmetrical and is not.**

**One boundary on that rule, since a wrong diagnosis of a related test was
briefly attached to it: the asymmetric lifetime is justified by what each
answer CLAIMS, not by anything about testability.** The decline self-clears
because persisting it would over-claim in evidence — that argument stands on
its own and needs no assertion set. It happens that the self-clearing reset is
also what can defuse a negative test written across it (§5b), but that is a
*consequence* of the design, not a reason for it. **Keeping the two apart
matters because the design rule is about honesty and the testing rule is about
ordering, and neither one supports the other.**

Storing one instance of a type outside the collection of that type is what
makes shape 1 reachable, and it is worth flagging on sight. `scarPhoto` is
correctly separate from `photos` — independent of protocol progress,
overwritten on retake — so the answer is not to merge them but for every
whole-case traversal to come from one helper that names both. **One traversal
that forgets the outlier is a defect; the fix is that there is only one
traversal.**

## 5. House rule: never let an absence assert something

A missing value means "we do not know." It must never be rendered, decoded, or
printed as a statement about the thing it describes. Five independent arrivals
at this rule on one day, from four people who were not coordinating:

| Surface | Absence | What it must NOT become |
|---|---|---|
| `MatchResult.algorithmVersion == nil` | result predates version stamping | back-filled with `.current` — that would claim an old score came from today's math |
| `CapturedPhoto.frameConfirmedClear == nil` | examiner was never asked | an amber "not confirmed" badge on a photo with nothing wrong with it |
| Evidence appendix, same `nil` | unmeasurable | an "examiner did not confirm" note (§1.1 of the appendix spec) |
| `preflight.py` signing check | no `DEVELOPMENT_TEAM` set | a blocking error — a Simulator build needs no team, so absence is not a defect |
| Report cover, examiner identity unbuilt | field does not exist yet | a blank signature line, which reads as an *unsigned* report rather than an unbuilt feature — omit the line instead |

**A verified patch has a shelf life measured in commits, not minutes.** The
fix above was verified against the tip, and the tip moved between verifying and
sending: two of its seven files no longer applied, one of them the very status
row whose restructuring the fix depended on. Then the *re-cut* was stale on
arrival too, because the substance had landed from the first cut in the
interval. **So verify by `git am` against the current tip immediately before
sending, not once per piece of work** — and on the receiving side, check whether
a re-cut is still needed before applying it, because re-landing a no-op is how
a correct patch produces a wrong tree. Both directions are the same
substitution with elapsed commits as the surface.

**A word inside locked copy can be the constraint, and softening it removes the
constraint silently.** "Measured" in the two flag notes is what makes each
sentence a claim about a measurement, and therefore what forbids driving its
trigger from a gate. Fixing the wiring and stating the rule here left the copy
table itself saying nothing: reword either note without that word and the
sentence becomes satisfiable by a gate again, with nothing in the document able
to catch the contradiction returning. **So a copy lock has to record which words
carry a constraint on the data behind them**, or the lock protects only the
wording it was meant to protect the meaning of.

**And copy rows can be coupled, which a table of independent strings does not
show.** The "sharpness was not measured" note is the *negative case* for the two
"the app measured…" notes — mutually exclusive at source, `!= nil` against
`== nil` — so an edit to any of the three has to be checked against the others.
That coupling is what made the defect disprovable from one document; recording
it is what lets the next editor inherit the check instead of rediscovering it.

**And the same "not in the type" blindness has a SwiftUI form: for a computed
property on an `ObservableObject`, ask what its inputs are published as, not
whether the property compiles.** `var x: Bool { a && b }` is correct,
observable, or neither, and the type says nothing about which.
`measuredNotSharp` and `measuredNotCloseEnough` read `sharpnessSatisfied` and
`framingMeasured`, **neither of which is `@Published`** — so the input that
carries the "measured" half of each claim is unobserved, and the fix when
either is surfaced is to publish it.

**But neither property is simply unobservable, and the difference changes what
a test would find: they are half-published.** `measuredNotSharp` is
`sharpnessScore != nil && !sharpnessSatisfied` and `sharpnessScore` **is**
`@Published`; `measuredNotCloseEnough` is `framingMeasured && !isCloseEnough`
and `isCloseEnough` **is** `@Published`. So a `body` reading either one *is*
invalidated — just not on every transition that changes the answer. **And today
it would refresh on all of them, for a reason that is an accident of the write
sites rather than a property of the code**: `sharpnessScore` is reassigned on
the same two lines that set `sharpnessSatisfied`, and `isCloseEnough` in the
same block that sets `framingMeasured`, so the published sibling fires on every
frame the private half can move. **The observation is correct by co-assignment,
not by design.** Guard either published write with an equality check, hoist it
out of that branch, or add a path that sets only the private half, and the
refresh stops with nothing in the type, the tests, or the diff to say so.

**That is the harder shape to catch, and it is why "would not be invalidated"
is the wrong thing to write down.** A view that never refreshes is uniformly
wrong and gets reported on first use; a view whose observation depends on which
line happens to write a sibling is right until the transition nobody tried.
Harmless today only because the sole readers are two imperative call sites in
`performCapture(auto:)`, neither inside any `body`. **Publish the whole input
set or none of it — a partially observed conjunction is the shape that survives
testing.** A stale view with no error anywhere is the same failure family as an
absence asserting the clean case: nothing is wrong, nothing is reported, and
the reader draws the wrong conclusion. Verified as a two-instance class rather
than assumed — the only other computed-from-unpublished pair in the tree is
`SensorData.pitchDegrees`/`rollDegrees`, and `SensorData` is a `struct` with no
observation in it at all, so it is a false positive. **A sweep for this has to
check that the declaring type is an `ObservableObject` before it reports
anything**, which is the phantom lesson from the never-written census in its
own domain.

**Closing a flagged caveat can be evidence rather than a green tick, and the
discriminating step is what makes the difference.** The isolation question on
those two properties could not be typechecked in-tree — no iOS SDK — so it was
answered on a reduced shape carrying the same isolation structure, under
`-strict-concurrency=complete`. **The step that made it evidence was checking
that the reduced shape FAILS when the isolation is removed.** A check that
passes both ways proves nothing; that is the same discrimination question as
verifying a gate through the gate rather than through the thing it wraps.
Reduced-shape typechecking is a tool for any SDK-blocked isolation or generics
question, and it is not a substitute for a real build: it says nothing about
the rest of the file.

**A missing checklist item is the mirror of an unpassable one.** An unpassable
item converts a tester's effort into false evidence; a missing item leaves a
disprovable claim untested. The contradiction here was demonstrable by one
manual shutter tap and an export, and no line asked anyone to do it — so when a
claim is disprovable from the artefact alone, the item that disproves it is
owed.

The general form: **an unset value is unmeasured, not failed; an unasked
question is unanswered, not declined; an unbuilt field is absent, not empty.**
When a surface cannot express the difference, it says nothing at all — silence
is the honest output. Applies to decoding, to UI, to report text, and to
tooling output alike.

**And it runs in the other direction too: a present artefact must not assert a
property nothing established.** That is the same defect wearing the opposite
sign, and the custody-page hash is the worked example — a digest computed by
the app that can rewrite the data implies tamper-evidence while establishing
only that the file matched itself. Attributing an automated event to whoever
was logged in is the same error: the trail would assert a person did something
the app did.

Both directions reduce to one test: **does the surface state exactly what is
known, and nothing more?** An absence dressed as a finding fails it. So does a
finding dressed as a proof.

## 5b. Checks, and why most of them are advisory

`scripts/preflight.py` is the mechanical half of this document: run
`python3 scripts/preflight.py --all` before handing over or landing a patch. It
enforces the pbxproj rules in §1, the persisted-model rule, and delimiter
balance on changed Swift files.

Two design rules govern it, and they are the reason to trust its output:

- **Blocking is reserved for a defect the next step cannot catch.** Everything
  else is advisory. A check that blocks work it should not have blocked gets
  bypassed with `--no-verify`, and the bypass takes every other check with it —
  so the cost of one over-eager check is all of them. Signing is advisory for
  exactly this reason: a Simulator build needs no development team, and
  blocking on it would re-import the wrong P0-1-gates-P0-2 ordering into the
  tooling.

  Two kinds qualify, and the second is the more important:

  1. **A silent reversion that breaks a build or a signature** — the pbxproj
     and build-setting-drift checks. The compiler would catch these eventually,
     but only after a wasted round-trip through the one machine that can
     compile.
  2. **A defect the compiler cannot catch at all, whose cost lands on the
     user.** A new non-optional field on a persisted model is valid Swift; the
     build goes green and then `keyNotFound` makes every existing case file
     unopenable at load time, with no partial recovery. In a tool where the
     case file *is* the evidence, that is data loss, not inconvenience — and
     no later step in this process would find it. This is the strongest reason
     to block that exists here, stronger than protecting a build.

  The test is therefore not "how bad is it" but **"what else would catch it,
  and at what cost?"** A defect the next step catches cheaply should warn. A
  defect nothing downstream catches should block.

- **A blocking check must be scoped more carefully than an advisory one, not
  less.** Its failure mode is not a wrong answer — it is someone reaching for
  `--no-verify`, which silences every other check at once. So the cost of one
  over-eager blocker is all of them. Any check argued *up* to blocking earns
  extra scrutiny of its false positives, not less.

- **Test that a check stays silent on safe input, not only that it fires on
  bad input.** "No failures reported" is exactly what a dead check looks like.
  A blocking check that has quietly stopped checking is worse than not having
  one, because everyone keeps trusting it — and two independent faults can mask
  each other into a green result. Assert both directions: hazards caught, and
  safe edits not flagged.
- **A check must report what it examined, not only what it found.** "Clear" and
  "not looking" have to be visibly different strings. A result line that names
  no scope gets read as broader than it was — so a check that examined a staged
  diff says so, and a check handed an unknown or empty scope exits non-zero
  rather than printing a clean line about nothing. This is the dead-check
  failure relocated: the code is working correctly and the *reader* draws the
  false conclusion, which is harder to catch because there is no bug to find.
  It is also the same defect as a rule in this document that describes intent
  rather than behaviour — an authoritative-looking statement about work that was
  never done.

  The worked example is a **real ref that is the wrong one**. `--since HEAD`
  after a rebase selects no commits, runs nothing, and exits 0 — the identical
  silence `--since` was built to eliminate, now reachable by a typo instead of a
  missing feature. So an empty selection must not return early: run what can
  still be run, and say outright that there was no change to judge. Scope
  belongs on every result line with a count, because "clear — 1 file" and
  "clear — 12 files" are different claims.
- **A report with no subject must not estimate its own significance.** When a
  check cannot identify what it was meant to examine, that report's entire job
  is to say "I do not know what I looked at". Appending a guess about how
  likely it is to be nothing — "probably a parsing gap rather than a real
  finding" — hands the reader a verdict the check is by construction unable to
  reach, and it is read as the finding. The estimate is not merely unwelcome,
  it is *structurally unavailable*: a check that cannot identify its subject
  has no information about what it missed, so any likelihood it offers is
  manufactured by the apparatus that reports it and inherits that apparatus's
  authority anyway — the p-value-floor defect applied to prose. That exact
  sentence stood on the advisory that was the only visible symptom of the
  nested-type misattribution fixed at `515e731`, and it produced the shrug it
  invited: two readers saw it and moved on, because the text told them to.
  **Reporting the gap is the check's competence; guessing its significance is
  not.** Landed in `97ddc3c`.

  The rule is narrower than "do not hedge", and the boundary is decidable by
  inspection: **does the sentence name a next action, or estimate a
  significance?** The delimiter check's *"probably truncated or mis-merged"*
  passes — it is a diagnosis attached to a finding the check *did* make, on a
  blocking failure the tool has already acted on. `doc-format`'s "fix the
  parser or restore the documented format" passes; it is an action. "Probably
  nothing" is a claim about a thing you did not see. You can apply this test
  without knowing anything about the check.
- **Read *which* check failed, not merely that something did.** A guard under
  test appeared to block; the blocking line was a missing `project.pbxproj` in
  the synthetic repo built for the test, and the guard under test had correctly
  warned. An exit code is a verdict on the run, not on the thing you are
  probing — one more way a correct probe gets read off the wrong surface. Three
  surfaces in one hour, two of them on the same verification, and the third
  generalises the other two: **the fixture is part of the instrument.** A
  residual demo died on a partial-clone pack error that briefly looked like the
  guard misbehaving and was the fixture being a worktree of a blobless clone.
  Before believing a probe's verdict, confirm the failure came from the subject
  and not from the scaffolding around it. Two
  people hit it within twenty minutes on the same verification, which is what
  makes it a clause rather than an anecdote: an exit code is a *representation*
  of a verdict, so this is the assert-on-behaviour rule below, one level down.
- **Assert on behaviour, not on a representation of it.** Both halves of this
  cost real time today at different scales, and they are one mistake:
  - *Source text is a representation of emitted copy.* Verifying a locked
    string by grepping the script returned `False` on a correct fix — the
    literal is split across two source lines, so the source never contains it
    contiguously. Trigger the branch and read the output. The same applies to
    every copy swap: confirm the report still *fires* with the new wording,
    because a swap that silently disabled the report is exactly the failure
    that line exists to prevent.
  - *A remote-tracking ref is a representation of a branch.* `git show
    origin/<branch>:<path>` is only as current as your last successful fetch,
    and it reads a force-pushed-away commit at full speed with no signal —
    which is why everyone reached for it: it *looks* like the ref-scoped,
    therefore-careful option. Three of us hit this in one hour on the same
    command, which makes it a property of the tool rather than three mistakes.
    Two clones were configured
    `remote.origin.fetch = +refs/heads/main:refs/remotes/origin/main` with
    `fetch.prune` unset, so `git fetch origin` had only ever updated
    `origin/main` and force-pushes to every other branch were structurally
    invisible. **Configure the wildcard refspec and `fetch.prune = true`, and
    before asserting a fact about a remote branch run `git ls-remote`, which
    queries the server.** A ref-scoped command is not self-updating.

    One of the three wrong claims was wrong in an instructive way, and the
    distinction matters in a document about reasons: a `decoder-completeness`
    count of 2 on `cross-section-exclude` was **accurate about
    `1a4ae2a`**, the real branch head when it was measured. The measurement was
    correct; the staleness was the defect. And **an unvalidated instrument that
    gives right answers is the one that never gets fixed** — the clone that
    produced a wrong number was diagnosed in twenty minutes, while the clone
    that produced correct numbers by habit rather than by configuration would
    have kept doing so until the day a force-push mattered.

    Report the ruler with the number. Seven and eleven for the same file were
    occurrences of the literal `--since` versus lines matching bare `since` —
    two people measuring correctly with different rulers and reporting the
    counts as if the ruler were implied. That cost a round of messages.
- **An unrecognised flag must exit non-zero, exactly like an unrecognised ref.**
  `preflight.py --sinse origin/main` fell through to staged mode and printed
  `nothing staged` at exit 0 — a clean run over nothing wearing the face of a
  clean run over everything, and the most reassuring line the tool can emit.
  The unknown-*ref* guard was written deliberately for this hazard, so the
  protection had stopped one argument short of itself. Scope validation belongs
  on every input that selects scope, argv included. Landed in `97ddc3c`.
- **The installed hook is not version-pinned, and this is an open hazard, not
  a solved one.** `--install-hook` writes `exec python3
  scripts/preflight.py` — path-relative. Install it once on `main`, check out a
  feature branch to build, and every commit from then on runs *that branch's*
  script. Proven end to end on `cross-section-exclude` @ `c6e749a`, whose
  script predates `decoder-completeness`: an undecoded `primerDepthMicrons`
  staged on `PaintAnalysis` gets `clear (3 advisory)` and **the commit is
  allowed**, while `main`'s script refuses the identical staged tree with one
  blocking failure naming the field. This is the day's shape in its most
  convincing costume — not a tool that ran and found nothing, but *the wrong
  tool* running and finding nothing, behind a correct-looking clean line. It
  cannot reach `main`: a trial merge of both branches onto `97ddc3c` merges
  `scripts/preflight.py` cleanly with `main`'s version winning, so the landing
  order is unaffected.

  **Decided and implemented, and it took two mechanisms because either alone
  leaves a hole.** `--install-hook` now writes a hook that resolves the script
  from `origin/main` and **refuses rather than falling back** to the worktree
  copy when that ref cannot be resolved (`e60604c`) — falling back is exactly
  the silent substitution it exists to prevent, and a hook that declines to run
  is recoverable where a hook running the wrong checks is not. And the script
  itself refuses to run when it is older than `origin/main`'s copy
  (`ad9e3c0`, `check_script_currency`), which covers every invocation that is
  not the hook.

  Pinning *alone* was the rejected option, and the reason is worth keeping — a
  pin protects only people who reinstall the hook, and on its own it executes a
  script that is not in the tree being committed, trading one "which tree is in
  force" trap for another. The self-check travels *in* the script, so any copy
  old enough to lack a check is also old enough to be refused by the copy that
  has it. Refusal is loud, which is the property this whole family of defects
  lacks.

  Three design details, each of which would have made it useless:

  - **Staleness is "check functions `origin/main` has that this copy does
    not", never "differs from `origin/main`."** This file is edited on
    branches that *add* checks; refusing those would block the work that fixes
    the hazard.
  - **It compares `__file__`, not a fixed repo path.** The first cut read
    `REPO/scripts/preflight.py` — the file at the path rather than the script
    actually executing — so a stale copy run from elsewhere compared `main`
    against `main` and cleared itself. That is this section's own
    assert-on-behaviour rule violated by the guard written to enforce it: a
    fixed path is a representation of "the script running", and for a hook
    that execs by path the two coincide only by luck.
  - **It fails open for a missing remote only**, with an advisory naming the
    fetch — a fresh clone or an offline machine has nothing to compare
    against, and blocking work it cannot judge is the over-eager-blocker
    failure above. It has no "probably fine" path, per the no-subject clause.
  - **The refusal names a runnable command and every missing check, not a
    count.** Per the no-subject clause a refusal states the gap and the next
    action; per §5b's scope rule a reader needs to know *which* checks were
    absent to judge what the clean line was worth.

  One residual, stated rather than hidden and since **demonstrated** on an
  isolated fixture: the comparison is against the local `origin/main` ref, so
  the guard inherits the staleness failure above. With the tracking ref pinned
  to an older commit the stale script emits **nothing** and clears itself; with
  the same script and the same tree and only the ref updated, it fails naming
  the missing check. The advisory covers the absent case, not the stale one.

  This is worth more than a footnote because **it composes with the
  misconfigured-clone defect above**: a main-only refspec plus this guard is a
  guard that silently approves itself, which is the `__file__` bug's failure
  mode arriving by another route. The remedy is already written — wildcard
  refspec, `fetch.prune`, `ls-remote` before asserting a remote fact — but the
  guard is now a *consumer* of that rule and not only a subject of it, so
  configuring the clone is a precondition of the guard working rather than
  personal hygiene. §1's
  "run `main`'s script against a feature branch" is enforced by the tool only
  for a tree that already carries the guard. Every branch in flight when it
  lands predates it and cannot refuse itself — verified zero occurrences in
  `c6e749a` and `6230c4f` — so for those §1 stays a disposition until each is
  rebased onto a `main` carrying the guard. This bootstrap gap is a property of
  any guard that travels inside the thing it guards, not a defect in this one,
  and it is the argument for landing it ahead of the remaining branch merges
  rather than after them — a call since borne out: with #5, #6, #7, #8, #10a,
  #10b, #11 and #13 merged, those trees carry `main`'s script and the guard is
  correctly silent on a current copy. What remains is any branch cut before the
  guard landed and not yet rebased: a smaller and shrinking set, but not an
  empty one. A rule that claims mechanical enforcement it does not
  yet have is the true-instruction-false-reason failure above.
- **Install a parser; the constraint was never real.** The missing toolchain
  was recorded here as a structural limit of this team and worked around in
  language for an afternoon — "nobody says a tree parses without naming who
  parsed it" — before anyone tried to remove it. A swift.org **Linux tarball is
  enough**: parsing needs no Xcode and no iOS SDK, and four environments went
  from zero to parsing in minutes once one person tried. The general form is
  this document's own error one level up: **a constraint nobody has attempted
  to remove is an assumption, not a constraint.** What remains is real — no
  Xcode and no device, so no type check and no run — and Compiled/run fields
  must say that rather than the superseded version.

  Two installation details, both of which produced a silently non-parsing
  check:

  - **Install where the discovery table looks, not in a version-suffixed
    directory.** `~/toolchains/swift-6.0.3` is invisible to it; symlink
    `~/toolchains/swift` at it. Two people hit this independently, because a
    version-suffixed directory is how the tarball extracts and the only way to
    keep more than one — an honest advisory, but a false negative on
    capability. **The symlink is load-bearing, not the `~/.profile` export**:
    the export is what makes an interactive run clean, the symlink is what
    makes the hook work, so a sandbox rebuild needs both the tarball and the
    symlink restored or the hook quietly drops to advisory. And not in `/tmp` — it parses from there and
    says it will stop, because `/tmp` does not survive a rebuild, and a reader
    who saw the check working yesterday will not reread the advisory.
  - **Verify in the environment the hook runs in, not the one you type in.**
    `SWIFT_FRONTEND` exported from `~/.profile` makes interactive runs clean
    while `git commit` still prints the no-toolchain advisory: the pre-commit
    hook runs with a bare environment. Check with
    `env -i PATH=/usr/bin:/bin HOME=$HOME`. The check was working exactly where
    it was being looked at and not where it actually fires, which is the
    assert-on-behaviour rule aimed at *which* behaviour.
- **"Parses" is now several different claims, so name the parser.** Four
  environments here run at least two frontend versions (5.10.1 and 6.0.3), and
  a tree that parses under one can fail under the other on syntax that is
  genuinely valid in the newer language. Sean's Xcode toolchain is a further
  version and the only one that decides whether the app builds. So a parse
  result carries its frontend version — which is why the check prints it — and
  no local parse is evidence about Sean's build beyond "worth compiling".
- **Passing means "worth compiling", never "works".** The tool says so in its
  own output. §4 clauses 4-6 still need Xcode and a device. Given this repo's
  history, tooling that could be mistaken for a build would be worse than no
  tooling.

### 5c. The other direction: code drifting from correct documentation

Every check in `preflight.py` assumes documentation goes stale behind code.
Two of task #10's three scoring divergences were the reverse:
`ALGORITHM_EXPLAINER.md` was **right**, and the Swift had drifted away from it.
Nothing monitored that direction, and the asymmetry is why — a stale doc is
caught by anyone reading the code, while correct documentation the code has
left behind is only caught by someone reading the doc *as authority*, which is
not a thing anyone does routinely. It was a review-habit gap before it was a
tooling gap.

`scripts/check_doc_drift.py` mechanizes the tractable subset: **numeric claims
only** — the factor weights and the height bands — which is where all three
real divergences lived. General prose agreement is not tractable and is not
attempted.

Two conditions on it, both from testing it against the way this document is
actually edited rather than against a regression:

- **It must assert the expected number of claims, not just compare the ones it
  finds.** Converting the height-band list to a markdown table made it check
  three bands instead of four and still print `clear`. That is the dead-check
  failure in its quietest form: the check did not break, it just quietly
  examined less, and the missing band was the rule-out row. A count that is
  expected must be asserted or a format change silently narrows the check.
- **A format failure must not be reported as a drift failure.** Rewording one
  heading from `(30% weight)` to `(weight 30%)` produced
  `doc [20,15,...] != code [30,20,...]` — which reads as a scoring regression
  and would send the reader to the Swift, where nothing is wrong. Failing on a
  prose rewrite is the *right* direction to fail, but it has to say that is what
  happened.

Accepted as the cheap version deliberately. The robust alternative is a data
file both the document and the code reference, which is more work and changes
how the document is authored; that is worth doing only if this fires often
enough to be annoying. Recorded so the choice is visible rather than defaulted
into.

- **A check's stated limits are part of its output, and a true claim resting on
  a mechanism that cannot support it is the same defect as a wrong reason.**
  `check_doc_drift.py`'s docstring says the height bands are "compared"; what
  is compared is a *static reading* of `heightAlignmentScore`, modelled as an
  ordered list of guards. Exercised rather than read, the parser is unmoved by
  reordering `if diff <= toleranceInches` above the rule-out guard — identical
  `100/75/50` output, no complaint — while in the real function that
  reordering hands a caller passing a tolerance above 6″ a `100` for a height
  difference that should exclude, which is the pre-#10a defect restored. The
  honest fix is to execute instead of parse, and that needs the Swift test
  target still at Stage 0; a cleverer parser would be the same mistake one
  level deeper, because it would still be a representation. Until then the
  docstring must say what it actually establishes. **A check that overstates
  its mechanism is trusted for coverage it does not have, and nobody looks
  again.**

**And the mirror of that, which cost a correction in the `@Published` rule:
a WARNING that overstates its defect is deleted by the first person who tests
it.** The rule as first landed said the two computed properties "would not be
invalidated" — false, because both are half-published, and a chip built on
either would have refreshed on every transition anyone tried. **The reader who
builds it, sees it work, and concludes the caveat was over-cautious then drops
the whole warning, including the true part.** Overstating a real defect is not
the safe direction: it makes the warning falsifiable by the cheapest possible
experiment, and a falsified warning takes its correct half with it.

**The specific failure was mine and it is worth naming, because it is not
carelessness — it is a category of review I had no rule for. I generalised a
teammate's finding into a rule without re-deriving the finding.** The
observation that the inputs were unpublished was checked; the *consequence*
claimed from it was carried over verbatim. **A finding and the conclusion drawn
from it are two claims, and promoting the first to a rule does not verify the
second.** The check that would have caught it took one grep — the same grep
that produced the finding, pointed at the sibling operand instead of the one
named. So: **when generalising someone else's finding, re-derive the
consequence from the source, not from their statement of it** — especially
when your commit makes it normative, because a rule is read by people who will
never see the message it came from.

**The Swift frontend advisory is available to clear, not only to report — and
executing a reduced shape beats typechecking one.** `preflight.py`'s
`swift-parse` advisory names the exact paths it searches, including
`~/toolchains/swift`. A swift.org Linux tarball needs no iOS SDK, installs in a
few minutes, and takes the whole-tree run from "1 advisory, 42 files NOT
parsed" to **0 advisories with all 42 actually parsed**. Every `NOT COMPILED`
handover today reported that advisory rather than removing it. Parsing is still
not a build — no iOS SDK, no type-check of a SwiftUI `body` — but "no frontend
found" is a fixable environment gap, not a property of the sandbox, and a check
that reports itself unavailable is worth less than the twenty minutes it costs
to make it run.

**And an installed toolchain is not the same as a working one — `preflight`
reported 0 advisories on a tree where nothing could be compiled at all.**
`swift-frontend -parse` links no curses, so the parse check passed 42/42 while
`check_doc_drift`'s guard-order probe — the one check here that actually
*builds and runs* code — failed on a missing `libncurses.so.6`. Its advisory
said so precisely ("a broken toolchain, not an absent one"), and it is a
`warn`, so a reader skimming for `preflight: clear` sees a green tree. **The
distinction the two checks disagree about is exactly the one that matters:
parsing proves the syntax is legal, and only executing proves an ordering
claim.** Fixed by the remedy the advisory already named — Ubuntu 24.04 ships
only the wide build, so `libncurses.so.6` is a symlink to `libncursesw.so.6` —
after which the probe reports `4 height bands executed` rather than `parsed`.
**That one-word difference in its output is the whole claim**, and it is the
only place either state is visible.

The reusable half, which is this section's own subject turned on the tooling:
**"the checks are clear" is a claim about the checks that RAN.** A `warn` that
degrades a check to a weaker check is not the same as a check that passed, and
a suite reporting a headline clear while one of its probes is silently
downgraded is a green tick over an unfailable check. **Read what each check
says it did, not the aggregate** — and prefer a check that fails loudly when it
cannot run.

**One correction, because it changes what the reader should conclude: this did
not affect every sandbox, and the reason is the part to act on.** The same
commits reported `4 height bands executed` — the strong form — in another
agent's environment, whose base image already carried
`libncurses.so.6`. So the number quoted in that handover was honest **and** the
probe was downgraded elsewhere on the identical tree, at the same time,
verified from the same plain clone. **A per-agent green is not a property of
the commit.** Which is worse than a uniformly broken check: the agent whose
probe ran had no way to know another's had not, and neither figure was wrong.
**So a `NOT COMPILED` handover has to name the environment the checks ran in,
not only the commit and the numbers** — the tree is shared, the toolchain is
not, and an environment-dependent check reports a property of the pair.

**And that obligation belongs in the tool, not in the handover discipline —
`check_doc_drift` now names the compiler it used.** Its clear line reads
`4 height bands executed by <path> (<version>)`; the degraded line still says
`parsed` with no compiler named at all. The reason is this section's own rule
applied one level down: a rule about what to state before believing a result
holds while it is fresh and lapses once it feels routine, so **the statement
has to be produced by the thing that knows the answer.**

**The path alone was not sufficient, and this thread proved it rather than
supposed it.** The probe resolves through `~/toolchains/swift`, a convenience
symlink pointing at a version-specific directory — and two agents here ran
**5.10.1 and 6.0.3** behind that identically-spelled path on the same day, on
the same tree. **A resolved path is not self-describing.** Same disguise as
the two shot lists: a name that looks authoritative and is one indirection
away from the fact.

**Verified in both directions, per §5b, because a check that only ever prints
green is the thing it was built to detect.** Forward: the clear line names
`swiftc` and its version. Reverse, two ways — `SWIFT_C` pointed at a
nonexistent path degrades to `parsed`, with the advisory naming the reason and
no compiler quoted; and hoisting the tolerance guard above the rule-out in
`heightAlignmentScore` still produces the `FAIL [doc-drift]` guard-order
disagreement. **The added reporting did not weaken the check it reports on**,
which is the claim worth making about a change to a check rather than to the
code it guards.

With a toolchain present, Vector's reduced-shape method extends one step:
**compile the shape AND run it, with `precondition`s for the behaviour the real
code must have.** A typecheck proves the shapes are legal; executing an
assertion set proves the state machine transitions the way the spec says. Its
discriminating half is unchanged and non-negotiable — **mutate the shape and
confirm each assertion FAILS.** Three mutations of the Item 2 attestation shape
(dropping the analysis-shot guard on the record, dropping it on the ask,
defaulting the tri-state to `false`) each failed on a different precondition;
had any passed, the assertion set would have been decorative. The limit is the
same as before: a reduced shape says nothing about the file it was reduced
from.

**Two correct patches can produce a defect neither one contains, when one of
them silently changes the POPULATION the other's guard reasoned about.** Every
correction today fixed a claim that was wrong when written. This one was not:
row five's guard, `sharpnessScore == nil && frameConfirmedClear != nil`, was a
sound proxy for *"this photograph postdates the sharpness field"* — for exactly
as long as the attestation only existed on the screen that measures sharpness.
Building the attestation on the protocol camera made both halves permanently
true there, and the scar-photo traversal fix is what first makes that page read
those photographs at all, so **the regression arrived with the fix rather than
after it.** A note written to mark the rare unmeasured photograph now fires on
nearly every analysis shot of every case, and **a note that fires always
carries no information — the reader stops reading it, including on the one
photograph it was written for.**

Neither patch is revertable and neither is wrong, which is what makes it worth
a rule: **a guard that infers a fact from a coincidence is correct until the
coincidence ends, and nothing in the guard says which fact it was standing in
for.** So when a condition tests a proxy — a `nil` check standing for
provenance, a field's presence standing for a code path, a count standing for a
state — **write down the fact it is a proxy FOR, because the next patch to
change the population will not see the inference.** The repair is a real test
of that fact, never a rewording of the consequence: rewording keeps the proxy
and moves the error somewhere harder to find.

**And the review consequence: after landing two independent patches, re-derive
any condition whose inputs either of them can now set.** Both were verified
against the tip and applied clean; the interaction is invisible to `git am`,
to the parse check, and to every per-patch review, because no single diff
contains it.

**Resolved by recording the fact, not by rewording the note:** the guard now
reads `sharpnessScore == nil && sharpnessMeasurable`, a stored `Bool` set only
by a capture path that actually measures. The scar screen sets it `true`, the
protocol camera leaves it `false` because it measures nothing, and it decodes
`false` for every photograph saved before the field existed — none of which
came from a measuring path either. **The copy is unchanged**, which is the
point: the sentence was always right and the predicate was reading the wrong
field. It cost one `Bool`.

**A footnote on the magnitude, because getting it wrong is the same class of
error:** the analysis shots per vehicle come from
`PhotoType.requiredCaptureProtocol` (2 `.closeupDamage` + 2 `.paintTransfer` =
**four**), not from `CaptureProtocolStep.fullProtocol`, which has 8 and 4 of
them across its 30 steps. `CaptureViewModel.protocolShots` is
`requiredCaptureProtocol`, and `fullProtocol` is a coaching-metadata lookup
table — `requiredCaptureProtocol`'s own doc comment says so, and says the
number was once duplicated inconsistently in three places. **Counting a
population from the richer-looking list is the shape that comment was written
about**, and the correct figure is smaller, which does not weaken the finding:
four notes per vehicle on every case is already a note that carries no
information.

**When a quantity has two plausible sources, the richer-looking one is the
wrong one by default.** The interaction finding above shipped with a population
figure of seven analysis shots per vehicle. It is four. Seven came from
`CaptureProtocolStep.fullProtocol`, a 30-step **coaching-metadata lookup
table**; the population is `PhotoType.requiredCaptureProtocol`, the 10-shot v1
list that `CaptureViewModel.protocolShots` derives from. **The doc comment on
the correct source exists precisely because that count was once duplicated
inconsistently across three places** — so the tree already carried a warning
against the mistake, attached to the very constant that answers it.

Two independent errors produced one figure, and they are worth separating.
**The first was reading a summarising comment instead of the array**: "ids 5, 6,
7, 11-13, 21, 26" was miscounted as seven where it enumerates eight, which
`grep -c` on the array settles in one command. **The second was choosing the
wrong array**, and no amount of care counting the first one would have caught
it. **A verified count of the wrong population is still wrong, and it looks
more trustworthy for having been counted.**

So: **name the source of every quantity you write down, in the same sentence as
the quantity.** Not for provenance — because naming it is what surfaces the
question of whether it is the right source, which counting never does. The
general form of both halves: **derive a figure from the definition the code
executes, not from prose about it** — a comment enumerating a list, a docstring
summarising a range, and a table describing a schema are all representations,
and this document has now been wrong three times in one day by trusting one
where the executable definition was one line away.

**A mutation that does not mutate passes, and reads exactly like coverage.**
The discriminating step above has its own failure mode, and it landed on both
of us independently while writing the row-five repair. Two shapes, two ways to
get a free pass:

- **The mutant is byte-identical to the original.** A `sed` whose pattern
  silently matches nothing compiles the unmodified shape, which then passes.
  Nothing distinguishes that from a mutation the assertions genuinely survived.
  **Confirm the mutant differs from the original before trusting that it
  passed** — a `diff` or a checksum of the source, not the exit status.
- **Every assertion passes the field explicitly, so none exercises the
  default.** Flipping a stored property's default then breaks nothing, because
  no case in the set was constructed the way the decoder and every unmigrated
  call site construct one: **by omission.** Any assertion set for a new field
  with a default needs at least one case that omits it.

- **The mutant does not compile.** A third shape, found by mechanising the two
  above rather than by reading them: a `sed` that produces invalid Swift makes
  the run fail, and a failing run is exactly what a killed mutant looks like.
  **A non-building mutant tests nothing** — it never reached the assertions.

So the pass condition is narrower than "the mutant failed": a mutant must
**differ**, then **build**, then **fail**. Three states, and the exit status
collapses all three into one bit.

The first two are the same error as an all-clear over a set no member can fail,
aimed at the check instead of the artefact: **a check that cannot fail is not a
check, and neither is a mutation that cannot change anything.**

**These guards belong in the runner, not in a reviewer's attention.** Each is a
rule about what to verify before believing a result — the kind that is followed
while a technique is fresh and skipped once it feels routine, which is why
`check_remedies` exists instead of a note asking authors to declare their
remedy kinds. Both of today's instances were missed by people who had just
written or just read the rule.

A runner that enforces differ-then-build-then-fail can also prove its own first
guard on every run, by carrying a deliberate **no-op canary**: a mutation whose
pattern cannot match, which the runner must report *as* a no-op rather than as
a pass. **A canary is the mutation-testing form of confirming that a reduced
shape fails when the property under test is removed** — the check checked
through itself rather than through the thing it wraps.

Run here and confirmed in both directions: all four mutants killed with the
canary reported as a no-op, and then — deleting the defaulted-argument
precondition from the harness — `flip-default` **survives** and the runner
exits non-zero naming it. **A runner that only ever prints green is the thing
it was built to detect**, so the second run is the one that establishes it
works.

**One portability note, and it is an instance of this section's own subject.**
The runner resolves `swiftc` from a fixed default path, which happens to
resolve in this sandbox only because of a convenience symlink pointing at a
version-specific directory. **A missing compiler makes the baseline check fail
loudly, which is the right direction** — but the toolchain path is exactly the
kind of per-environment fact that made the same commit report two different
`check_doc_drift` results today. **A tool that verifies claims about a tree
should say which compiler it used**, for the same reason its probe says
"executed" rather than "parsed".

**Done, and fixing it produced two more instances of the same class — both
found by running the fix rather than reading it.** The runner now resolves a
compiler in order (`$SWIFTC`, then `PATH`, then the known toolchain path),
prints the binary, its `--version` and the host before doing anything, and
repeats them in the verdict line. Then:

- **An explicitly-set `SWIFTC` was not validated.** A typo'd override reached
  the baseline step and reported `BASELINE DOES NOT COMPILE` — which reads as
  *the code under test is broken* when the truth is *the path is wrong*. **A
  diagnostic that misattributes its own failure is worse than no diagnostic**,
  because it sends the reader to the wrong file. It now refuses with exit 2 and
  says which path it was given.
- **The reverse-direction run appeared to exit 0.** Piping the runner into
  `tail` to read the verdict returned the *pipe's* status, so the deliberately
  broken assertion set looked like a pass in the terminal. The runner was
  correct — `$?` on the unpiped invocation is `1` — but the transcript said
  otherwise. **A harness that is right and reports through a lossy channel is
  indistinguishable from one that is wrong**, which is the same failure as an
  exit status collapsing differ/build/fail into one bit, one layer further out.

Neither is exotic and both were invisible to reading. The pattern worth
carrying: **a verification tool needs its own failure modes exercised on
purpose** — wrong compiler, missing compiler, broken assertion set — and each
must be distinguishable in its output. Three distinct exit codes (`0` pass,
`1` a mutant survived, `2` cannot run) rather than pass/fail, for the reason
`preflight`'s "worth compiling" disclaimer exists: **the useful distinction is
not between good and bad news, it is between a result and the absence of
one.**

**Checked against the runner as shipped, and the prose is ahead of the tool —
which is this section's own subject, so it is recorded rather than quietly
reconciled.** The attached runner is byte-identical to the previous revision
(same MD5), still resolves `swiftc` from the one fixed default path, prints no
`--version`, and on an unusable `SWIFTC` still reports `BASELINE DOES NOT
COMPILE` and exits `1` — exactly the misattributing diagnostic described above
as fixed. The three-exit-code design and the compiler-naming requirement are
right; **what exists so far is the specification of them.** No claim verified
with this runner is affected — the mutation results reproduce and the canary
fires — but **"the runner now names its compiler" and "the runner should name
its compiler" are different claims, and only the second one is currently true.**
Found by running it rather than reading the patch, which is the same
discrimination the canary exists to enforce, applied to the tool that carries
the canary.

**A surviving mutant tells you an assertion set has a hole; it does not tell
you where, and the obvious reading can be wrong.** The decline affordance's
leak test survived its mutant, and the diagnosis recorded with it was that the
test used the *decline* path, which self-clears after its capture, so nothing
was left to leak — the affirmative being the only state that can leak. Run
against a reduced shape, that is not what defuses it: a decline followed
immediately by a reference shot still holds `false` and **does** kill the
mutant, because the post-capture reset has not run yet. What defuses the test
is the **capture sitting between the answer and the reference shot** —
`answerNo(); afterCapture(); isAnalysisShot = false` passes identically with
the guard and without it.

So the property is **ordering, not which answer was used**, and the corrected
rule is more general than the original: **a negative test is only a test while
its precondition survives to the moment of the assertion.** Any step between
setup and assertion that can reset the state under test — a post-capture
cleanup, a lifecycle hook, a teardown — silently converts the test into a
tautology. The affirmative case is worth adding because it *cannot* be reset,
which makes it the robust one; but stating the reason as "use the affirmative"
would leave a reader with a rule that fails the moment the reset moves.

Both readings produce the same patch here, which is exactly why this is worth
recording: **a fix can be right while the reason attached to it is wrong, and
the reason is what gets generalised.** Verify the diagnosis the same way the
finding was verified — by constructing the case the diagnosis predicts and
confirming it behaves as claimed.

**Naming an interaction correctly and mis-routing it is its own failure, and
it is the one that keeps a defect open.** The row-five interaction was reported
in the same message as the patch that caused it — described accurately, as a
rarity note becoming furniture — and filed as a copy question for the owner of
the locked strings. It was never a copy question. **A note whose predicate
reads the wrong field cannot be fixed by any wording**, so the only person who
could act on it was not the person it was addressed to, and the routing was
what would have kept it open rather than the description.

The existing placement rule asks which artefact the reader opens. **This adds
the prior question: which change would actually resolve this?** Answer that
first, and the owner follows from it. A finding routed by its *subject* —
this concerns copy, so it goes to copy — lands on whoever owns the words when
the repair is a data change. **The test is what the fix touches, not what the
symptom is made of.**

Worth stating because everyone involved did their half right: the interaction
was spotted immediately, described without overstatement, and recorded in the
same commit as its cause. **A correct finding addressed to the wrong owner
looks completely handled**, which is why it survives review — nobody is
waiting on it and nobody is working on it.

**And the guards belong in a runner, because a rule about what to verify
before believing a result lapses exactly when the technique stops feeling
new.** Vector's `mutate.sh` mechanises all three: a mutant must **differ**,
then **build**, then **fail** — and the exit status collapses those three
states into one bit, which is why every free pass reads as coverage. It carries
a deliberate no-op canary (a pattern that cannot match) which it must report
*as* a no-op rather than as a pass, so guard 1 is proven on every run. **That
canary is the mutation-testing form of confirming a reduced shape fails when
the property under test is removed: the check checked through itself rather
than through the thing it wraps.**

Worth recording what it caught the first time it was pointed at new work.
Running it over the decline-affordance shape killed three mutants and reported
a fourth **surviving** — a mutation that wrote the live attestation onto a
reference shot. **The gap was real and the fix was right; the reason first
recorded for it was wrong**, and the correction is above: the property is
ordering, not which answer was used. **A fix can be right while the reason
attached to it is wrong, and the reason is what gets generalised** — that
wrong reason had already been carried into §4c as a rule about answer
lifetimes before anyone constructed the case it predicted.

**Grouping two findings by a shared symptom asserts they share a cause.**
`isTooClose` and `hasMotionBlur` travelled as one open item for a month —
"written on no path, no gate measures them" — and the second half was true of
one and false of the other. The gyro was measured at 30 Hz the whole time;
what `hasMotionBlur` lacked was a **window**, not a sensor. Pairing them
meant every reader who accepted the item accepted the false half with the true
one, and the pair read as a single well-understood gap. **Split an item the
moment its members' causes differ, even when the remediation is identical** —
and when a shared item is closed, say which member closed and why the other
did not.

**The item was mine and it survived a month of exactly the reviews that should
have caught it, which is the part worth generalising.** Every re-derivation
this round re-measured claims: reachability, populations, write sites,
diagnoses. **Nobody re-derived the item's own STRUCTURE**, because a grouped
item presents as one claim and gets checked as one — the shared symptom is
what a reader verifies, and it was true. **A false clause inside a true item
is invisible in a way a false item is not**, since the item as a whole passes
every test applied to it.

So the check is cheap and specific: **for any item naming two subjects, state
each one's cause separately and see whether the sentence still holds.** Here
"no gate measures them" splits into a truth and a falsehood the moment it is
written twice. The same test catches the inverse error — items split apart
that share a cause, where fixing one silently fixes the other and the second
gets closed as done without a diff. **An item list is a set of claims, and a
claim about two things is two claims wearing one bullet.**

**A guard no reachable state can falsify is worth keeping, but say so
explicitly.** The mutation runner reported `drop-measured-guard` as surviving
on the motion-blur shape, and it was right: a sample is only ever appended to
`motionSamples` — before the trailing-window rewrite, the peak was only ever
raised — on the same line that sets `motionMeasured`, so the first clause is
implied by the second in every reachable state. (Recorded against the `peakRotationRate`
field, which the trailing-window fix has since replaced with a rolling
`motionSamples` buffer; the guard and the reasoning carry over unchanged, since
the buffer's recency filter is likewise only fed where `motionMeasured` is
set.) **That is a fact about the
guard, not a hole in the assertions** — and the wrong responses are deleting
the guard (it becomes load-bearing the moment any path seeds a peak without a
reading: a replayed buffer, a restored draft, a fixture) and adding an
assertion that merely re-states the reachable behaviour. The right one is an
assertion of the **implication** over the state space, plus a case
constructing the unreachable state directly, so a future edit that breaks it
fails there rather than in an evidence appendix. **A redundant guard on a
persisted claim costs one `&&`; the failure it prevents is a finding asserted
about a device that measured nothing.** And it is a **third instance of the
half-published class**, stronger than the two that produced that rule:
`measuredMotionBlur` reads `motionMeasured` and the rolling `motionSamples`
buffer (previously `peakRotationRate`) and **neither is `@Published`**, where the earlier pair each had one published
operand and refreshed by co-assignment. So a `body` reading it would not
refresh at all — harmless only because its single reader is the imperative
call site in `performCapture`, and the fix when it is surfaced is the same:
publish the whole input set. **Three instances in one file means the rule is
about this service's shape, not about two properties** — every new
`measured*` computed property here starts unobservable by default, so the
check belongs at the point one is written rather than at the point one is
displayed. (Found on a run whose verdict I first
read through a pipe, and so first read as passing — the pipe-masking failure
recorded above, hit in the course of using the rule that names it.)

**A copy constraint that says "neutral", "symmetrical" or "not a fault" is
not a constraint on characters, so a string comparison cannot enforce it.**
The two attestation answers passed their lock entry byte-for-byte while
shipping an `exclamationmark.circle` on the decline and a dimmed capsule
against a blue primary one — **a warning glyph is a warning adjective the copy
lock cannot see**, and the button hierarchy said the same thing again in
layout. The wording was written precisely to keep the decline from reading as
a confession, because an answer that reads as an admission is one nobody gives
twice, and that loses the finding instead of recording it.

**So when copy carries attribution, neutrality or symmetry, check the icon,
colour, weight and order against the same constraint.** It survived four
readers for this section's own reason: **the strings were the unit of review,
so a channel outside the strings was outside the review** — the same route as
§4.0's cited-document rule, where the report contained no banned language and
merely pointed at it. A lock that inspects strings cannot see one hop away,
whether that hop is a citation or a glyph.

**Two mechanical notes worth keeping.** The repair is **no icon on either
answer** rather than a matched pair, because any mark on the adverse option
reads as severity and a mark on the favourable one alone restores the
hierarchy — neutrality is not achieved by balancing two signals. And the
symmetry is held by **one shared label builder per screen**, not two call
sites that currently agree: two independent builders drift the moment someone
restyles one, which is the single-source reasoning that made
`captureNotes(for:)` the only source of the note conditions and
`captureConditionPhotos(in:)` the only traversal.

**Verified in the tree, and the argument does not stop where it was applied:
there is one builder per SCREEN and their bodies are byte-identical across the
two.** `attestationAnswerLabel` and `scarAnswerLabel` are the same six
modifiers, so the symmetry is structural *within* a screen and maintained by
coincidence *between* them — which is the position the two answers were in
before the fix, one level up. Two screens agreeing today drift the moment
someone restyles one, and the failure is the asymmetry re-entering on a single
camera while the other stays correct: **harder to notice than the original,
because the screen a reviewer opens looks right.**

Not refactored here, deliberately — a shared component is a `Views/` change
with its own diff, and the duplication is currently correct. **But it is
recorded where a reader restyling either row will see it, because "held
structurally" is true of each screen and false of the pair, and only the
second claim is the one a future edit tests.** The general form:
**deduplicating a claim inside one file leaves the same claim duplicated
across files, and the second copy is invisible from the first.**

**A computed property with no reader is not a fix — it is the always-false
disguise with a better name.** The trailing-window repair added
`motionMeasurable` on the service, correctly reasoned and correctly named, and
nothing read it: one declaration, one doc mention, zero consumers.
`hasMotionBlur` is a plain `Bool` persisted into evidence, so `false` still
meant both "motion was measured and the phone was steady" and "motion was
never measured", and a gyro-less device produced the second while the report
read the first. **The distinction existed in the service and could not reach
the artefact that makes the claim** — the same failure as a field that exists,
decodes, and always reads `false`.

The check is one grep and it belongs in every "recorded, not inferred" fix:
**after adding a field that separates measured from unmeasured, confirm the
distinction reaches the artefact** — persisted on the model, decoded
additively, read by the renderer, and named by a condition. Second instance
today after `sharpnessMeasurable`, which is why it is a rule rather than an
anecdote. Its mirror is worth naming in the same breath, because both surfaced
in one round: **a condition with no writer** (§1.2's unreachable decline) and
**a writer with no condition** (`hasMotionBlur` persisted with no note row).
Neither is visible from the side you are standing on.

**And the second unfalsifiable guard in two patches, so record the pattern
rather than the instance.** `motionMeasurable`'s gyro-presence clause is
implied by a non-empty window in every state reachable through the sample sink,
exactly as `motionMeasured` was implied by a nonzero peak. Both were found by a
runner reporting the clause-dropping mutant as surviving, and the response is
the same: keep the clause, assert the **implication** across the state space,
and construct the unreachable state directly. **Two instances in one service
means the shape belongs to the design — a guard on a persisted claim costs an
`&&`, and its absence is only ever discovered in an evidence artefact.**

**A patch that deletes a field owes a sweep of the prose that names it.** The
trailing-window fix removed `peakRotationRate`, and three passages named it:
two in this section and one on the task #4 row, including the third
half-published instance, whose *point* survives intact because the rolling
buffer replacing the field is equally unpublished. **A conflict-free `git am`
would have produced a document citing a field that no longer exists** — the
apply is mechanical and the citation is semantic, so nothing in the merge can
see it. Corrected by naming the buffer with the old field in parentheses, so
the instance count stays at three and the history is still followable. This is
the **deletion direction** of the status-row rule: a sentence describing a
field outlives the field by default, exactly as a sentence describing owed work
outlives the work.

**And two honest counts of the same quantity disagree when they count different
trees, which convergence hides rather than reveals.** Three of us reported
`Totals:` figures of 21573, 21583 and 21624 within minutes, each correct about
a different tree — `main` without the window fix, one agent's local base plus
it, and `main` with it. **A number that matches is not a number that agrees**:
reconciling to a shared figure without naming the tree is how two measurements
of different things come to look like confirmation of one. Same correction as a
per-agent green being a property of the pair rather than of the commit, so
**a count in a handover names the commit it was taken at, not only the value.**

**A count taken mid-conflict is a count of index entries, not of files.**
`git ls-files` reports each conflicted path once per stage, so a tree with two
conflicts reads as 79 tracked files where 75 exist — and the aggregate says
"79" with nothing in its output to explain why. Confirmed here with
`git ls-files -u`, which reports the unmerged entries directly and is `0` on a
clean tree. **Count from a clean tree, or count the stages you are standing
in** — the same shape as reading a verdict through a pipe: the tool was right
and the reading was not.

**And the sweep is owed by whoever lands ON the rename, not only by the
renamer.** A patch authored against the pre-rename tree carries pre-rename
citations forward through a clean apply, and its author is the one who can
still see both names. This section caught the `motionMeasurable` patch that
way, doing exactly that.

**A qualification that fires on every artefact is furniture, so the repair for
an over-claiming sentence is usually a second variant rather than a softer
sentence.** §2.3's all-clear covered a photograph whose motion was never
measured as though its steadiness had been verified — a member missing a check,
independent of the set-missing-a-member defect repaired in the same section, so
the first repair did nothing for it. **The tempting fix is to weaken the one
sentence** ("the checks that could be run"), which is honest on the reports
that have an unmeasured photograph and needless on every other, and a
qualification a reader sees every time is one they stop reading. The variant is
emitted only where the tree can show the condition, so **the plain form keeps
its strength and the qualified form keeps its meaning.**

**A PROHIBITION STATED ABOUT WORDING DOES NOT BIND THE PREDICATE THAT SELECTS
IT.** §2.3 forbade a permanently-qualified all-clear in four paragraphs, and
the owed selector — `contains { !$0.motionMeasurable }` — made the qualified
form the only reachable variant: the eight protocol analysis shots across two
vehicles (`PhotoType.requiredCaptureProtocol`, 2 `closeupDamage` + 2
`paintTransfer` each) carry the struct default because one capture path writes
the field. **My first version of this paragraph said "twelve", read off the
30-step `CaptureProtocolStep.fullProtocol` COACHING table whose own doc
comment warns against that reading — corrected by Vector, who had made the
identical error hours earlier. Twice in one day by two people is a trap, not a
slip: a count taken from a coaching artefact is a count of INSTRUCTIONS, not
of photographs, and it survived because the number was never load-bearing for
the conclusion.** **The forbidden
outcome arrived through the SELECTOR while every word of the prohibition held.**
So: **state a prohibition over the OUTCOME — what the report may print — not
over the mechanism expected to cause it.** A variant count of two under a
predicate that can only pick one is a one-variant section that reads as two,
and both of the row-counting checks pass it because they match the string and
never the predicate.

**Before a default-valued field becomes a predicate, count how much of the
population carries the default** (the Designer's, and the sharpest rule of the
round). "`motionMeasurable` defaults `false` everywhere else" was written as
reassurance that the trigger reads the persisted model rather than a gate —
true — and **the same words state that the trigger is satisfied for almost
every photograph in the app. Same sentence, opposite conclusion, and the
reassuring reading is the one a reviewer reaches for.** A field that
distinguishes correctly at its one writing site distinguishes nothing across a
set most of whose members never reach that site: **persisting a distinction
and predicating on it are two different completions.**

**A ROW WITH NO BRANCH AND A BRANCH WITH THE WRONG CONDITION ARE NOT THE SAME
CLASS, AND ONLY THE FIRST IS NOW DETECTABLE.** Counting locked rows against
renderer branches closes "specified but never rendered". It cannot see a
branch that exists and guards wrongly — §6.1's filtered verdict is exactly
that, and it is the most damaging item on the board: the code path is present,
reads the unfiltered p-value, and prints a verdict the section marks
**Required** to suppress. **A mechanised count is not a rendered report, and
the widened population must be marked for specced-not-built rows or its
immediate advisories normalise the clear run it exists to protect** (the Tech
Lead's caution, adopted).

**AN UNQUALIFIED QUANTITY INHERITS ITS SUBJECT FROM THE SENTENCE NEXT TO IT.**
§6.1's locked template names a FILTERED percentage; `headlineDisplay` carries
the UNFILTERED score. Using the template whole would make the number lie to fit
the lock, so the implementation kept the claim-bearing sentence verbatim and
left the score bare — and a bare percentage beside "for a filtered subset"
reads as the filtered percentage. **The correct claim silently mislabelled the
figure, and both halves passed review because each was right on its own.**
Rule: **when a locked template cannot be used whole because one of its figures
is not the figure at hand, name the subject of the figure you DO have** — never
drop the qualifier, never keep a bare number. A reader cannot see that a
quantity was computed somewhere other than the sentence it sits in.

**WHEN A FIX HAS TWO HALVES, MUTATE EACH HALF SEPARATELY AND REQUIRE EACH TO
FAIL ASSERTIONS THE OTHER DOES NOT.** The rule is sound and it is kept. **It
has no exemplar in this repository, and the story it was nearly attached to is
the more valuable record** — see below. Vector's form is the one-guard version:
an assertion that cannot fail without the thing under test is not testing it.

**AN UNVERIFIED CORRECTION SPREADS FASTER THAN THE DEFECT IT NAMES, BECAUSE
AGREEING WITH A SELF-CRITICISM FEELS SAFE.** A finding was raised that the
Designer's filtered-headline shape check measured one defect twice: reverting
both guards failed 7, reverting the headline guard alone also failed 7, so the
colour assertions never discriminated. **Three of us endorsed it within four
minutes. I wrote it into this section as fact. She rewrote a correct instrument
on it. Nobody re-ran it.**

**It was false, and the check had been doing the thing it was accused of not
doing.** Measured on the attached v1 by two of us independently: **colour guard
alone fails 3 (two of them the named colour assertions), headline guard alone
fails 5 with no colour assertion among them, both fail 7 — 3 + 5 − 1 shared
totalising assertion = 7 exactly.** The failure sets were disjoint from the
start.

**The mechanism is worth more than the correction: both guards match the same
text.** `reportableSignificance`'s `guard !hasExclusions else { return nil }`
and the headline's `guard !hasExclusions else {` share a pattern, so a
single-pattern edit removes **both** and reproduces the double-revert count.
Confirmed here: a naive pattern-replace on the v1 file yields exactly that
artefact. **A mutation applied by pattern rather than by location is not the
mutation you named**, and its plausible-looking failure profile carries no
diagnostic value.

**So the round produced three nested versions of one shape, and the last is the
one to keep.** A fix can be right while its reason is wrong. **A CORRECTION can
be wrong while everyone's agreement makes it feel verified.** And the
correction was the least-checked artefact in the exchange precisely because it
was volunteered against its own author — **nobody re-runs a claim someone has
made against themselves.** A self-criticism is an artefact like any other, and
this thread has been saying all round that an artefact stating its own limits
still needs its limits checked.

**THE THIRD SHARE IS DISTINCT FROM BOTH MEASUREMENT ERRORS, so it is recorded
separately: REPRODUCE A CORRECTION BEFORE ACTING ON IT, EXACTLY AS YOU WOULD A
BUG REPORT** (the UI/UX Designer's, about her own rewrite). Three different
failures fed one false conclusion — one agent **measured** wrong, one
**verified the wrong version**, and one **rewrote a working instrument without
reproducing the defect at all.** Only the third is available to the person
being corrected, and it is the one the reflex to accept criticism produces.
**A correction is a claim, and one aimed at you is not thereby verified.**

**And the reason the round's own instincts gave no protection here:** every
other defect made something **absent look fine**, so *distrust the all-clear*
was the correct reflex all day. **This one made something fine look absent, and
that reflex pointed the wrong way.** A reflex is calibrated to a failure
direction, so **the one correction that runs backwards arrives with every habit
endorsing it.**

**AND MY OWN "INDEPENDENT VERIFICATION" WAS THE WORST LINK IN THAT CHAIN, which
is the part that indicts the process rather than any one of us.** I compiled and
ran a shape check to test the independence claim and reported that it held — but
I ran the **rewritten v2**, which the false correction had already induced.
**The artefact under dispute was v1, and nothing in the chain touched it.**
Everyone re-ran something; nobody re-ran the thing being corrected. **A
verification that does not load the disputed artefact is a verification of
agreement**, and it reads as strong evidence precisely because it involved
compiling and running real code.

**So the operational rule: when checking a correction, load the artefact AS IT
WAS WHEN THE CLAIM WAS MADE.** Name the version in the claim and in the answer.
A "verified independently" that silently moved to the corrected version confirms
only that the correction is self-consistent — **which is exactly what a wrong
correction also is.**

**And the failure direction is inverted from everything else in this round,
which is why it slipped past four readers** (the Tech Lead's, and it is the
generalisable half): every other defect today made something **absent look
fine** — an always-false flag, a row with no branch, an unreachable variant,
a heading over nothing. **This one made something fine look absent, and it
cost a working instrument.** A hunt tuned to one direction is blind to the
other, and a correction is the one artefact whose failure runs backwards.

**MUTATE ONE LINE BY NUMBER, AND ASSERT THE MUTANT DIFFERS FROM THE ORIGINAL IN
EXACTLY ONE PLACE** (the Tech Lead's rule, and it makes the failure impossible
rather than discouraged). **A pattern that matches twice is a double mutation
wearing a single mutation's clothes** — and the count it produces is
indistinguishable from a real double revert, which is why it survived four
readers.

**MUTATE THE GUARD, NEVER THE MODEL THE GUARD READS — and mutate BY LOCATION,
never by pattern.** A second false measurement in the same exchange came from
editing `exclusionCount > 0`, the fixture predicates, instead of the guards
themselves: **mutating the fixture changes what "correct" means, so every count
moves and nothing is isolated.**

**Two mutations whose failure SETS differ is the evidence; two mutations whose
COUNTS match is the warning** — and the denominator rule has its seventh
instance inside the correction itself: **"7 and 7" supported the right
conclusion, that the fix works, so nobody put pressure on it.**

**The Designer's rewritten check is a genuine improvement and is kept on its
merits, not as a repair.** Asserting the colour channel while holding the
string correct, plus the cross-channel relation below, is strictly stronger
than v1. **"Mutation-verified" was never the false claim.**

**And a cross-channel relation is the assertion a string-only check cannot
express:** *the loudest signal must not disagree with the words beside it.* Its
absence is what let a green headline through a review that read every word —
the `confirm.no` glyph class, one channel out. **A check scoped to one channel
cannot see a contradiction between channels**, so the relation has to be
asserted directly rather than implied by both halves passing.

**A FILE'S EXTENSION IS PART OF A COUNTED POPULATION, SO ADDING A FILE CAN MOVE
A NUMBER NOBODY EDITED.** The manifest's totals check counts every tracked
`.swift` with no scoping; `tracked_swift()` — the "42/42 parsed" population —
is scoped to `ios/VehicleDamageForensics`. **The two have been the same 42 in
every handover, so a `.swift` verification instrument would have made them
diverge while both stayed correct**, and every past "42/42, 42 Swift sources"
would read as two claims rather than one. Instruments land as `.shapecheck`,
and the reason lives in the `Totals:` prose rather than in anyone's memory.
**Two agents quoting the same figure from different populations is that defect
one level out** — one had been counting unscoped all day and would have
reported 43/43 where the check reported 42/42. **Name the population, not just
the number.**

**AND ONE FOUND BY RUNNING THE RUNNER BARE, FIXED IN THE SAME COMMIT THAT
RECORDED IT: `run.sh` RETURNED rc=2 for TWO different conditions** — "no shape checks
found" and "no `swiftc` on PATH". The printed lines distinguish them correctly;
the **exit code does not**, and an exit code is what a caller reads. **A missing
toolchain and an empty directory are opposite problems** — one means the
instruments could not be run, the other means there are none to run — and
reporting them identically makes "the checks did not execute" indistinguishable
from "there is nothing to execute". **The absent-toolchain case now has its own
code** (rc=3), so a wrapper cannot treat an unrun suite as an empty one; the
four codes are 0 pass / 1 ran-and-failed / 2 nothing-to-execute / 3
could-not-execute, and they are documented in the runner and its README because
a caller reads the code, not the prose. Verified bare, one condition at a time.
**And the Designer's addition is the better half of the repair: the verdict now
goes to STDERR as well as stdout, because stderr survives a stdout pipe.** The
slip that surfaced all of this was reading `bash run.sh | tail; echo $?` --
`| tail` is the natural way to read seven ok lines, and the piped form lost the
only machine-readable signal while the TEXT still said "1 failing". **Cheaper to
stop rewarding the mistake than to write a rule nobody re-reads:** a rule
guards the reader who remembers it, a redundant channel guards the one who does
not. Verified through the exact command that hid it.
Third instance of the shape the runner was built to prevent, in the runner:
**the diagnostic is right and the channel a caller reads is not.**

**MEASURING THE WRONG OBJECT PRODUCES A CONFIDENT NUMBER, AND THE ROUND
PRODUCED THREE OF THEM.** Mutating a **pattern** that matches two guards
measures a double revert. Mutating the **fixture** the guard reads moves what
"correct" means. And reading `bash run.sh | tail; echo RC=$?` reports **`tail`'s
exit status, not the runner's** — which showed rc=0 on a deliberately broken
check and nearly published a working runner as broken. **All three return a
plausible integer with no error anywhere**, which is why none of them is caught
by looking harder at the result. **Name the object you are measuring, then
check that the command's output is about that object:** mutate one line by
number and assert exactly one difference; run a process bare and read its own
rc; never take a status through a pipe. Same family as reading a verdict
through a pipe (§4c above) and as quoting a count without its population — **the
tool answered exactly what it was asked, and the question was about something
else.**

**A RUNNER THAT REPORTS CLEAR OVER NOTHING IS THE INSTRUMENT COMMITTING THE
DEFECT IT HUNTS**, and the empty-directory case failed the **wrong way** on the
first attempt: without `nullglob` the glob fell through as a literal filename,
the loop ran once, and it printed *"1 shape check, 1 failing"* — **a real
failure reported as the wrong one, which is worse than silence because it sends
a reader to fix a file that does not exist.** Found by reading what the runner
PRINTED on a mutant rather than what it was written to print. Empty is now
rc=2 and names the condition; a non-compiling check is rc=1, because **a check
that no longer compiles is not a passing check.**

**VERIFY A DIAGNOSTIC BY READING ITS EMITTED TEXT ON A MUTANT, NOT ITS SOURCE**
(Vector's, from two edits to a warning string that silently no-oped). The check
fired correctly while naming the old population and the wrong file — **a true
alarm pointing at the wrong place, which is how a reader is sent to correct
working code.** Same class as a check that names the wrong member: the signal
is right and the address is not, which is the citation rule arriving inside an
instrument.

**A DECLARATION MECHANISM CONVERTS A SILENT OMISSION INTO A PROMPT, NOT INTO A
DIAGNOSIS** — and this is the honest limit of the declared-hold design, stated
by the agent who argued for it all round. A held declaration is a **copy**, so
it goes stale in the dangerous direction: the copy stops matching, the row
reports **owed**, and that reads as an oversight rather than a decision. There
is a guard for staleness now. **But no guard distinguishes a STALE hold from an
OBSOLETE one** — `attest.body` was held while owed, then built, so its
declaration went obsolete rather than mismatched, and both states report
identically. **The third defect kind again, one artefact out: the branch exists
and its condition cannot tell two cases apart.**

**A fix that removes an over-claim can create a LEGIBILITY hazard, and only
one of the two is visible from inside the tree.** Labelling §6.1's headline
score replaced one mislabelled figure with two correctly labelled ones on the
same page. **The repair for that, if a device shows it, is the labels'
prominence and never the numbers** — dropping a figure loses information and
re-merging them recreates the bare number. **Record the new exposure with the
fix; a defect closed silently at the cost of a new one is a trade nobody
reviewed.**

**AND A COUNT OF CALL SITES IS NOT A COUNT OF EXPOSED CALL SITES.** I recorded
§6.1 as wrong at four render sites; two of them read `ScarFingerprintMatch`,
which has no `exclusions` and no `filteredOutcome` — no filtered state to
misreport, so those sites are correct as they stand. **Verify that a type HAS
the feature before counting its render sites.** That was the second wrong
denominator in one day supporting a right conclusion, after the coaching-table
"twelve", and the pattern is the durable part: **a wrong denominator that
supports the right conclusion is never put under pressure by the exchange that
follows**, because everyone is agreeing about the conclusion. **Quote a
population with the symbol it was counted from**, the way a measurement travels
with its method.

**A locked TEMPLATE and a locked SENTENCE are different artefacts, so
"every locked string wherever written" cannot be a verbatim match.** Widening
a check's population by the class rather than by the found instance is right in
direction, and a template carrying `NN%` or `M of N` produces a false absence
under exact comparison. **Name and scope a check by its population, never by
the artefact the defect turned up in** — which is §4.1's lock scope, widened
three times for that reason, arriving at a check.

**The paired constraint, and it is the one that decides the shape: a
per-artefact qualification and a per-item note are not interchangeable.** The
same true fact stated once per report costs a clause; stated once per
photograph it annotates every photograph on a device that lacks the sensor and
destroys the note's meaning for the one that needed it. **Ask what the claim's
subject is — the set or the member — and put the qualification at that level.**
Softening the member's note to cover the set's problem is how the always-firing
note re-enters after being removed.

**A rule written here and a check written in code must agree, and when they
drift the code wins silently.** Prose that overclaims is visible to anyone who
reads it; a check scoped by a stale comment looks authoritative and is not.
So a correction to a rule in this document is not finished until the
corresponding check has been re-verified against the behaviour it guards —
against what the generator or compiler actually does, not what its comment
says it does.

## 6. Reporting up

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
