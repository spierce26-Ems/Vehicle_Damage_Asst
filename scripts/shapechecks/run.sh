#!/usr/bin/env bash
# Compile and run every shape check. Exit non-zero if any fails or any
# fails to compile -- a check that no longer compiles is not a passing check,
# which is the absence-asserting-the-clean-case failure aimed at this script.
set -uo pipefail
cd "$(dirname "$0")"
SWIFTC="${SWIFTC:-swiftc}"
command -v "$SWIFTC" >/dev/null || { echo "no $SWIFTC on PATH"; exit 2; }
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
  if ! "$SWIFTC" -O "$tmp/c.swift" -o "$tmp/c" >"$tmp/err" 2>&1; then
    echo "COMPILE FAIL  $f"; sed 's/^/    /' "$tmp/err" | head -5; fail=$((fail+1)); continue
  fi
  out=$("$tmp/c" 2>&1); rc=$?
  last=$(printf '%s\n' "$out" | tail -1)
  if [ $rc -ne 0 ] || printf '%s\n' "$out" | grep -q 'FAIL'; then
    echo "FAIL          $f -- $last"; fail=$((fail+1))
  else
    echo "ok            $f -- $last"
  fi
done
[ "$n" -eq 0 ] && { echo "no shape checks found -- an empty pass is not a pass"; exit 2; }
echo; echo "$n shape check(s), $fail failing."
[ "$fail" -eq 0 ]
