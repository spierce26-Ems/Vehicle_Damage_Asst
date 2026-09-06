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
    python3 scripts/preflight.py --install-hook

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


def staged_files():
    out = sh("git", "diff", "--cached", "--name-only", "--diff-filter=ACMR")
    return [f for f in out.splitlines() if f]


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
    out = sh("git", "diff", "--cached", "--numstat")
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

    added_removed = sh("git", "diff", "--cached", "--name-only",
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

    Scoped to Models/, which is the persistence format; a non-optional stored
    property elsewhere is not a decoding hazard. Existing fields are exempt
    from the optionality rule -- they are already in the format.
    """
    model_files = [f for f in files
                   if f.startswith(MODELS_DIR) and f.endswith(".swift")]
    for f in model_files:
        diff = sh("git", "diff", "--cached", "-U0", "--", f)
        if not diff:
            continue

        # A type change appears as a -/+ pair on the same field name, so the
        # removed side has to be collected before the added side can be
        # judged. Nothing about such a line looks dangerous in review.
        removed = {}
        for line in diff.splitlines():
            if line.startswith("-") and not line.startswith("---"):
                parsed = _parse_field(line[1:].strip())
                if parsed:
                    removed[parsed[0]] = parsed[1]

        for line in diff.splitlines():
            if not line.startswith("+") or line.startswith("+++"):
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

    whole_tree = "--all" in args
    files = tracked_swift() if whole_tree else staged_files()
    if not files and not whole_tree:
        print("preflight: nothing staged")
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
        print(f"\npreflight: {len(failures)} blocking, "
              f"{len(warnings)} advisory. Commit refused.")
        print("Override with --no-verify only if you know why.")
        return 1
    print(f"\npreflight: clear ({len(warnings)} advisory).")
    print("This means 'worth compiling'. It does not mean it compiles -- "
          "PROCESS.md sec.4 clauses 4-6 still need Xcode and a device.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
