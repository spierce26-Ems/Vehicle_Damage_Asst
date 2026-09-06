#!/usr/bin/env python3
"""Regenerate COMPLETE_FILE_MANIFEST.md's per-file line counts, to a fixed point.

Every patch that grows a tracked file changes that file's manifest row, so
every such patch conflicts with every other on that row. Compass's rule from
four consecutive conflicts: never hand-pick a side. His data is why it is a
rule and not a habit -- in one resolution NEITHER side was right on EITHER
row (tree at 1683/1924 against sides at 1677/1682 and 1920/1905), so there is
no resolution strategy based on choosing, only on recomputing.

Then the second-order edge the Tech Lead hit: the manifest LISTS ITSELF, so
rewriting rows changes the file's own length and one pass leaves the
self-referential row describing the pre-write file. It has to iterate to a
fixed point. Ten passes is a bound, not an expectation -- it converges in one
or two, and failing loudly beats looping.

Run this after resolving a manifest conflict, then `preflight --all`
immediately -- after the RESOLUTION, not after the whole stack.

Two behaviours from Compass's independent version, which earned their keep:

  --check  reports and writes NOTHING, exit 1 when stale. So it can gate
           without being able to paper over anything.

  Rows naming an UNTRACKED path are reported and SKIPPED, not silently
  matched by os.path.exists. Path drift is check_manifest_drift's subject,
  and a regenerator that quietly fixed rows for untracked files would hide
  it.

Also his precise trigger for the fixed point, sharper than "one pass is not
enough": ONE PASS SUFFICES WHEN A COUNT'S DIGITS CHANGE, AND FAILS WHEN THE
ROW COUNT CHANGES -- adding or removing a row always shifts the manifest's own
length, so the self-row then describes the pre-write file. The failing case is
exactly "a patch that adds a file", which is most patches.

What this deliberately does NOT touch: the `Totals:` prose sentence. Prose is
Ledger's, and a regenerator with an opinion about his sentences is how a
document loses its author. preflight names that number in three checks now
(files, Swift count, and the header's line total), so a patch that adds or
deletes a file still edits that one line by hand and --all catches it.
"""
import os
import re
import subprocess
import sys

mp='ios/reference/COMPLETE_FILE_MANIFEST.md'
pat=re.compile(r'^\|\s*`([^`]+)`\s*\|\s*([^|]*?)\s*\|$')
check_only='--check' in sys.argv
try:
    tracked=set(subprocess.run(['git','ls-files'],capture_output=True,
                               text=True,check=True).stdout.split())
except (OSError,subprocess.CalledProcessError):
    # Compass's catch. check_output raised CalledProcessError and this exited
    # 0 with a traceback -- a gate that crashes while reporting success, the
    # dead-check shape inside the tool written to end a day of them.
    sys.exit("not inside a git repository, or git ls-files failed")
untracked_rows=[]
stale=[]
for it in range(10):
    lines=open(mp).read().split('\n')
    changed=0
    for i,l in enumerate(lines):
        m=pat.match(l)
        if not m: continue
        f,v=m.group(1),m.group(2).strip()
        if not v.isdigit(): continue
        if f not in tracked:
            # Reported, never rewritten -- see the docstring.
            if it==0 and os.path.exists(f): untracked_rows.append(f)
            continue
        a=open(f,'rb').read().count(b'\n')
        if a!=int(v):
            changed+=1
            if it==0: stale.append("%s says %s, has %d"%(f,v,a))
            lines[i]="| `%s` | %d |"%(f,a)
    if not changed:
        print("fixed point after %d pass(es)"%it); break
    if check_only: break
    open(mp,'w').write('\n'.join(lines))
else:
    print("did not converge in 10 passes -- something else is editing the "
          "table"); sys.exit(1)

for f in untracked_rows:
    print("row names an untracked path, skipped (that is "
          "check_manifest_drift's subject): %s"%f)
if check_only and stale:
    for d in stale: print("stale: %s"%d)
    sys.exit(1)
