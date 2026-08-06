"""Knowledge entities: canonical mirrors of Convex people and provisional
references. The Convex person id is an opaque external mapping only."""

from __future__ import annotations

import uuid
from typing import Any

import psycopg

from . import db
from .identity import normalize_name


def mirror_convex_person(
    conn: psycopg.Connection,
    owner_id: uuid.UUID,
    convex_person_id: str,
    display_name: str,
) -> uuid.UUID:
    """Idempotently mirror one Convex person as a canonical entity."""
    if not convex_person_id.strip() or not display_name.strip():
        raise ValueError("convex_person_id and display_name are required")
    with db.transaction(conn) as cur:
        cur.execute(
            """
            select id from haven_knowledge.knowledge_entities
            where owner_id = %s and convex_person_id = %s and deleted_at is null
            """,
            (owner_id, convex_person_id),
        )
        row = cur.fetchone()
        if row is not None:
            # Keep the mirror's display name current; the entity is a node,
            # not a second profile, so name is the only thing refreshed.
            cur.execute(
                """
                update haven_knowledge.knowledge_entities
                set display_name = %s, normalized_name = %s, updated_at = now()
                where id = %s and display_name is distinct from %s
                """,
                (display_name, normalize_name(display_name), row["id"], display_name),
            )
            return row["id"]
        cur.execute(
            """
            insert into haven_knowledge.knowledge_entities
                (owner_id, entity_type, entity_state, display_name, normalized_name,
                 convex_person_id)
            values (%s, 'person', 'canonical', %s, %s, %s)
            returning id
            """,
            (owner_id, display_name, normalize_name(display_name), convex_person_id),
        )
        return cur.fetchone()["id"]


def create_provisional_person(
    cur: psycopg.Cursor,
    owner_id: uuid.UUID,
    surface_text: str,
) -> uuid.UUID:
    """Create an unresolved provisional person for a mention. Never merges by
    name: two mentions of "Alex" in different entries create one provisional
    per normalized surface within this owner, found by exact normalized match
    among unresolved provisionals (same-name reuse keeps recall coherent
    without asserting identity with any canonical Alex)."""
    normalized = normalize_name(surface_text)
    cur.execute(
        """
        select id from haven_knowledge.knowledge_entities
        where owner_id = %s and entity_state = 'provisional'
          and resolution_status = 'unresolved' and normalized_name = %s
          and deleted_at is null
        limit 1
        """,
        (owner_id, normalized),
    )
    row = cur.fetchone()
    if row is not None:
        return row["id"]
    cur.execute(
        """
        insert into haven_knowledge.knowledge_entities
            (owner_id, entity_type, entity_state, display_name, normalized_name,
             resolution_status)
        values (%s, 'person', 'provisional', %s, %s, 'unresolved')
        returning id
        """,
        (owner_id, surface_text.strip(), normalized),
    )
    return cur.fetchone()["id"]


def get_entity(
    conn: psycopg.Connection, owner_id: uuid.UUID, entity_id: uuid.UUID
) -> dict[str, Any] | None:
    with conn.cursor() as cur:
        cur.execute(
            """
            select * from haven_knowledge.knowledge_entities
            where id = %s and owner_id = %s and deleted_at is null
            """,
            (entity_id, owner_id),
        )
        return cur.fetchone()


def entity_public_view(row: dict[str, Any]) -> dict[str, Any]:
    """The shape safe to return: no owner ids, no internal timestamps."""
    return {
        "entity_id": str(row["id"]),
        "entity_type": row["entity_type"],
        "entity_state": row["entity_state"],
        "display_name": row["display_name"],
        "convex_person_id": row["convex_person_id"],
        "resolution_status": row["resolution_status"],
        "resolved_to_entity_id": (
            str(row["resolved_to_entity_id"]) if row["resolved_to_entity_id"] else None
        ),
    }
