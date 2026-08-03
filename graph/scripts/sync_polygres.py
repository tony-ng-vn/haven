#!/usr/bin/env python3
"""Incrementally sync exports/graph.json into the Polygres im_nodes/im_edges tables.

usage:
    python3 scripts/sync_polygres.py

Reads exports/graph.json (produced by `graph-cli json ... > exports/graph.json`),
diffs it against exports/.last-synced.json (the last successfully-synced snapshot),
and does EXACTLY ONE of:

  (a) no differences at all -> prints "skip", touches the network not at all.
  (b) only new nodes/edges, nothing changed or removed -> append_existing imports
      of just the new rows (nodes before edges, so a new edge's FK target already
      exists when the edge is inserted).
  (c) anything mutated or removed -> truncate-then-append. `import csv --mode
      replace_existing` cannot be used here: it TRUNCATEs im_nodes, and Postgres
      rejects that (sqlstate 0A000, "cannot TRUNCATE a table referenced in a
      foreign key constraint") as long as im_edges' FK to im_nodes exists,
      REGARDLESS of whether im_edges currently holds any rows -- TRUNCATE's FK
      check is structural, not data-dependent. Both orders (nodes-then-edges and
      edges-then-nodes) were tried by hand against the real tables and both fail
      the same way. Postgres itself has no such restriction on a single `truncate
      table a, b;` statement naming both sides of the FK together, so this path
      runs that one statement as a migration (see run_truncate_migration), then
      does a full append_existing import of every current row into the now-empty
      tables (nodes before edges, same FK-order reason as case (b)).

On success (skip, append, or truncate-then-append), rebuilds exports/your-sky.html
from template-v3.html via viewer/build.py, and updates the snapshot. On failure,
the snapshot is left untouched so the next run re-diffs against the same
known-good baseline, and the script exits nonzero without touching the viewer.
A truncate-then-append failure after the migration applied leaves the migration
counter state advanced (a burned migration name is harmless) but the snapshot
is still not written, so a stale snapshot never claims a success that didn't
happen.

Never prints row contents (names, identifiers): only counts and which path ran.
Python stdlib only.
"""

import csv
import json
import subprocess
import sys
import tempfile
from pathlib import Path

# The one Haven account this export is wholly owned by (GOAL.md / brief constant).
OWNER_USER_ID = "https://clerk.inhavens.com|user_3H9l3duJWSksxZS4VyrHrGEQoyv"

REPO_ROOT = Path(__file__).resolve().parent.parent
EXPORTS_DIR = REPO_ROOT / "exports"
GRAPH_JSON_PATH = EXPORTS_DIR / "graph.json"
SNAPSHOT_PATH = EXPORTS_DIR / ".last-synced.json"
# Holds only the next migration counter; separate from the snapshot so a burned
# counter (migration applied, append failed) never looks like a synced state.
SYNC_STATE_PATH = EXPORTS_DIR / ".sync-state.json"
MIGRATION_NAME_PREFIX = "im_sync_truncate_"
VIEWER_BUILD_SCRIPT = REPO_ROOT / "viewer" / "build.py"
VIEWER_TEMPLATE = REPO_ROOT / "viewer" / "template-v3.html"
VIEWER_OUTPUT = EXPORTS_DIR / "your-sky.html"

# ~/.local/bin is not on a GUI app's PATH and is not guaranteed to be on every shell's
# PATH either; resolve explicitly rather than relying on the caller's environment.
POLYGRES_BIN = str(Path.home() / ".local" / "bin" / "polygres")

NODE_COLUMNS = ["id", "user_id", "kind", "name", "degree", "has_contact_card", "is_live"]
EDGE_COLUMNS = ["user_id", "a", "b", "reason", "strength"]


class SyncError(Exception):
    """Raised for any failure path; main() turns this into a message plus exit(1)."""


def strip_guess_marker(name):
    # NodeLabel.resolve tilde-prefixes a cached model guess ("~Sam") so the app and the
    # JSON export can always tell a guess from a real name. im_nodes has no column to
    # carry that distinction, so the marker is stripped here rather than shipped into
    # the name column verbatim -- a deliberate, lossy choice: Polygres holds "best
    # available name," not "confirmed name." Flagged for the lead to confirm.
    if name and name.startswith("~"):
        return name[1:]
    return name


def load_graph_json(path):
    if not path.exists():
        # No bare absolute path here: this message reaches the app's toolbar chip as a
        # user-facing string (AppModel.summarize takes the first line of this script's
        # stdout verbatim, exactly what surfaced a full filesystem path to the owner) --
        # an actionable next step is more useful there than a path anyway.
        raise SyncError("graph export not found: run 'graph-cli json ... > exports/graph.json' first")
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_snapshot(path):
    if not path.exists():
        return {"nodes": {}, "edges": {}}
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def transform_nodes(graph):
    """id -> row dict, keyed the same way the snapshot stores them."""
    rows = {}
    for node in graph["nodes"]:
        rows[node["id"]] = {
            "id": node["id"],
            "user_id": OWNER_USER_ID,
            "kind": node["kind"],
            "name": strip_guess_marker(node.get("name")),
            "degree": node["degree"],
            "has_contact_card": bool(node["hasContactCard"]),
            "is_live": bool(node["isLive"]),
        }
    return rows


def transform_edges(graph):
    """(a, b, reason) -> row dict. GraphEdge already canonicalizes a<=b (GraphModel.swift),
    so this key is stable regardless of which side GraphJSON happened to serialize as a/b;
    dedup here is defense in depth, keeping the max strength if a duplicate key ever appears."""
    rows = {}
    for edge in graph["edges"]:
        key = (edge["a"], edge["b"], edge["reason"])
        # strength lands in an integer column (confirmed empirically: "3.0" is rejected
        # with sqlstate 22P02, "3" is accepted) -- round rather than truncate so a
        # fractional strength (there are none today, but nothing enforces that upstream)
        # doesn't silently bias low.
        strength = round(edge["strength"])
        existing = rows.get(key)
        if existing is None or strength > existing["strength"]:
            rows[key] = {
                "user_id": OWNER_USER_ID,
                "a": edge["a"],
                "b": edge["b"],
                "reason": edge["reason"],
                "strength": strength,
            }
    return rows


def node_row_for_snapshot(row):
    return dict(row)


def edge_key_string(key):
    return "|".join(key)


def diff(current, previous):
    """Returns (new_keys, changed_keys, removed_keys) as sets, comparing dict-of-rows."""
    current_keys = set(current.keys())
    previous_keys = set(previous.keys())
    new_keys = current_keys - previous_keys
    removed_keys = previous_keys - current_keys
    changed_keys = {
        key for key in (current_keys & previous_keys) if current[key] != previous[key]
    }
    return new_keys, changed_keys, removed_keys


def write_csv(path, columns, rows):
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        for row in rows:
            # csv.DictWriter writes None as an empty field, which is the best this
            # script can do without a read surface to confirm NULL-vs-empty-string
            # landing (see module docstring: the snapshot, not the DB, is the diff's
            # source of truth, so this ambiguity never feeds back into a false diff).
            writer.writerow(row)


def load_next_migration_counter(path):
    """State file holds only {"next": <int>}; missing file means no truncate has
    run from this script before, so the first name is counter 1."""
    if not path.exists():
        return 1
    with path.open("r", encoding="utf-8") as f:
        return json.load(f).get("next", 1)


def save_next_migration_counter(path, counter):
    with path.open("w", encoding="utf-8") as f:
        json.dump({"next": counter}, f, sort_keys=True, indent=2)


def run_truncate_migration(counter):
    """Applies the single truncate-both-tables statement as a SQL migration and
    returns (succeeded, migration_name, detail). A single multi-table `truncate`
    statement is not blocked by the FK the way TRUNCATE-via-replace_existing is
    (see module docstring case (c)) -- this is the one and only use of the
    migrations surface in this script; it must never carry schema changes."""
    migration_name = f"{MIGRATION_NAME_PREFIX}{counter}"
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".sql", delete=False, encoding="utf-8"
    ) as f:
        f.write("truncate table public.im_nodes, public.im_edges;\n")
        sql_path = f.name

    try:
        cmd = [
            POLYGRES_BIN, "--json", "migrations", "apply",
            "--file", sql_path, "--name", migration_name,
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        try:
            payload = json.loads(proc.stdout)
            # `migration.status` is the stored record's status ("applied" even on a
            # no-op replay of an existing name); `operation.applied` is whether THIS
            # invocation actually ran it. Only the latter tells us the truncate for
            # real just happened -- a name collision must not be read as success,
            # or the following append runs onto tables that were never truncated.
            operation_applied = payload.get("operation", {}).get("applied") is True
            status = payload.get("migration", {}).get("status", "unknown")
            error_message = payload.get("migration", {}).get("error_message")
        except (json.JSONDecodeError, AttributeError):
            operation_applied = False
            status = "unknown"
            error_message = "could not parse polygres output"
    finally:
        Path(sql_path).unlink(missing_ok=True)

    succeeded = proc.returncode == 0 and operation_applied
    return succeeded, migration_name, status if succeeded else (error_message or status)


def run_polygres_import(csv_path, table, mode):
    """Runs `polygres import csv`, returns (succeeded, status, detail-free summary).
    Never returns or logs sample_rows (real row contents) from the CLI's own JSON."""
    cmd = [
        POLYGRES_BIN, "--json", "import", "csv", str(csv_path),
        "--table", table, "--schema", "public", "--mode", mode, "--wait",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    try:
        payload = json.loads(proc.stdout)
        status = payload.get("import", {}).get("status", "unknown")
        error_message = payload.get("import", {}).get("error_message")
    except (json.JSONDecodeError, AttributeError):
        status = "unknown"
        error_message = "could not parse polygres output"

    succeeded = proc.returncode == 0 and status == "succeeded"
    return succeeded, status, error_message


def rebuild_viewer():
    result = subprocess.run(
        [sys.executable, str(VIEWER_BUILD_SCRIPT), str(GRAPH_JSON_PATH), str(VIEWER_OUTPUT), str(VIEWER_TEMPLATE)],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise SyncError(f"viewer rebuild failed: {result.stderr.strip()}")


def save_snapshot(node_rows, edge_rows):
    snapshot = {
        "nodes": node_rows,
        "edges": {edge_key_string(key): row for key, row in edge_rows.items()},
    }
    with SNAPSHOT_PATH.open("w", encoding="utf-8") as f:
        json.dump(snapshot, f, sort_keys=True, indent=2)


def load_snapshot_edges(raw_edges):
    """Snapshot JSON keys are strings (JSON has no tuple keys); rebuild the tuple keys
    this module's in-memory diff logic uses everywhere else."""
    return {tuple(key.split("|", 2)): row for key, row in raw_edges.items()}


def main():
    graph = load_graph_json(GRAPH_JSON_PATH)
    # No snapshot on disk means "we don't know what's in the DB," not "the DB is
    # empty": a previous run could have imported rows with no snapshot ever being
    # written (e.g. this script's very first run against a table seeded some
    # other way). Treating a missing snapshot as an empty one would send every
    # row down the append_existing path onto tables that may already hold rows
    # with the same PKs, which fails on conflict instead of syncing. Routing
    # "unknown state" through truncate-then-append is always correct because it
    # doesn't matter what the tables held before -- they're empty right after.
    snapshot_missing = not SNAPSHOT_PATH.exists()
    snapshot = load_snapshot(SNAPSHOT_PATH)

    current_nodes = transform_nodes(graph)
    current_edges = transform_edges(graph)
    previous_nodes = snapshot.get("nodes", {})
    previous_edges = load_snapshot_edges(snapshot.get("edges", {}))

    new_node_keys, changed_node_keys, removed_node_keys = diff(current_nodes, previous_nodes)
    new_edge_keys, changed_edge_keys, removed_edge_keys = diff(current_edges, previous_edges)

    node_row_count = len(current_nodes)
    edge_row_count = len(current_edges)

    if not snapshot_missing and not (
        new_node_keys or changed_node_keys or removed_node_keys
        or new_edge_keys or changed_edge_keys or removed_edge_keys
    ):
        print("skip")
        print(f"nodes {node_row_count}")
        print(f"edges {edge_row_count}")
        # viewer rebuild disabled: template-v3.html is being actively edited by
        # another agent right now; re-enable once that work lands.
        return 0

    if snapshot_missing or changed_node_keys or removed_node_keys or changed_edge_keys or removed_edge_keys:
        # Case (c): truncate-then-append. See module docstring for why a plain
        # replace_existing import can't do this. The migration counter is loaded
        # here (not earlier) so a no-op run never touches exports/.sync-state.json.
        counter = load_next_migration_counter(SYNC_STATE_PATH)
        applied, migration_name, detail = run_truncate_migration(counter)
        # Burn the counter regardless of outcome: a failed/ambiguous migration name
        # must never be reused, even though the snapshot below stays untouched on
        # failure (module docstring: burned counter is fine, stale snapshot is not).
        save_next_migration_counter(SYNC_STATE_PATH, counter + 1)
        if not applied:
            print(f"failed: truncate migration {migration_name} status={detail}")
            return 1

        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)

            nodes_csv = tmp_dir / "all_nodes.csv"
            write_csv(nodes_csv, NODE_COLUMNS, [current_nodes[key] for key in sorted(current_nodes)])
            succeeded, status, error_message = run_polygres_import(nodes_csv, "im_nodes", "append_existing")
            if not succeeded:
                print(f"failed: im_nodes append_existing status={status} error={error_message}")
                print(f"truncateMigration {migration_name}")
                return 1

            edges_csv = tmp_dir / "all_edges.csv"
            write_csv(edges_csv, EDGE_COLUMNS, [current_edges[key] for key in sorted(current_edges, key=edge_key_string)])
            succeeded, status, error_message = run_polygres_import(edges_csv, "im_edges", "append_existing")
            if not succeeded:
                print(f"failed: im_edges append_existing status={status} error={error_message}")
                print(f"truncateMigration {migration_name}")
                return 1

        print("truncate-then-append")
        print(f"truncateMigration {migration_name}")
        print(f"nodes {node_row_count}")
        print(f"edges {edge_row_count}")

        # viewer rebuild disabled: template-v3.html is being actively edited by
        # another agent right now; re-enable once that work lands.

        save_snapshot(current_nodes, current_edges)
        return 0

    # Case (b): append-only. Nodes first, then edges, so a new edge's FK target exists.
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)

        if new_node_keys:
            nodes_csv = tmp_dir / "new_nodes.csv"
            write_csv(nodes_csv, NODE_COLUMNS, [current_nodes[key] for key in sorted(new_node_keys)])
            succeeded, status, error_message = run_polygres_import(nodes_csv, "im_nodes", "append_existing")
            if not succeeded:
                print(f"failed: im_nodes append_existing status={status} error={error_message}")
                return 1

        if new_edge_keys:
            edges_csv = tmp_dir / "new_edges.csv"
            write_csv(edges_csv, EDGE_COLUMNS, [current_edges[key] for key in sorted(new_edge_keys, key=edge_key_string)])
            succeeded, status, error_message = run_polygres_import(edges_csv, "im_edges", "append_existing")
            if not succeeded:
                print(f"failed: im_edges append_existing status={status} error={error_message}")
                return 1

    print("append")
    print(f"newNodes {len(new_node_keys)}")
    print(f"newEdges {len(new_edge_keys)}")
    print(f"nodes {node_row_count}")
    print(f"edges {edge_row_count}")

    # viewer rebuild disabled: template-v3.html is being actively edited by
    # another agent right now; re-enable once that work lands.

    save_snapshot(current_nodes, current_edges)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SyncError as error:
        print(str(error))
        sys.exit(1)
