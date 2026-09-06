#!/usr/bin/env python3
"""
Pre-commit preflight for Vehicle_Damage_Asst.

Checks the failure modes this project has actually suffered, in the order they
have actually bitten. Every check is mechanical: no check here claims a change
"works" -- that bar is docs/PROCESS.md sec.4 clauses 4-6 and needs Xcode and a
device. This only catches the things that waste a build round-trip.

Usage:
    python3 scripts/preflight.py              # check staged changes
    python3 scripts/preflight.py --all        # check the whole tree
    python3 scripts/preflight.py --since REF  # check commits since REF
    python3 scripts/preflight.py --install-hook

--since exists for the case PROCESS.md sec.1 names as highest-risk: after a
rebase or conflict resolution the changes are COMMITTED, so a staged-diff run
sees nothing and --all cannot judge a diff at all. `--since origin/main`
compares the resolved tree against where it is going.

Exit codes: 0 = clear, 1 = blocking failure, 0 with warnings = proceed.
"""
import os
import re
import subprocess
import sys

REPO = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                      capture_output=True, text=True).stdout.strip()
PBXPROJ = "ios/VehicleDamageForensics.xcodeproj/project.pbxproj"
SKELETON = "scripts/pbxproj_skeleton.txt"
SOURCE_ROOT = "ios/VehicleDamageForensics"
MODELS_DIR = f"{SOURCE_ROOT}/Models"

# A single commit that grows one file by more than this many lines is the
# shape that took Xcode down (reverted at 9b6a67e). Warn, do not block --
# a legitimately large new file exists, it just deserves a second thought.
BIG_DIFF_LINES = 200

failures = []
warnings = []


def fail(check, msg, remedy):
    failures.append((check, msg, remedy))


def warn(check, msg, remedy):
    warnings.append((check, msg, remedy))


def sh(*args):
    return subprocess.run(args, capture_output=True, text=True,
                          cwd=REPO).stdout


# Set by main() when --since REF is used, so the commit-shaped checks compare
# against REF instead of the index. A rebase's product is committed, not
# staged; without this the checks that matter most at a conflict resolution
# are the ones that go silent.
DIFF_BASE = None


def diff_args():
    """The `git diff` selector the commit-shaped checks should use."""
    return ["--cached"] if DIFF_BASE is None else [f"{DIFF_BASE}...HEAD"]


def changed_files():
    out = sh("git", "diff", *diff_args(), "--name-only", "--diff-filter=ACMR")
    return [f for f in out.splitlines() if f]


def staged_files():
    return changed_files()


def tracked_swift():
    out = sh("git", "ls-files", f"{SOURCE_ROOT}/**/*.swift",
             f"{SOURCE_ROOT}/*.swift")
    return sorted({f for f in out.splitlines() if f.endswith(".swift")})


# ---------------------------------------------------------------- check 1
def check_pbxproj_registration():
    """Every Swift file in the tree must be registered in the target.

    PROCESS.md sec.1: an unregistered Swift file compiles into nothing and
    presents as a mystery failure. This has already happened twice
    (bf3bc5a, 3f56117). It is the single cheapest check in this file and
    the one most likely to save a build round-trip.
    """
    path = os.path.join(REPO, PBXPROJ)
    if not os.path.exists(path):
        fail("pbxproj", f"{PBXPROJ} not found", "run from a full checkout")
        return
    pbx = open(path).read()

    missing = []
    for f in tracked_swift():
        name = os.path.basename(f)
        # Registered means both a PBXBuildFile entry and membership in the
        # sources build phase. The generator writes both; a hand-edit often
        # writes only one, which fails in a way that looks like check 1
        # passing.
        if f"{name} in Sources */" not in pbx or f"/* {name} */" not in pbx:
            missing.append(f)
    if missing:
        fail("pbxproj",
             f"{len(missing)} Swift file(s) not registered in the target: "
             + ", ".join(missing),
             "cd ios && python3 ../scripts/build_pbxproj.py   "
             "(then re-stage the pbxproj)")

    # Reverse direction: a reference to a file that no longer exists breaks
    # the build just as hard, and happens on renames and reverts.
    referenced = set(re.findall(r"/\* ([A-Za-z0-9_+\-]+\.swift) in Sources \*/", pbx))
    on_disk = {os.path.basename(f) for f in tracked_swift()}
    ghosts = sorted(referenced - on_disk)
    if ghosts:
        fail("pbxproj",
             "pbxproj references file(s) that are not in the tree: "
             + ", ".join(ghosts),
             "regenerate the pbxproj, or restore the file if the deletion "
             "was accidental")


# ---------------------------------------------------------------- check 2
def check_skeleton_drift():
    """Build settings must match between the live pbxproj and the skeleton.

    scripts/build_pbxproj.py regenerates project.pbxproj from
    scripts/pbxproj_skeleton.txt. A **build setting** changed only in the live
    file is silently reverted the next time the generator runs -- which
    surfaces days later as "signing broke itself" with no diff to blame.

    Scope is build settings only, deliberately. The skeleton carries no file
    references at all (verified: zero `.swift` mentions in it); the generator
    discovers sources by walking the tree with os.walk. So registering a new
    Swift file needs no skeleton edit and is not drift -- only a changed
    setting is.
    """
    live_p = os.path.join(REPO, PBXPROJ)
    skel_p = os.path.join(REPO, SKELETON)
    if not (os.path.exists(live_p) and os.path.exists(skel_p)):
        return

    def build_settings(text):
        """Map setting name -> set of values, from buildSettings blocks only.

        Parsing the blocks rather than the whole file keeps a setting name
        appearing in a comment or a file path out of the comparison.
        """
        found = {}
        for block in re.finditer(r"buildSettings = \{(.*?)\n\t+\};",
                                 text, re.S):
            for key, val in re.findall(r"\n\t+([A-Z][A-Z0-9_]+) = ([^;]+);",
                                       block.group(1)):
                found.setdefault(key, set()).add(val.strip())
        return found

    live = build_settings(open(live_p).read())
    skel = build_settings(open(skel_p).read())

    # These are the ones whose silent reversion breaks a build or a signature
    # rather than merely surprising someone. Drift in them is blocking; drift
    # in anything else is advisory, so an intentional divergence someone adds
    # later cannot wedge the commit path.
    critical = {"DEVELOPMENT_TEAM", "CODE_SIGN_STYLE", "CODE_SIGN_IDENTITY",
                "CODE_SIGN_ENTITLEMENTS", "PRODUCT_BUNDLE_IDENTIFIER",
                "IPHONEOS_DEPLOYMENT_TARGET", "SWIFT_VERSION",
                "INFOPLIST_FILE", "PROVISIONING_PROFILE_SPECIFIER"}

    # Compare every setting present in either file, not a hand-listed few:
    # the setting that bites is the one nobody thought to watch.
    for key in sorted(set(live) | set(skel)):
        lv = sorted(live.get(key, []))
        sv = sorted(skel.get(key, []))
        if lv == sv:
            continue
        report = fail if key in critical else warn
        remedy = f"set {key} in BOTH {PBXPROJ} and {SKELETON}"
        if key == "DEVELOPMENT_TEAM":
            remedy += " -- ./scripts/set_dev_team.sh <team-id> does both"
        report("skeleton-drift",
               f"{key} differs: project.pbxproj has {lv or 'nothing'}, "
               f"skeleton has {sv or 'nothing'}",
               remedy)


# ---------------------------------------------------------------- check 3
def check_signing_configured():
    """Warn while DEVELOPMENT_TEAM is unset -- device builds cannot sign.

    Not a failure: a Simulator build compiles with no team selected, so this
    must never block the compiler-error hunt (P0-2 does not depend on P0-1).
    """
    path = os.path.join(REPO, PBXPROJ)
    if not os.path.exists(path):
        return
    pbx = open(path).read()
    teams = re.findall(r"DEVELOPMENT_TEAM = ([^;]+);", pbx)
    n_cfg = len(re.findall(r"CODE_SIGN_STYLE = ", pbx))
    if not teams:
        warn("signing",
             "DEVELOPMENT_TEAM is not set -- Simulator builds are fine, "
             "device builds and TestFlight will fail to sign",
             "./scripts/set_dev_team.sh <10-char Apple Team ID>")
    elif len(teams) < n_cfg:
        fail("signing",
             f"DEVELOPMENT_TEAM set in {len(teams)} of {n_cfg} build "
             "configurations",
             "set it in both Debug and Release, or Release archives fail "
             "while Debug looks healthy")


# ---------------------------------------------------------------- check 4
def check_delimiter_balance(files):
    """Brace/paren/bracket balance on changed Swift files.

    Explicitly weak: it catches a truncated or mis-merged file, nothing more.
    PROCESS.md sec.4 is blunt about this -- "balance-checked and looks right"
    is not done. Treat a pass here as "worth compiling", never as "compiles".
    Strings and comments are stripped first, otherwise a brace in a literal
    produces a false alarm and the check gets ignored, which is worse than
    not having it.
    """
    for f in files:
        if not f.endswith(".swift"):
            continue
        p = os.path.join(REPO, f)
        if not os.path.exists(p):
            continue
        src = open(p, encoding="utf-8", errors="replace").read()
        src = re.sub(r'"""(?:.|\n)*?"""', '""', src)
        src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)
        src = re.sub(r"//[^\n]*", "", src)
        src = re.sub(r"/\*(?:.|\n)*?\*/", "", src)
        for open_c, close_c, name in (("{", "}", "braces"),
                                      ("(", ")", "parens"),
                                      ("[", "]", "brackets")):
            d = src.count(open_c) - src.count(close_c)
            if d:
                fail("balance",
                     f"{f}: {name} unbalanced by {d:+d}",
                     "the file is probably truncated or mis-merged; open it "
                     "before committing")


# ---------------------------------------------------------------- check 5
def check_commit_size(files):
    """One logical change per commit; never grow one file by hundreds of lines.

    PROCESS.md sec.1, from the ScarCaptureView incident. Advisory: the point is
    that a large diff should be a decision, not an accident.
    """
    out = sh("git", "diff", *diff_args(), "--numstat")
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        added, removed, path = parts
        if added == "-" or not path.endswith(".swift"):
            continue
        if int(added) > BIG_DIFF_LINES:
            warn("commit-size",
                 f"{path} grows by {added} lines in one commit",
                 "split it if you can; if not, commit alone and open the "
                 "file in Xcode immediately after")

    swift = [f for f in files if f.endswith(".swift")]
    layers = {"Models": 0, "ViewModels": 0, "Views": 0}
    for f in swift:
        for layer in layers:
            if f"/{layer}/" in f:
                layers[layer] += 1
    if sum(1 for v in layers.values() if v) >= 3:
        warn("commit-size",
             "this commit touches Models, ViewModels and Views together",
             "PROCESS.md sec.1 wants three commits in order: "
             "model -> plumbing -> UI, each buildable alone")


# ---------------------------------------------------------------- check 6
def check_docs_owed(files):
    """Name the documentation a change owes, per PROCESS.md sec.3.

    Advisory by design. It reminds; it does not gate, and it never writes
    changelog prose -- that is Ledger's, and only Ledger's.
    """
    swift = [f for f in files if f.endswith(".swift")]
    if swift and not any(f.endswith("ios/README.md") for f in files):
        warn("docs",
             "functional commit with no ios/README.md changelog entry staged",
             "send Ledger what changed / why / which files -- the entry and "
             "the on-device checklist come back written")

    added_removed = sh("git", "diff", *diff_args(), "--name-only",
                       "--diff-filter=AD")
    if any(f.endswith(".swift") for f in added_removed.splitlines()):
        warn("docs",
             "a Swift file was added or removed",
             "regenerate ios/reference/COMPLETE_FILE_MANIFEST.md "
             "(regenerate, never hand-edit)")

    scoring_dirs = ("/Utilities/", "/ForensicEngine/")
    if any(d in f for f in swift for d in scoring_dirs):
        warn("docs",
             "scoring or analysis code changed",
             "ios/reference/ALGORITHM_EXPLAINER.md may need updating; a "
             "determinism check belongs in the on-device checklist")


# ---------------------------------------------------------------- check 7
def _underlying(type_str):
    """Type with optionality removed -- `Data?` and `Data` both give `Data`.

    Optionality is compared separately from the underlying type because the
    two directions are not symmetric. Widening T to T? is the migration FIX:
    existing files carry the key with the same underlying type, so it still
    decodes. Only a change of underlying type throws typeMismatch.
    """
    return type_str.rstrip("?").strip()


def _parse_field(decl):
    """(name, type) for a stored, decodable property -- else None.

    Skips everything Codable does not put in the payload: computed properties
    and inline getters (a brace anywhere in the declaration -- testing only
    the end of the line misreads `var x: String { "y" }` as a hazard),
    property wrappers, and statics. A false alarm on a blocking check is
    expensive beyond itself: the --no-verify that silences it silences every
    other check too.
    """
    if "{" in decl or decl.startswith("@"):
        return None
    if re.match(r"(static|class)\s", decl):
        return None
    # Strip a trailing line comment before parsing the type: the type in
    # `var x: String  // note` is String, and capturing the comment as part
    # of it would turn any comment edit into a phantom type change.
    decl = re.sub(r"\s*//.*$", "", decl)
    m = re.match(r"(?:var|let)\s+(\w+)\s*:\s*([^=]+?)\s*(?:=|$)", decl)
    if not m:
        return None
    return m.group(1), m.group(2).strip()


def codable_line_spans(path):
    """1-based (start, end, name) for every Codable type body in `path`.

    Used to scope the persisted-field check to types that actually get
    encoded. Brace-matched rather than regex-to-end-of-type so a nested
    type inside a Codable one is handled correctly.

    Strings and comments are stripped first for brace counting only -- a
    brace inside a string literal or a doc comment would otherwise close a
    type early and silently shrink the checked region, which is exactly the
    failure mode that makes a checker miss the thing it exists to catch.
    Character offsets are preserved during stripping so line numbers stay
    accurate.
    """
    try:
        with open(os.path.join(REPO, path), encoding="utf-8") as fh:
            src = fh.read()
    except OSError:
        return []

    out = list(src)
    i, n = 0, len(src)
    while i < n:
        two = src[i:i + 2]
        if two == "//":
            while i < n and src[i] != "\n":
                out[i] = " "
                i += 1
        elif two == "/*":
            depth = 1
            out[i] = out[i + 1] = " "
            i += 2
            while i < n and depth:
                if src[i:i + 2] == "/*":
                    depth += 1
                    out[i] = out[i + 1] = " "
                    i += 2
                elif src[i:i + 2] == "*/":
                    depth -= 1
                    out[i] = out[i + 1] = " "
                    i += 2
                else:
                    if src[i] != "\n":
                        out[i] = " "
                    i += 1
        elif src[i:i + 3] == '"""':
            for k in range(i, min(i + 3, n)):
                out[k] = " "
            i += 3
            while i < n and src[i:i + 3] != '"""':
                if src[i] != "\n":
                    out[i] = " "
                i += 1
            for k in range(i, min(i + 3, n)):
                out[k] = " "
            i += 3
        elif src[i] == '"':
            out[i] = " "
            i += 1
            while i < n and src[i] != '"':
                if src[i] == "\\":
                    out[i] = " "
                    i += 1
                    if i < n:
                        out[i] = " "
                        i += 1
                    continue
                if src[i] != "\n":
                    out[i] = " "
                i += 1
            if i < n:
                out[i] = " "
                i += 1
        else:
            i += 1
    clean = "".join(out)

    line_of = {}
    line = 1
    for idx, ch in enumerate(clean):
        line_of[idx] = line
        if ch == "\n":
            line += 1

    spans = []
    for m in re.finditer(
            r"\b(?:struct|class|enum|actor|extension)\s+(\w+)[^{}\n]*?:"
            r"[^{}\n]*?\bCodable\b[^{}]*?\{", clean):
        open_idx = clean.find("{", m.end() - 1)
        if open_idx < 0:
            continue
        depth = 0
        # Only the type's OWN member level counts. A `var` declared inside a
        # func or a computed-property body is a local, not a stored property
        # -- `var parts: [String] = []` inside a `displayLine` getter is not
        # persisted and must not be reported. Nested bodies are therefore
        # excluded by recording only the depth-1 stretches of the type body,
        # rather than the whole body as one span.
        #
        # Indentation is not usable as the discriminator: real nested fields
        # and locals both appear at non-member indentation, so it cannot
        # separate them.
        segment_start = None
        for j in range(open_idx, len(clean)):
            if clean[j] == "{":
                depth += 1
                if depth == 1:
                    segment_start = j
                elif depth == 2 and segment_start is not None:
                    # Entering a nested body: close the member-level run.
                    spans.append((line_of.get(segment_start, 1),
                                  line_of.get(j, line),
                                  m.group(1)))
                    segment_start = None
            elif clean[j] == "}":
                depth -= 1
                if depth == 1:
                    # Back out to member level; resume collecting.
                    segment_start = j
                elif depth == 0:
                    if segment_start is not None:
                        spans.append((line_of.get(segment_start, 1),
                                      line_of.get(j, line),
                                      m.group(1)))
                    break
    return spans


def types_added_in_diff(path):
    """Names of Codable types whose DECLARATION is added in the current diff.

    A non-optional field on a brand-new persisted type is harmless by
    construction: no saved case can contain a type that did not exist when it
    was written, so there is no old payload missing the key. Treating "new
    field in a diff" as "new field on an existing persisted type" is what
    produced eight false positives on the first real rebase -- and the whole
    hazard lives in that difference.
    """
    diff = sh("git", "diff", *diff_args(), "--", path)
    added = set()
    for line in diff.splitlines():
        if not line.startswith("+") or line.startswith("+++"):
            continue
        m = re.match(r"\+\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+)?"
                     r"(?:final\s+)?(?:struct|class|enum|actor)\s+(\w+)",
                     line)
        if m:
            added.add(m.group(1))
    return added


def types_with_custom_decoder(path, spans):
    """Names of types declaring their own `init(from:)`.

    Imperfect on purpose. A hand-written decoder CAN still decode a new key
    non-optionally, so this does not prove the migration is safe. What it
    proves is that a human made a decoding decision for this type -- and the
    remedy this check recommends IS `decodeIfPresent` in an explicit
    `init(from:)`, so blocking a type that has one blocks the fix. Moving the
    judgement to someone who has demonstrably thought about decoding beats
    refusing every correct migration; a blocking check that fires on correct
    code gets --no-verify'd, and that flag takes every other check with it.
    """
    try:
        with open(os.path.join(REPO, path), encoding="utf-8") as fh:
            lines = fh.readlines()
    except OSError:
        return set()
    out = set()
    for lo, hi, name in spans:
        body = "".join(lines[lo - 1:hi])
        if re.search(r"\binit\s*\(\s*from\s+\w+\s*:\s*Decoder\s*\)", body):
            out.add(name)
    return out


def check_persisted_model(files):
    """Persisted-model changes that survive a green build and lose case data.

    Blocking under PROCESS.md sec.5b kind 2: the compiler cannot catch either
    of these, and the cost lands on the user rather than the developer.

    - A new NON-OPTIONAL field -> keyNotFound on every existing case file.
      Swift's synthesized init(from:) never consults the property's default
      value, so `= false` in the declaration does not make decoding tolerant.
    - A CHANGED underlying type on an existing field -> typeMismatch on every
      existing case file. Optionality does not help: decodeIfPresent throws
      typeMismatch when the key is present with the wrong type, so `Double?`
      becoming `String?` is as destructive as the keyNotFound case and looks
      far more innocent in review.

    Scope is every Swift file under the source root, NOT just Models/, and
    that difference is load-bearing. Six persisted Codable types reach a
    saved ForensicCase from Utilities/: StriationCrossSection,
    StriationProfile and ToolMarkComparison (ToolMarkAnalysis.swift), plus
    ScarMinutia, ScarMinutiaMatch and ScarFingerprintMatch
    (ScarFingerprintAnalysis.swift). They persist via
    CapturedPhoto.scarMinutiae / .toolMarkStriationProfile and
    MatchResult.toolMarkComparison / .scarFingerprintMatch, so both hazards
    above land on every saved case from there exactly as they would from
    Models/. A Models/-only scope passes the real bug that motivated the
    optionality rule -- task #6 added `exclusions` to ToolMarkComparison in
    Utilities/ and needed a hand-written init(from:) for precisely this
    reason -- and it would equally miss a type change on any striation or
    minutia field.

    Rather than enumerate directories (the next persisted type will land
    somewhere new), the hazard is keyed to what creates it: the enclosing
    type conforming to Codable. Existing fields stay exempt from the
    optionality rule -- they are already in the format.
    """
    model_files = [f for f in files
                   if f.startswith(SOURCE_ROOT) and f.endswith(".swift")]
    for f in model_files:
        diff = sh("git", "diff", *diff_args(), "-U0", "--", f)
        if not diff:
            continue

        # Only properties inside a Codable type body are part of the
        # persisted payload. Widening the file scope without this would
        # report every non-optional property in a view model or service.
        codable_spans = codable_line_spans(f)
        if not codable_spans:
            continue

        # Two exemptions, both about whether an OLD payload can exist.
        new_types = types_added_in_diff(f)
        decoded_by_hand = types_with_custom_decoder(f, codable_spans)

        # A type change appears as a -/+ pair on the same field name, so the
        # removed side has to be collected before the added side can be
        # judged. Nothing about such a line looks dangerous in review.
        # Removed lines are matched by field NAME only, with no span test:
        # they describe the pre-image, whose line numbers do not map onto
        # the current file's spans. A name collected here is only ever used
        # to interpret an added line that has already passed the span test,
        # so a stray match cannot by itself report anything.
        removed = {}
        for line in diff.splitlines():
            if line.startswith("-") and not line.startswith("---"):
                parsed = _parse_field(line[1:].strip())
                if parsed:
                    removed[parsed[0]] = parsed[1]

        # -U0 hunk headers carry the post-image line number of each added
        # run, which is what maps an added property onto the Codable spans.
        new_line = 0
        for line in diff.splitlines():
            hunk = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)
            if hunk:
                new_line = int(hunk.group(1))
                continue
            if not line.startswith("+") or line.startswith("+++"):
                continue
            current_line, new_line = new_line, new_line + 1
            enclosing = [nm for lo, hi, nm in codable_spans
                         if lo <= current_line <= hi]
            if not enclosing:
                continue
            # Innermost wins: a nested type inside a Codable one is its own
            # persistence unit, and the outer type's decoder says nothing
            # about it.
            owner = enclosing[-1]

            # Exemption 1: the type itself is introduced in this diff, so no
            # saved case can hold a payload missing the key.
            if owner in new_types:
                continue
            parsed = _parse_field(line[1:].strip())
            if not parsed:
                continue
            name, type_str = parsed
            was = removed.get(name)

            if was is not None:
                if _underlying(was) != _underlying(type_str):
                    fail("persisted-model",
                         f"{f}: field `{name}` changes type "
                         f"{was} -> {type_str} on a persisted model",
                         "every existing case file stores the old type and "
                         "will throw typeMismatch on decode -- optionality "
                         "does not help. Add a new optional field and "
                         "migrate, or write an explicit init(from:) that "
                         "reads both shapes.")
                # An existing field, so the optionality rule does not apply:
                # it is already in the persisted format either way.
                continue

            if type_str.endswith("?") or type_str.startswith("Optional"):
                continue

            # Exemption 2: the type has a hand-written init(from:), which is
            # the remedy this check recommends -- blocking it would block the
            # fix. Advisory rather than silent: the decoder still has to read
            # this key tolerantly, and only a human can confirm that.
            if owner in decoded_by_hand:
                warn("persisted-model",
                     f"{f}: new non-optional field `{name}: {type_str}` on "
                     f"`{owner}`, which has a hand-written init(from:)",
                     "not blocking -- an explicit decoder is the recommended "
                     "remedy. Confirm it reads this key with decodeIfPresent "
                     "and a default, since a custom decoder can still decode "
                     "a new key non-optionally.")
                continue

            fail("persisted-model",
                 f"{f}: new non-optional field `{name}: {type_str}` on a "
                 "persisted model",
                 f"make it `{type_str}?` (or decodeIfPresent with an explicit "
                 "init(from:)). Every case file already on a device predates "
                 "this field and will fail to decode -- the build stays green "
                 "while real case data becomes unopenable.")


# ---------------------------------------------------------------- reporting
def main():
    args = sys.argv[1:]
    if "--install-hook" in args:
        hook = os.path.join(REPO, ".git", "hooks", "pre-commit")
        with open(hook, "w") as fh:
            fh.write("#!/bin/sh\nexec python3 scripts/preflight.py\n")
        os.chmod(hook, 0o755)
        print(f"installed {hook}")
        return 0

    global DIFF_BASE
    if "--since" in args:
        i = args.index("--since")
        if i + 1 >= len(args):
            print("preflight: --since needs a git ref, e.g. --since origin/main")
            return 1
        DIFF_BASE = args[i + 1]
        # Fail loudly on an unknown ref: silently diffing against nothing
        # would report a clean run, which is the dead-check failure this
        # whole flag exists to avoid.
        if subprocess.run(["git", "rev-parse", "--verify", "--quiet",
                           f"{DIFF_BASE}^{{commit}}"],
                          cwd=REPO, capture_output=True).returncode != 0:
            print(f"preflight: unknown git ref '{DIFF_BASE}'")
            return 1

    whole_tree = "--all" in args
    files = tracked_swift() if whole_tree else changed_files()
    if not files and not whole_tree:
        where = "staged" if DIFF_BASE is None else f"changed since {DIFF_BASE}"
        print(f"preflight: nothing {where}")
        return 0

    # Tree-wide checks: valid whether or not anything is staged.
    check_pbxproj_registration()
    check_skeleton_drift()
    check_signing_configured()
    check_delimiter_balance(files)

    # Commit-shaped checks: only meaningful against a staged diff. In --all
    # mode there is no commit to judge, and firing them anyway trains people
    # to ignore the output -- which would also blunt the checks above.
    if not whole_tree:
        check_commit_size(files)
        check_docs_owed(files)
        check_persisted_model(files)

    for check, msg, remedy in warnings:
        print(f"warn  [{check}] {msg}\n      -> {remedy}")
    for check, msg, remedy in failures:
        print(f"FAIL  [{check}] {msg}\n      -> {remedy}")

    if failures:
        scope = ("whole tree" if whole_tree
                 else "staged changes" if DIFF_BASE is None
                 else f"changes since {DIFF_BASE}")
        print(f"\npreflight: {len(failures)} blocking, "
              f"{len(warnings)} advisory -- {scope}. Commit refused.")
        print("Override with --no-verify only if you know why.")
        return 1
    scope = ("whole tree" if whole_tree
             else "staged changes" if DIFF_BASE is None
             else f"changes since {DIFF_BASE}")
    print(f"\npreflight: clear ({len(warnings)} advisory) -- {scope}.")
    print("This means 'worth compiling'. It does not mean it compiles -- "
          "PROCESS.md sec.4 clauses 4-6 still need Xcode and a device.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
