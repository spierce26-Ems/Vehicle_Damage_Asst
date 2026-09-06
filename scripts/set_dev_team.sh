#!/usr/bin/env bash
# P0-1: set DEVELOPMENT_TEAM for automatic code signing.
# Usage (from the repo root): ./scripts/set_dev_team.sh ABCDE12345
#   ABCDE12345 = your 10-char Apple Developer Team ID (Membership details,
#   or the Team dropdown in Xcode > Signing & Capabilities). It is a public
#   identifier -- unlike certificates, .p12 files and API keys, which must
#   never be pasted into chat or committed.
set -euo pipefail
TEAM="${1:?usage: ./scripts/set_dev_team.sh <10-char Apple Team ID>}"
[[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || { echo "error: '$TEAM' is not a 10-char alphanumeric Team ID" >&2; exit 1; }
# Both the live project AND the regeneration skeleton: scripts/build_pbxproj.py
# rebuilds from the skeleton, so a Team ID set only in the live file is silently
# lost the next time anyone registers a new Swift file that way.
FILES=(
  "ios/VehicleDamageForensics.xcodeproj/project.pbxproj"
  "scripts/pbxproj_skeleton.txt"
)
for F in "${FILES[@]}"; do
  [[ -f "$F" ]] || { echo "error: $F not found -- run from the repo root" >&2; exit 1; }
  if grep -q "DEVELOPMENT_TEAM" "$F"; then
    echo "error: DEVELOPMENT_TEAM already present in $F -- inspect manually, not overwriting." >&2; exit 1
  fi
done

for F in "${FILES[@]}"; do
  # Anchor on ENABLE_PREVIEWS so the key lands in Xcode's own alphabetical
  # order (CODE_SIGN_STYLE, CURRENT_PROJECT_VERSION, DEVELOPMENT_TEAM,
  # ENABLE_PREVIEWS) -- otherwise Xcode reorders it on first save and the
  # next diff is noise.
  N=$(grep -c "ENABLE_PREVIEWS = YES;" "$F")
  [[ "$N" -eq 2 ]] || { echo "error: expected 2 ENABLE_PREVIEWS lines (Debug+Release), found $N" >&2; exit 1; }
  perl -0pi -e "s/(\t+)(ENABLE_PREVIEWS = YES;)/\$1DEVELOPMENT_TEAM = $TEAM;\n\$1\$2/g" "$F"
  echo "Patched 2 configurations (Debug + Release) in $F"
done

echo
echo "Result:"
grep -n "DEVELOPMENT_TEAM" "${FILES[@]}"
echo
echo "Verify with: python3 scripts/preflight.py --all   (expect 0 advisory)"
echo "Then commit this alone, open Xcode, select a real LiDAR device and"
echo "Cmd+Shift+K, Cmd+B. Signing & Capabilities should show the team with no"
echo "red banner. If Xcode says the bundle id is unavailable, the App ID is"
echo "registered to a different team -- that is an App Store Connect fix."
