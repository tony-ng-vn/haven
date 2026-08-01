#!/usr/bin/env python3
"""Inject a `graph-cli json` export into viewer/template.html.

The template holds no data and is safe to commit; the rendered output holds
real names and lands in graph/exports/, which is gitignored (GOAL.md
constraint 3). Keeping the two apart is the whole point of this script.

usage:
    graph-cli json --chat-db ... --contacts-db ... > exports/graph.json
    python3 viewer/build.py exports/graph.json exports/my-graph.html [template.html]

The template defaults to viewer/template.html. Pass a third argument to render a
different one (viewer/template-v3.html is the design-handoff layout).
"""

import json
import sys
from pathlib import Path

PLACEHOLDER = "__GRAPH_JSON__"


def main(argv):
    if len(argv) not in (3, 4):
        print(__doc__, file=sys.stderr)
        return 64

    json_path, out_path = Path(argv[1]), Path(argv[2])
    # Explicit over implicit: silently defaulting to one template while the caller
    # names a different output file is exactly how the wrong design got rendered once.
    template_path = Path(argv[3]) if len(argv) == 4 else Path(__file__).parent / "template.html"
    if not template_path.is_absolute() and not template_path.exists():
        template_path = Path(__file__).parent / template_path.name
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
    if PLACEHOLDER not in template:
        print(f"error: {PLACEHOLDER} not found in template", file=sys.stderr)
        return 1

    # Re-serialize rather than splicing the source text: ensure_ascii escapes every
    # non-ASCII name (there are real ones like "Chi Bong"), and escaping "</" keeps a
    # name that contains "</script>" from closing the tag it is embedded in.
    payload = json.dumps(data, ensure_ascii=True, separators=(",", ":"))
    payload = payload.replace("</", "<\\/")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(template.replace(PLACEHOLDER, payload), encoding="utf-8")

    kinds = {}
    for n in nodes:
        kinds[n.get("kind", "?")] = kinds.get(n.get("kind", "?"), 0) + 1
    summary = ", ".join(f"{v} {k}" for k, v in sorted(kinds.items()))
    print(f"wrote {out_path} from {template_path.name} ({summary}, {len(edges)} edges)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
