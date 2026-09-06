#!/usr/bin/env python3
"""Every remedy in preflight.py must declare what following it achieves.

Why this exists rather than another rule. Six unperformable remedies landed on
one document in one day, each found the same way -- somebody happened to follow
one and got the identical failure back. Four sweeps were run for them, by four
people, and every sweep was correct about the sites it enumerated and blind to
the ones it did not: scoped by symptom, then by check, then by neighbourhood,
then by grepping one string. Ledger's rule is the diagnosis -- THE UNIT AN
AUDIT CLEARS IS THE UNIT IT ACTUALLY EXERCISED, NEVER THE ARTEFACT IT WAS
AIMED AT -- and his open question was the only thing that would settle it: a
sweep that EXECUTES each remedy instead of reading it.

That harness cannot exist, and the reason is worth stating rather than
discovering later. Executing a remedy means mutating the tree into the
condition the check reports, running an arbitrary shell command the remedy
names, and deciding whether the finding cleared. Some remedies name Xcode, a
device, or Ledger. Some are correctly UNCLEARABLE -- see the reminder class
below. A harness that "ran them all" would be the day's own defect one level
up: a green line asserting more than it measured, which is exactly how a
wrong all-clear becomes durable.

So this enforces the property by CONSTRUCTION instead of by measurement. Every
warn()/fail() site in preflight.py carries a declaration of its remedy's kind
on the line above it, and this script fails if any site lacks one. A new check
cannot be added without its author answering the question that took six
instances to ask.

    # remedy: fixes      following it removes this finding. Must name the
    #                    thing that does. Compass's test applies: run it,
    #                    re-run the check, expect silence.
    # remedy: reminder   this finding is keyed to the DIFF, not to state, and
    #                    NO correct work clears it in this run. It must say so
    #                    outright and name the checks that verify the result.
    #                    Compass measured why: he did all three steps of a
    #                    correct remedy and the warning still fired, which is
    #                    worse than the original defect because the reader has
    #                    now DONE the work and been told it did not take.
    # remedy: external   clearing it needs something outside this repo -- a
    #                    device, Xcode, a person, a push. Names the next
    #                    action and whose it is, per sec.5b.
    # remedy: state      the finding IS the state and the remedy restores it
    #                    from elsewhere (git history, a full checkout). No
    #                    generator here; say so, since "regenerate it" named a
    #                    capability that never existed.

The declaration is a claim by the author, not a proof -- this script cannot
know whether a `fixes` remedy really fixes. That is deliberate and is the
honest bound: it converts a silent omission into a written claim someone can
be wrong about in public, which is the difference between the six instances
and their absence. Where a claim was tested, the test belongs in the commit
body.

What this does NOT do, stated because the day's whole lesson is that a tool's
claim gets read as more than it measured: it does not verify that a `fixes`
remedy fixes. 38 sites, 6 ever performed across five sweeps -- the other 32
are UNEXERCISED, which is neither suspect nor clear. That is a real bound, not
a formality. What it buys is that the claim is WRITTEN: an unperformable remedy
now requires someone to have typed `fixes` next to it, which is a mistake
another reader can see rather than an omission nobody can. Ledger's sentence is
the mechanism -- a remedy is read as instruction, never as a claim, and nobody
audits an imperative.

Remedy kind of this script's own findings: fixes -- add the declaration.

Run: python3 scripts/check_remedies.py    (rc=1 on any undeclared site)
"""
import ast
import re
import sys

TARGET = "scripts/preflight.py"
KINDS = ("fixes", "reminder", "external", "state")
DECL = re.compile(r"#\s*remedy:\s*(\w+)")

# A reminder's remedy must SAY it will not clear, or the reader does the work
# and concludes the check is broken. Compass's sixth instance, and the first
# one whose honest remedy is "this will not clear -- here is what does".
#
# This one predicate matches PROSE, and Ledger flagged the hazard in it before
# it could bite: a prose predicate goes stale in WORDING while staying true in
# SUBSTANCE, which is this repo's own dead-check shape arriving through the
# tool built to end it. Two mitigations, both deliberate:
#
#   1. It is a disjunction over several phrasings, not one canonical string,
#      and adding a phrasing is a one-line change with no behaviour attached.
#   2. It is ADVISORY IN KIND -- a site can opt out with `# remedy-clears-note:
#      ok` on the declaration line when it states the fact in words this list
#      does not know. That escape hatch is the difference between a check and
#      a spelling rule: a false positive here costs a correct remedy being
#      rewritten to satisfy a regex, which is how a tool starts training the
#      bypass habit.
#
# If the opt-out ever gets used more than once or twice, this predicate is
# wrong and should be deleted rather than extended -- the declaration itself
# is the load-bearing part; this is a courtesy on top of it.
REMINDER_MUST_SAY = ("will not clear", "will NOT clear", "does not clear",
                     "not clear in this run", "not a drift check",
                     "keyed to the diff", "reminder keyed to")
OPT_OUT = "remedy-clears-note: ok"


def sites(src):
    """Every warn()/fail() call, with the function holding it."""
    out = []

    class V(ast.NodeVisitor):
        def __init__(self):
            self.fn = None

        def visit_FunctionDef(self, node):
            prev, self.fn = self.fn, node.name
            self.generic_visit(node)
            self.fn = prev

        def visit_Call(self, node):
            if isinstance(node.func, ast.Name) and \
                    node.func.id in ("warn", "fail"):
                out.append((node.lineno, node.func.id, self.fn, node))
            self.generic_visit(node)

    V().visit(ast.parse(src))
    return sorted(out)


def declared_kind(lines, lineno):
    """The `# remedy:` declaration above a call, skipping blanks."""
    i = lineno - 2
    while i >= 0 and not lines[i].strip():
        i -= 1
    seen, opted_out = None, False
    # Walk up through the contiguous comment block, so a declaration may sit
    # above an explanatory comment rather than being wedged against the call.
    while i >= 0 and lines[i].lstrip().startswith("#"):
        if OPT_OUT in lines[i]:
            opted_out = True
        m = DECL.search(lines[i])
        if m:
            seen = m.group(1)
            break
        i -= 1
    return seen, opted_out


def remedy_text(node):
    """The third positional argument, when it is a literal."""
    if len(node.args) < 3:
        return None
    try:
        val = ast.literal_eval(node.args[2])
    except (ValueError, TypeError, SyntaxError):
        return None
    return val if isinstance(val, str) else None


def main():
    src = open(TARGET, encoding="utf-8").read()
    lines = src.split("\n")
    undeclared, bad_kind, silent_reminder = [], [], []

    found = sites(src)
    if not found:
        # Anchor assertion, the pattern this repo now uses everywhere: a
        # harness that finds nothing must distinguish "nothing to check" from
        # "did not read its subject". A rename of warn/fail would empty this
        # silently and print clear.
        print(f"no warn()/fail() call sites found in {TARGET} -- this check "
              "read nothing. The reporting helpers were probably renamed; "
              "re-point this script.")
        return 1

    for lineno, kind_fn, fn, node in found:
        kind, opted_out = declared_kind(lines, lineno)
        if kind is None:
            undeclared.append((lineno, fn, kind_fn))
        elif kind not in KINDS:
            bad_kind.append((lineno, fn, kind))
        elif kind == "reminder" and not opted_out:
            text = remedy_text(node)
            if text is not None and not any(p in text
                                            for p in REMINDER_MUST_SAY):
                silent_reminder.append((lineno, fn))

    for lineno, fn, kind_fn in undeclared:
        print(f"{TARGET}:{lineno}: {kind_fn}() in {fn}() has no "
              f"`# remedy: <{'|'.join(KINDS)}>` declaration")
    for lineno, fn, kind in bad_kind:
        print(f"{TARGET}:{lineno}: {fn}() declares unknown remedy kind "
              f"{kind!r} -- expected one of {', '.join(KINDS)}")
    for lineno, fn in silent_reminder:
        print(f"{TARGET}:{lineno}: {fn}() declares `remedy: reminder` but its "
              "remedy text never says it will not clear -- a reader who does "
              "the work correctly will see the same warning and conclude the "
              "check is broken. If it does say so in words this script does "
              "not know, add `# remedy-clears-note: ok` to the declaration "
              "line rather than rewording a correct remedy to satisfy a "
              "regex")

    total = len(undeclared) + len(bad_kind) + len(silent_reminder)
    if total:
        print(f"\n{total} remedy site(s) need attention of "
              f"{len(found)} checked.")
        return 1
    print(f"all {len(found)} remedy sites in {TARGET} declare their kind "
          "(this records the author's claim; it does not prove it)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
