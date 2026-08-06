"""Builds the merged graph configuration: everything currently applied plus
the haven_knowledge registrations. haven_users, auth_identities, outbox, and
claims are deliberately not registered; owner_id is a filter column, never a
relationship."""

import json
import sys

with open("scripts/knowledge/graph-config-export.json") as f:
    export = json.load(f)

cfg = export["configuration"]
desired = cfg.get("desired_configuration") or cfg["applied_configuration"]

print("sample table keys:", sorted(desired["registered_tables"][0].keys()), file=sys.stderr)

tables = desired["registered_tables"]
rels = desired["registered_relationships"]
filters = desired.get("filter_columns", [])

names = {(t["schema"], t["table"]) for t in tables}
assert ("haven_knowledge", "knowledge_entities") not in names

tables = tables + [
    {
        "schema": "haven_knowledge",
        "table": "knowledge_entities",
        "id_columns": ["id"],
        "columns": [
            "id", "owner_id", "entity_type", "entity_state", "display_name",
            "normalized_name", "resolution_status",
        ],
        "tenant_column": "owner_id",
    },
    {
        "schema": "haven_knowledge",
        "table": "entity_relations",
        "id_columns": ["id"],
        "columns": [
            "id", "owner_id", "subject_entity_id", "predicate_key",
            "object_entity_id", "lifecycle_status", "confidence",
        ],
        "tenant_column": "owner_id",
    },
]

rels = rels + [
    {
        "from_schema": "haven_knowledge",
        "from_table": "entity_relations",
        "from_column": "subject_entity_id",
        "to_schema": "haven_knowledge",
        "to_table": "knowledge_entities",
        "to_column": "id",
        "label": "entity_relations_subject_entity_id_fkey",
        "bidirectional": True,
    },
    {
        "from_schema": "haven_knowledge",
        "from_table": "entity_relations",
        "from_column": "object_entity_id",
        "to_schema": "haven_knowledge",
        "to_table": "knowledge_entities",
        "to_column": "id",
        "label": "entity_relations_object_entity_id_fkey",
        "bidirectional": True,
    },
]

filters = filters + [
    {"schema": "haven_knowledge", "table": "knowledge_entities", "column": c, "type": t}
    for c, t in [
        ("owner_id", "uuid"), ("entity_state", "text"), ("entity_type", "text"),
        ("display_name", "text"), ("normalized_name", "text"),
        ("resolution_status", "text"),
    ]
] + [
    {"schema": "haven_knowledge", "table": "entity_relations", "column": c, "type": t}
    for c, t in [
        ("owner_id", "uuid"), ("predicate_key", "text"),
        ("lifecycle_status", "text"), ("confidence", "numeric"),
    ]
]

merged = {
    "registered_tables": tables,
    "registered_relationships": rels,
    "filter_columns": filters,
}

with open("scripts/knowledge/graph-config-merged.json", "w") as f:
    json.dump({"configuration": merged}, f, indent=2)
print("wrote scripts/knowledge/graph-config-merged.json:",
      len(tables), "tables,", len(rels), "relationships", file=sys.stderr)
