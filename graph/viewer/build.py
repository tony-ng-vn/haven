#!/usr/bin/env python3
"""Build a connection-graph viewer HTML file from a `graph-cli json` export.

TESTED CODE == SHIPPED CODE, mechanically, not by convention:
viewer_core.mjs is the single source of truth for the viewer's pure logic (adapt/degrade, community + region detection, the "everyone here knows each other" tier recompute, shortest path, stale-mark rejection, the deterministic layout).
tests.mjs imports it directly and runs under plain `node`.
This script inlines that EXACT file into template-v4.html's single script block by stripping the `export ` keyword from its `export function` / `export const` declarations -- nothing else about the file's text changes -- and splicing the result in at the __VIEWER_CORE_JS__ placeholder.
The regex is literally:

    re.sub(r"(?m)^export (function|const)\\b", r"\\1", core_src)

The RAW graph export is injected the same way it always has been, at the __GRAPH_JSON__ placeholder.

To verify the shipped script is what it claims to be, extract the built output's single script block and run node's own syntax check on it:

    python3 -c "import re,sys; print(re.search(r'<script>(.*)</script>', \\
      open(sys.argv[1]).read(), re.S).group(1))" out.html > /tmp/extracted.js
    node --check /tmp/extracted.js

That one-liner also works pointed at template-v4.html itself (pre-build): both placeholders are bare identifiers, which are syntactically valid JavaScript on their own, so the un-built template already passes node --check even though neither placeholder is bound to anything at runtime yet.

usage:
    graph-cli json --chat-db ... --contacts-db ... > exports/graph.json
    python3 build.py exports/graph.json exports/my-graph.html template-v4.html

All three arguments are required.
There is deliberately no default template: a silent default once rendered the wrong design while the output filename said otherwise, and this script would rather fail loudly than repeat that.
"""

import json
import re
import sys
from pathlib import Path

JSON_PLACEHOLDER = "__GRAPH_JSON__"
CORE_PLACEHOLDER = "__VIEWER_CORE_JS__"
CORE_FILENAME = "viewer_core.mjs"


def strip_exports(core_src):
    # The one-liner from the header comment, kept in exactly one place so the
    # docstring and the actual behavior can never drift apart.
    return re.sub(r"(?m)^export (function|const)\b", r"\1", core_src)


def main(argv):
    if len(argv) != 4:
        print("error: exactly three arguments are required (json, out, template)", file=sys.stderr)
        print(__doc__, file=sys.stderr)
        return 64

    json_path, out_path, template_path = Path(argv[1]), Path(argv[2]), Path(argv[3])
    if not template_path.exists():
        print(f"error: template not found: {template_path}", file=sys.stderr)
        return 1

    core_path = Path(__file__).parent / CORE_FILENAME
    if not core_path.exists():
        print(f"error: {CORE_FILENAME} not found next to build.py: {core_path}", file=sys.stderr)
        return 1

    raw = json_path.read_text(encoding="utf-8")
    # Parse before injecting: a truncated or error-laden export should fail here
    # with a clear message rather than producing an HTML file that silently
    # renders nothing.
    data = json.loads(raw)
    nodes, edges = data.get("nodes", []), data.get("edges", [])
    if not nodes:
        print("error: export contains no nodes", file=sys.stderr)
        return 1

    template = template_path.read_text(encoding="utf-8")
    # Exactly one, not just "at least one": str.replace() below replaces every
    # occurrence, so a stray second mention (e.g. the placeholder name written out
    # in a doc comment) would silently get the payload spliced into the comment
    # too. Fail loudly instead of shipping a corrupted file.
    for placeholder in (CORE_PLACEHOLDER, JSON_PLACEHOLDER):
        count = template.count(placeholder)
        if count == 0:
            print(f"error: {placeholder} not found in template", file=sys.stderr)
            return 1
        if count > 1:
            print(f"error: {placeholder} appears {count} times in template, expected exactly 1", file=sys.stderr)
            return 1

    core_js = strip_exports(core_path.read_text(encoding="utf-8"))

    # Re-serialize rather than splicing the source text: ensure_ascii escapes every
    # non-ASCII name (there are real ones like "Chi Bong"), and escaping "</" keeps a
    # name that contains "</script>" from closing the tag it is embedded in.
    payload = json.dumps(data, ensure_ascii=True, separators=(",", ":"))
    payload = payload.replace("</", "<\\/")

    output = template.replace(CORE_PLACEHOLDER, core_js).replace(JSON_PLACEHOLDER, payload)
    if CORE_PLACEHOLDER in output or JSON_PLACEHOLDER in output:
        print("error: a placeholder survived substitution -- refusing to write a broken output", file=sys.stderr)
        return 1

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(output, encoding="utf-8")

    kinds = {}
    for n in nodes:
        kinds[n.get("kind", "?")] = kinds.get(n.get("kind", "?"), 0) + 1
    summary = ", ".join(f"{v} {k}" for k, v in sorted(kinds.items()))
    acq = len(data.get("acquaintances", []))
    fully = len(data.get("fullyAcquaintedChatIds", []))
    print(
        f"wrote {out_path} from {template_path.name} "
        f"({summary}, {len(edges)} edges, {acq} acquaintances, {fully} fully-acquainted chats)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
