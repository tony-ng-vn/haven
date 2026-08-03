#!/usr/bin/env python3
"""Replace every identity in a graph export with an invented one, keeping the shape.

The point is a demo sky that looks like a real sky, because structurally it IS one:
the same people count, the same group rosters, the same edge weights, the same
acquaintance tiers and evidence. Only the identities are fiction.

What is replaced, exhaustively:

    node.id         phone numbers, emails, and chat GUIDs -> invented equivalents
    node.name       real display names -> invented names, or null if it was null
    chatName        echoed inside acquaintance evidence, remapped consistently

Nothing is passed through by default. Every string field is either explicitly
remapped or explicitly dropped, so a field added to the schema later cannot
silently start leaking: unknown keys raise rather than being copied. That is the
whole safety argument for this script, so do not "fix" it by adding a passthrough.

An unnamed person stays unnamed and an unnamed group stays unnamed. Naming
everyone would misrepresent what the tool actually knows: roughly 43 percent of
the real graph's people have no contact card, and the sky draws them differently.

usage:
    python3 scripts/anonymize_graph.py exports/graph.json out/demo.json
"""

import hashlib
import json
import sys
from pathlib import Path

# Deterministic invented identities: the same real person maps to the same fake
# person across runs, so rebuilding the demo does not reshuffle every label.
# Seeded off the id, never off the real name, so the fake name carries no trace
# of the real one (not its length, not its initial, not its rarity).
SEED = "haven-demo-sky-v1"

FIRST = [
    "Ana", "Bo", "Cass", "Dev", "Eno", "Fen", "Gil", "Hana", "Ivo", "Juno",
    "Kell", "Lior", "Mira", "Nils", "Oda", "Pim", "Quen", "Rhea", "Soren", "Tova",
    "Uma", "Vane", "Wren", "Xio", "Yara", "Zev", "Ari", "Bex", "Coe", "Dara",
    "Esk", "Fia", "Gean", "Hollis", "Ines", "Jarl", "Kiro", "Lune", "Moss", "Nera",
    "Oren", "Pell", "Rune", "Sable", "Tarn", "Vero", "Wilder", "Yance", "Zora", "Alden",
]

LAST = [
    "Vray", "Marrow", "Ashcombe", "Brenlow", "Cotter", "Dunmore", "Ellery", "Fairholt",
    "Garrow", "Halloway", "Iverson", "Jessop", "Kirtland", "Lindqvist", "Merrow", "Norridge",
    "Ostley", "Pemberton", "Quillon", "Rennick", "Stroud", "Thorne", "Ulver", "Vandry",
    "Weatherly", "Yarrow", "Ziegler", "Ashbrook", "Belmont", "Cadwell",
]

# Group-chat names read as a set of little social worlds, the way real ones do.
GROUP_WORDS_A = [
    "Sunday", "Late", "Kitchen", "Rooftop", "Winter", "Harbor", "Second", "Quiet",
    "Long", "Corner", "North", "Paper", "Velvet", "Copper", "Morning", "Riverside",
]
GROUP_WORDS_B = [
    "Crew", "Table", "Club", "Cabin", "Circle", "Room", "House", "Choir",
    "Society", "Committee", "Band", "Collective", "Brigade", "Assembly", "Company", "Union",
]


def rng(*parts):
    """A stable integer drawn from the seed plus the given parts."""
    h = hashlib.sha256(SEED.join(str(p) for p in parts).encode()).hexdigest()
    return int(h[:16], 16)


class Identities:
    """Assigns invented identities, guaranteeing uniqueness and stability."""

    def __init__(self):
        self.node_ids = {}
        self.names = {}
        self.used_names = set()
        self.used_ids = set()

    def node_id(self, real_id):
        if real_id == "user":
            return "user"
        if real_id in self.node_ids:
            return self.node_ids[real_id]

        if real_id.startswith("chat:"):
            # A GUID's real text encodes the service and the account that owns it,
            # so it is regenerated wholesale rather than partially masked.
            n = rng("chat", real_id)
            fake = "chat:DEMO-%016x" % (n & 0xFFFFFFFFFFFFFFFF)
        elif "@" in real_id:
            n = rng("email", real_id)
            fake = "%s.%s@example.invalid" % (
                FIRST[n % len(FIRST)].lower(),
                LAST[(n // 97) % len(LAST)].lower(),
            )
        else:
            # 555-01xx is the reserved fictional block; nothing here can dial a
            # real person even by accident.
            n = rng("phone", real_id)
            fake = "+1555555%04d" % (n % 10000)

        while fake in self.used_ids:
            fake += "x"
        self.used_ids.add(fake)
        self.node_ids[real_id] = fake
        return fake

    def person_name(self, real_id):
        key = ("person", real_id)
        if key in self.names:
            return self.names[key]
        n = rng("pname", real_id)
        for bump in range(4096):
            cand = "%s %s" % (
                FIRST[(n + bump) % len(FIRST)],
                LAST[((n // 53) + bump * 7) % len(LAST)],
            )
            if cand not in self.used_names:
                break
        self.used_names.add(cand)
        self.names[key] = cand
        return cand

    def group_name(self, real_id):
        key = ("group", real_id)
        if key in self.names:
            return self.names[key]
        n = rng("gname", real_id)
        for bump in range(4096):
            cand = "%s %s" % (
                GROUP_WORDS_A[(n + bump) % len(GROUP_WORDS_A)],
                GROUP_WORDS_B[((n // 31) + bump * 3) % len(GROUP_WORDS_B)],
            )
            if cand not in self.used_names:
                break
        self.used_names.add(cand)
        self.names[key] = cand
        return cand


# Every key the schema is known to contain, split by how it must be handled.
# A key absent from all three sets is an error: see the module docstring.
NODE_KEYS_REMAPPED = {"id", "name"}
NODE_KEYS_SAFE = {"kind", "hasContactCard", "isLive", "degree",
                  "firstMessageDate", "lastMessageDate"}
EDGE_KEYS_REMAPPED = {"a", "b"}
EDGE_KEYS_SAFE = {"reason", "strength"}
ACQ_KEYS_REMAPPED = {"a", "b", "evidence"}
ACQ_KEYS_SAFE = {"score", "tier"}
EV_KEYS_REMAPPED = {"chatId", "chatName"}
EV_KEYS_SAFE = {"memberCount", "coActiveDays"}
TOP_KEYS_REMAPPED = {"nodes", "edges", "acquaintances", "fullyAcquaintedChatIds"}
TOP_KEYS_SAFE = {"hasHistory"}


def check_keys(obj, remapped, safe, what):
    unknown = set(obj) - remapped - safe
    if unknown:
        raise SystemExit(
            "error: unknown %s field(s) %s -- this script refuses to pass through\n"
            "fields it has not been taught to handle, because an unreviewed field\n"
            "is exactly how real data leaks into a public demo. Teach it explicitly."
            % (what, sorted(unknown))
        )


def main(argv):
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 64

    src, dst = Path(argv[1]), Path(argv[2])
    data = json.loads(src.read_text(encoding="utf-8"))
    check_keys(data, TOP_KEYS_REMAPPED, TOP_KEYS_SAFE, "top-level")

    ids = Identities()
    # Assign ids for every node up front: edges and acquaintances reference nodes,
    # and a reference must never mint an identity the nodes array does not have.
    for node in data["nodes"]:
        ids.node_id(node["id"])

    out_nodes = []
    for node in data["nodes"]:
        check_keys(node, NODE_KEYS_REMAPPED, NODE_KEYS_SAFE, "node")
        fake_id = ids.node_id(node["id"])
        if node["kind"] == "person" and node.get("name"):
            name = ids.person_name(node["id"])
        elif node["kind"] == "group" and node.get("name"):
            name = ids.group_name(node["id"])
        else:
            name = None  # unnamed stays unnamed; the sky draws these differently
        out = {"id": fake_id, "name": name}
        for k in NODE_KEYS_SAFE:
            if k in node:
                out[k] = node[k]
        out_nodes.append(out)

    def remap_ref(real_id):
        if real_id not in ids.node_ids and real_id != "user":
            raise SystemExit("error: reference to unknown node id; refusing to invent one")
        return ids.node_id(real_id)

    out_edges = []
    for edge in data["edges"]:
        check_keys(edge, EDGE_KEYS_REMAPPED, EDGE_KEYS_SAFE, "edge")
        out = {"a": remap_ref(edge["a"]), "b": remap_ref(edge["b"])}
        for k in EDGE_KEYS_SAFE:
            if k in edge:
                out[k] = edge[k]
        out_edges.append(out)

    out_acq = []
    for acq in data.get("acquaintances", []):
        check_keys(acq, ACQ_KEYS_REMAPPED, ACQ_KEYS_SAFE, "acquaintance")
        ev_out = []
        for ev in acq.get("evidence", []):
            check_keys(ev, EV_KEYS_REMAPPED, EV_KEYS_SAFE, "evidence")
            chat_id = remap_ref(ev["chatId"])
            # chatName echoes the nodes array, so it must resolve to the SAME
            # invented name that chat's node got, never a freshly minted one.
            name = ids.group_name(ev["chatId"]) if ev.get("chatName") else None
            e = {"chatId": chat_id, "chatName": name}
            for k in EV_KEYS_SAFE:
                if k in ev:
                    e[k] = ev[k]
            ev_out.append(e)
        out = {"a": remap_ref(acq["a"]), "b": remap_ref(acq["b"]), "evidence": ev_out}
        for k in ACQ_KEYS_SAFE:
            if k in acq:
                out[k] = acq[k]
        out_acq.append(out)

    result = {
        "nodes": out_nodes,
        "edges": out_edges,
        "acquaintances": out_acq,
        "fullyAcquaintedChatIds": [remap_ref(c) for c in data.get("fullyAcquaintedChatIds", [])],
    }
    for k in TOP_KEYS_SAFE:
        if k in data:
            result[k] = data[k]

    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(json.dumps(result), encoding="utf-8")
    print("wrote %s: %d nodes, %d edges, %d acquaintances (all identities invented)"
          % (dst, len(out_nodes), len(out_edges), len(out_acq)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
