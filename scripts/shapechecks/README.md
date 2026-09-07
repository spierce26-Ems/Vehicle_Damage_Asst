# Shape checks

Reduced Swift models of a defect and its fix. Each one compiles standalone,
runs in under a second, and prints failing assertions.

**They say nothing about the tree.** A shape check encodes the facts its
author read out of the tree at a named commit; if the tree moves, the model
does not follow. It is evidence that an argument holds, never that the app
builds — no SwiftUI `body` is typechecked by any of them.

## Why `.shapecheck` and not `.swift`

Two figures are quoted as verification signals in every handover here: `42/42
parsed` and `42 Swift sources`. **They read from different populations.**
`preflight`'s `tracked_swift()` IS scoped to `ios/VehicleDamageForensics`, so
a `.swift` file under `scripts/` would NOT move the parse figure — but the
manifest counts every tracked `.swift` in the tree, so it WOULD move the Swift
total. Measured on the landed tree: scoped 42, unscoped 42, and under a
`.swift` home the manifest read `(44 Swift)` with three advisories.

*Correction, and it is this file's own author's: an earlier revision of this
section said `.swift` here would move `42/42 parsed`. It would not. Only the
manifest total moves. The claim was checkable and went unchecked in the file
written to record how to check things.*

**The hazard is not a wrong count. It is two figures that have been the same
number in every handover quietly becoming different while both stay correct**
(Ledger's framing, and it is the reason the extension matters rather than a
restatement of it). A diff of a count shows its value, never its population —
the same defect as a locked string whose meaning changed with no character
diff.

So: **a file's extension is part of a counted population, and adding a file
can move a figure nobody edited.** A verification instrument is not app
source. When you quote 42/42, quote it from the scoped population;
`git ls-files '*.swift'` is not scoped.

## Running one

```sh
cp scripts/shapechecks/filtered-headline.shapecheck /tmp/c.swift
swiftc -O /tmp/c.swift -o /tmp/c && /tmp/c
```

## Running all of them

`run.sh` compiles and runs every `*.shapecheck` here. `SWIFTC=` overrides the
compiler. **Read its BARE exit status** — see the pipe note below.

| rc | meaning |
|---:|---|
| 0 | every check compiled, ran and passed |
| 1 | at least one check failed or would not compile |
| 2 | **nothing to run** — no `*.shapecheck` files here |
| 3 | **could not run** — no usable Swift compiler |

Mutation-tested five ways, each verified to produce its own code:

  - a broken guard         -> FAIL, names the file, rc=1
  - a non-compiling check  -> COMPILE FAIL, rc=1. A check that no longer
                              compiles is not a passing check.
  - an empty directory     -> rc=2, "an empty pass is not a pass"
  - no compiler on PATH    -> rc=3, "the shape checks did NOT run"
  - piped (`| tail`)       -> the verdict still reaches you, on STDERR

**2 and 3 shared one code until Ledger ran this bare and noticed.** The printed
lines distinguished them correctly; **the exit code did not, and an exit code is
what a caller reads.** They are opposite problems — *the instruments could not
be run* versus *there are none to run* — so one code made "the checks did not
execute" indistinguishable from "there is nothing to execute", and a caller
treating 2 as "empty, fine" would have swallowed a missing toolchain.

**The empty case failed the WRONG WAY first.** Without `nullglob` the glob fell
through as a literal filename, the loop ran once, and the run printed *"1 shape
check, 1 failing"* — a real failure reported as the wrong one, which sends a
reader to fix a file that does not exist.

**And the pipe case is the same shape, found the same way.** `bash run.sh |
tail; echo RC=$?` reads `tail`'s status, not the script's: bare rc=1, piped
rc=0, `${PIPESTATUS[0]}`=1. That nearly got this runner reported as broken. The
measurement was wrong, not the runner — but `| tail` is the natural way to read
seven ok lines, and the piped form lost the only machine-readable signal **while
the text still said "1 failing"**: a true report with a false status. The
verdict is now on stderr too, redundantly, because stderr survives a stdout
pipe. **Cheaper to stop rewarding the mistake than to write a rule nobody
re-reads.**

Both were found by reading what the runner PRINTED on a mutant rather than what
it was written to print.

## Writing one

- **Assert what the ARTEFACT may conclude, not what a flag holds.** The
  filtered-headline check asserts over the report's possible claims; that is
  what let it express a contradiction between two channels.
- **Show it fails on the defect.** An assertion that cannot fail without the
  thing under test is not testing it.
- **Mutate each half of a two-part fix separately, and require each to fail
  assertions the other does not.** A check whose two mutations are not
  independent measures one defect twice.
- **Mutate the GUARD, never the model the guard reads.** Mutating the fixture
  changes what "correct" means, so every count moves and nothing is isolated.
- **Beware a single textual pattern matching both guards.** Two lines reading
  `guard !hasExclusions` are removed together by one pattern edit, which
  reproduces the double-revert count exactly and looks like non-independence.
- **Compare failure SETS, not counts.** A matching pair of test counts is a
  number that matches, not a number that agrees.
- **Assert cross-channel relations directly.** *The loudest signal must not
  disagree with the words beside it* — a check scoped to one channel cannot
  see a contradiction between channels, which is why the hue defect in
  `filtered-headline` survived a review that read every word.
- **Measure the object you mean — measuring the wrong object produces a
  confident number.** Mutating a *pattern* that matches two guards measures a
  double revert. Mutating the *fixture* moves what "correct" means. Reading a
  status through `| tail` reports `tail`. Quoting a count without its
  population compares two numbers from different sets. **All four return a
  plausible integer with no error anywhere**, which is why looking harder at
  the result catches none of them: the tool answered exactly what it was
  asked, and the question was about something else.
- **Mutate one line by NUMBER and assert the mutant differs from the original
  in exactly one place.** A pattern that matches twice is a double mutation
  wearing a single mutation's clothes.

## Re-run the artefact under dispute, not a descendant of it

The most expensive mistake of the round these were written in was not a
defect in the tree. A mutation finding against `filtered-headline` was wrong,
three agents endorsed it inside four minutes, and this check's author rewrote
a **working** instrument on it. One of the confirmations then re-ran the
already-rewritten version, so the chain never touched the artefact under
dispute. Everyone re-ran something; nobody re-ran the thing being corrected.

Two properties made it spread. **Agreeing with a self-criticism feels safe**,
so nobody audits a claim someone volunteered against themselves. And the
**failure direction was inverted** from every other defect hunted that day:
the others made something absent look fine, this made something fine look
absent — so the usual instinct, distrust of an all-clear, pointed the wrong
way.

The author's own share of it, recorded because it is the reusable part: a
correction naming a defect in *my* work arrived, and I fixed the artefact
without first reproducing the defect. **Reproduce a correction before acting
on it, exactly as you would reproduce a bug report** — a correction is a
claim, and one aimed at you is not thereby verified.
