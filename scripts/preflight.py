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
import glob
import os
import re
import shutil
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
# True when DIFF_BASE was derived from a merge in progress, so the changes to
# judge are in the WORKING TREE rather than in HEAD. See diff_args().
MERGE_BASE_IS_WORKTREE = False


def diff_args():
    """The `git diff` selector the commit-shaped checks should use.

    MERGE_BASE_IS_WORKTREE is set when a merge is in progress: the resolution
    is in the working tree, not in HEAD, so `BASE...HEAD` would compare HEAD
    to itself and report nothing changed -- a clean line over the exact
    commit shape that produced today's two worst defects.
    """
    if DIFF_BASE is None:
        return ["--cached"]
    if MERGE_BASE_IS_WORKTREE:
        return [DIFF_BASE]
    return [f"{DIFF_BASE}...HEAD"]


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
        # remedy: state
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
        # remedy: fixes
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
        # remedy: state
        #
        # Declared `fixes` in the first draft of this annotation, and Compass
        # measured that claim FALSE within the hour -- which is the harness
        # doing its only job. `build_pbxproj.py` only ADDS missing sources; it
        # never removes an entry, so a ghost PBXBuildFile survives a run that
        # reports success. Worse than the manifest string in one respect: the
        # tool says it worked. The finding IS the state -- restore the file, or
        # delete the stale entries by hand.
        fail("pbxproj",
             "pbxproj references file(s) that are not in the tree: "
             + ", ".join(ghosts),
             "restore the file if the deletion was accidental. If the "
             "deletion is intended, DELETE the stale PBXBuildFile and "
             "PBXFileReference entries by hand: build_pbxproj.py only ADDS "
             "missing sources and never removes an entry, so running it "
             "leaves this failure standing. \"Regenerate the pbxproj\" "
             "named a capability nothing here has -- measured, the script "
             "reports a clean no-op run while the ghost reference survives")


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
            # NOT "set_dev_team.sh does both" unconditionally. That script
            # refuses when DEVELOPMENT_TEAM is already present in either
            # file -- which is true in every case that reaches this branch
            # except a key missing from both. Measured: with the pbxproj's
            # team emptied, the remedy's own command exits 1 with "already
            # present ... not overwriting" and the failure stands. Eighth
            # unperformable remedy today, and the first found in the 32
            # sites nobody had executed (PROCESS sec.4c).
            remedy += (" -- ./scripts/set_dev_team.sh only sets an ABSENT "
                       "key and exits 1 when one is already present, so it "
                       "will not reconcile a mismatch")
        # remedy: state
        # `state`, not `fixes`. set_dev_team.sh refuses when the key is
        # already present -- true for every mismatch that reaches here -- so
        # no tool reconciles these two files; both are edited by hand. The
        # other keys are the same shape: two files that must agree, with
        # nothing that makes them agree.
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
        # remedy: fixes
        warn("signing",
             "DEVELOPMENT_TEAM is not set -- Simulator builds are fine, "
             "device builds and TestFlight will fail to sign",
             "./scripts/set_dev_team.sh <10-char Apple Team ID>")
    elif len(teams) < n_cfg:
        # remedy: external
        #
        # Not `fixes`: set_dev_team.sh refuses when the key is already present
        # ("already present ... not overwriting", exit 1), correctly -- silently
        # overwriting a signing identity is worse than stopping. So no script
        # clears this; a person sets the team in both configurations. Compass's
        # new variety, one site over: a remedy whose precondition is the
        # NEGATION of its trigger, true for first-time setup and false for
        # every mismatch that reaches this branch.
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
                # remedy: external
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
            # remedy: external
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
        # remedy: external
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
        # remedy: external
        warn("docs",
             "functional commit with no ios/README.md changelog entry staged",
             "send Ledger what changed / why / which files -- the entry and "
             "the on-device checklist come back written")

    added_removed = sh("git", "diff", *diff_args(), "--name-only",
                       "--diff-filter=AD")
    if any(f.endswith(".swift") for f in added_removed.splitlines()):
        # "Regenerate" is the wrong VERB for an add or a delete, and this is
        # the reminder that fires on exactly those patches. regen_manifest.py
        # maintains rows and never adds or removes one -- the fifth instance
        # of the unperformable remedy, found by finishing the sweep a65e612
        # started rather than waiting to be hit. The missing-rows warning
        # already says this; the reminder that PRECEDES it did not.
        # remedy: reminder
        warn("docs",
             "a Swift file was added or removed",
             "update ios/reference/COMPLETE_FILE_MANIFEST.md in this commit, "
             "in three steps: add or delete the file's row, hand-edit the "
             "Totals: sentence (all THREE numbers -- files, Swift sources, "
             "lines), then run python3 scripts/regen_manifest.py for the "
             "counts -- the regenerator covers only the third. This warning "
             "is a REMINDER keyed to the diff, not a drift check: it stands "
             "until the file stops being added or removed, so it does NOT "
             "clear when the work is done. The manifest and manifest-lines "
             "checks are what verify the result")

    scoring_dirs = ("/Utilities/", "/ForensicEngine/")
    if any(d in f for f in swift for d in scoring_dirs):
        # remedy: reminder
        warn("docs",
             "scoring or analysis code changed",
             "ios/reference/ALGORITHM_EXPLAINER.md may need updating; a "
             "determinism check belongs in the on-device checklist. Keyed to "
             "the diff, like the reminder above: it will not clear in this "
             "run -- check_doc_drift is what verifies the explainer against "
             "the code")


def check_default_valued_predicates():
    """A field defaulted `false` and predicated on may select nothing.

    # remedy: fixes

    NOTE(Vector), 2026-09-07. Found by the Designer against a selector I had
    written. sec.2.3's owed selector was
    `captureConditionPhotos(in:).contains { !$0.motionMeasurable }`, and
    `motionMeasurable` is written on exactly ONE path
    (`ScarCaptureView.performCapture`) while `false` is the struct default.
    `PhotoType.requiredCaptureProtocol` contributes four analysis shots per
    vehicle through `CameraService`, whose `CapturedPhoto(...)` call passes no
    `motionMeasurable` at all -- so the predicate is true on every real
    report, the qualified all-clear becomes the ONLY reachable variant, and
    the plain sentence goes dead. THE ALWAYS-FIRING QUALIFICATION THE LOCK
    FORBIDS, ARRIVING THROUGH THE SELECTOR INSTEAD OF THE WORDING.

    The reusable half is that the section already said "defaults `false`
    everywhere else" as REASSURANCE that the trigger reads the persisted model
    rather than a gate. The same words say the trigger is true for almost
    every photograph in the app. Same sentence, opposite conclusion, and the
    reassuring reading is the one a reviewer reaches for.

    So: before a default-valued field becomes a predicate, count how much of
    the population carries the default. This check states that mechanically --
    a persisted `Bool` defaulted `false` on a model, negated inside a
    `contains`/`filter`/`first(where:)`, is reported unless every initialiser
    call site passes it.

    Scope, so a clear run is not read as stronger: it compares INITIALISER
    CALL SITES against the field, which catches "one writer, many defaults".
    It cannot tell whether a path that DOES pass the field passes a correct
    value, and it says nothing about a field whose default is the intended
    reading for most of the population. A row with no branch is now
    detectable; a branch with the wrong condition is what this closes; a
    branch with a subtly wrong VALUE remains invisible to every check here.
    """
    model = os.path.join(REPO, "ios", "VehicleDamageForensics", "Models",
                         "CapturedPhoto.swift")
    if not os.path.exists(model):
        return
    text = open(model).read()
    fields = set(re.findall(r"^\s*var (\w+): Bool = false", text, re.M))
    if not fields:
        return
    swift = [f for f in tracked_swift() if f.endswith(".swift")]
    for field in sorted(fields):
        negated = []
        writers = 0
        inits = 0
        for f in swift:
            try:
                body = open(os.path.join(REPO, f)).read()
            except OSError:
                continue
            if re.search(r"(contains|filter|first\(where:|allSatisfy)"
                         r"[^\n]*!\s*\$0\." + field, body):
                negated.append(f)
            if re.search(r"^\s*" + field + r":\s", body, re.M):
                writers += 1
            inits += len(re.findall(r"CapturedPhoto\(\s*$", body, re.M))
        if not negated:
            continue
        if writers < inits:
            # remedy: fixes
            warn("default-predicate",
                 f"`{field}` defaults false, is negated in a set predicate "
                 f"({', '.join(os.path.basename(n) for n in negated)}), and "
                 f"{inits - writers} of {inits} CapturedPhoto initialiser "
                 f"call sites pass no value for it",
                 "count how much of the population carries the DEFAULT before "
                 "predicating on the field: a predicate true for almost every "
                 "photograph selects the qualified branch always, which is the "
                 "always-firing note in a new channel. Either pass the field "
                 "from every capture path, or use a per-path capability field "
                 "-- never a second flag that happens to agree today")


def strip_trailing_comment(line):
    """Drop a trailing `//` comment, respecting string literals.

    Ledger's sec.4c-xxiii: `all(...startswith("//"))` separates a comment
    LINE from a code line and NOT code from commentary, so a regressed line
    carrying the correct expression in a trailing comment keeps every guard
    green while getting quieter each time somebody documents it.

    String-literal aware because sec.2.3's locked variants contain `//`
    nowhere today, but a URL in a locked string would be silently truncated
    by a naive split -- a guard that corrupts its own haystack is the
    wrong-object family again.
    """
    out, i, in_str, esc = [], 0, False, False
    while i < len(line):
        c = line[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            out.append(c)
        elif c == '"':
            in_str = True
            out.append(c)
        elif c == "/" and i + 1 < len(line) and line[i + 1] == "/":
            break
        else:
            out.append(c)
        i += 1
    return "".join(out).rstrip()


def check_shapecheck_anchors():
    """A shape check must be ANCHORED to the tree line it models.

    # remedy: fixes

    NOTE(Vector), 2026-09-07. Reviewing the Designer's capability-field
    patch I mutated the LANDED selector in `PDFReportGenerator` back to v1
    -- the exact defect `allclear-variant-selector.shapecheck` was written
    to catch -- and `preflight --all` stayed CLEAR at 0 advisories. Mutating
    the shape check's OWN copy of the selector fails it correctly. So the
    instrument discriminates perfectly, on a model that no longer has any
    connection to the file.

    This is the storage-versus-execution finding one turn further out. That
    one asked whether anything RUNS the checks; this asks whether what they
    run against is the SHIPPING CODE. A reduced model is a legitimate way to
    test a shape without an SDK -- but a reduced model plus a claim about the
    tree is two artefacts, and only the first was being verified. Every one
    of the eight shape checks re-declares its subject as a local `struct`
    and a local `func`, so all eight pass on a tree whose real predicate has
    been deleted. Eight instruments, mutation-tested, all satisfiable by an
    empty repository.

    The mechanism is the same one that made a citation to `File:NNN` read as
    precision: a check names its subject in prose (`// Encodes only facts
    read from the tree at e685c06`) and prose does not fail. A commit sha in
    a comment records WHEN the model was true and nothing detects that it
    stopped being true.

    So: each `.shapecheck` must declare `// anchor: <path> <substring>`, and
    the substring must be PRESENT in that file. This is deliberately the
    weakest possible binding -- a grep, not a parse -- because the strong
    version is the compile that PROCESS.md sec.4 still owes. What it buys is
    exactly one property: mutating or deleting the modelled line in the real
    file makes a shape check fail. The check cannot tell whether the anchor
    is the RIGHT line; it can tell that the line the author named still
    exists.

    Blocking rather than advisory, and this is the one place I'll spend that:
    an unanchored shape check reports a property of its own file while its
    name says it reports one about the app, and today it did so through a
    clear run in front of three reviewers.

    NOTE(Tech Lead), 2026-09-07, third clause. AN ANCHOR THAT RESOLVES
    INSIDE A COMMENT IS THE PROSE DEFECT THIS CHECK WAS BUILT TO CLOSE,
    ARRIVING THROUGH THE CHECK ITSELF. Measured on the stacked tree: regress
    the real selector in `PDFReportGenerator` to v1 AND add a one-line
    history comment quoting the old predicate -- entirely natural in the
    same commit, since documenting what changed is what a careful author
    does -- and `substring in file_text` resolves against the COMMENT. All
    fourteen anchors hold, `--strict` returns 0, `run.sh` is 8/8, and the
    renderer is regressed. Done inside an existing comment line rather than
    on a new one it costs no line-count advisory either, so the manifest
    figures do not flinch.

    The mechanism is exactly the one three paragraphs up: a check names its
    subject in prose and prose does not fail. `hay` was the whole file, so
    the anchor never asked WHERE the line lives. So: an anchor must resolve
    on at least one line that is not a comment. Still a grep -- it cannot
    see a string literal, a `#if`, or dead code, and the strong version is
    still sec.4's compile -- but the ONE failure mode it removes is the one
    that repairs itself with a sentence about the code it broke.
    """
    d = os.path.join(REPO, "scripts", "shapechecks")
    if not os.path.isdir(d):
        return
    checks = sorted(n for n in os.listdir(d) if n.endswith(".shapecheck"))
    if not checks:
        return
    missing, broken, prose = [], [], []
    for name in checks:
        text = open(os.path.join(d, name), encoding="utf-8").read()
        anchors = re.findall(r"^//\s*anchor:\s*(\S+)\s+(.+?)\s*$",
                             text, re.M)
        # `// anchor-seq: <path> :: frag :: frag :: ...` -- Ledger's sec.4c-xix
        # limit, closed for the sign-and-pairing case. An `anchor:` binds a
        # substring's PRESENCE, so anything expressible BETWEEN two anchored
        # tokens is outside it. A seq binds the fragments in ORDER and
        # ADJACENT modulo whitespace, putting the RELATION inside the binding
        # rather than between two members of it.
        seqs = re.findall(r"^//\s*anchor-seq:\s*(\S+)\s+::\s*(.+?)\s*$",
                          text, re.M)
        if not anchors and not seqs:
            missing.append(name)
            continue
        for rel, needle in anchors:
            target = os.path.join(REPO, rel)
            if not os.path.exists(target):
                broken.append(f"{name} -> {rel} (no such file)")
                continue
            hits = [ln for ln in open(target, encoding="utf-8")
                    .read().splitlines() if needle in ln]
            if not hits:
                broken.append(f"{name} -> {rel} (`{needle[:60]}` absent)")
                continue
            # An anchor is a claim about CODE. A line that resolves only
            # inside a comment resolves against prose about the code -- and
            # prose does not fail, which is the defect the anchors were
            # added to close, arriving one hop further in.
            if all(ln.strip().startswith("//") for ln in hits):
                prose.append(f"{name} -> {rel} (`{needle[:60]}` resolves "
                             f"only in a comment)")
        for rel, spec in seqs:
            target = os.path.join(REPO, rel)
            if not os.path.exists(target):
                broken.append(f"{name} -> {rel} (no such file)")
                continue
            raw = open(target, encoding="utf-8").read()
            frags = [f.strip() for f in spec.split("::") if f.strip()]
            # The Tech Lead's sec.4c-xx rule, carried DELIBERATELY because a
            # seq is a second code path and inherits nothing from the fix he
            # made to the first. And BLOCK comments as well as line comments:
            # my first version stripped `//` only, and a `/* ... */`
            # reproducing the whole relation defeated the seq entirely --
            # found by mutation, not by reading. A `//` prefix is
            # non-whitespace and so already broke adjacency; a block
            # comment's body is whitespace-adjacent verbatim code, which
            # makes a seq MORE exposed to commentary than a single anchor,
            # not less.
            code = re.sub(r"/\*.*?\*/", "", raw, flags=re.S)
            code = "\n".join(
                "" if ln.strip().startswith("//")
                else strip_trailing_comment(ln)
                for ln in code.splitlines())
            pattern = r"\s*".join(re.escape(f) for f in frags)
            if not re.search(pattern, code):
                absent = next((f for f in frags if f not in code), None)
                if absent is not None:
                    why = (f"`{absent[:50]}` absent from code"
                           + (" (present only in a comment)"
                              if absent in raw else ""))
                else:
                    why = ("all fragments present in code but NOT in this "
                           "order and adjacency -- the RELATION changed, not "
                           "the members: a swapped arm, an inserted "
                           "negation, or a rebinding between the condition "
                           "and its arms")
                broken.append(f"{name} -> {rel} seq: {why}")
    if missing:
        # remedy: fixes
        fail("shapecheck-anchors",
             f"{len(missing)} of {len(checks)} shape checks declare no "
             f"`// anchor:` line ({', '.join(missing)}) -- each models a "
             f"shape it re-declares locally, so it passes on a tree whose "
             f"real code was deleted",
             "add `// anchor: <path> <substring>` naming the line in the "
             "shipping file the model stands for. A reduced model tests a "
             "shape; only an anchor makes it test THIS tree's shape. A sha "
             "in a comment records when the model was true and never "
             "detects that it stopped being")
    if broken:
        # remedy: fixes
        fail("shapecheck-anchors",
             f"{len(broken)} shape-check anchor(s) no longer resolve: "
             f"{'; '.join(broken)}",
             "the modelled line changed or moved. Re-read the shipping code "
             "and either update the model and its anchor together, or fix "
             "the code the model says is correct -- never the anchor alone, "
             "which converts a real alarm into a silent one")
    if prose:
        # remedy: fixes
        fail("shapecheck-anchors",
             f"{len(prose)} shape-check anchor(s) resolve only inside a "
             f"comment: {'; '.join(prose)}",
             "the anchored text survives as PROSE ABOUT the code while the "
             "code itself changed -- a regression plus a history note "
             "restores the anchor and the check goes green. Re-point the "
             "anchor at the executable line, or if the code is genuinely "
             "gone, delete the model rather than anchoring it to its own "
             "obituary")


def swift_code_only(src):
    """A Swift file's CODE: block, whole-line and trailing comments removed.

    NOTE(Designer), 2026-09-07. Named once because three text-matching guards
    in this file read the same renderer and the comment-stripping fix reached
    them one at a time, over four hops, each time by someone auditing the
    guard they had just touched.

    The Tech Lead's own sec.4c-xxiv ordering rule is the argument for a
    helper rather than a fourth clause: A DEFECT CLASS IS A PROPERTY OF A
    TECHNIQUE, SO ITS AUDIT IS SCOPED BY THE TECHNIQUE, NEVER BY THE DIFF.
    A shared view makes the technique one object that can be audited once;
    three private copies make it three, and the two written first are the
    ones nobody re-reads. Measured on `efe6d0a`: his clause strips `//`
    lines and trailing comments but not BLOCK comments, so a correct ternary
    parked in a `/* */` above a negated live one left `variant-binding`
    silent -- the mutant was caught only by Vector's anchor-seq, through a
    different instrument than the one named for the defect. That is the
    coverage-by-accident sec.4c-xxii refuses to accept, and it survived the
    patch written FOR this class.

    String literals are preserved deliberately: every locked variant these
    checks match IS a string literal, so stripping them would blind the
    guards to their own subject. `strip_trailing_comment` is reused rather
    than re-derived -- it is already literal-aware, and a duplicated helper
    is two predicates that must agree.
    """
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return "\n".join(
        "" if ln.strip().startswith("//") else strip_trailing_comment(ln)
        for ln in src.splitlines())


def check_locked_variant_conditions():
    """The DOCUMENT's stated condition must be the renderer's condition.

    # remedy: fixes

    NOTE(Designer), 2026-09-07. Third edge of one defect, and the only one
    still open after two patches. The Tech Lead mutated the renderer's
    sec.2.3 selector back to v1 and preflight stayed clean; Vector's
    `// anchor:` lines closed that, blocking, for all eight instruments.

    This is the edge neither closes. sec.2.3's PROSE specified the condition
    as `motionMeasurable == false` -- the v1 selector -- in five places,
    including the locked ledger row's `Why` cell. So a reviewer who doubted
    the renderer and checked it against the owning document would have found
    the regression CORRECT and closed the review. A DOCUMENT CARRYING A
    SUPERSEDED CONDITION DOES NOT MERELY FAIL TO CATCH THE REGRESSION, IT
    RATIFIES IT -- and it is the artefact a reviewer consults precisely when
    they doubt the code, so its failure is silent in the direction of
    agreement.

    Measured, not argued: with the anchors in place, regressing the DOC's
    wording while the renderer stays correct produced no finding at all.
    The two halves are independent -- an anchor proves the tree still
    contains the expression the model models, and says nothing about whether
    the prose describes the same expression.

    The copy lock is the precedent and the reason this is a separate
    mechanism. It guards sec.2.3's WORDS in four paragraphs, byte for byte,
    and the always-firing qualification it exists to forbid arrived through
    the PREDICATE those words were locked against. A lock over copy cannot
    see a condition; that is not a gap in the lock, it is a second artefact.

    Scope, so a clear run is not read as stronger than it is: this matches an
    expression TEXTUALLY between the declaration and the renderer, so it
    proves the document and the code state the same predicate. It cannot say
    the predicate is CORRECT -- both move together when the declaration is
    edited to match a wrong selector, which is why Vector's anchor (bound to
    the shape check, reviewed as code) stays the guard on the expression
    itself. It closes "the prose ratifies a regression the code checks
    catch" and nothing else. A variant with NO declaration is REPORTED, not
    skipped: a check whose population can silently empty is the absence
    asserting a pass, and that is this check's own regression.
    """
    doc = os.path.join(REPO, "docs", "EVIDENCE_APPENDIX_CAPTURE_NOTES.md")
    gen = os.path.join(REPO, "ios", "VehicleDamageForensics", "Services",
                       "PDFReportGenerator.swift")
    if not os.path.exists(doc) or not os.path.exists(gen):
        return
    text = open(doc).read()
    lines = text.splitlines()
    declared = re.findall(r"<!--\s*CONDITION:\s*(\S+)\s*=\s*(.+?)\s*-->",
                          text)
    # Count sec.2.3's locked variants, so a DELETED declaration is reported
    # rather than shrinking the population to zero and passing. One
    # declaration covers both variants: the renderer computes ONE selector
    # and branches a ternary, so the plain sentence's guard is that
    # expression's else-branch and has no separate condition. Two
    # independently declared conditions would be two predicates that must
    # agree -- the duplicate-with-diverging-claims defect this repository has
    # hit at every layer -- while one selector with two branches cannot drift
    # against itself.
    variant_count = 0
    in_23 = False
    prev_quote = False
    for l in lines:
        if l.startswith("### 2.3"):
            in_23 = True
            continue
        if not in_23:
            continue
        if l.startswith("### "):
            break
        is_quote = l.startswith("> ")
        if is_quote and not prev_quote:
            variant_count += 1
        prev_quote = is_quote
    if variant_count and not declared:
        # remedy: fixes
        warn("variant-condition",
             f"sec.2.3 defines {variant_count} locked all-clear variant(s) "
             f"and declares no guarding condition",
             "add a `<!-- CONDITION: <key> = <expression> -->` line in the "
             "section that owns the copy. Without it the variant's STRING is "
             "guarded by check_note_rows_implemented, its EXPRESSION by "
             "Vector's shape-check anchor, and the PROSE a reviewer reads by "
             "nothing -- which is how a superseded condition ratifies a "
             "regression")
        return
    if not declared:
        return
    # Code only, and the declaration compared against the SELECTOR's own
    # expression rather than against the whole file.
    #
    # NOTE(Vector), 2026-09-07. Two holes measured in this comparison, both
    # of which let the v1 selector -- the one condition this check exists to
    # catch -- pass silently.
    #
    # (1) SUBSTRING. `!$0.motionMeasurable` IS a substring of
    #     `$0.motionMeasurementAttempted && !$0.motionMeasurable`, so
    #     `want not in flat` can never fire when the declaration regresses to
    #     v1. Measured: corrupted the declaration to the v1 form and preflight
    #     stayed clear at rc=0. The Designer's own rule names it exactly --
    #     an assertion that cannot fail is not an assertion -- and here the
    #     input it cannot fail on is the defect, not an edge case.
    # (2) COMMENTS. `flat` was the whole file, and line ~1037 of the renderer
    #     quotes `contains { !$0.motionMeasurable }` in prose explaining what
    #     was replaced. That is the Tech Lead's sec.4c-xx defect -- a check
    #     that reads a file as text cannot distinguish the code from the
    #     commentary about the code -- arriving in the third instrument in a
    #     row. Its general form now has three independent instances, which
    #     makes it the rule and not the exception for grep-strength checks.
    #
    # Fixed by narrowing the haystack to the selector's own expression, taken
    # from the `let motionUnmeasured = photos.contains { ... }` binding, and
    # requiring EQUALITY there rather than containment anywhere.
    gen_src = open(gen).read()
    gen_code = swift_code_only(gen_src)
    flat = " ".join(gen_code.split())
    m = re.search(r"let motionUnmeasured = photos\.contains \{(.+?)\}", flat)
    selector = " ".join(m.group(1).split()) if m else None
    for key, expr in declared:
        want = " ".join(expr.split())
        if key == "allclear.partial" and selector is not None:
            if want != selector:
                # remedy: fixes
                fail("variant-condition",
                     f"`{key}`'s declared condition does not EQUAL the "
                     f"renderer's selector: document says `{want}`, "
                     f"renderer computes `{selector}`",
                     "one of the two moved. Containment was not enough: the "
                     "v1 form `!$0.motionMeasurable` is a SUBSTRING of the "
                     "correct selector, so a declaration regressed to v1 "
                     "satisfied a containment test -- the check could not "
                     "fail on the one input it exists to catch. Read which "
                     "side moved before editing either")
        elif want not in flat:
            # remedy: fixes
            warn("variant-condition",
                 f"`{key}`'s declared condition `{want}` does not appear in "
                 f"PDFReportGenerator.swift",
                 "read which side moved before editing either. If the "
                 "renderer changed, Vector's shape-check anchor is failing "
                 "too and that is the finding; if only this fires, the "
                 "DECLARATION is stale -- and a stale condition in the "
                 "owning document is the artefact a reviewer trusts when "
                 "they doubt the code")
        # The prose a reviewer actually reads, not only the declaration: the
        # declaration is a copy, and a copy of a claim goes stale the way
        # every duplicate in this repository does. sec.2.3 named the v1
        # condition in five places while any single declaration would have
        # matched, so the check asks whether the SUPERSEDED form still reads
        # as current -- an unqualified `motionMeasurable == false` presented
        # as the trigger, rather than as the form that was replaced.
        if key != "allclear.partial":
            continue
        for i, l in enumerate(lines):
            if not re.search(r"emit this instead", l):
                continue
            # The DECLARATION must be stripped from the window before the
            # prose is judged. Caught by mutation, not by reading: with the
            # comment left in, regressing the prose to v1 shortened it by a
            # line, pulled `<!-- CONDITION: ... -->` into the window, and the
            # correct expression it carries satisfied the very test meant to
            # find the stale prose. THE DECLARATION IMMUNISED THE CHECK
            # AGAINST THE DEFECT IT DECLARES -- an artefact that is both the
            # reference and part of the searched text, which is the
            # mutate-the-fixture member of the wrong-object family arriving
            # inside my own check.
            # Ledger's sec.4c-xxiii one syntax level down, and the third
            # instance of this defect in my own check: dropping declaration
            # LINES distinguishes a comment line from a prose line and NOT
            # prose from commentary. A trailing `<!-- ... -->` on the emit
            # instruction ITSELF is a prose line carrying the correct
            # expression, so it vouched for a v1 instruction on the same
            # line. Strip the comment CONTENT: a declaration must never be
            # able to vouch for the prose beside it, wherever it sits.
            window = re.sub(r"<!--.*?-->", " ",
                            " ".join(lines[max(0, i - 6):i + 1]),
                            flags=re.S)
            if "motionMeasurable == false" in window and want not in window:
                # remedy: fixes
                warn("variant-condition",
                     "sec.2.3's emit instruction states the condition as "
                     "`motionMeasurable == false`, which is the superseded "
                     "v1 selector, while the renderer uses "
                     f"`{want}`",
                     "correct the prose, not only the declaration: a "
                     "reviewer checking the renderer against this document "
                     "would find a v1 regression CORRECT. The v1 form is "
                     "true of every photograph that never claimed a "
                     "measurement, which makes the qualified variant the "
                     "only reachable one")


def check_variant_output_binding():
    """The condition must be bound to the ARM, not merely present.

    # remedy: fixes

    NOTE(Designer), 2026-09-07. Ledger's finding, measured on the fully
    stacked tree: negate the ternary's TEST and leave the anchored condition
    untouched, and every instrument passes -- `preflight --all --strict`
    clear at rc=0, `run.sh` 8/8. A renderer emitting the wrong variant on
    every report, with the selector correct, both strings locked byte-exact
    and both variants reachable. WIRED TO THE WRONG ARMS.

    And the direction is the bad one. Inverted, a photograph that ATTEMPTED
    and FAILED to measure motion prints the UNQUALIFIED all-clear -- "All
    analysis photographs met the app's capture-quality checks." That is the
    sec.2.3 over-claim the entire variant mechanism exists to stop, on the
    page an examiner signs.

    Why nothing saw it: mutation-testing proves a check DISCRIMINATES, an
    anchor proves the modelled line EXISTS, and neither asks whether the
    line's VALUE reaches the reader unnegated. A grep-strength anchor binds a
    substring's PRESENCE, so anything expressible BETWEEN the condition and
    the drawn string is outside all fourteen anchors: a `!`, a swapped
    ternary, a shadowed local, an early `return`. Ledger's framing is the
    one to keep -- row-with-no-branch is detectable, the wrong CONDITION is
    what the anchors close, and A CORRECT CONDITION WIRED TO THE WRONG OUTPUT
    was invisible to everything we had.

    Ledger declined to propose a check and recorded it as the anchors'
    standing limit, on the ground that the assertion which catches it renders
    the block and reads the emitted string -- sec.4's compile-and-run debt.
    THAT IS RIGHT ABOUT THE CLASS AND WRONG ABOUT THIS MEMBER, and taking the
    limit at its word is what a stated limit gets. The class needs a renderer.
    But the SIGN is not between the condition and the string here: the
    ternary's test and both arms are one expression, textually adjacent, so
    which literal sits on the TRUE arm is a property a grep can read. This
    check buys exactly that: the qualified string must be on the arm the
    condition selects when it is TRUE.

    It closes the instance and NOT the class, and that distinction is the
    whole lesson of today's Swift-count round -- a fix that removes today's
    instance while the class stays open reads exactly like a closure. So:
    the class stays open in Ledger's sec.4c-xx as compile-and-run debt, and
    a clean run here must not be read as covering a shadowed local, an early
    return, or a variant drawn from a second call site.

    Blocking, unlike my prose check: an inverted variant is a false statement
    on a signed page, and unlike an environment-dependent shape check this is
    a property of the tree alone.
    """
    gen = os.path.join(REPO, "ios", "VehicleDamageForensics", "Services",
                       "PDFReportGenerator.swift")
    doc = os.path.join(REPO, "docs", "EVIDENCE_APPENDIX_CAPTURE_NOTES.md")
    if not os.path.exists(gen) or not os.path.exists(doc):
        return
    # sec.4c-xxiv (Tech Lead). Flatten the CODE only, reusing Vector's
    # `strip_trailing_comment` rather than a second copy of it. This check
    # reads a file as text, so it inherits the prose-does-not-fail defect
    # exactly as the anchors did: `re.search` takes the FIRST match, so a
    # commented copy of the CORRECT ternary parked above a negated live one
    # satisfied the check that exists to catch the negated live one --
    # measured at `clear`, rc=0, with the renderer emitting the wrong
    # variant on every report. Vector's anchor-seq catches that mutant
    # incidentally through the anchor path; this check, which is the
    # instrument NAMED as the guard on the sign, reported clear alone.
    # Via the shared view, which additionally strips BLOCK comments: the
    # local version here missed `/* */`, so a correct ternary parked in a
    # block above a negated live one left this check silent and the mutant
    # was caught only by the anchor-seq -- a different instrument than the
    # one named for this defect.
    flat = " ".join(swift_code_only(open(gen).read()).split())
    # The QUALIFIED variant is the second blockquote in sec.2.3 -- taken from
    # the document rather than written here, so the check cannot drift into
    # asserting its own copy of a locked string. That is the
    # duplicate-with-diverging-claims defect aimed at a checker, and this
    # file has already committed it once via HELD_UNEMITTED.
    lines = open(doc).read().splitlines()
    variants = []
    buf = []
    in_23 = False
    for l in lines:
        if l.startswith("### 2.3"):
            in_23 = True
            continue
        if not in_23:
            continue
        if l.startswith("### "):
            break
        if l.startswith("> "):
            buf.append(l[2:].strip())
        elif buf:
            variants.append(" ".join(buf))
            buf = []
    if buf:
        variants.append(" ".join(buf))
    if len(variants) < 2:
        # remedy: fixes
        warn("variant-binding",
             f"sec.2.3 parsed to {len(variants)} locked variant(s); this "
             "check needs both to know which belongs on which arm",
             "verify the section's blockquote shape rather than trusting "
             "this check's silence -- a population that can silently empty "
             "is the absence asserting a pass")
        return
    qualified = " ".join(variants[1].split())
    ternary = re.search(r"let allClear = (!?)(\w+)\s*\?\s*\"(.*?)\"\s*:",
                        flat)
    if not ternary:
        # remedy: fixes
        fail("variant-binding",
             "could not find sec.2.3's `let allClear = <cond> ? ... : ...` "
             "ternary in PDFReportGenerator.swift",
             "the all-clear may have been restructured (an if/else, a "
             "helper, a second call site). Re-point this check AND re-read "
             "whether the new shape still puts the qualified variant on the "
             "condition's true arm -- an anchor that finds nothing is the "
             "absence asserting a pass")
        return
    negated, cond, true_arm = ternary.groups()
    if negated or " ".join(true_arm.split()) != qualified:
        # remedy: fixes
        fail("variant-binding",
             "sec.2.3's all-clear is wired to the wrong arm: the QUALIFIED "
             f"variant must be the true arm of `{cond}` and the test must "
             "not be negated",
             "inverted, a photograph that ATTEMPTED and FAILED to measure "
             "motion prints the UNQUALIFIED all-clear -- the sec.2.3 "
             "over-claim the variant mechanism exists to stop, on the page "
             "an examiner signs. The selector, the anchors and both locked "
             "strings are all still correct when this fires: a correct "
             "condition wired to the wrong output is a different defect")


def check_shapechecks_run():
    """The shape-check runner must actually be RUN by something.

    # remedy: fixes

    NOTE(Vector), 2026-09-07. `scripts/shapechecks/run.sh` is mutation-tested
    three ways and correct. Nothing invoked it. A TRACKED CHECK NOBODY RUNS
    DECAYS INTO A FILE -- the same shape as `check_remedies.py`, which was
    written, reviewed and landed unwired earlier today and reported nothing
    for a full round.

    Giving the instruments a durable home solved storage; this solves
    execution, and they are different problems. A check nobody can re-run is
    a claim; a check nobody does re-run is a decoration.

    Scope, so a clear run is not read as stronger than it is: this proves each
    shape check still COMPILES and its own assertions still HOLD. It does not
    prove any of them still DISCRIMINATES -- that a mutation of the property
    under test would make it fail. Verifying that requires mutating the tree,
    which a preflight check must not do, so the entry condition stays a
    written requirement in the README. And a passing shape check is evidence
    about a reduced MODEL, which says nothing about the tree.

    Advisory, and NAMED rather than silent when no toolchain is present: an
    environment-dependent check reports a property of the pair, never of the
    commit, and "the checks are clear" is a claim about the checks that RAN.
    """
    runner = os.path.join(REPO, "scripts", "shapechecks", "run.sh")
    if not os.path.exists(runner):
        return
    swiftc = os.environ.get("SWIFTC") or shutil.which("swiftc")
    if not swiftc:
        home = os.path.join(os.path.expanduser("~"),
                            "toolchains", "swift", "usr", "bin", "swiftc")
        swiftc = home if os.access(home, os.X_OK) else None
    if not swiftc:
        # remedy: external
        warn("shapechecks",
             "the shape checks were NOT RUN -- no Swift compiler found "
             "(set SWIFTC)",
             "install a swift.org toolchain or set SWIFTC. Named rather than "
             "skipped silently: a check that did not run must say so, or a "
             "clear aggregate reads as coverage it does not have")
        return
    env = dict(os.environ, SWIFTC=swiftc)
    # Captured, never piped: reading a runner's verdict through a pipe returns
    # the PIPE's status, which is how a failing run was read as passing today.
    out = subprocess.run(["bash", runner], capture_output=True, text=True,
                         cwd=REPO, env=env)
    # rc=3 is "could not run", not "failed" -- Ledger's exit-code split. A
    # caller that treats every non-zero alike reports an absent toolchain as a
    # failing instrument, which is the misattributing diagnostic this file has
    # now hit four times: right about there being a problem, wrong about whose.
    if out.returncode == 3:
        # remedy: external
        warn("shapechecks",
             "the shape checks were NOT RUN -- run.sh reports no usable Swift "
             "compiler (rc=3)",
             "set SWIFTC to a swift.org toolchain. Named rather than skipped "
             "silently, and deliberately NOT reported as a failure: no result "
             "and a bad result are different claims")
        return
    if out.returncode == 2:
        # remedy: fixes
        warn("shapechecks",
             "run.sh found NO shape checks (rc=2) -- an empty pass is not a "
             "pass",
             "restore the instruments or remove the runner: a check that "
             "examines nothing cannot fail, which is the absence asserting "
             "the clean case")
        return
    if out.returncode != 0:
        # Name the FILES that failed, not the runner's whole FAIL line: the
        # line carries the interpreter's own trailing output (a Swift
        # precondition prints a backtrace), so quoting it verbatim produced
        # "motionblur-window.shapecheck -- Backtrace took 0.00s" -- a true
        # alarm whose text points at nothing. Verified by reading the EMITTED
        # message on a mutant rather than the format string.
        failing = []
        for line in out.stdout.splitlines():
            stripped = line.strip()
            if not stripped.lower().startswith(("fail", "compile fail")):
                continue
            for token in stripped.split():
                if token.endswith(".shapecheck"):
                    failing.append(token)
                    break
        detail = ", ".join(sorted(set(failing))) if failing else \
            f"runner exited {out.returncode} with no FAIL line"
        # remedy: fixes
        warn("shapechecks",
             f"scripts/shapechecks/run.sh reports failures: {detail}",
             "read the failing assertion's NAME before deciding which side "
             "moved: a reduced model says nothing about the tree on its own, "
             "so either the model is wrong or the behaviour it models "
             "changed, and the assertion name is what distinguishes them")


def check_note_rows_implemented():
    """Every note row the appendix SPECIFIES must exist in the renderer.

    # remedy: fixes

    NOTE(Vector), 2026-09-07. `qualityFlags.hasMotionBlur` was written into
    evidence from 6c2202f: persisted on CapturedPhoto, decoded additively,
    carried through duplication, and given a row in sec.2.2's note table.
    `PDFReportGenerator.captureNotes(for:)` implemented five of the table's
    six rows and never read it. The flag reached the model and the artefact
    never asked, so a photograph the app had MEASURED as moved printed an
    all-clear -- for two rounds, through three reviews, past a doc table that
    said otherwise.

    That is the zero-reader defect one layer out from where it was found. Its
    first instance was a computed property with no reader anywhere; the
    repair gave it a reader on the MODEL, which is not the artefact that
    makes the claim. A spec row and a rendered note are different artefacts,
    and only the second is what an examiner reads. THE POPULATION FOR "IS
    THIS WIRED" IS THE RENDERED PAGE, NOT THE STRUCT.

    So this check is the population stated mechanically: read the copy table
    that OWNS the wording, and assert each row's string appears verbatim in
    the renderer. Advisory rather than blocking, because the table is
    Ledger's document and a new row legitimately lands before its code.

    Scope, stated so a clear run is not read as stronger than it is: this
    matches the note STRING, so it proves the copy is present and reachable
    in the file -- not that the predicate guarding it is correct. A row
    guarded by `if false` passes. It closes the "specified but never
    rendered" gap and nothing else.
    """
    doc = os.path.join(REPO, "docs", "EVIDENCE_APPENDIX_CAPTURE_NOTES.md")
    gen = os.path.join(REPO, "ios", "VehicleDamageForensics", "Services",
                       "PDFReportGenerator.swift")
    if not os.path.exists(doc) or not os.path.exists(gen):
        return
    lines = open(doc).read().splitlines()
    # The note table is the one whose header names the condition and the note.
    start = None
    for i, l in enumerate(lines):
        head = l.lower()
        if (l.startswith("|") and "note" in head
                and ("trigger" in head or "condition" in head)):
            start = i + 2
            break
    if start is None:
        # remedy: fixes
        warn("note-rows",
             "could not locate the sec.2.2 condition/note table in "
             "EVIDENCE_APPENDIX_CAPTURE_NOTES.md",
             "this check anchors on a table header naming Trigger/Condition "
             "and Note; "
             "if the table moved or was retitled, re-point the anchor -- an "
             "anchor that silently finds nothing is the absence asserting a pass")
        return
    rows = []
    for l in lines[start:]:
        if not l.startswith("|"):
            break
        cells = [c.strip() for c in l.strip("|").split("|")]
        if len(cells) >= 2 and cells[1]:
            rows.append((cells[0], cells[1]))
    if not rows:
        # remedy: fixes
        warn("note-rows",
             "the sec.2.2 note table parsed to zero rows",
             "a check that examines nothing cannot fail -- verify the table's "
             "shape rather than trusting this check's silence")
        return
    # sec.2.3's all-clear variants are BLOCKQUOTES, not table rows, and the
    # same defect lives there. Ledger found this by taking the docstring's
    # stated scope literally and asking what else it does not reach.
    #
    # NOTE(Vector), 2026-09-07. This widening is the check failing its own
    # rule on its first reuse: it was scoped to "the note table" because a
    # note table was the instance in hand, and the population is every locked
    # string the renderer is supposed to emit. A CHECK SCOPED TO THE SHAPE OF
    # ITS FIRST INSTANCE COVERS THAT INSTANCE AND READS AS COVERING THE CLASS.
    #
    # A variant that is locked and deliberately NOT emitted is declared in the
    # table below rather than reported, so an intentional hold reads as a hold
    # and not as an oversight. sec.2.3's `allclear.partial` is held on the
    # Designer's finding: its owed selector is true on every real report, so
    # emitting it would make the qualified form the only reachable variant --
    # the always-firing qualification the lock forbids, arriving through the
    # selector instead of the wording.
    # HELD_UNEMITTED: locked strings deliberately NOT rendered, each with the
    # reason. Empty is the correct state right now and that is worth saying:
    # sec.4.3.1's `attest.body` was held here while it was RULED-and-owed, and
    # 40e4709 built it -- so the hold became obsolete rather than stale, which
    # this check cannot tell apart from a hold whose string drifted. Both
    # report the same way and both mean "re-read the row"; that is the
    # honest limit of a declaration mechanism.
    #
    # sec.2.3's `allclear.partial` is NOT held here and must not be: its
    # locked wording is absent from the tree by DESIGN pending a per-path
    # capability field, and it is declared in the appendix section itself
    # where a reader meets it. A hold declared in two places is the
    # duplicate-with-diverging-claims defect aimed at a checker.
    # NOTE(Designer), 2026-09-07. EMPTY, and sec.2.3's hold is LIFTED
    # because the blocker is gone: `CapturedPhoto.motionMeasurementAttempted`
    # is a per-path capability field, so the selector can now distinguish
    # "attempted and unavailable" from "never claimed" and both all-clear
    # variants are reachable. `allclear.partial` is rendered.
    #
    # Left as an empty dict rather than deleted. Vector's bound on this
    # mechanism is why: a declaration cannot tell a STALE hold from an
    # OBSOLETE one, and both report identically -- so an obsolete entry left
    # here would read as a live decision. Removing the ENTRY while keeping the
    # structure records that the mechanism is still wanted and nothing is
    # currently held.
    HELD_UNEMITTED: set[str] = set()
    variants = []
    buf = []
    in_23 = False
    for l in lines:
        if l.startswith("### 2.3"):
            in_23 = True
            continue
        if not in_23:
            continue
        if l.startswith("### "):
            break
        if l.startswith("> "):
            buf.append(l[2:].strip())
        elif buf:
            # A blockquote ENDS at the first non-quote line. Flushing on the
            # loop's tail instead concatenated both variants into one string
            # that matched nothing, and the check then BLAMED THE VARIANT
            # THAT IS RENDERED -- a check naming the wrong member sends a
            # reader to correct working code.
            variants.append(" ".join(buf))
            buf = []
    if buf:
        variants.append(" ".join(buf))
    rows += [(f"sec.2.3 all-clear variant {i + 1}", v)
             for i, v in enumerate(variants)
             if " ".join(v.split()) not in
             {" ".join(h.split()) for h in HELD_UNEMITTED}]

    # THE LEDGER TABLE IS THE POPULATION. Third widening, and the Tech Lead's
    # point is that this one is the whole class rather than another member:
    # sec.2.2's rows and sec.2.3's blockquotes are two places locked strings
    # happen to live, while the ledger table (date, key, was, now, why) is the
    # artefact that OWNS every locked string in this document. `attest.body`
    # and sec.6.1's filtered wording were both locked, both recorded as owed,
    # and neither was in the population -- so the two strings most likely to
    # be forgotten were the two nothing recomputed.
    #
    # NOTE(Vector), 2026-09-07. This is sec.4c-xi committed twice by the same
    # check: scoped to a table, widened to blockquotes, and still enumerating
    # PLACES rather than naming the population. Widening to "one more shape"
    # is what a member-shaped fix looks like; the set-shaped fix is to read
    # the register.
    #
    # `Now` cells carrying markdown annotation rather than a rendered string
    # (`*(text unchanged; ...)*`) are skipped: a ledger row recording that a
    # string's MEANING moved without a diff has no literal to find, and
    # reporting it would be the check inventing an absence.
    ledger = []
    for i, l in enumerate(lines):
        if l.startswith("|") and "| Key |" in l and "| Now |" in l:
            for row in lines[i + 2:]:
                if not row.startswith("|"):
                    break
                cells = [c.strip() for c in row.strip("|").split("|")]
                if len(cells) >= 4 and cells[1] and cells[3]:
                    ledger.append((cells[1], cells[3]))
            break
    held = {" ".join(h.split()) for h in HELD_UNEMITTED}
    # A HELD declaration is a COPY of a locked string, so it goes stale the
    # way every duplicate in this repository does -- and it fails silently in
    # the dangerous direction: the copy stops matching, the row reports as
    # owed, and it reads as an oversight rather than as a stale hold. This
    # caught itself once already: sec.4.3.1's wording was re-ruled into first
    # person after the declaration was written.
    ledger_flat = {" ".join(re.sub(r"\s*\*\(.*?\)\*\s*", " ", n).split())
                   for _, n in ledger}
    for h in sorted(held):
        if h not in ledger_flat:
            # remedy: fixes
            warn("note-rows",
                 "a HELD_UNEMITTED declaration matches no ledger row -- the "
                 "hold is stale and is protecting nothing",
                 "re-copy the string from the ledger row it is holding, or "
                 "drop the declaration if the row is gone. A hold that no "
                 "longer matches reports its row as owed, which reads as an "
                 "oversight rather than as a decision")
    for key, now in ledger:
        # A `Now` cell may carry an italic ANNOTATION after the string --
        # `Tape measure out of frame? *(text unchanged; now a question ...)*`.
        # Strip it: the annotation is the ledger's note to a reader, not part
        # of the rendered copy, and matching it whole reported a string that
        # IS in the tree at two call sites as absent. A checker that includes
        # the commentary in the thing being checked reports a documentation
        # style as a code defect.
        now = re.sub(r"\s*\*\(.*?\)\*\s*", " ", now).strip()
        # A locked TEMPLATE is not a locked SENTENCE -- the Tech Lead's
        # caution, arriving as a real false positive. sec.6.1's row carries
        # `NN%` / `M of N` placeholders that a format string fills at runtime,
        # so no literal can ever match it. Compare only the placeholder-free
        # SENTENCES of such a row: the claim is in those, and the figure is
        # the part the code is supposed to substitute.
        if re.search(r"\bNN%|\bM of N\b", now):
            sentences = [t.strip() for t in re.split(r"(?<=\.)\s+", now)
                         if t.strip() and not re.search(r"\bNN%|\bM of N\b", t)]
            if not sentences:
                continue
            now = " ".join(sentences)
        # A row whose entire cell is annotation records a string whose MEANING
        # moved without a diff (`confirm.arm`'s first row). There is no
        # literal to find, and reporting it would be the check inventing an
        # absence -- the failure sec.5 forbids, committed by the checker.
        if not now:
            continue
        if " ".join(now.split()) in held:
            continue
        rows.append((f"ledger {key}", now))

    # Two different populations need two different search scopes, and
    # conflating them was the first version of this widening's bug: sec.2.2's
    # notes and sec.2.3's all-clears are REPORT copy and live only in
    # PDFReportGenerator, while a ledger row may be BUTTON copy
    # (`confirm.yes`, `confirm.arm`) that correctly appears nowhere near the
    # report. Searching the whole tree for the first group would let a note
    # satisfy the check from a comment; searching one file for the second
    # reported four present strings as absent.
    #
    # A check with one population and two homes has to say which home it is
    # asking about -- "the string exists" and "the string exists WHERE IT IS
    # RENDERED" are different claims, and only the second is the requirement.
    # CODE only, via the shared view. sec.4c-xxv: this is the OLDEST
    # grep-strength instrument in the file -- written a full day before the
    # class had a name -- and it was still reading whole files. Comment out a
    # note row's `notes.append("...")` and leave the string in the disabled
    # line, which is what a careful author does when parking code, and this
    # check reported NOTHING while deleting the same emit reported it
    # correctly. So it told a DELETED note from a PRESENT one and could not
    # tell a DISABLED one from either -- the worst of the three, because
    # disabling is the reversible-looking option a reviewer waves through,
    # and the appendix specifies a RENDERED string while a disabled emit
    # renders nothing. Found by aiming the audit at the oldest instrument
    # rather than the newest, per the Tech Lead's ordering rule; fixed
    # through the Designer's shared view rather than a fourth private copy,
    # which is the same rule applied to the remedy.
    report_flat = " ".join(swift_code_only(open(gen).read()).split())
    tree_flat = ""
    for f in tracked_swift():
        try:
            tree_flat += " " + " ".join(swift_code_only(
                open(os.path.join(REPO, f)).read()).split())
        except OSError:
            continue
    missing = []
    for label, note in rows:
        haystack = tree_flat if label.startswith("ledger ") else report_flat
        if " ".join(note.split()) not in haystack:
            missing.append((label, note))
    if missing:
        names = "; ".join(c for c, _ in missing)
        # remedy: fixes
        warn("note-rows",
             f"the appendix specifies {len(rows)} rendered strings "
             f"(sec.2.2 note rows, sec.2.3 all-clear variants and ledger "
             f"rows, excluding any declared as held); {len(missing)} have no "
             f"literal where they are rendered ({names})",
             "copy the string VERBATIM into the surface that renders it -- a "
             "note or all-clear into PDFReportGenerator.captureNotes(for:) / "
             "drawCaptureConditions guarded by the recorded flag and never by "
             "a live gate, a ledger row into whichever surface owns it "
             "(report copy vs button copy). If the string is deliberately "
             "NOT built, declare it in this check's HELD_UNEMITTED with the "
             "reason -- a hold that is not declared is indistinguishable from "
             "an oversight in this output")


def check_cited_doc_copy():
    """A document the app CITES to a reader is report copy.

    The sec.6.4 ban list is enforced against rendered strings, and the
    rendered strings are clean. But MatchScoreCalculator's exclusion text
    tells an investigator "see ALGORITHM_EXPLAINER §2", so the report does
    not CONTAIN the abandoned verdict-and-probability framing -- it POINTS at
    it. A reader who follows the citation lands three sections later on a
    table reading "60-79 | 60-85% | MEDIUM | Probable match", which is
    exactly what MatchResult.scoreRangeLabel refuses to say ("a score band,
    NOT a statistical probability") and what the legacyProbabilityRange
    decode path exists to migrate away from.

    So the lock has to follow the citation. Any reference document named in a
    user-visible string is scanned for the framing the app abandoned; a doc
    nobody cites is documentation and not this check's business.

    Scope, stated because a clear run should not read as stronger than it is:
    the check assumes user-visible copy lives in Swift source as literals,
    which is true today. `NSLocalizedString("some.key", ...)` passes silently
    and honestly -- the copy is not in the file. If localisation ever lands,
    the strings move into .strings/.stringsdict catalogues and this check has
    to follow them; the anchor assertion below is what makes that move loud
    instead of silent.

    Advisory, and it never rewrites prose -- ios/reference/ is Ledger's. Found
    by Prism while closing out the ALGORITHM_EXPLAINER advisory on his own
    scoring commits; the multiline blind spot was found by Prism testing the
    check against the one string it could not see.
    """
    banned = [
        (r"\|\s*\d+\s*-\s*\d+\s*\|\s*\d+\s*-\s*\d+\s*%",
         "a score band mapped to a probability range"),
        (r"pursue legal action", "an action recommendation the app does not make"),
        (r"PROBABLE MATCH|Probable match", "a verdict label"),
        (r"deterministic \(no randomness\)",
         "a no-randomness claim (both matchers run seeded permutation "
         "shuffles; determinism holds, the stated reason does not)"),
    ]

    cited = set()
    scanned_literals = 0
    for f in sh("git", "ls-files", f"{SOURCE_ROOT}/*.swift").splitlines():
        if not f:
            continue
        try:
            with open(os.path.join(REPO, f), encoding="utf-8") as fh:
                text = fh.read()
        except OSError:
            continue

        # Multiline literals come out FIRST, before any comment stripping.
        # A line-oriented sweep sees only the `"""` delimiters, and the
        # single-line literal pattern below excludes \n by construction, so a
        # Swift multiline string was invisible either way. There is exactly
        # one in the app: MatchResult.disclaimerText, drawn in the PDF's
        # boxed cover callout. It is the legally load-bearing copy and the
        # string most likely to acquire a "see X for scoring detail" line, so
        # a check covering every report string EXCEPT that one fails open on
        # the string whose framing is guaranteed to reach a reader.
        #
        # Blanking each span (newlines preserved) also stops a `//` inside
        # disclaimer prose reading as a comment, and stops the closing
        # delimiter being re-matched as an empty single-line literal.
        literals = []

        def _lift(match):
            literals.append(match.group(0))
            return "\n" * match.group(0).count("\n")

        text = re.sub(r'"""(?:.|\n)*?"""', _lift, text)
        text = re.sub(r"/\*(?:.|\n)*?\*/", "", text)
        text = re.sub(r"(?m)//.*$", "", text)
        literals.extend(re.findall(r'"(?:\\.|[^"\\\n])*"', text))
        scanned_literals += len(literals)

        # Harvest from string literals ONLY. The previous sweep read whole
        # non-comment lines, so a TRAILING `// see ALGORITHM_EXPLAINER
        # section 2` pulled that document into the lock -- penalising exactly
        # the provenance form sec.4.0 asks people to use. Only a name a
        # reader can see cites anything.
        for lit in literals:
            for name in re.findall(r"([A-Z][A-Z0-9_]+\.md|[A-Z][A-Z0-9_]{3,})",
                                   lit):
                base = name[:-3] if name.endswith(".md") else name
                cited.add(base)

    # Anchor assertion: a harness that finds nothing must distinguish "no
    # citations" from "no subject". A rename of SOURCE_ROOT, or report copy
    # moving into .strings catalogues under localisation, empties the literal
    # set and this check would print clear on a codebase it never read.
    if not scanned_literals:
        # remedy: state
        warn("cited-doc",
             f"no Swift string literals found under {SOURCE_ROOT} -- "
             "this check read nothing",
             "the check assumes user-visible copy lives in source as "
             "literals; if the path moved or the strings went into "
             ".strings catalogues, point it at the strings before "
             "trusting a clear result")
        return

    for doc in sh("git", "ls-files", "ios/reference/*.md",
                  "docs/*.md").splitlines():
        if not doc:
            continue
        stem = os.path.splitext(os.path.basename(doc))[0]
        if stem not in cited:
            continue
        try:
            with open(os.path.join(REPO, doc), encoding="utf-8") as fh:
                body = fh.read()
        except OSError:
            continue
        # A document that RECORDS a correction quotes the wording it
        # removed -- Ledger's explainer notices do exactly that, in
        # blockquotes and italicised "Corrected <date>:" notes, and
        # deliberately, because the old framing is quoted in external
        # material. Flagging those would penalise the honest form of the
        # fix and push the next correction toward silent deletion, which
        # is strictly worse for a reader who arrives expecting the old
        # text. Only prose that still TEACHES the framing counts.
        live = []
        for raw in body.splitlines():
            stripped = raw.strip()
            if stripped.startswith(">"):
                continue
            if re.match(r"[-*]?\s*\*+\s*Corrected\b", stripped):
                continue
            if re.match(r"[-*]?\s*\*+.*\bpreviously (read|mapped)\b",
                        stripped):
                continue
            # Live prose may also NAME the removed wording in quotes while
            # saying it is gone -- "the earlier 'pursue legal action' cell
            # asserted otherwise and is removed". That sentence is the
            # correction, not the claim. Recognised by a retrospective
            # marker on the same line as the quoted phrase.
            if re.search(r"\b(previously|earlier|removed|no longer|"
                         r"abandoned|Corrected)\b", stripped) and '"' in raw:
                continue
            live.append(raw)
        live_body = "\n".join(live)

        hits = [why for pat, why in banned
                if re.search(pat, live_body)]
        if hits:
            # remedy: external
            warn("cited-doc",
                 f"{doc} is cited in a user-visible string and contains "
                 + "; ".join(hits),
                 "the citation makes this document report copy -- send "
                 "Ledger the sections; a report that points at the "
                 "abandoned framing asserts it just as surely as printing it")


def check_doc_drift():
    """Code that has drifted away from CORRECT documentation (sec.5c).

    Every other check here assumes documentation goes stale behind code. Two
    of task #10's three scoring divergences were the reverse: the explainer
    was right and the Swift had drifted from it. scripts/check_doc_drift.py
    owns the comparison; this wrapper runs it so the failure appears in the
    same report as everything else rather than in a script nobody remembers
    to invoke.

    Wired only now because it anchors on `heightRuleOutInches`, which reached
    main in dc069a1. Landed earlier it would have reported an anchor failure
    on every run -- the anchor assertion working correctly, and noise that
    trains people to ignore the output.

    Severity mirrors the sub-check: doc-drift and doc-anchor are blocking
    (the numbers disagree, or the check lost its subject and cannot claim
    anything), doc-format is blocking too, because a comparison that was NOT
    performed must not read as a pass. The sub-script prints its own
    three-class diagnosis; this only reports that it ran and how it ended,
    per sec.5b -- naming a next action, never estimating significance.
    """
    script = os.path.join(REPO, "scripts", "check_doc_drift.py")
    if not os.path.exists(script):
        # remedy: state
        warn("doc-drift",
             "scripts/check_doc_drift.py not found -- the explainer/code "
             "number comparison did not run",
             "restore the script or drop this call; a clear preflight "
             "currently says nothing about scoring-doc agreement")
        return
    proc = subprocess.run([sys.executable, script, REPO],
                          cwd=REPO, capture_output=True, text=True)
    if proc.returncode != 0:
        detail = (proc.stdout + proc.stderr).strip().splitlines()
        head = detail[0] if detail else "check_doc_drift.py failed"
        # The sub-script prefixes its own `FAIL [doc-format]` / `[doc-anchor]`
        # / `[doc-drift]` tag. Keep the sub-class -- it is the whole point of
        # reporting them apart -- but strip the duplicated FAIL so the line
        # does not read `FAIL [doc-drift] FAIL [doc-format] ...`, which
        # misattributes a format failure to the drift class in the summary
        # line most readers stop at.
        m = re.match(r"FAIL\s+\[(doc-\w+)\]\s+(.*)", head)
        subclass, head = (m.group(1), m.group(2)) if m else ("doc-drift", head)
        # remedy: external
        fail(subclass,
             head,
             "run `python3 scripts/check_doc_drift.py` for the full "
             "three-class diagnosis: doc-format means the comparison did "
             "not run, doc-anchor means it lost its subject in the Swift, "
             "doc-drift means the numbers genuinely disagree")


def check_remedy_declarations():
    """Run scripts/check_remedies.py, so the harness is a gate and not a file.

    It was submitted standalone -- and a gate nobody invokes is the dead-check
    shape this whole section exists for. `preflight --all` reported CLEAR on a
    tree where check_remedies.py exited 1, which is the wrong all-clear with
    the tooling itself as the subject.

    # remedy: fixes
    Advisory, not blocking, per sec.5b's test: what else would catch it, and
    at what cost? A missing declaration misleads a future reader of the
    script; it does not break a build or corrupt a case file, and blocking
    here would refuse every commit between adding a check and annotating it --
    which is how a check teaches people to reach for --no-verify.

    It reports its subprocess's own output rather than paraphrasing it, and an
    ABSENT script is reported as unchecked rather than passed, because a
    silently missing gate reads exactly like a clean one.
    """
    script = os.path.join(REPO, "scripts", "check_remedies.py")
    if not os.path.exists(script):
        # remedy: state
        warn("remedy-decl",
             "scripts/check_remedies.py not found -- the remedy declarations "
             "were NOT checked",
             "restore the script from git history, or drop this call; a clear "
             "preflight currently says nothing about whether preflight's own "
             "remedies declare what following them achieves")
        return
    proc = subprocess.run([sys.executable, script], cwd=REPO,
                          capture_output=True, text=True)
    if proc.returncode != 0:
        detail = (proc.stdout or proc.stderr or "").strip().split("\n")
        head = detail[0] if detail else "no output"
        more = f" (+{len(detail) - 1} more line(s))" if len(detail) > 1 else ""

        # The harness reports THREE findings and they need three remedies.
        # Reporting one, keyed to the most common, is how a remedy stops
        # matching its trigger: an orphaned check told the reader to "add the
        # missing declaration(s)" when the declarations were all present and
        # the CALL was missing, and a crashed harness told them the same. That
        # is the annotation-versus-string shape one layer out -- the message
        # was accurate and the remedy beside it was not performable.
        #
        # Parse the sub-class out of the sub-process's own words rather than
        # re-wrapping them: flattening failure classes across a process
        # boundary is the defect the doc-drift wiring already made once.
        if "never calls it" in "\n".join(detail):
            # remedy: fixes
            # Not `state`: adding the call to main() clears this, measured by
            # deleting check_manifest_line_counts()'s call (rc=1, orphan
            # reported) and restoring it (rc=0).
            warn("remedy-decl",
                 f"a declared check is never called from main(): {head}{more}",
                 "add the check's call to main() -- its remedies are declared "
                 "and unreachable, so its declarations were audited and its "
                 "findings can never fire. Run python3 "
                 "scripts/check_remedies.py for the full list; this is NOT a "
                 "missing declaration, so adding a `# remedy:` comment will "
                 "not clear it")
        elif "no `# remedy:" in "\n".join(detail) or "declaration" in head:
            # remedy: fixes
            warn("remedy-decl",
                 f"a remedy site does not declare its kind: {head}{more}",
                 "run python3 scripts/check_remedies.py for the full list and "
                 "add the missing `# remedy: <fixes|reminder|external|state>` "
                 "declaration(s); it names the line and the function. Check "
                 "the remedy STRING says the same thing as the kind you "
                 "declare -- the harness reads the annotation, the reader "
                 "acts on the string")
        else:
            # remedy: state
            # The harness itself failed. A tool failure reported as a source
            # defect sends the reader to edit correct code, so this says what
            # did NOT get checked instead of naming a fix.
            warn("remedy-decl",
                 f"scripts/check_remedies.py exited {proc.returncode} without "
                 f"a recognised finding, so NO remedy site's kind and no "
                 f"check's reachability were verified: {head}{more}",
                 "run python3 scripts/check_remedies.py directly and read its "
                 "output -- this reports that the check could not complete, "
                 "not that preflight.py is wrong")


def check_manifest_line_counts():
    """The manifest's per-file line counts must match the tree.

    check_manifest_drift compares tracked PATHS and the file/Swift COUNTS.
    It never reads the line numbers, and the manifest states one per file
    plus a Swift total. On 4122028 that total was 17338 against a tree of
    19837 -- 2,499 lines that do not exist, wrong across 25 rows -- while
    --all reported zero advisories all afternoon.

    Same shape as everything else today: the check examined part of a
    document and its clean line was read as covering the whole of it. A
    generated file is only as trustworthy as the widest assertion anyone
    validates, so the counts are now validated rather than described.

    Advisory, not blocking. A stale count misleads a reader; it does not
    break a build, and blocking here would refuse every commit between
    editing a file and regenerating the manifest -- which is how a check
    trains people to pass --no-verify.
    """
    man = os.path.join(REPO, "ios/reference/COMPLETE_FILE_MANIFEST.md")
    if not os.path.exists(man):
        return
    with open(man, encoding="utf-8") as fh:
        text = fh.read()
    rows = re.findall(r"^\|\s*`([^`]+)`\s*\|\s*(\d+)\s*\|", text, re.M)

    # The Totals: header check that was here is now in
    # check_manifest_drift, beside the file and Swift counts it belongs with
    # -- Prism's version, which also refuses to assert a total measured over
    # a Swift file it could not read and defers to the path-drift finding
    # instead of reporting a partial sum. Two checks for one assertion is the
    # duplicate-work waste; his is the better of the two.
    if not rows:
        # remedy: state
        warn("manifest-lines",
             "no `path | lines` rows parsed from COMPLETE_FILE_MANIFEST.md "
             "-- the per-file line counts were NOT checked",
             "the manifest's table format changed; re-point this check or "
             "regenerate the document. This says nothing about the tree.")
        return
    wrong = []
    for rel, claimed in rows:
        path = os.path.join(REPO, rel)
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                actual = sum(1 for _ in fh)
        except OSError:
            continue          # path drift is check_manifest_drift's job
        if actual != int(claimed):
            wrong.append(f"{rel} says {claimed}, has {actual}")
    if wrong:
        shown = "; ".join(wrong[:3])
        more = f" (+{len(wrong) - 3} more)" if len(wrong) > 3 else ""
        # remedy: fixes
        warn("manifest-lines",
             f"{len(wrong)} manifest line count(s) disagree with the tree: "
             f"{shown}{more}",
             "run python3 scripts/regen_manifest.py -- this is the one "
             "manifest warning it clears completely. Never hand-edit a row, "
             "and never resolve a manifest conflict by picking a side: each "
             "side is right about its own patch's file and stale about the "
             "other's, and both are plausible integers")


def check_conflict_markers():
    """No tracked text file may contain a source-control conflict marker.

    Blocking, and tree-wide rather than staged-diff, because the failure this
    exists for is a MERGE commit: `f7921d8` (merge of #7 and #11) committed
    two unresolved hunks into Models/Case.swift and they reached `main`,
    survived four further commits, and were still there at `644c8fe`. Every
    check that could have caught it was aimed somewhere else --
    delimiter_balance runs only over Swift files it was handed and a conflict
    whose two sides are both balanced passes it, decoder_completeness and
    commit_size are staged-diff only and a merge resolution has nothing
    staged, and doc-drift and the manifest were clean because the defect was
    inside a file both already knew about. So the tree was reported clear with
    a file in it that does not parse.

    That is the sec.1 failure shape, not a missed lint: the tool printed the
    right output format for a tree it had not actually examined. Found by
    parsing all 42 tracked Swift files with swift-frontend -parse rather than
    by reading a report -- which is sec.5b's own rule, assert on behaviour and
    not on a representation of it.

    Both sides of that conflict were purely additive (two new enum cases and
    two new switch arms against one of each), which is why nobody saw it: the
    resolution was "keep both" and the merge would have been clean if anyone
    had opened the file. A conflict is only a choice when both sides make the
    same claim, and an unresolved marker is the case where no choice was made
    at all.

    Matched anchored at column 0 with the marker's required trailing space or
    line end, so a marker discussed in prose (or in this docstring) does not
    trip it. Skips nothing by extension: the merge that caused this touched
    Swift, but a marker in a .md, .json or .pbxproj is equally a broken file,
    and pbxproj especially would fail in Xcode rather than here.
    """
    lead, mid, tail = "<" * 7, "=" * 7, ">" * 7
    pats = (re.compile(r"(?m)^" + lead + r"(?:[ \t]|$)"),
            re.compile(r"(?m)^" + mid + r"$"),
            re.compile(r"(?m)^" + tail + r"(?:[ \t]|$)"))
    for f in sh("git", "ls-files").splitlines():
        if not f:
            continue
        p = os.path.join(REPO, f)
        if not os.path.exists(p):
            continue
        try:
            src = open(p, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue          # binary or unreadable: not our subject
        hits = sorted({m.start() for pat in pats for m in pat.finditer(src)})
        if not hits:
            continue
        lines = [src.count("\n", 0, h) + 1 for h in hits]
        # remedy: external
        fail("conflict-markers",
             f"{f}: {len(lines)} unresolved conflict marker(s) at line(s) "
             + ", ".join(str(n) for n in lines),
             "open the file and finish the merge -- check whether the two "
             "sides are additive (keep both) or actually contradict; then "
             "re-run, because a file with a marker in it does not compile "
             "and every other clean line in this report was measured on it")


# Searched in order. The /tmp entries are last and deliberately flagged as
# ephemeral: /tmp does not survive a sandbox rebuild, so a toolchain unpacked
# there gives a check that works today and silently reverts to the advisory
# later -- and a reader who saw it working yesterday will not reread the
# report. Found by Compass, who hit exactly that and moved to ~/toolchains.
# The advisory is honest about not parsing; it cannot be honest about a
# location the user thought was permanent, so the check says so up front.
SWIFT_PARSER_PATHS = (
    ("$SWIFT_FRONTEND", None, False),
    ("swift-frontend", "which", False),
    ("swiftc", "which", False),
    ("~/toolchains/swift/usr/bin/swift-frontend", "home", False),
    # glob: the swift.org tarball extracts to a VERSION-PINNED directory
    # (~/toolchains/swift-5.10.1), which is also how you keep more than one.
    # Two of us installed that way and the table above missed both -- an
    # honest advisory, but a false negative on capability. Compass found it.
    ("~/toolchains/swift*/usr/bin/swift-frontend", "glob", False),
    ("/usr/local/swift/usr/bin/swift-frontend", None, False),
    ("/usr/local/swift*/usr/bin/swift-frontend", "glob", False),
    ("/tmp/swift/usr/bin/swift-frontend", None, True),
)


def _swift_parser():
    """Locate a Swift frontend able to PARSE (not compile) a source file.

    No iOS SDK is needed -- parsing is syntax only, which is the whole
    question this check asks and the reason it runs without Xcode. A
    swift.org Linux tarball (~600 MB) is sufficient; two environments on this
    team installed one within the hour after "we need Xcode" turned out to be
    the wrong shape of the problem.

    Returns (path, version, ephemeral, broken). `ephemeral` marks a location
    that does not survive a sandbox rebuild, so the caller can warn while
    still running the check -- see SWIFT_PARSER_PATHS. `broken` lists
    candidates that EXIST but cannot run, which is a different report from
    finding nothing.
    """
    broken = []
    for spec, kind, ephemeral in SWIFT_PARSER_PATHS:
        if spec == "$SWIFT_FRONTEND":
            path = os.environ.get("SWIFT_FRONTEND") or None
        elif kind == "which":
            path = shutil.which(spec)
        elif kind == "home":
            path = os.path.expanduser(spec)
        elif kind == "glob":
            # Newest version first, so a pinned install is deterministic
            # rather than whichever the filesystem lists first.
            hits = sorted(glob.glob(os.path.expanduser(spec)), reverse=True)
            path = hits[0] if hits else None
        else:
            path = spec
        if not path or not os.path.exists(path):
            continue
        # EXISTS is not RUNS. `swiftc` on Ubuntu 24.04 wants
        # libncurses.so.6 and the distro ships only the wide variant, so the
        # binary is present and cannot load. Probed by executing it, because
        # an existence test cannot tell a missing tool from an unloadable
        # one -- the Tech Lead lost twenty minutes to a report that said "no
        # compiler found" when the compiler was right there.
        #
        # This mattered more than a confusing message. Before this probe an
        # unloadable frontend made every file "fail to parse", so a broken
        # toolchain was reported as 42 blocking source defects -- the tool
        # blaming the code for its own inability to run, which is the worst
        # available direction for a check meant to protect Sean's build.
        ok, why = _parser_runs(path)
        if ok:
            return path, _swift_version(path), ephemeral, None
        broken.append((path, why))
    return None, None, False, broken or None


def _parser_runs(path):
    """Can this binary actually execute? Returns (ok, reason_if_not).

    A loader failure prints to stderr and exits non-zero without ever
    reading a source file, so it is distinguishable from a parse error --
    but only if something looks.
    """
    try:
        proc = subprocess.run([path, "--version"], capture_output=True,
                              text=True, timeout=30)
    except OSError as exc:
        return False, str(exc)
    except subprocess.TimeoutExpired:
        return False, "timed out running --version"
    text = (proc.stdout + proc.stderr).strip()
    if "[Ss]wift version" and re.search(r"[Ss]wift version", text):
        return True, None
    first = text.splitlines()[0] if text else f"exited {proc.returncode}"
    if proc.returncode == 0:
        # Ran, but did not identify itself as Swift. Do not use it: naming
        # the parser is only worth anything if the name is real.
        return False, f"did not report a Swift version ({first})"
    return False, first


def _swift_version(path):
    """The frontend's own version string, for the report.

    Named rather than assumed, per Compass: "42 files parse" is a claim whose
    instrument cannot be audited. He had tree_sitter_swift sweeping all 42
    files and it flagged StorageService.swift on an empty tuple `()` that the
    real frontend accepts -- 41 of 42 correct, which is what a working tool
    looks like, and it had detected the historical marker breakage too, so it
    looked authoritative in the direction being tested. A grammar
    approximation standing in for a compiler is this repo's own
    unvalidated-instrument failure, so the report names which binary answered.
    """
    out = subprocess.run([path, "--version"], capture_output=True, text=True)
    for line in (out.stdout + out.stderr).splitlines():
        m = re.search(r"[Ss]wift version (\S+)", line)
        if m:
            return m.group(1)
    return "unknown version"


def check_swift_parses():
    """Does every tracked Swift file actually parse?

    This is the check that would have caught the worst defect of 2026-09-06,
    and it is the only one here that asks whether the tree is VALID rather
    than whether it is consistent. f7921d8 merged two unresolved conflict
    hunks into Models/Case.swift; they reached main and survived five
    commits. Through all of it `--all` printed "clear -- whole tree", three
    of us reported that clean line, and a structural audit confirmed 42 files
    registered in the Sources phase with no duplicate types -- all true, and
    all measured on a tree that did not parse. The proxy is not the parse.

    Every other check here is a proxy, and each was correct about what it
    measured: delimiter_balance passes a conflict whose two sides are each
    brace-balanced; pbxproj registration asks about membership; manifest and
    doc-drift ask whether documents match the tree. Proxies are cheap and
    they are worth having. What they cannot do is answer the compiler's
    question, and adjacency is what made them feel sufficient.

    Blocking when a parser is available: a file that does not parse cannot
    compile, so unlike a stale line count this is not a matter of degree.
    There is no window in which it is legitimately broken, which is the
    standing advisory-vs-blocking test -- a check that refuses only genuinely
    invalid trees trains no bypass habit.

    ADVISORY, and explicitly named, when no toolchain is present. This
    matters more than the check: only one of the four agent environments
    working on this repo has a Swift toolchain, so "42 files parse" is a
    claim most of us cannot make. A silent skip would turn that into a clean
    line asserting the one property nothing verified -- today's defect
    exactly, rebuilt inside the check written to prevent it. So an absent
    parser is reported, with what to install.

    Parse-only via `-frontend -parse`: no SDK, no linking, no build. It does
    NOT mean the tree compiles -- type checking, imports and the iOS SDK are
    still Xcode's job, per sec.4 clauses 4-6. It means the tree is syntax.
    """
    swift = [f for f in sh("git", "ls-files").splitlines()
             if f.endswith(".swift")]
    if not swift:
        return
    parser, version, ephemeral, broken = _swift_parser()
    if parser is None:
        if broken:
            shown = "; ".join(f"{b} ({why})" for b, why in broken[:2])
            # remedy: external
            warn("swift-parse",
                 f"a Swift frontend EXISTS but cannot run, so {len(swift)} "
                 f"tracked Swift file(s) were NOT parsed: {shown}",
                 "this is a broken toolchain, not broken source: a loader "
                 "error means the binary never read a file. On Ubuntu 24.04 "
                 "swiftc wants libncurses.so.6 and the distro ships only the "
                 "wide variant -- symlink libncursesw.so.6. Fix the install, "
                 "not the code")
            return
        looked = ", ".join(spec for spec, _, _ in SWIFT_PARSER_PATHS)
        # remedy: external
        warn("swift-parse",
             f"no Swift frontend found -- {len(swift)} tracked Swift file(s) "
             "were NOT parsed, and no other check here asks whether they are "
             f"valid. Searched: {looked}",
             "install a Swift toolchain (swift.org, Linux tarball is enough "
             "-- parsing needs no iOS SDK) or set SWIFT_FRONTEND to one. If "
             "your interactive shell parses but `git commit` says this, the "
             "hook runs with a BARE environment: a profile export does not "
             "reach it, so put the toolchain on one of the paths above (a "
             "~/toolchains/swift symlink is enough)")
        return

    if ephemeral:
        # remedy: external
        warn("swift-parse",
             f"the Swift frontend in use ({parser}) is under a path that "
             "does not survive a sandbox rebuild -- the parse ran, but it "
             "will revert to 'NOT parsed' later without anything changing "
             "in the repo",
             "move the toolchain somewhere durable (~/toolchains/swift) and "
             "export SWIFT_FRONTEND from your shell profile; a check that "
             "worked yesterday is one nobody rereads")

    args = ([parser, "-frontend", "-parse"] if parser.endswith("swift-frontend")
            else [parser, "-parse", "-"])
    bad = []
    for f in swift:
        proc = subprocess.run(args[:-1] + [f] if args[-1] == "-"
                              else args + [f],
                              cwd=REPO, capture_output=True, text=True)
        if proc.returncode != 0:
            first = ""
            for line in (proc.stderr or proc.stdout).splitlines():
                if ": error:" in line:
                    first = line.split(": error:", 1)[1].strip()
                    break
            bad.append((f, first or "did not parse"))
    if bad:
        shown = "; ".join(f"{f}: {why}" for f, why in bad[:3])
        more = f" (+{len(bad) - 3} more)" if len(bad) > 3 else ""
        # remedy: external
        fail("swift-parse",
             f"{len(bad)} of {len(swift)} tracked Swift file(s) do not "
             f"parse (swift {version}): {shown}{more}",
             "open the named file at the reported location -- a file that "
             "does not parse cannot compile, so every other clean line in "
             "this report was measured on a tree that is not valid Swift")


# Shas a document cites ON PURPOSE despite not resolving. Both are correct
# prose, found by running check_cited_commits before trusting it -- its first
# pass flagged four and two were these. `abc1234` is the sec.2 entry
# template's placeholder. `1a4ae2a` is cited in sec.5b BECAUSE it was
# force-pushed away: the passage's whole subject is a measurement that was
# accurate about a commit that no longer exists. Blocking those would demand
# the document stop discussing its own central example -- wrong in the
# section about being wrong for the right reason.
#
# An allow-list rather than a comment marker, so adding one is a deliberate
# edit here with a reason attached, not a tag anyone can sprinkle to silence
# the check.
CITED_SHA_EXEMPT = {
    "abc1234": "sec.2 entry-template placeholder",
    "1a4ae2a": "sec.5b cites it precisely because it was force-pushed away",
}


def _sha_is_reachable(sha):
    """Is this sha a commit a READER can reach, not merely one we still hold?

    `git cat-file -t` was the first cut and it was wrong in the worst
    direction available to this check. It reads the LOCAL object store, and a
    long-lived clone keeps rebased-away objects alive for weeks -- so it
    cheerfully resolves a sha nobody else can see. The Tech Lead nearly
    failed to confirm the two dead README shas because all four resolved in
    his clone; he only saw the failure from a fresh one. The instrument used
    to audit the stale document was the one guaranteed to agree with it.

    That is this repo's own defect, in the check written to end its third
    instance: `exists` standing in for `runs`, one more time, with "exists in
    my object store" standing in for "exists for a reader".

    So the predicate is REACHABILITY from a ref, not existence. A commit
    reachable from any local branch, tag or remote-tracking ref is one a
    reader with the same remote can fetch; a loose object that nothing points
    at is not, however well it resolves here. Proven on `3c262e2`: `cat-file`
    calls it a commit in my clone, and it is an ancestor of nothing.

    Scoped to remote-tracking refs and tags, not local branches -- see the
    comment in the body. A local branch is my view of history, not a
    reader's, and that gap was not theoretical: it passed two dead shas in
    the Tech Lead's clone through leftover scratch branches.

    The remaining bound, stated rather than hidden per sec.5b: a
    remote-tracking ref can be stale, so `git fetch --prune` before trusting
    a clean line is required -- the same rule this section already states
    about asserting any remote fact.
    """
    if sh("git", "cat-file", "-t", sha).strip() != "commit":
        return False
    # --contains over all refs: cheaper and more direct than walking history
    # ourselves, and it answers exactly "does any ref lead here".
    # refs/remotes and refs/tags ONLY -- deliberately not refs/heads.
    #
    # The residual this docstring used to state as theoretical was already
    # firing. The Tech Lead had ~40 leftover scratch branches from today's
    # testing (`_t6`, `_t13b`, ...) that existed on no remote, and two shas
    # dead for every reader were REACHABLE in his clone through them. The
    # check passed them until he pruned. So "reachable from any ref" is the
    # same mistake one step out: a local branch is my view, not a reader's.
    #
    # A remote-tracking ref or a tag is a claim about what the REMOTE has, so
    # it is the closest thing a local command can get to the reader's
    # question. Requiring a prune is a remedy that depends on the reader
    # already suspecting the problem, which is the shape this repo spent the
    # day removing.
    #
    # Honest bound, still: a remote-tracking ref can itself be stale, so
    # `git fetch --prune` before trusting a clean line is the standing
    # requirement -- sec.5b's own rule about asserting a remote fact. What
    # this now cannot do is pass a sha kept alive only by a local branch,
    # which is what it was doing.
    # refs/tags is NOT in this set, and the reason is measured rather than
    # argued. `git tag` creates a purely LOCAL ref -- nothing about a tag says
    # whether it was ever pushed. Verified on this predicate as landed: an
    # empty commit off origin/main, its branch deleted, one `git tag` on it,
    # and a cited sha reachable from that tag alone passed `--all` clean at
    # zero advisories. So a tag is a claim about the remote only when it
    # happens to have been pushed, and no local command distinguishes the two
    # cases.
    #
    # That is the same substitution one notation further out: the local
    # namespace wearing the one form this check treats as published. It was
    # already firing twice today -- Vector's first verification run passed
    # because a leftover `_tt` from this check's own test suite still pointed
    # at 3c262e2, so the check had never fired; the Tech Lead reproduced the
    # tag case and recorded it as accepted by design. It should not be: the
    # accepted bound is "a remote-tracking ref can be stale", which a fetch
    # fixes, not "any local tag vouches for a sha", which nothing fixes.
    #
    # Cost of excluding tags: a sha reachable ONLY from a pushed tag and from
    # no branch now blocks. That is rare -- a release tag is normally an
    # ancestor of a branch, so refs/remotes already covers it -- and
    # CITED_SHA_EXEMPT takes the exception with a reason. Right trade: a false
    # block is visible and gets argued, a false pass is neither.
    refs = sh("git", "for-each-ref", "--format=%(refname)",
              "--contains", sha, "refs/remotes").strip()
    return bool(refs)


def check_cited_commits():
    """Every commit sha cited in a tracked document must resolve.

    Blocking. A sha is either a real commit or it is nothing, and there is no
    window in which citing a dead one is acceptable -- the standing
    advisory-vs-blocking test.

    This is the phantom-hash defect, produced three times in one day from
    three directions. The manifest header named the commit carrying it, which
    cannot exist when the file is written (removed in 13fc278).
    `AuditEntry.examinerName` would have resolved the examiner live,
    rewriting the chain of custody on every rename (avoided by copy-at-write).
    And ios/README.md's branch table cites `aa7b695` and `d9a8725` --
    pre-rebase heads that no longer exist, so the two rows a reader uses to
    audit tasks #6 and #13 point at nothing. That third one is what this
    found; nobody had looked.

    Compass's predicate: the tool asked "did I get a result" when it needed
    to ask "which of the things that could have happened, happened". A cited
    sha reads as provenance and resolves to whatever is true when read --
    Ledger's general form, an artefact that looks like a record and is
    actually a query.

    Prism's dropped commit is why this is a check and not a one-time edit: a
    changelog entry cited a fix that had never landed, and every check passed
    because each was true of the commit that DID land. A document recording a
    fix is not evidence the fix landed. This cannot verify a sha means what
    the prose claims and says so -- it establishes only that the reference is
    not dangling, which is the part a tool can establish.

    Reachability, not existence -- see _sha_is_reachable. A sha that resolves
    only in the local object store is a sha no reader can see.

    At least one digit is required so English words in hex letters ("added",
    "facade", "decade") cannot trip a blocking check; leading-digit would be
    wrong, since plenty of shas are all letters. Shas that are also tracked
    paths are skipped.
    """
    tracked = sh("git", "ls-files").splitlines()
    tracked_set = set(tracked)
    pat = re.compile(r"`([0-9a-f]{7,40})`")
    dangling = []
    for doc in [f for f in tracked if f.endswith(".md")]:
        try:
            text = open(os.path.join(REPO, doc), encoding="utf-8").read()
        except OSError:
            continue
        for sha in sorted(set(pat.findall(text))):
            if (sha in tracked_set or sha in CITED_SHA_EXEMPT
                    or not re.search(r"\d", sha)):
                continue
            if not _sha_is_reachable(sha):
                dangling.append((doc, sha))
    if dangling:
        shown = "; ".join(f"{d}: {h}" for d, h in dangling[:4])
        more = f" (+{len(dangling) - 4} more)" if len(dangling) > 4 else ""
        # remedy: external
        fail("cited-commits",
             f"{len(dangling)} cited commit sha(s) are not citable: {shown}"
             f"{more}",
             "no ref leads to the commit -- it was rebased away or never "
             "landed. Note the wording: the sha may still RESOLVE in your "
             "clone via `git cat-file -t` and be dead for every reader, "
             "which is how all of today's instances survived, so do not "
             "check it that way -- use `git for-each-ref --contains <sha>`. "
             "Replace it with the sha actually in history, or drop it: a "
             "dead sha reads as provenance and resolves to nothing, which "
             "is worse than citing none. If the citation is deliberate, "
             "add it to CITED_SHA_EXEMPT with the reason")


def check_manifest_drift():
    """Does COMPLETE_FILE_MANIFEST.md still describe the tracked tree?

    The docs_owed reminder above fires only when a Swift file is ADDED or
    REMOVED in the staged diff, so it cannot see drift that already landed --
    and drift that already landed is the only kind that reaches a reader. On
    d8187ba the manifest asserted 68 tracked files against a tree of 70, and
    omitted eight paths including scripts/preflight.py, this file. A generated
    document that lags its tree is a document asserting something false, and
    the manifest asserts its own totals in prose, which makes the falsehood
    checkable rather than a matter of opinion.

    Tree-wide and advisory. It reports the drift and never writes the file:
    the manifest is regenerated, never hand-edited, and the prose in it is
    Ledger's.
    """
    rel = "ios/reference/COMPLETE_FILE_MANIFEST.md"
    tracked_paths = sh("git", "ls-files").splitlines()
    try:
        with open(os.path.join(REPO, rel), encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        # Say so rather than returning. A missing manifest is a bigger
        # problem than a stale one, and a check that goes silent when its
        # subject is absent is the failure this repo hit three times in one
        # day -- here it would be self-inflicted, in the check written to
        # notice exactly this class of falsehood.
        if rel in tracked_paths:
            # remedy: state
            warn("manifest",
                 f"{rel} is tracked but could not be read -- manifest NOT "
                 "checked",
                 "restore the file, or remove it from the tree if it is "
                 "genuinely gone")
        else:
            # Sixth instance, and the starkest: there is no generator for
            # the whole document. regen_manifest.py exits when the file is
            # missing, so "regenerate it from git ls-files" names a
            # capability that has never existed anywhere in this repo.
            # remedy: state
            warn("manifest",
                 f"{rel} is absent -- manifest NOT checked",
                 "the file manifest is the map a reader starts from: restore "
                 "it from git history. No script regenerates the document -- "
                 "regen_manifest.py fills counts into rows that already "
                 "exist and exits when the file is gone")
        return

    tracked = [f for f in tracked_paths if f]
    if not tracked:
        return
    # "Swift sources" means APP sources -- the same population `tracked_swift`
    # parses and `check_pbxproj_registration` requires in the Xcode target.
    #
    # NOTE(Vector), 2026-09-07. This counted every tracked `.swift` file while
    # `tracked_swift()` counts only those under SOURCE_ROOT: TWO DEFINITIONS
    # OF "SWIFT FILE" IN ONE REPOSITORY, agreeing for months only because
    # every `.swift` file happened to be an app source -- the coincidence
    # doing the work of a definition.
    #
    # The shape checks were landed as `.shapecheck` so the figure would not
    # move, and that is right for those files (a verification instrument is
    # not app source). But the extension was the WORKAROUND, not the fix: a
    # real `.swift` file anywhere outside SOURCE_ROOT still moves this figure
    # and not the parsed/pbxproj one. Measured on a probe at
    # `ios/probe.swift`: tracked_swift 42, this check 43. So the two figures
    # all four of us quote as one signal can still silently become different
    # while both stay correct, which is the hazard the extension choice was
    # made to avoid.
    #
    # A number quoted as a signal must be computed from the same set every
    # time, or it is a different number wearing the same words.
    swift = [f for f in tracked
             if f.endswith(".swift") and f.startswith(SOURCE_ROOT + "/")]

    m = re.search(r"(\d+)\s*tracked files.*?(\d+)\s*Swift sources",
                  text, re.S)
    if not m:
        # The totals sentence is the half of this check that is verifiable
        # against the document's own claim. If a regeneration rewords it,
        # this signal disappears -- and a silently absent signal reads as a
        # pass. Report that the assertion could not be found instead.
        # remedy: fixes
        warn("manifest",
             f"{rel} states no machine-readable file/Swift totals -- that "
             "half of the manifest check could not run",
             "keep a totals sentence of the form "
             "'N tracked files, of which M Swift sources', or update this "
             "check's pattern alongside the wording")
    else:
        claimed_total, claimed_swift = int(m.group(1)), int(m.group(2))
        if claimed_total != len(tracked) or claimed_swift != len(swift):
            # remedy: fixes
            warn("manifest",
                 f"{rel} asserts {claimed_total} tracked files "
                 f"({claimed_swift} Swift); the tree has {len(tracked)} "
                 f"({len(swift)})",
                 f"edit the `Totals:` sentence by hand to say "
                 f"{len(tracked)} tracked files, of which {len(swift)} "
                 "Swift sources -- this line is PROSE and "
                 "scripts/regen_manifest.py deliberately does not touch it "
                 "(rows mechanical, header editorial). Running the "
                 "regenerator will NOT clear this")

        # Both numbers above live in the SAME prose sentence as the line
        # total below, so both take the hand-edit remedy. 521e341 fixed the
        # line total's remedy and left this one pointing at the regenerator
        # -- verified still unperformable on that commit: set the file count
        # to 99, the check fires, run regen_manifest.py as instructed, re-run
        # --all, identical failure. The fix was applied to the number that
        # was reported rather than to the sentence that was wrong, which is
        # how one half of a two-number claim keeps a defect the other half
        # just lost.
        # The LINE TOTAL in the same sentence, which nothing compared until
        # 309f25b was found to claim 19887 against a tree of 19890. Three
        # layers validate this document -- per-file rows
        # (check_manifest_line_counts), file and Swift counts (just above),
        # path presence (below) -- and none of them touched the header's own
        # number, so the manifest could be internally perfect and still open
        # with a false one.
        #
        # Ledger's general form, which is why this is a check rather than the
        # edit that corrected it: the summary line is the least-checked
        # assertion in a generated file, because validation gets written
        # against the rows. It is also the widest claim in the document and
        # the only one a reader cannot test by inspection, which makes it the
        # number people quote.
        #
        # Advisory, matching the rest of this check, and it reports the
        # absence of the parenthetical rather than going quiet -- a signal
        # that vanishes when the wording changes reads as a pass.
        lm = re.search(r"Swift sources\s*\((\d+)\s*lines\)", text)
        if lm is None:
            # remedy: fixes
            warn("manifest",
                 f"{rel} states no machine-readable Swift LINE total -- "
                 "that half of the totals sentence could not be checked",
                 "keep the parenthetical of the form "
                 "'M Swift sources (L lines)', or update this check's "
                 "pattern alongside the wording")
        else:
            claimed_lines = int(lm.group(1))
            actual_lines = 0
            for f in swift:
                try:
                    with open(os.path.join(REPO, f), "rb") as sfh:
                        actual_lines += sum(1 for _ in sfh)
                except OSError:
                    # A tracked path that will not open is check_manifest_
                    # drift's own subject below; do not assert a total
                    # measured over a file we could not read.
                    actual_lines = None
                    break
            if actual_lines is None:
                # remedy: state
                warn("manifest",
                     f"{rel}'s Swift line total NOT checked -- a tracked "
                     "Swift file could not be read",
                     "see the path-drift finding below; fix that first")
            elif claimed_lines != actual_lines:
                # The remedy MUST name the hand-edit. Ledger measured the
                # first version of this: injected a wrong total, the check
                # fired, he ran the regenerator it named, re-ran --all, and
                # got the IDENTICAL failure -- because regen_manifest.py
                # rewrites rows and leaves the prose header alone, by design
                # (see its docstring, and PROCESS sec.3's ownership row).
                #
                # A REMEDY THAT DOES NOT REMOVE THE CONDITION IS WORSE THAN
                # NONE: the reader follows it, sees the same failure, and
                # concludes the CHECK is broken rather than that the header
                # is wrong. Same routing failure as cited-commits sending
                # readers to `git cat-file` -- the one instrument guaranteed
                # to agree with the stale document. So this names the exact
                # edit and the exact number.
                # remedy: fixes
                warn("manifest",
                     f"{rel} asserts {claimed_lines} Swift lines; the tree "
                     f"has {actual_lines}",
                     f"edit the `Totals:` sentence by hand to say "
                     f"{actual_lines} -- this line is PROSE and "
                     "scripts/regen_manifest.py deliberately does not touch "
                     "it (rows mechanical, header editorial). Running the "
                     "regenerator will NOT clear this")

    listed = set(re.findall(r"`([^`]+)`", text))
    missing = [f for f in tracked if f not in listed]
    if missing:
        shown = ", ".join(missing[:4])
        more = f" (+{len(missing) - 4} more)" if len(missing) > 4 else ""
        # Fourth instance of the routing failure, found by sweeping every
        # remedy on this file rather than waiting for someone to hit it.
        # regen_manifest.py MAINTAINS existing rows and deliberately does not
        # ADD one -- a new path is check_manifest_drift's subject, and a
        # regenerator that invented rows would decide where in the table a
        # file belongs, which is editorial. So the named remedy could not
        # clear this either. Name the edit.
        # remedy: fixes
        warn("manifest",
             f"{len(missing)} tracked file(s) absent from {rel}: {shown}{more}",
             "add a `| `path` | N |` row for each, in the section it belongs "
             "to, then run scripts/regen_manifest.py to fill the counts -- "
             "the regenerator maintains rows and never ADDS one, so running "
             "it alone will NOT clear this")


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


def _blank_comments_and_strings(src):
    """Blank comments and string literals, preserving offsets and newlines.

    Extracted from codable_line_spans so brace matching in
    types_with_custom_decoder uses the same blanking. Both need it for the
    same reason: a brace inside a comment or a literal must not open or
    close a type body.
    """
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
    return "".join(out)


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

    clean = _blank_comments_and_strings(src)

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

    Scanned across the WHOLE file per type name, not only inside the type's
    own Codable spans. A decoder is frequently written in an extension --
    `extension ForensicCase { init(from:) ... }` -- and such an extension
    carries no `Codable` in its declaration, so it is not a Codable span at
    all. Looking only inside the spans finds nothing and the exemption
    silently fails to apply, which blocks correct code: exactly the false
    positive this exemption exists to prevent, relocated one level down.
    """
    try:
        with open(os.path.join(REPO, path), encoding="utf-8") as fh:
            src = fh.read()
    except OSError:
        return set()

    names = {name for _, _, name in spans}
    if not names:
        return set()

    out = set()
    # Attribute each decoder to the type whose BODY encloses it, brace
    # matched. The previous version bounded a declaration at the next
    # declaration keyword, which credits a decoder to whichever type happens
    # to be declared last before it -- and a NESTED type is declared after
    # its parent's fields but before the parent's own init(from:). So
    # `PaintAnalysis` (custom decoder, nine stored properties) handed its
    # decoder to the nested `enum SurfaceCondition`, which has none. Effects
    # were both directions at once: SurfaceCondition reported the "no stored
    # properties" no-subject advisory, and PaintAnalysis dropped out of the
    # exemption set entirely, so its real fields were never checked. A field
    # added to PaintAnalysis and omitted from its hand-written decoder --
    # exactly this check's hazard -- was silent.
    #
    # Comments and string literals are already blanked in `stripped` for
    # brace counting, so a brace inside either cannot close a body early.
    stripped = _blank_comments_and_strings(src)
    for m in re.finditer(r"\b(struct|class|enum|actor|extension)\s+(\w+)",
                         stripped):
        name = m.group(2)
        if name not in names or name in out:
            continue
        brace = stripped.find("{", m.end())
        if brace < 0:
            continue
        depth, i, n = 0, brace, len(stripped)
        while i < n:
            if stripped[i] == "{":
                depth += 1
            elif stripped[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        body = stripped[brace:i]
        # Only decoders at this type's OWN nesting level count; one inside a
        # nested type's braces belongs to that nested type, not to this one.
        own = re.sub(r"\{[^{}]*\}", lambda _m: " " * len(_m.group(0)), body)
        while re.search(r"\{[^{}]*\}", own):
            own = re.sub(r"\{[^{}]*\}", lambda _m: " " * len(_m.group(0)), own)
        if re.search(r"\binit\s*\(\s*from\s+\w+\s*:\s*Decoder\s*\)",
                     body):
            # `body` finds it anywhere inside; require that the signature is
            # not itself sunk inside a nested type body.
            for sig in re.finditer(
                    r"\binit\s*\(\s*from\s+\w+\s*:\s*Decoder\s*\)",
                    body):
                prefix = body[:sig.start()]
                if prefix.count("{") - prefix.count("}") == 1:
                    out.add(name)
                    break
    return out


def check_decoder_completeness(files):
    """A hand-written init(from:) that never reads a stored property.

    Blocking under PROCESS.md sec.5b kind 2, and it is the mirror image of
    check_persisted_model. That check asks whether an OLD payload can still
    be read by NEW code. This one asks whether NEW code still reads
    everything the payload CARRIES.

    Swift's synthesized decoder reads every stored property, so this hazard
    cannot exist until someone writes their own -- and writing one is the
    remedy check_persisted_model recommends, so the two arrive together.
    From that moment the decoder is a hand-maintained list, and a field
    added to the type by anyone else is silently not decoded. The property
    keeps its declared default, the build stays green, `encode(to:)` stays
    synthesized so the value is still WRITTEN to disk, and the loss appears
    only as that field reverting to its default on every load.

    The concrete case this was written for: `ToolMarkComparison` gained a
    hand-written `init(from:)` on one branch (for `exclusions`) while
    gaining `permutationPValue` and `nullTrialCount` on another. A union
    resolution that compiles perfectly drops both on decode, and
    `isStatisticallySignificant` then returns nil -- which renders as "no
    significance test was possible", the honest-absence state the team
    deliberately built. A silent data loss wearing the exact appearance of
    correct behaviour.

    Scoped to types that have BOTH a Codable span and a hand-written
    decoder, since a synthesized decoder needs no list to fall out of date.
    """
    for f in files:
        if not f.endswith(".swift"):
            continue
        spans = codable_line_spans(f)
        if not spans:
            continue
        by_hand = types_with_custom_decoder(f, spans)
        if not by_hand:
            continue
        try:
            with open(os.path.join(REPO, f), encoding="utf-8") as fh:
                lines = fh.read().split("\n")
        except OSError:
            continue

        # One type yields SEVERAL spans: codable_line_spans records depth-1
        # stretches so that locals inside function and getter bodies are not
        # read as stored fields. Group them back per type and check the union
        # once -- iterating spans directly reports the same type repeatedly
        # and, worse, judges each fragment on its own, so a fragment holding
        # no declarations looks like a type with no stored properties.
        by_name = {}
        for lo, hi, name in spans:
            by_name.setdefault(name, []).append((lo, hi))

        whole = "\n".join(lines)
        for name, ranges in by_name.items():
            if name not in by_hand:
                continue
            body = []
            for lo, hi in ranges:
                body.extend(lines[lo - 1:hi])
            fields = []
            for raw in body:
                decl = raw.strip()
                if not re.match(r"(?:var|let)\s", decl):
                    continue
                parsed = _parse_field(decl)
                if parsed:
                    fields.append(parsed[0])
            if not fields:
                # No stored properties found. Rather than report clean --
                # which is indistinguishable from a check that ran and
                # found nothing wrong -- say the subject was absent.
                #
                # The remedy states what is unknown and what to do, and
                # deliberately does NOT estimate how likely it is to be
                # nothing. The previous wording said "probably a parsing gap
                # rather than a real finding", and that sentence was covering
                # a blocking-severity hole for as long as it stood: the
                # nested-type misattribution fixed at 515e731 produced this
                # exact advisory for `SurfaceCondition` while `PaintAnalysis`
                # -- nine stored properties, hand-written decoder -- silently
                # left the checked set. Both readers who saw it shrugged,
                # because the text told them to.
                #
                # Reporting the gap is this check's competence; guessing its
                # significance is not, and the one message whose whole job is
                # "I do not know what I looked at" is the worst possible
                # place to append a confidence estimate. Rule per Vector,
                # after his own remedy text hid his own defect; PROCESS.md
                # sec.5b now forbids the string. Prism's extension is why it
                # is a rule and not a style note: a check that cannot
                # identify its subject has, by construction, no information
                # about what it missed, so any likelihood it offers is
                # manufactured by the apparatus and inherits the check's
                # authority anyway.
                #
                # Remedy copy is Ledger's locked replacement, taken verbatim
                # -- ios/reference/ and the locked strings are his.
                # remedy: external
                warn("decoder-completeness",
                     f"{f}: `{name}` has a hand-written init(from:) but no "
                     "stored properties were found -- this decoder was NOT "
                     "checked",
                     "a check with no subject cannot fail -- this reports "
                     "the gap, not a finding. Either this type genuinely "
                     "has no stored properties, or the parser missed them "
                     "and a field could be dropped on load with no "
                     "warning. Confirm which before trusting a clear run.")
                continue

            # The decoder may live in an extension outside the span, so
            # search the whole file for assignments to each field.
            missing = [fld for fld in fields
                       if not re.search(
                           r"(?:self\.)?" + re.escape(fld) +
                           r"\s*=\s*try\s+\w+\.decode", whole)]
            if missing:
                # remedy: external
                fail("decoder-completeness",
                     f"{f}: `{name}` has a hand-written init(from:) that "
                     "never decodes " +
                     ", ".join(f"`{m}`" for m in missing),
                     "a hand-written decoder is a hand-maintained list of "
                     "every stored property. An undecoded field silently "
                     "reverts to its default on load while encode(to:) "
                     "keeps writing it -- green build, lost case data. Add "
                     "a decodeIfPresent for each, or delete the custom "
                     "decoder if the synthesized one now suffices.")


def check_persisted_model(files):
    """Persisted-model changes that survive a green build and lose case data.

    Blocking under PROCESS.md sec.5b kind 2: the compiler cannot catch either
    of these, and the cost lands on the user rather than the developer.

    KNOWN LIMIT, and it is the same one that made check_decoder_completeness
    unreachable (see the comment at the call site): both hazards below are
    TRANSITIONS -- an old payload that exists versus a new declaration -- so
    unlike a decoder's completeness they cannot be read off the tree at all.
    A `let x: String?` that has always been `String?` is correct; the defect
    is only visible as a -/+ pair. That means this check needs a diff, and a
    MERGE RESOLUTION STAGES NOTHING: `--all` on a merged tree reports clear
    for a type change that will throw typeMismatch on every saved case.

    Moving it tree-wide is therefore not the fix -- there is nothing tree-wide
    to test. The remedy is a diff base, not a scope change, which is the test
    for whether a check belongs in the commit-shaped group: ask whether its
    subject could be true of a tree with no history. Decoder completeness
    could; this cannot.

    CLOSED as of the MERGE_HEAD base derivation below: when a merge is in
    progress the base is derived automatically and announced on stdout, so
    this no longer depends on anyone remembering `--since`. That matters
    because a merge is exactly when nobody remembers, and it is also the
    commit shape that produced this repo's two worst defects.

    Verified on a real merge rather than a fixture: `examinerName` String? ->
    Int? on a side branch, an unrelated commit on the base, `git merge
    --no-commit` -> 1 blocking, commit refused. `--all` on the merged tree is
    still silent, which is correct and is why the derivation exists.

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
                    # remedy: external
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
                # remedy: external
                warn("persisted-model",
                     f"{f}: new non-optional field `{name}: {type_str}` on "
                     f"`{owner}`, which has a hand-written init(from:)",
                     "not blocking -- an explicit decoder is the recommended "
                     "remedy. Confirm it reads this key with decodeIfPresent "
                     "and a default, since a custom decoder can still decode "
                     "a new key non-optionally.")
                continue

            # remedy: external
            fail("persisted-model",
                 f"{f}: new non-optional field `{name}: {type_str}` on a "
                 "persisted model",
                 f"make it `{type_str}?` (or decodeIfPresent with an explicit "
                 "init(from:)). Every case file already on a device predates "
                 "this field and will fail to decode -- the build stays green "
                 "while real case data becomes unopenable.")


def check_script_currency():
    """Refuse to run when this script is older than origin/main's copy.

    Blocking, and it runs BEFORE any check, because a stale script is not a
    degraded run -- it is a clean line printed by the wrong tool.

    The hook `--install-hook` USED to write a path-relative line:

        #!/bin/sh
        exec python3 scripts/preflight.py

    which executed whatever `scripts/preflight.py` happened to be in the
    working tree. Install it once on main, check out a feature branch to
    build, and every commit from then on ran that BRANCH's copy. That hook
    was replaced at e60604c and now resolves the script from origin/main,
    refusing rather than falling back -- so this guard is the second of two
    mechanisms, not the only one. Both are needed: the hook covers the
    commit path, this covers every direct invocation. Found by
    Compass on cross-section-exclude @ c6e749a, whose script is 228 lines
    shorter than main's and predates decoder-completeness, cited-doc and the
    argv guard -- so the branch that FIXES a decoder hazard shipped beside a
    script that cannot detect it. Reproduced: an undecoded field in
    PaintAnalysis gives `clear, exit 0` on the branch script and `1 blocking`
    naming the field on main's, on the identical tree.

    That is worse than the failure shapes PROCESS.md sec.1 already names. A
    tool reporting nothing to do at least reports something odd; this is the
    RIGHT tool's output format carrying the WRONG tool's coverage, and it is
    indistinguishable from a pass.

    Pinning the hook to main's copy was the alternative. This is the version
    chosen because it cannot be defeated by checking out a branch: the guard
    travels IN the script, so any copy old enough to lack a check is also old
    enough to be refused by the copy that has it. A pinned hook only protects
    people who reinstall it.

    Deliberately advisory-free: there is no "probably fine" path. Either the
    script is current or its clean line means nothing -- and per sec.5b this
    report names a next action rather than estimating its own significance.

    Fails OPEN, and only for a missing remote: with no origin/main fetched
    (a fresh clone, an offline machine) there is nothing to compare against,
    so it says so and proceeds rather than blocking work it cannot judge.
    """
    # __file__, NOT a fixed repo path. The first cut of this guard read
    # REPO/scripts/preflight.py -- the file at the path rather than the
    # script actually executing -- so running a stale copy from anywhere
    # else compared main against main and printed clear. That is this
    # repo's own sec.5b rule ("assert on behaviour, not on a
    # representation of it") violated by the guard written to enforce
    # it: a fixed path is a representation of "the script running", and
    # for a hook that execs by path they only coincide by luck. Caught
    # by grafting the guard onto the stale branch copy and watching it
    # clear itself.
    here = os.path.abspath(__file__)

    # The refspec is a PRECONDITION of this guard, so it is checked here
    # rather than left to a setup note. Everything below compares against the
    # LOCAL origin/main ref, and a main-only refspec --
    #
    #     remote.origin.fetch = +refs/heads/main:refs/remotes/origin/main
    #
    # -- was the default in four of five clones on this project. It updates
    # origin/main and nothing else, so force-pushes to feature branches are
    # invisible and `git show origin/<branch>:<path>` silently reads a
    # commit that no longer exists. That is a documented sec.5b failure; what
    # makes it worth a check is the COMPOSITION: the hook resolves its script
    # from local origin/main too, so a clone whose refs go stale runs an old
    # main script -- old enough, in the demonstrated case, to lack this very
    # guard. A guard that reads a stale ref can approve itself.
    #
    # Advisory, not blocking. A wrong refspec makes results untrustworthy but
    # does not make the tree wrong, and blocking here would stop work on a
    # correct commit. Names the two commands, per sec.5b: a next action, not
    # an estimate of its own significance.
    # Empty means no `origin` remote is configured at all (a local-only
    # repo), which is not a misconfiguration -- warning there would fire on
    # every fresh `git init`. Filter before testing, because "".split("\n")
    # is [""], a TRUTHY list: the first cut of this check warned on a repo
    # with no remote for exactly that reason.
    fetch_specs = [spec.strip() for spec
                   in sh("git", "config", "--get-all",
                         "remote.origin.fetch").split("\n") if spec.strip()]
    if fetch_specs and not any(
            re.match(r"\+?refs/heads/\*:", spec) for spec in fetch_specs):
        # remedy: fixes
        warn("script-currency",
             "remote.origin.fetch does not fetch all branches -- "
             "remote-tracking refs for feature branches will go stale "
             "silently, including the origin/main this guard and the "
             "pre-commit hook both read",
             "git config --unset-all remote.origin.fetch && "
             "git config --add remote.origin.fetch "
             "'+refs/heads/*:refs/remotes/origin/*' && "
             "git config fetch.prune true && git fetch --prune --force origin")

    ref = sh("git", "rev-parse", "--verify", "--quiet",
             "origin/main:scripts/preflight.py").strip()
    if not ref:
        # No fetched origin/main to compare against. Not a finding.
        # remedy: external
        warn("script-currency",
             "origin/main:scripts/preflight.py not available -- could not "
             "confirm this script is current",
             "fetch origin before trusting a clear run on a feature branch, "
             "since a branch copy may predate checks main already has")
        return 0
    try:
        with open(here, encoding="utf-8") as fh:
            local = fh.read()
    except OSError:
        return 0
    remote = sh("git", "show", "origin/main:scripts/preflight.py")
    if local == remote:
        return 0

    # Differing is not automatically stale: this file is edited on branches
    # that ADD checks, and refusing those would block the work that fixes
    # this. Only a LOCAL copy missing checks that origin/main has is stale.
    def check_names(text):
        return set(re.findall(r"^def (check_\w+)", text, re.M))

    missing = sorted(check_names(remote) - check_names(local))
    if not missing:
        return 0
    print("FAIL  [script-currency] this scripts/preflight.py is missing "
          f"{len(missing)} check(s) that origin/main has: "
          + ", ".join(missing))
    print("      -> a clean run from this copy does not cover them. Run "
          "origin/main's copy instead:")
    print("         git show origin/main:scripts/preflight.py > /tmp/pf.py "
          "&& python3 /tmp/pf.py --since origin/main")
    print("\npreflight: refusing to run -- stale script.")
    return 1


# ---------------------------------------------------------------- reporting
_PRE_COMMIT_HOOK = r"""#!/bin/sh
# Installed by scripts/preflight.py --install-hook. Do not edit by hand;
# re-run --install-hook instead.
#
# This hook runs origin/main's preflight.py, NOT the worktree copy.
#
# Compass found why that matters. The old hook was `exec python3
# scripts/preflight.py` -- path-relative and version-pinned to nothing. Install
# it once on main, check out a feature branch to build, and every commit from
# then on runs THAT BRANCH's script. On cross-section-exclude the branch script
# is 836 lines and predates decoder-completeness, cited-doc and the argv guard:
# an undecoded field injected into PaintAnalysis on that very tree reports
# `clear`, exit 0, while main's script reports 1 blocking and names the field.
# The branch whose whole purpose was fixing a decoder hazard shipped with a
# script that cannot see it.
#
# That is the day's failure shape in its most convincing costume -- not a tool
# that ran and found nothing, but the WRONG TOOL running and finding nothing,
# printing a clean line that looks exactly like the right one.
#
# So: resolve the script from origin/main and refuse if it cannot be resolved.
# Falling back to the worktree copy is precisely the silent substitution this
# exists to prevent, and a hook that declines to run is recoverable while a
# hook that runs the wrong checks is not.
set -e
SCRIPT="$(git rev-parse --git-dir)/preflight-from-origin-main.py"
if ! git cat-file -e origin/main:scripts/preflight.py 2>/dev/null; then
    echo "preflight hook: cannot resolve origin/main:scripts/preflight.py" >&2
    echo "  Your remote-tracking refs may be missing or stale -- run:" >&2
    echo "    git fetch origin '+refs/heads/*:refs/remotes/origin/*' --prune" >&2
    echo "  Refusing to run the worktree copy instead: a feature branch's" >&2
    echo "  script may be missing checks that main has, and would print a" >&2
    echo "  clean line anyway. Commit blocked." >&2
    exit 1
fi
git show origin/main:scripts/preflight.py > "$SCRIPT"
exec python3 "$SCRIPT"
"""


def main():
    args = sys.argv[1:]
    if "--install-hook" in args:
        # `git rev-parse --git-common-dir`, NOT REPO/.git. In a linked
        # worktree .git is a FILE pointing at .git/worktrees/<name>, so the
        # hardcoded path raised NotADirectoryError and the hook was never
        # installed -- and hooks are shared across worktrees, so the common
        # dir is also the right place. Found by running --install-hook in a
        # worktree, which is where all of today's patches were built: the
        # guard that resolves the script from origin/main could not be
        # installed by the trees doing the work.
        common = sh("git", "rev-parse", "--git-common-dir").strip()
        if not common:
            print("cannot locate the git directory -- is this a repository?",
                  file=sys.stderr)
            return 1
        hooks = os.path.join(REPO, common) if not os.path.isabs(common) \
            else common
        hooks = os.path.join(hooks, "hooks")
        os.makedirs(hooks, exist_ok=True)
        hook = os.path.join(hooks, "pre-commit")
        with open(hook, "w") as fh:
            fh.write(_PRE_COMMIT_HOOK)
        os.chmod(hook, 0o755)
        print(f"installed {hook}")
        print("The hook runs origin/main's preflight.py, not the worktree "
              "copy, and refuses if it cannot resolve that ref.")
        return 0

    # Self-staleness guard. See check_script_currency's docstring.
    if check_script_currency() != 0:
        return 1

    global DIFF_BASE, MERGE_BASE_IS_WORKTREE
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
    elif os.path.exists(os.path.join(sh("git", "rev-parse",
                                        "--git-dir").strip() or ".git",
                                     "MERGE_HEAD")):
        # A merge resolution in progress, and nothing is staged relative to
        # HEAD in the way the transition checks need. Compass measured the
        # gap: examinerName String? -> Int? with a matching decoder edit is
        # SILENT under --all and blocking under --since. His distinction is
        # why this is a diff base rather than a check moved tree-wide --
        # persisted-model's subject is a TRANSITION (an old payload versus a
        # new declaration), so there is no tree-wide fact to test, while
        # decoder completeness is a property of the tree alone, which is why
        # moving THAT one worked (21e18cf).
        #
        # The remedy was `--since origin/main` after a merge, which required
        # remembering. A merge is exactly when nobody remembers, and it is
        # the commit shape that produced both of today's worst defects. So
        # the base is derived rather than requested: diff against the first
        # parent, which is what the merge is bringing changes ON TOP of.
        first_parent = sh("git", "rev-parse", "--verify", "--quiet",
                          "HEAD").strip()
        if first_parent:
            DIFF_BASE = first_parent
            MERGE_BASE_IS_WORKTREE = True
            print(f"preflight: merge in progress -- comparing against HEAD "
                  f"({first_parent[:7]}) so the transition checks have a "
                  f"diff to read")

    # Reject an argument we do not recognise, rather than ignoring it and
    # falling through to staged mode. `--sinse origin/main` (or `--al`)
    # otherwise prints "nothing staged" and exits 0 -- a clean run over
    # nothing at all, wearing the same face as a clean run over everything.
    # That is the day's recurring shape one level up from the checks: an
    # unknown ref already fails loudly here, so an unknown FLAG must too.
    known = {"--all", "--since", "--install-hook", "--strict"}
    unknown = [a for i, a in enumerate(args)
               if a.startswith("-") and a not in known
               and not (i > 0 and args[i - 1] == "--since")]
    if unknown:
        print("preflight: unknown option(s) "
              + ", ".join(f"'{a}'" for a in unknown)
              + f"; known: {' '.join(sorted(known))}")
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
    check_manifest_drift()
    check_cited_doc_copy()
    check_shapecheck_anchors()
    check_variant_output_binding()
    check_shapechecks_run()
    check_note_rows_implemented()
    check_locked_variant_conditions()
    check_default_valued_predicates()
    check_doc_drift()
    check_conflict_markers()
    check_cited_commits()
    check_swift_parses()
    check_manifest_line_counts()
    check_remedy_declarations()
    # NOT commit-shaped, despite reading like one. The defect it exists for
    # arrived in f7921d8 -- a MERGE, which stages nothing, so the staged-diff
    # gate below never ran it on the one commit shape most likely to produce
    # it. That is the same blindness that let six conflict markers reach main
    # (see check_conflict_markers), and entry #6 of the changelog documents
    # this very hazard as the defect a merge resolution fixed. A hand-written
    # decoder is a hand-maintained list; whether it is complete is a property
    # of the TREE, not of a diff. Tree-wide when --all, staged files otherwise.
    check_decoder_completeness(files)

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
    # WORDING, not severity. Ledger's ruling, and his measurement is what
    # makes it necessary: a shape check can FAIL, `check_shapechecks_run` can
    # name the right file with no backtrace noise, and the summary still ends
    # in the word `clear`. Three readers each read a different non-text
    # channel -- the exit code, the summary line, a piped status -- and the
    # finding, which lived only in the text, reached none of them.
    #
    # `clear` is a claim about the tree. It must not be made while any
    # instrument reported anything. A finding not yet triaged is neither
    # `clear` nor `blocking`, and this file had no third word for it, so the
    # aggregate borrowed the wrong one. It has one now.
    #
    # Severity is deliberately UNCHANGED, on this file's own rule: a blocking
    # check needs more scoping care than an advisory one, because its failure
    # mode is somebody reaching for `--no-verify`, which silences every check
    # at once. rc=1 here would also be environment-dependent -- a property of
    # the pair, never of the commit.
    #
    # Necessary and NOT sufficient, which is why `--strict` above exists: the
    # word fixes what a READER sees, and the exit code is what a verifier
    # SCRIPTS against. Both channels or neither.
    headline = ("clear" if not warnings
                else f"{len(warnings)} advisory, nothing blocking")
    print(f"\npreflight: {headline} -- {scope}.")
    if warnings:
        print("NOT 'clear': every advisory above is a finding that has not "
              "been triaged. Read the warn lines -- an advisory is not an "
              "absence, and this summary is not a verdict on the tree.")
    print("This means 'worth compiling'. It does not mean it compiles -- "
          "PROCESS.md sec.4 clauses 4-6 still need Xcode and a device.")
    # `--strict`: exit 4 when advisories are present but nothing is blocking.
    #
    # NOTE(Vector), 2026-09-07, from the Tech Lead's finding. Our verification
    # commands read `preflight`'s EXIT CODE, and rc=0 means "did not refuse to
    # proceed" -- it has never meant "found nothing". A round of `>/dev/null
    # 2>&1; echo PF=$?` therefore reported "0 advisories" out of a channel
    # where the advisory count is not present at all: re-read, those clones
    # held 1, 1 and 3 advisories, and the third was the run that declared the
    # tree clean while a `.pyc` was sitting in the text.
    #
    # The remedy is a rule ("read the advisory line, never the exit code") and
    # a rule that could be a check should not be a habit -- the same argument
    # that put `.pyc` in `.gitignore` instead of a note, and it applies harder
    # here because the habit already failed under pressure for three of us.
    # `--strict` lets a verifier ASK for advisory-clean and get an answer its
    # `$?` can actually carry.
    #
    # 4, not 1: a blocking failure and an advisory are different claims and a
    # caller that collapses them undoes the split. Same discipline as run.sh's
    # rc=3 for NOT RUN. Opt-in, because the pre-commit hook must keep passing
    # on advisories -- an advisory that refuses a commit is a failure by
    # another name, and this file argues against exactly that everywhere else.
    if "--strict" in args and warnings:
        print(f"preflight --strict: {len(warnings)} advisory present, "
              f"nothing blocking (rc=4). rc=0 answers 'did it refuse to "
              f"proceed', never 'did it find anything'.")
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
