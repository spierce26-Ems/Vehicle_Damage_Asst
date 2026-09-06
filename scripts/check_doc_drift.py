#!/usr/bin/env python3
"""Detect CODE drifting away from CORRECT documentation.

Every other check in preflight.py assumes documentation goes stale behind
code. Two of task #10's three scoring divergences were the reverse:
`ALGORITHM_EXPLAINER.md` was RIGHT and the Swift had drifted away from it.
Nothing monitored that direction (PROCESS.md sec.5c).

Mechanizable subset: NUMERIC claims only -- the factor weights and the
height-alignment bands -- which is where all three real divergences lived.
General prose agreement is not tractable and is not attempted.

Three failure classes, deliberately reported apart, because they send the
reader to three different places:

  doc-format   The document no longer parses the way this script expects.
               Says NOTHING about the Swift. Fix the parser or the heading
               format; do not go looking for a scoring regression.
  doc-anchor   A Swift construct this script keys on is gone, renamed, or is
               no longer a comparable constant. The check has lost its
               subject and cannot make any claim at all.
  doc-drift    Both sides parsed and the NUMBERS DISAGREE. This one is a real
               finding: either the Swift drifted from a correct document or
               the document was edited without the code.

Both non-drift classes exist because of the dead-check failure mode: a check
that quietly examines less than it claims is worse than no check. Expected
CLAIM COUNTS are asserted, not merely compared -- converting the height-band
list to a markdown table made an earlier cut of this script check three bands
instead of four and still print `clear`, and the band it dropped was the
rule-out row.

Known limits, so a clear run is not read as stronger than it is:
  - Only two claim families. Scar and tool-mark content was never documented
    numerically, so nothing there is checkable by this route.
  - Tied to the explainer's markdown shape. It fails rather than silently
    passing, which is the right direction, but ordinary prose edits can trip
    it -- that is what doc-format is for.
  - If a weight ever becomes device- or case-dependent, the document has no
    single number to check against and this check must be retired for that
    factor rather than fitted to one arbitrary case.
  - `require_stored_constant` guards the `let` -> computed-property rename:
    a same-named computed property would satisfy a bare name search while no
    longer being a constant anyone can compare.
  - **The graded bands are EXECUTED when a Swift compiler is present and
    only PARSED when one is not**, and every band failure says which, so the
    weaker method never reports under the stronger one's wording. The gap
    between them is not academic: `_score_band` reads
    `heightAlignmentScore`'s guards as an ordered list and assumes the
    default `toleranceInches = 2.0`, but that argument is caller-supplied and
    `HeightAlignmentAnalyzer` threads a caller value through all four call
    sites. Hoisting `if diff <= toleranceInches` above the rule-out guard
    produces BYTE-IDENTICAL parser output while restoring the pre-#10a
    defect -- a caller passing 8" then scores 100 for a 7" difference that
    must exclude. The executed path catches it, because a caller-supplied
    tolerance is just an argument. A cleverer parser would have been the same
    mistake one level deeper: still a representation of the behaviour rather
    than the behaviour (PROCESS.md sec.5b).
  - Without a compiler the guard-order probe does not run at all, and says
    so as a `doc-anchor` failure rather than passing quietly.

Usage: python3 scripts/check_doc_drift.py [repo_root]
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import pathlib

DOC = "ios/reference/ALGORITHM_EXPLAINER.md"
MATCH_RESULT = "ios/VehicleDamageForensics/Models/MatchResult.swift"
MEASUREMENT_HELPERS = "ios/VehicleDamageForensics/Utilities/MeasurementHelpers.swift"

# Asserted, not discovered. If the document legitimately gains or loses a
# factor or a band, this number changes in the same commit -- which is the
# point: the change becomes visible instead of silently narrowing the check.
EXPECTED_WEIGHT_COUNT = 7
EXPECTED_BAND_COUNT = 4


# ---------------------------------------------------------------- doc side

def doc_weights(text):
    """Factor weights the document asserts, in document order."""
    return [int(m) for m in re.findall(r"\((\d+)%\s+weight\)", text)]


def doc_height_bands(text):
    """The height-alignment bands as (upper_bound_inches, percent).

    Only the Height Alignment section is scanned: the Impact Geometry section
    uses the identical `- 10-30 degrees difference = 50%` shape, and a
    whole-file scan would silently mix degrees into an inches comparison.
    """
    section = _section(text, "Height Alignment")
    if section is None:
        return None
    out = []
    for line in section.splitlines():
        m = re.match(r'\s*-\s*([\d.]+)\s*-\s*([\d.]+)"\s*difference\s*=\s*(\d+)%', line)
        if m:
            out.append((float(m.group(2)), int(m.group(3))))
            continue
        m = re.match(r'\s*-\s*>\s*([\d.]+)"\s*difference\s*=\s*(\d+)%', line)
        if m:
            out.append((float(m.group(1)), int(m.group(2))))
    return out


def _section(text, heading_contains):
    """Text of the `### ...` section whose heading contains the given string."""
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if line.startswith("### ") and heading_contains in line:
            start = i
            break
    if start is None:
        return None
    for j in range(start + 1, len(lines)):
        if lines[j].startswith("### "):
            return "\n".join(lines[start:j])
    return "\n".join(lines[start:])


# --------------------------------------------------------------- code side

def code_weights(src):
    """Weights from ForensicFactor.weight, in source order.

    Returns (weights, anchor_error). A case whose body is not a bare numeric
    literal is reported rather than skipped: a device- or case-dependent
    weight has no single number for the document to state, so the honest
    result is that this check no longer applies -- not a shorter list quietly
    compared against a longer one.
    """
    m = re.search(r"var\s+weight:\s*Double\s*\{(.*?)\n    \}", src, re.S)
    if not m:
        return None, ("ForensicFactor.weight not found as `var weight: Double` "
                      "-- renamed, reshaped, or moved")
    body = m.group(1)
    cases = re.findall(r"case\s+\.(\w+):\s*return\s+([^\n]+)", body)
    if not cases:
        return None, "ForensicFactor.weight found but no `case ...: return ...` arms parsed"
    weights = []
    for name, expr in cases:
        expr = expr.strip().rstrip(";")
        if not re.fullmatch(r"[0-9]*\.?[0-9]+", expr):
            return None, (f"ForensicFactor.weight case .{name} returns `{expr}`, not a "
                          f"numeric literal -- the weight is no longer a single number "
                          f"the document can state; retire this check for that factor")
        weights.append(round(float(expr) * 100))
    return weights, None


def require_stored_constant(src, name, kind="Double"):
    """Value of `static let <name>: <kind> = <literal>`.

    Returns (value, anchor_error). Deliberately strict about `let`: a rename
    to a computed property of the same name keeps every bare name search
    happy while the thing stops being a constant that can be compared, which
    is exactly the drift this file exists to notice.
    """
    m = re.search(rf"static\s+let\s+{re.escape(name)}\s*:\s*{kind}\s*=\s*([0-9]*\.?[0-9]+)", src)
    if m:
        return float(m.group(1)), None
    if re.search(rf"\bvar\s+{re.escape(name)}\s*:\s*{kind}\s*\{{", src):
        return None, (f"`{name}` is now a computed property, not a stored constant "
                      f"-- there is no single value left to compare against the document")
    if re.search(rf"\b{re.escape(name)}\b", src):
        return None, (f"`{name}` appears but not as `static let {name}: {kind} = <literal>` "
                      f"-- reshaped or given a non-literal initialiser")
    return None, f"`{name}` not found -- renamed or removed"


# ------------------------------------------------------------------ driver

def main(root="."):
    root = pathlib.Path(root)
    fmt, anchor, drift, unverified = [], [], [], []

    try:
        doc = (root / DOC).read_text()
        mr = (root / MATCH_RESULT).read_text()
        mh = (root / MEASUREMENT_HELPERS).read_text()
    except FileNotFoundError as exc:
        print(f"FAIL [doc-anchor] {exc.filename} not found -- moved or renamed")
        print("     -> this check cannot run; fix the path in scripts/check_doc_drift.py")
        return 1

    # --- factor weights -----------------------------------------------
    dw = doc_weights(doc)
    if len(dw) != EXPECTED_WEIGHT_COUNT:
        fmt.append(f"expected {EXPECTED_WEIGHT_COUNT} `(N% weight)` headings in the "
                   f"explainer, parsed {len(dw)} -- the heading format changed, so the "
                   f"weight comparison was NOT performed (this says nothing about the Swift)")
    cw, err = code_weights(mr)
    if err:
        anchor.append(err)
    if len(dw) == EXPECTED_WEIGHT_COUNT and cw is not None:
        if len(cw) != EXPECTED_WEIGHT_COUNT:
            anchor.append(f"ForensicFactor has {len(cw)} weighted cases, expected "
                          f"{EXPECTED_WEIGHT_COUNT} -- a factor was added or removed in code")
        elif dw != cw:
            drift.append(f"factor weights: doc {dw} != code {cw}")

    # --- height bands ---------------------------------------------------
    bands = doc_height_bands(doc)
    if bands is None:
        fmt.append('no `### ... Height Alignment ...` section found in the explainer '
                   '-- the height-band comparison was NOT performed')
        bands = []
    elif len(bands) != EXPECTED_BAND_COUNT:
        fmt.append(f"expected {EXPECTED_BAND_COUNT} height bands in the Height Alignment "
                   f"section, parsed {len(bands)} -- the band list format changed (a "
                   f"markdown table does this), so the rule-out comparison was NOT "
                   f"performed; this says nothing about the Swift")
        bands = []

    ro, err = require_stored_constant(mh, "heightRuleOutInches")
    if err:
        anchor.append(err)
    if bands and ro is not None:
        doc_ro = [inches for inches, pct in bands if pct == 0]
        if len(doc_ro) != 1:
            fmt.append(f"expected exactly one 0% (rule-out) height band, parsed "
                       f"{len(doc_ro)} -- rule-out comparison NOT performed")
        elif doc_ro[0] != ro:
            drift.append(f'height rule-out: doc >{doc_ro[0]}" != code {ro}"')

        # The graded bands the document states must also be what the scorer
        # RETURNS. The 6.1" case that scored 39/100 lived here, not in the
        # rule-out constant.
        #
        # EXECUTED against the real function when a Swift compiler is
        # available; parsed only as a fallback, and any failure says which
        # method produced it so the weaker one never borrows the stronger
        # one's authority. The difference is not academic -- see the
        # guard-order probe below.
        executed, why_not_executed = _score_bands_executed(root, bands)
        how = "executed" if executed is not None else "parsed"
        for upper, pct in bands:
            if pct == 0:
                continue
            got = executed.get(upper) if executed is not None else _score_band(mh, upper)
            if got is None:
                anchor.append(f"heightAlignmentScore not {how} -- cannot verify "
                              f'the {upper}" band')
                break
            if got != pct:
                drift.append(f'height band <= {upper}" ({how}): doc {pct}% '
                             f"!= code {got}%")

        # GUARD ORDER, which only execution can see, and which the parse
        # missed by construction. `toleranceInches` is caller-supplied and
        # HeightAlignmentAnalyzer threads a caller value through all four
        # call sites, so a tolerance wider than the rule-out is reachable.
        # The rule-out must still win. Hoisting `if diff <= toleranceInches`
        # above the rule-out guard produced byte-identical output from
        # _score_band while restoring the pre-#10a defect -- a caller
        # passing 8" then scores 100 for a 7" difference that must exclude.
        # PROCESS.md sec.5b: assert on behaviour, not on a representation
        # of it. This probe is that rule applied to this file's own method.
        wide = executed.get("_wide_tolerance") if executed is not None else None
        if wide is None:
            # Advisory, not blocking, and graded the same way preflight's
            # parse check grades a missing toolchain: an environment without
            # a compiler must not be refused, but it must not print a clean
            # line asserting what it could not test either. Blocking here
            # would refuse every commit on a toolchain-less machine, which
            # is how a check trains the bypass habit for the checks beside
            # it.
            unverified.append(
                f"guard-order probe did NOT run ({why_not_executed}) -- the "
                "band numbers above were PARSED, and a parse cannot see guard "
                "order. That the rule-out survives a caller-supplied tolerance "
                "is UNVERIFIED here, not verified")
        else:
            if wide != 0:
                drift.append(
                    "guard order: heightAlignmentScore(0, 7, toleranceInches: 8) "
                    f"returns {wide}, not 0 -- a caller-supplied tolerance above "
                    "the rule-out defeats it, which is the pre-#10a defect. The "
                    "rule-out guard must be evaluated before the tolerance band.")

    for m in fmt:
        print(f"FAIL [doc-format] {m}")
    if fmt:
        print("     -> fix the parser in scripts/check_doc_drift.py or restore the "
              "documented format. Do NOT read this as a scoring regression.")
    for m in anchor:
        print(f"FAIL [doc-anchor] {m}")
    if anchor:
        print("     -> the check lost its subject in the Swift. Re-point it, or retire "
              "it for that claim. Do NOT read this as a scoring regression.")
    for m in unverified:
        print(f"warn [doc-unverified] {m}")
    if unverified:
        # The remedy has to match the cause. "Install a toolchain" is actively
        # misleading for a toolchain that IS installed and dies loading a
        # library -- it sends the reader to redo the one thing already done.
        if any("cannot run" in m or "did not build" in m for m in unverified):
            print("     -> a compiler is installed but unusable: read the reason "
                  "above and fix THAT, do not reinstall. For a missing "
                  "libncurses.so.6 on Ubuntu 24.04 the distro ships only the "
                  "wide build, so symlink libncursesw.so.6 to it. Set SWIFT_C "
                  "to override discovery.")
        else:
            print("     -> install a Swift toolchain (swift.org Linux tarball is "
                  "enough -- no iOS SDK) or set SWIFT_C, and this becomes a real "
                  "check in this environment")
    for m in drift:
        print(f"FAIL [doc-drift]  {m}")
    if drift:
        print("     -> REAL disagreement. Decide which side is right: the document has "
              "been correct and the code wrong before (task #10).")

    if not (fmt or anchor or drift):
        how = "executed" if executed is not None else "parsed"
        print(f"doc-drift: clear ({len(dw)} weights, {len(bands)} height bands "
              f"{how}; numeric claims only -- see the limits in this script's "
              f"docstring)")
        return 0
    return 1


def _first_line(text):
    """First non-empty line of a compiler's output, trimmed for one report line."""
    for line in (text or "").splitlines():
        line = line.strip()
        if line:
            return line[:300]
    return ""


def _build_failure_reason(swiftc, build):
    """Say WHY the compiler could not build, distinguishing broken from absent.

    A shared-library failure at exec is the case that actually bit: `swiftc`
    exists and is executable, so discovery succeeds, and the driver then dies
    loading a library the distro did not ship. Reporting that as "no Swift
    compiler found" sends the reader to reinstall a toolchain that is already
    installed, and hides a fix that is one symlink long.
    """
    err = _first_line(build.stderr) or _first_line(build.stdout)
    if "error while loading shared libraries" in err or "cannot open shared object" in err:
        lib = ""
        m = re.search(r"(lib[\w.+-]*\.so[\w.]*)", err)
        if m:
            lib = m.group(1)
        return ("a Swift compiler was FOUND but cannot run: "
                + (f"{lib} is missing" if lib else "a shared library is missing")
                + f" ({swiftc}). This is a broken toolchain, not an absent one -- "
                  "note that swift-frontend -parse still works, so preflight's "
                  "parse check can report a clean tree while this probe cannot "
                  "build at all")
    return ("a Swift compiler was FOUND but the probe did not build: "
            + (err or "no diagnostic output"))


def _score_bands_executed(root, bands):
    """Run heightAlignmentScore for real, when a Swift compiler exists.

    Returns `(probe, None)` on success, where probe is {upper_bound: score}
    plus a `_wide_tolerance` entry; otherwise `(None, reason)` -- in which
    case the caller falls back to _score_band's parse AND labels its findings
    `parsed`, so a weaker method never reports under the stronger one's
    wording.

    The `reason` is load-bearing, not cosmetic. A compiler that is absent and
    a compiler that is present but cannot execute are different environments
    with different remedies, and the advisory that names the wrong one sends
    the reader to install a toolchain they already have. Measured here: a
    swift.org 5.10.1 tarball on Ubuntu 24.04 has a `swiftc` that exists, is
    executable, and dies at exec on `libncurses.so.6` -- the distro ships
    only the wide build, `libncursesw.so.6`. `-parse` never loads the driver,
    so preflight's parse check is unaffected and reports 42 files clean while
    this probe cannot build a binary: the same toolchain is simultaneously
    working and broken, depending on which mode you ask for.

    MeasurementHelpers.swift imports only Foundation, so this builds on Linux
    from a swift.org tarball: no iOS SDK, no Xcode. That is the whole reason
    the honest version of this check is reachable off a Mac. Discovery order
    matches preflight.py's parse check, durable paths before ephemeral ones.

    Any build or run failure returns None rather than a verdict: a probe that
    could not run must not be reported as agreement.
    """
    swiftc = os.environ.get("SWIFT_C") or shutil.which("swiftc")
    if swiftc is None:
        for cand in (os.path.expanduser("~/toolchains/swift/usr/bin/swiftc"),
                     os.path.expanduser("~/toolchains/swift-5.10.1/usr/bin/swiftc"),
                     os.path.expanduser("~/toolchains/swift-6.0.3/usr/bin/swiftc"),
                     "/usr/local/bin/swiftc",
                     "/usr/local/swift/usr/bin/swiftc",
                     "/tmp/swift/usr/bin/swiftc"):
            if os.path.exists(cand):
                swiftc = cand
                break
    if swiftc is None:
        return None, "no Swift compiler found"
    helpers = os.path.join(root, MEASUREMENT_HELPERS)
    if not os.path.exists(helpers):
        return None, f"{MEASUREMENT_HELPERS} not found in the tree"

    lines = ["import Foundation"]
    for upper, pct in bands:
        if pct == 0:
            continue
        lines.append(f'print("{upper}", MeasurementHelpers'
                     f".heightAlignmentScore(0, {upper}), separator: \"=\")")
    lines.append('print("_wide_tolerance", MeasurementHelpers'
                 '.heightAlignmentScore(0, 7, toleranceInches: 8), '
                 'separator: "=")')

    tmp = tempfile.mkdtemp(prefix="docdrift-")
    try:
        main = os.path.join(tmp, "main.swift")
        with open(main, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
        binary = os.path.join(tmp, "probe")
        build = subprocess.run([swiftc, "-o", binary, helpers, main],
                               capture_output=True, text=True)
        if build.returncode != 0 or not os.path.exists(binary):
            return None, _build_failure_reason(swiftc, build)
        run = subprocess.run([binary], capture_output=True, text=True)
        if run.returncode != 0:
            return None, (f"the probe built but exited {run.returncode}: "
                          f"{_first_line(run.stderr) or 'no stderr'}")
        out = {}
        for line in run.stdout.splitlines():
            key, _, val = line.partition("=")
            try:
                num = float(val)
            except ValueError:
                continue
            out[key if key.startswith("_") else float(key)] = int(num)
        if not out:
            return None, "the probe ran but printed nothing parseable"
        return out, None
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _score_band(src, upper):
    """What heightAlignmentScore returns for a diff just inside `upper`.

    Parsed from the banded implementation rather than executed. Returns None
    if the function is not in the shape this parser understands, which is an
    anchor failure, not a pass.
    """
    m = re.search(r"static\s+func\s+heightAlignmentScore\s*\([^)]*\)\s*->\s*Double\s*\{(.*?)\n    \}",
                  src, re.S)
    if not m:
        return None
    body = m.group(1)
    rules = []          # (bound, value); bound None = fallthrough
    for line in body.splitlines():
        line = line.split("//")[0].strip()
        g = re.match(r"if\s+diff\s*>\s*heightRuleOutInches\s*\{\s*return\s+([\d.]+)", line)
        if g:
            rules.append(("ruleout", float(g.group(1))))
            continue
        g = re.match(r"if\s+diff\s*<=\s*toleranceInches\s*\{\s*return\s+([\d.]+)", line)
        if g:
            rules.append((2.0, float(g.group(1))))      # default toleranceInches = 2.0
            continue
        g = re.match(r"if\s+diff\s*<=\s*([\d.]+)\s*\{\s*return\s+([\d.]+)", line)
        if g:
            rules.append((float(g.group(1)), float(g.group(2))))
            continue
        g = re.match(r"return\s+([\d.]+)", line)
        if g:
            rules.append((None, float(g.group(1))))
    if not rules:
        return None
    for bound, value in rules:
        if bound == "ruleout":
            continue
        if bound is None or upper <= bound:
            return int(value)
    return None


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
