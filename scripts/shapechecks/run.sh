#!/usr/bin/env bash
# Compile and run every shape check. Exit non-zero if any fails or any
# fails to compile -- a check that no longer compiles is not a passing check,
# which is the absence-asserting-the-clean-case failure aimed at this script.
#
# EXIT CODES, and they are distinct on purpose:
#   0  every check compiled, ran and passed
#   1  at least one check FAILED or would not compile
#   2  nothing to run    -- no *.shapecheck files here
#   3  could not run     -- no usable Swift compiler
#
# NOTE(UI/UX Designer), after Ledger ran this bare and found 2 and 3 sharing
# one code. The printed lines distinguished them correctly; the EXIT CODE did
# not, and an exit code is what a caller reads. Those are opposite problems --
# "the instruments could not be run" versus "there are none to run" -- so one
# code made "the checks did not execute" indistinguishable from "there is
# nothing to execute", and a caller treating 2 as "empty, fine" would swallow a
# missing toolchain. Third instance in this script of the shape it was written
# to prevent: the diagnostic is right and the channel a caller reads is not.
set -uo pipefail
cd "$(dirname "$0")"
SWIFTC="${SWIFTC:-swiftc}"
if ! command -v "$SWIFTC" >/dev/null 2>&1; then
  echo "no usable Swift compiler ('$SWIFTC') -- the shape checks did NOT run" >&2
  echo "  set SWIFTC=/path/to/swiftc, or install a toolchain" >&2
  echo "SHAPECHECKS NOT RUN (no compiler) -- exit 3" >&2
  exit 3
fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
# nullglob, so an empty directory yields an EMPTY LOOP rather than the literal
# pattern. Without it the glob falls through as a filename, the loop runs once,
# and the run reports "1 shape check, 1 failing" -- a real failure reported as
# the wrong one, which is worse than silence because it sends a reader to fix a
# file that does not exist. Verified against an empty directory.
shopt -s nullglob
fail=0; n=0
for f in *.shapecheck; do
  n=$((n+1))
  cp "$f" "$tmp/c.swift"
  # -warnings-as-errors, and it is the point of sec.4c-xxxvii rather than
  # tidiness. `if true { return }` folded onto an existing line -- sec.4c-xxv
  # member (b), the one item nothing in this repository reaches -- is not
  # invisible to the compiler: swiftc reports `will never be executed` at the
  # SIL stage. preflight's Swift instrument stops at `-frontend -parse`, which
  # is silent on it, so the mode is why the finding never arrives, not the
  # technique. A shape check is the one Swift here that COMPILES, so it is the
  # one place the diagnostic can be made to cost something. Measured: all nine
  # checks at a803c0b pass under this flag unchanged, so it is free today and
  # only ever fires on a check whose own assertions stopped running.
  if ! "$SWIFTC" -O -warnings-as-errors "$tmp/c.swift" -o "$tmp/c" >"$tmp/err" 2>&1; then
    echo "COMPILE FAIL  $f"; sed 's/^/    /' "$tmp/err" | head -5; fail=$((fail+1)); continue
  fi
  out=$("$tmp/c" 2>&1); rc=$?
  last=$(printf '%s\n' "$out" | tail -1)

  # THE VERDICT MUST BE VERDICT-SHAPED, and this arm replaces the
  # empty-output arm below rather than sitting beside it (sec.4c-xli).
  #
  # Ledger measured the case next to the empty one: a check that COMPILES and
  # then TRAPS prints a multi-page Swift backtrace whose final line is the
  # BACKTRACER'S STOPWATCH, so the runner printed
  # `FAIL <file> -- Backtrace took 0.00s`. The refusal is correct and the one
  # line a reader takes away is meaningless -- and `-warnings-as-errors`
  # cannot reach it (the file compiles) while the empty-output arm cannot
  # either (the output is enormous). Reproduced here on pushed 9804a8b with
  # an out-of-range subscript: rc=132, Signal 4.
  #
  # Every check in this directory ends in `N failing assertion(s).` or
  # `all shape assertions hold`, so the SHAPE of the last line is available
  # as a signal, and both the empty case and the trap case are the absence
  # of it. rc >= 128 is reported as a trap by name, because "it crashed" and
  # "it failed an assertion" are different findings.
  # DESIGNER'S DELTA, ported onto Vector's base rather than either taken
  # whole: her arm PREFERS the check's own last VERDICT-SHAPED line to the
  # literal last line, so a check that prints diagnostics AFTER its verdict
  # reports the verdict rather than the noise. Vector's `case` below tests
  # the shape of `$last` and refuses anything that is not verdict-shaped --
  # which catches the trap and the empty case, but would ALSO refuse a check
  # whose verdict is real and merely not last. Her rescue runs first; his
  # shape test then judges what she recovered, so both hold.
  verdict=$(printf '%s\n' "$out" \
            | grep -E 'failing assertion|all shape assertions hold' \
            | tail -1)
  [ -n "$verdict" ] && [ "$rc" -lt 128 ] && last="$verdict"

  case "$last" in
    *"failing assertion(s)."|*"all shape assertions hold") ;;
    *)
      if [ "$rc" -ge 128 ]; then
        echo "FAIL          $f -- TRAPPED (signal $((rc-128))); no verdict line -- the backtrace is not a result"
      elif [ -z "$last" ]; then
        echo "FAIL          $f -- produced NO output; an empty verdict is not a pass"
      else
        echo "FAIL          $f -- last line is not a verdict: ${last:0:60}"
      fi
      fail=$((fail+1)); continue
      ;;
  esac

  # AND THE ASSERTIONS MUST HAVE RUN, which the verdict does not say.
  # `N failing assertion(s).` counts FAILURES, not assertions: comment out
  # every `expect(` line-neutrally and the check prints `0 failing
  # assertion(s).`, the runner prints `ok`, and `9/9` counts it. Measured on
  # pushed 9804a8b against decoder-roundtrip: rc=0, zero findings, and the
  # instrument that proves the round-trip mechanism asserted nothing.
  #
  # It tells a FAILING check from a passing one and cannot tell a DISABLED
  # one from either -- the same asymmetry my note-rows check had at the Swift
  # layer, now in the verdict channel, and disabling is the reversible-looking
  # edit reviewers wave through. Derived from the check's OWN source (count
  # the `expect(` statements) rather than declared, so adding an assertion
  # re-derives the floor instead of needing a number kept in agreement.
  # Precondition-style checks print nothing when they pass, so they are
  # covered by the verdict shape above plus the fact that commenting a
  # `precondition` out leaves its subject unused and fails the compile.
  # Comment-blind, and that arm is the one my first version got wrong:
  # counting `^expect(` in the file makes the FLOOR fall with the mutation,
  # so commenting every assertion out left sites=0 and the check passed. The
  # extractor was reading the mutated text as its own specification. Counting
  # only NON-comment lines fixes the floor's blindness; the case where the
  # count legitimately reaches zero is handled as its own finding below,
  # because a check that asserts nothing is the defect either way.
  code=$(sed -e 's://.*::' "$f")
  sites=$(printf '%s\n' "$code" | grep -c 'expect(' || true)
  precs=$(printf '%s\n' "$code" | grep -c 'precondition(' || true)
  ran=$(printf '%s\n' "$out" | grep -c '^  \(ok  \|FAIL\)' || true)
  # `func expect(` is the definition, not a site.
  sites=$((sites > 0 ? sites - 1 : 0))

  # A COMMENTED-OUT ASSERTION IS THE DISABLED CASE, and it is the one the
  # live/reported comparison cannot see: disable HALF the assertions
  # line-neutrally and both sides of that comparison fall together, so the
  # check reports `4 of 4` and passes. Measured. There is no legitimate
  # reason for a commented `expect(` or `precondition(` in an instrument, so
  # the whole-file count minus the live count IS the finding -- the same
  # code-only-versus-declared split as my note-rows check, with the
  # commented copy here being evidence rather than noise.
  # `func expect(` is excluded from BOTH sides, so the difference is sites and
  # never the definition. My first version added it back only when a live
  # site remained, so disabling all eight reported nine -- a correct finding
  # with a wrong number, which is the shape this file spent the day on.
  allsites=$(grep -v 'func expect(' "$f" | grep -c 'expect(\|precondition(' || true)
  live=$((sites + precs))
  if [ "$allsites" -gt "$live" ]; then
    echo "FAIL          $f -- $((allsites - live)) assertion site(s) COMMENTED OUT; a disabled assertion still reports 0 failing"
    fail=$((fail+1)); continue
  fi

  if [ "$sites" -eq 0 ] && [ "$precs" -eq 0 ]; then
    echo "FAIL          $f -- asserts NOTHING: no live expect()/precondition() site in non-comment source"
    fail=$((fail+1)); continue
  fi
  if [ "$sites" -gt 0 ] && [ "$ran" -lt "$sites" ]; then
    echo "FAIL          $f -- $ran of $sites assertion(s) reported; a check that does not RUN its assertions still prints 0 failing"
    fail=$((fail+1)); continue
  fi
  # An EMPTY verdict is not a passing verdict, and this loop used to print
  # `ok  <file> -- ` for it: rc=0, no `FAIL` in the output, nothing asserted.
  # Measured on a file whose whole body was `func nothing() {}` -- reported
  # `ok`, and every existing check prints either `N failing assertion(s).` or
  # `all shape assertions hold`, so the ABSENCE of a verdict line is
  # available as a signal and was being read as the clean case. Same shape
  # as sec.4c-xxii: this runner is the artefact that decides what `9/9` means,
  # and `9/9` counted a check that said nothing.
  if [ $rc -ne 0 ] || printf '%s\n' "$out" | grep -q 'FAIL'; then
    echo "FAIL          $f -- $last"; fail=$((fail+1))
  else
    echo "ok            $f -- $last"
  fi
done
if [ "$n" -eq 0 ]; then
  echo "no *.shapecheck files here -- an empty pass is not a pass" >&2
  echo "SHAPECHECKS NOT RUN (none found) -- exit 2" >&2
  exit 2
fi
echo; echo "$n shape check(s), $fail failing."

# NOTE(UI/UX Designer). The verdict is written to STDERR as well as stdout, and
# it is deliberately redundant with the count above.
#
# The Tech Lead nearly reported this runner's exit code as broken after reading
# `bash run.sh | tail; echo RC=$?` -- which captures `tail`'s status, not this
# script's. He caught it before publishing. Reproduced here: bare rc=1, piped
# rc=0, `${PIPESTATUS[0]}`=1. The measurement was wrong, not the runner.
#
# But the runner can stop rewarding the mistake, and that is cheaper than a
# rule nobody re-reads. `| tail` is the natural way to read this output --
# seven ok lines are noise -- and the piped form silently loses the only
# machine-readable signal while the TEXT still says "1 failing". So a reader
# who pipes gets a true report and a false status, which is the same shape as
# a true alarm naming the wrong file.
#
# stderr is not swallowed by a stdout pipe, so the verdict survives `| tail`
# and stays visible next to whatever the reader kept.
if [ "$fail" -eq 0 ]; then
  echo "SHAPECHECKS OK ($n/$n)" >&2
  exit 0
fi
echo "SHAPECHECKS FAILED ($fail/$n) -- exit 1; if you piped this, read \${PIPESTATUS[0]}, not \$?" >&2
exit 1
