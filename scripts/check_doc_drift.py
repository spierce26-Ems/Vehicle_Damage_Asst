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
  - **The graded bands are PARSED, not executed, and the parse is weaker than
    it looks.** `_score_band` reads `heightAlignmentScore`'s guards as an
    ordered list and assumes the default `toleranceInches = 2.0`. That
    argument is caller-configurable and `HeightAlignmentAnalyzer` threads a
    caller value through all four call sites, so guard ORDER matters in ways
    the parse cannot see. Verified: hoisting `if diff <= toleranceInches`
    above the rule-out guard produces byte-identical parser output while
    restoring the pre-#10a defect -- a caller passing a tolerance above 6"
    then scores 100 for a height difference that should exclude. The honest
    fix is to execute the function, which needs the Swift test target; a
    cleverer parser would be the same mistake one level deeper, since it
    would still be a representation of the behaviour rather than the
    behaviour (PROCESS.md sec.5b). Until then this file checks that the band
    NUMBERS agree, not that the scorer applies them in the documented order.

Usage: python3 scripts/check_doc_drift.py [repo_root]
"""
import re
import sys
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
    fmt, anchor, drift = [], [], []

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
        # returns. The 6.1" case that scored 39/100 lived here, not in the
        # rule-out constant.
        for upper, pct in bands:
            if pct == 0:
                continue
            got = _score_band(mh, upper)
            if got is None:
                anchor.append(f"heightAlignmentScore not parseable -- cannot verify the "
                              f'{upper}" band')
                break
            if got != pct:
                drift.append(f'height band <= {upper}": doc {pct}% != code {got}%')

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
    for m in drift:
        print(f"FAIL [doc-drift]  {m}")
    if drift:
        print("     -> REAL disagreement. Decide which side is right: the document has "
              "been correct and the code wrong before (task #10).")

    if not (fmt or anchor or drift):
        print(f"doc-drift: clear ({len(dw)} weights, {len(bands)} height bands checked; "
              f"numeric claims only -- see the limits in this script's docstring)")
        return 0
    return 1


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
