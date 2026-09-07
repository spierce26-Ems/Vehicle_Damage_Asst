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
  # An EMPTY verdict is not a passing verdict, and this loop used to print
  # `ok  <file> -- ` for it: rc=0, no `FAIL` in the output, nothing asserted.
  # Measured on a file whose whole body was `func nothing() {}` -- reported
  # `ok`, and every existing check prints either `N failing assertion(s).` or
  # `all shape assertions hold`, so the ABSENCE of a verdict line is
  # available as a signal and was being read as the clean case. Same shape
  # as sec.4c-xxii: this runner is the artefact that decides what `9/9` means,
  # and `9/9` counted a check that said nothing.
  if [ -z "$last" ]; then
    echo "FAIL          $f -- produced NO output; an empty verdict is not a pass"
    fail=$((fail+1)); continue
  fi
  # sec.4c-xliii (Designer), Ledger's owed `rc >= 128` arm. A check that
  # COMPILES and then TRAPS prints a Swift runtime backtrace whose final
  # line is the BACKTRACER'S STOPWATCH, so `tail -1` reported
  # `FAIL  zz-crash.shapecheck -- Backtrace took 0.00s`. Reproduced here
  # with an out-of-range subscript: rc=132, signal 4. The refusal is
  # correct -- `fail` increments, rc=1, nothing is laundered -- and the one
  # line a reader takes away is meaningless. NEITHER existing arm reaches
  # it: `-warnings-as-errors` cannot, because the file compiles, and the
  # empty-verdict arm cannot, because the output is enormous. Third
  # instance of "the diagnostic is right and the channel a caller reads is
  # not", inside the artefact that decides what `9/9` means.
  #
  # Two channels in this order, because a trap and a failed assertion are
  # different findings and one verdict line must not flatten them:
  #   rc >= 128  died on a SIGNAL. `128 + N` is the shell's own encoding,
  #              so this is not a heuristic. Report the trap AS a trap and
  #              name the signal; never quote a line from the dump.
  #   otherwise  prefer the check's own last VERDICT-SHAPED line to the
  #              literal last line, so a check that prints diagnostics
  #              after its verdict still reports the verdict.
  # Ledger's ranking kept: between "said nothing" and "said the wrong
  # thing", the empty arm caught the first and this catches the second.
  if [ "$rc" -ge 128 ]; then
    echo "TRAP          $f -- died on signal $((rc - 128)) (rc=$rc) after" \
         "compiling; a backtrace's last line is the backtracer's own" \
         "timing, not a verdict"
    printf '%s\n' "$out" | grep -E 'Fatal error|error:|Crash' | head -3 \
      | sed 's/^/    /'
    fail=$((fail+1)); continue
  fi
  verdict=$(printf '%s\n' "$out" \
            | grep -E 'failing assertion|all shape assertions hold|FAIL' \
            | tail -1)
  [ -n "$verdict" ] && last="$verdict"
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
