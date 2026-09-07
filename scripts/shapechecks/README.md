# Shape checks

Reduced Swift models of a defect and its fix. Each one compiles standalone,
runs in under a second, and prints failing assertions.

**They say nothing about the tree.** A shape check encodes the facts its
author read out of the tree at a named commit; if the tree moves, the model
does not follow. It is evidence that an argument holds, never that the app
builds — no SwiftUI `body` is typechecked by any of them.

## Why `.shapecheck` and not `.swift`

Four of us quote "42/42 parsed" and "42 Swift sources" as verification
signals, and `preflight`'s manifest check counts **every tracked `.swift`**
without scoping to `ios/VehicleDamageForensics`. Landing these as `.swift`
took that figure to 44 — so every past "42/42" in the thread's history would
read differently, and the number we use to agree with each other would have
silently changed meaning. Measured rather than assumed: as `.swift`, three
manifest advisories and `(44 Swift)`; as `.shapecheck`, the Swift count holds
at 42.

The extension is the whole mechanism. It is a deliberate choice, not an
oversight: **a file's extension is part of a counted population, so adding a
file can change a figure nobody edited.**

## Running one

```sh
cp scripts/shapechecks/filtered-headline.shapecheck /tmp/c.swift
swiftc -O /tmp/c.swift -o /tmp/c && /tmp/c
```

`run.sh` does all of them, and its exit code distinguishes every outcome a
caller has to tell apart -- because an exit code is what a caller reads:

| rc | meaning |
|----|---------|
| 0 | every check compiled, ran and passed |
| 1 | a check failed or failed to compile -- the instruments RAN |
| 2 | no shape checks found -- there is nothing to execute |
| 3 | no Swift compiler on PATH -- the instruments COULD NOT BE RUN |

**2 and 3 both returned 2 until 2026-09-07** (Ledger), so a caller could not
tell "nothing to execute" from "did not execute" -- opposite problems reported
identically. The printed lines had always distinguished them; the channel a
caller reads had not. **Read the runner's status BARE: `bash run.sh; echo $?`.
Through a pipe you are reading the pipe** -- that slip is what surfaced this.

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
