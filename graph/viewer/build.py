#!/usr/bin/env python3
"""Build a connection-graph viewer HTML file from a `graph-cli json` export.

template-sky.html, the two-plane closeness sky, is the product's only graph presentation.
It declares the __GRAPH_JSON__ placeholder (its own graph data) and the __VIEWER_CORE_JS__
placeholder, which CORE_FILENAME (sky_lens.mjs, the connection lens's pure neighbor-selection
logic) fills: this script inlines CORE_FILENAME's exact contents into the template's single
script block by stripping the `export ` keyword from its `export function` / `export const`
declarations -- nothing else about the file's text changes. The regex used for stripping
exports is literally:

    re.sub(r"(?m)^export (function|const)\\b", r"\\1", core_src)

Core inlining is skipped entirely for a template that omits __VIEWER_CORE_JS__ (CORE_FILENAME
is not even read in that case, and does not need to exist on disk) -- kept as a conditional,
not a hard requirement, so a future template with its logic fully inline again is still a
valid shape.

The RAW graph export is injected the same way it always has been, at the __GRAPH_JSON__ placeholder -- every template must declare that one, exactly once, regardless of whether it also uses the core placeholder.

To verify the shipped script is what it claims to be, extract the built output's single script block and run node's own syntax check on it:

    python3 -c "import re,sys; print(re.search(r'<script>(.*)</script>', \\
      open(sys.argv[1]).read(), re.S).group(1))" out.html > /tmp/extracted.js
    node --check /tmp/extracted.js

That one-liner also works pointed at the template itself (pre-build): __GRAPH_JSON__ and __VIEWER_CORE_JS__ are bare identifiers, which are syntactically valid JavaScript on their own, so an un-built template already passes node --check even though the placeholders it declares are not bound to anything at runtime yet.

usage:
    graph-cli json --chat-db ... --contacts-db ... > exports/graph.json
    python3 build.py exports/graph.json exports/my-graph.html template-sky.html

All three arguments are required.
There is deliberately no default template: a silent default once rendered the wrong design while the output filename said otherwise, and this script would rather fail loudly than repeat that.
"""

import json
import re
import sys
from pathlib import Path

JSON_PLACEHOLDER = "__GRAPH_JSON__"
CORE_PLACEHOLDER = "__VIEWER_CORE_JS__"
CORE_FILENAME = "sky_lens.mjs"


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
    # __GRAPH_JSON__ is required in every template, exactly once: str.replace()
    # below replaces every occurrence, so a stray second mention (e.g. the
    # placeholder name written out in a doc comment) would silently get the
    # payload spliced into the comment too. Fail loudly instead of shipping a
    # corrupted file.
    json_count = template.count(JSON_PLACEHOLDER)
    if json_count == 0:
        print(f"error: {JSON_PLACEHOLDER} not found in template", file=sys.stderr)
        return 1
    if json_count > 1:
        print(f"error: {JSON_PLACEHOLDER} appears {json_count} times in template, expected exactly 1", file=sys.stderr)
        return 1

    # __VIEWER_CORE_JS__ is optional, not required, so this stays a template-shape
    # check rather than a hard requirement: zero occurrences means "skip core
    # inlining entirely" -- CORE_FILENAME is not even read for that build. More
    # than one occurrence is the same corruption risk as __GRAPH_JSON__ above.
    core_count = template.count(CORE_PLACEHOLDER)
    if core_count > 1:
        print(f"error: {CORE_PLACEHOLDER} appears {core_count} times in template, expected 0 or 1", file=sys.stderr)
        return 1

    if core_count == 1:
        core_path = Path(__file__).parent / CORE_FILENAME
        if not core_path.exists():
            print(f"error: {CORE_FILENAME} not found next to build.py: {core_path}", file=sys.stderr)
            return 1
        core_js = strip_exports(core_path.read_text(encoding="utf-8"))
        template = template.replace(CORE_PLACEHOLDER, core_js)

    # Re-serialize rather than splicing the source text: ensure_ascii escapes every
    # non-ASCII name (there are real ones like "Chi Bong"), and escaping "</" keeps a
    # name that contains "</script>" from closing the tag it is embedded in.
    payload = json.dumps(data, ensure_ascii=True, separators=(",", ":"))
    payload = payload.replace("</", "<\\/")

    output = template.replace(JSON_PLACEHOLDER, payload)
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
