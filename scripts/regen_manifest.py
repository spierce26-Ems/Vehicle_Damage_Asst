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
"""
import os
import re
import sys

mp='ios/reference/COMPLETE_FILE_MANIFEST.md'
pat=re.compile(r'^\|\s*`([^`]+)`\s*\|\s*([^|]*?)\s*\|$')
for it in range(10):
    lines=open(mp).read().split('\n')
    changed=0
    for i,l in enumerate(lines):
        m=pat.match(l)
        if not m: continue
        f,v=m.group(1),m.group(2).strip()
        if not v.isdigit() or not os.path.exists(f): continue
        a=open(f,'rb').read().count(b'\n')
        if a!=int(v):
            changed+=1
            lines[i]="| `%s` | %d |"%(f,a)
    if not changed:
        print("fixed point after %d pass(es)"%it); break
    open(mp,'w').write('\n'.join(lines))
else:
    print("did not converge"); sys.exit(1)
