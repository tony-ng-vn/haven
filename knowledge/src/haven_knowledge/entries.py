"""Source-entry lifecycle: create, revise, delete, read. The synchronous
capture transaction saves the raw source, makes it text-searchable, and
enqueues background work atomically; it never waits on a model."""

from __future__ import annotations

import datetime as dt
import hashlib
import uuid
from typing import Any

import psycopg

from . import db
from .config import new_request_id

MAX_RAW_TEXT_CHARS = 20_000

KNOWN_SOURCE_TYPES = {
    "typed",
    "dictated",
    "imported",
    "screenshot",
    "legacy_convex_context",
    "system_test",
}


def content_hash(raw_text: str) -> str:
    return hashlib.sha256(raw_text.encode("utf-8")).hexdigest()


def validate_raw_text(raw_text: str) -> str:
    if not raw_text or not raw_text.strip():
        raise ValueError("raw_text must be non-empty")
    if len(raw_text) > MAX_RAW_TEXT_CHARS:
        raise ValueError(f"raw_text exceeds {MAX_RAW_TEXT_CHARS} characters")
    return raw_text


def _enqueue(
    cur: psycopg.Cursor,
    owner_id: uuid.UUID,
    job_type: str,
    idempotency_key: str,
    source_entry_id: uuid.UUID | None = None,
    source_entry_version_id: uuid.UUID | None = None,
    payload: dict[str, Any] | None = None,
) -> None:
    cur.execute(
        """
        insert into haven_knowledge.knowledge_outbox
            (owner_id, job_type, source_entry_id, source_entry_version_id,
             idempotency_key, payload)
        values (%s, %s, %s, %s, %s, %s)
        on conflict (idempotency_key) do nothing
        """,
        (
            owner_id,
            job_type,
            source_entry_id,
            source_entry_version_id,
            idempotency_key,
            psycopg.types.json.Jsonb(payload or {}),
        ),
    )


def _insert_raw_retrieval_item(
    cur: psycopg.Cursor,
    owner_id: uuid.UUID,
    primary_entity_id: uuid.UUID,
    entry_id: uuid.UUID,
    version_id: uuid.UUID,
    raw_text: str,
) -> uuid.UUID:
    cur.execute(
        """
        insert into haven_knowledge.retrieval_items
            (owner_id, primary_entity_id, item_kind, source_entry_id,
             source_entry_version_id, retrieval_text, text_hash)
        values (%s, %s, 'raw_source', %s, %s, %s, %s)
        returning id
        """,
        (owner_id, primary_entity_id, entry_id, version_id, raw_text, content_hash(raw_text)),
    )
    return cur.fetchone()["id"]


def create_source_entry(
    conn: psycopg.Connection,
    owner_id: uuid.UUID,
    *,
    primary_entity_id: uuid.UUID,
    raw_text: str,
    source_type: str,
    captured_at: dt.datetime | None = None,
    idempotency_key: str | None = None,
) -> dict[str, Any]:
    raw_text = validate_raw_text(raw_text)
    if source_type not in KNOWN_SOURCE_TYPES:
        raise ValueError(f"unknown source_type {source_type!r}")
    request_id = new_request_id()
    captured = captured_at or dt.datetime.now(dt.timezone.utc)

    with db.transaction(conn) as cur:
        # v0 accepts person_anchored only; the scope column already supports
        # global entries for the future interface.
        cur.execute(
            """
            select id, entity_state from haven_knowledge.knowledge_entities
            where id = %s and owner_id = %s and deleted_at is null
            """,
            (primary_entity_id, owner_id),
        )
        entity = cur.fetchone()
        if entity is None:
            raise ValueError("primary person not found for this owner")
        if entity["entity_state"] != "canonical":
            raise ValueError("primary person must be a canonical entity")

        cur.execute(
            """
            insert into haven_knowledge.source_entries
                (owner_id, scope, primary_entity_id, source_type, client_idempotency_key)
            values (%s, 'person_anchored', %s, %s, %s)
            on conflict (owner_id, client_idempotency_key)
                where client_idempotency_key is not null
            do nothing
            returning id
            """,
            (owner_id, primary_entity_id, source_type, idempotency_key),
        )
        inserted = cur.fetchone()
        if inserted is None:
            cur.execute(
                """
                select id, current_version_id from haven_knowledge.source_entries
                where owner_id = %s and client_idempotency_key = %s
                """,
                (owner_id, idempotency_key),
            )
            existing = cur.fetchone()
            if existing is None or existing["current_version_id"] is None:
                raise RuntimeError("idempotent source entry is not visible; retry")
            return {
                "status": "already",
                "source_entry_id": str(existing["id"]),
                "source_entry_version_id": str(existing["current_version_id"]),
                "request_id": request_id,
                "raw_searchable": True,
            }
        entry_id = inserted["id"]
        cur.execute(
            """
            insert into haven_knowledge.source_entry_versions
                (owner_id, source_entry_id, version_number, raw_text, captured_at,
                 content_hash)
            values (%s, %s, 1, %s, %s, %s)
            returning id
            """,
            (owner_id, entry_id, raw_text, captured, content_hash(raw_text)),
        )
        version_id = cur.fetchone()["id"]
        cur.execute(
            "update haven_knowledge.source_entries set current_version_id = %s, updated_at = now() where id = %s",
            (version_id, entry_id),
        )
        item_id = _insert_raw_retrieval_item(
            cur, owner_id, primary_entity_id, entry_id, version_id, raw_text
        )
        _enqueue(
            cur, owner_id, "extract_source", f"extract:{version_id}",
            source_entry_id=entry_id, source_entry_version_id=version_id,
        )
        _enqueue(
            cur, owner_id, "embed_retrieval_item", f"embed:{item_id}",
            source_entry_id=entry_id, source_entry_version_id=version_id,
            payload={"retrieval_item_id": str(item_id)},
        )

    return {
        "status": "created",
        "source_entry_id": str(entry_id),
        "source_entry_version_id": str(version_id),
        "primary_entity_id": str(primary_entity_id),
        "processing_status": "queued",
        "raw_searchable": True,
        "request_id": request_id,
    }


def _deactivate_version_derivations(
    cur: psycopg.Cursor,
    owner_id: uuid.UUID,
    version_id: uuid.UUID,
    new_status: str,
) -> None:
    """Supersede or delete everything derived from one version, in one
    transaction with whatever triggered it."""
    timestamp_col = "superseded_at" if new_status == "superseded" else "deleted_at"
    cur.execute(
        f"""
        update haven_knowledge.source_entry_versions
        set lifecycle_status = %s, {timestamp_col} = now()
        where owner_id = %s and id = %s and lifecycle_status <> %s
        """,
        (new_status, owner_id, version_id, new_status),
    )
    cur.execute(
        f"""
        update haven_knowledge.entity_mentions
        set lifecycle_status = %s, {timestamp_col} = now()
        where owner_id = %s and source_entry_version_id = %s
          and lifecycle_status <> %s
        """,
        (new_status, owner_id, version_id, new_status),
    )
    cur.execute(
        f"""
        update haven_knowledge.knowledge_claims
        set lifecycle_status = %s, {timestamp_col} = now()
        where owner_id = %s and source_entry_version_id = %s
          and lifecycle_status = 'active'
        """,
        (new_status, owner_id, version_id),
    )
    cur.execute(
        """
        update haven_knowledge.entity_relations r
        set lifecycle_status = c.lifecycle_status,
            deleted_at = case when c.lifecycle_status = 'deleted' then now() else r.deleted_at end
        from haven_knowledge.knowledge_claims c
        where r.source_claim_id = c.id and r.owner_id = %s
          and c.source_entry_version_id = %s and r.lifecycle_status = 'active'
        """,
        (owner_id, version_id),
    )
    item_status = "superseded" if new_status == "superseded" else "deleted"
    cur.execute(
        """
        update haven_knowledge.retrieval_items
        set lifecycle_status = %s,
            deleted_at = case when %s = 'deleted' then now() else deleted_at end,
            updated_at = now()
        where owner_id = %s and source_entry_version_id = %s
          and lifecycle_status = 'active'
        """,
        (item_status, item_status, owner_id, version_id),
    )


def _sweep_unsupported_provisionals(cur: psycopg.Cursor, owner_id: uuid.UUID) -> int:
    """Mark provisional entities deleted when no active claim or relation
    supports them any more (decision: deletion recomputes provisional
    support)."""
    cur.execute(
        """
        update haven_knowledge.knowledge_entities e
        set deleted_at = now(), updated_at = now()
        where e.owner_id = %s and e.entity_state = 'provisional' and e.deleted_at is null
          and e.resolution_status = 'unresolved'
          and not exists (
              select 1 from haven_knowledge.knowledge_claims c
              where c.owner_id = e.owner_id and c.lifecycle_status = 'active'
                and (c.subject_entity_id = e.id or c.object_entity_id = e.id)
          )
          and not exists (
              select 1 from haven_knowledge.entity_mentions m
              where m.owner_id = e.owner_id and m.entity_id = e.id
                and m.lifecycle_status = 'active'
          )
        """,
        (owner_id,),
    )
    return cur.rowcount


def revise_source_entry(
    conn: psycopg.Connection,
    owner_id: uuid.UUID,
    *,
    source_entry_id: uuid.UUID,
    raw_text: str,
    captured_at: dt.datetime | None = None,
) -> dict[str, Any]:
    raw_text = validate_raw_text(raw_text)
    request_id = new_request_id()
    captured = captured_at or dt.datetime.now(dt.timezone.utc)

    with db.transaction(conn) as cur:
        cur.execute(
            """
            select e.id, e.primary_entity_id, e.current_version_id, v.version_number
            from haven_knowledge.source_entries e
            join haven_knowledge.source_entry_versions v on v.id = e.current_version_id
            where e.id = %s and e.owner_id = %s and e.lifecycle_status = 'active'
            for update of e
            """,
            (source_entry_id, owner_id),
        )
        entry = cur.fetchone()
        if entry is None:
            raise ValueError("source entry not found for this owner")

        cur.execute(
            """
            insert into haven_knowledge.source_entry_versions
                (owner_id, source_entry_id, version_number, raw_text, captured_at,
                 supersedes_version_id, content_hash)
            values (%s, %s, %s, %s, %s, %s, %s)
            returning id
            """,
            (
                owner_id, source_entry_id, entry["version_number"] + 1, raw_text,
                captured, entry["current_version_id"], content_hash(raw_text),
            ),
        )
        new_version_id = cur.fetchone()["id"]
        cur.execute(
            "update haven_knowledge.source_entries set current_version_id = %s, updated_at = now() where id = %s",
            (new_version_id, source_entry_id),
        )
        _deactivate_version_derivations(cur, owner_id, entry["current_version_id"], "superseded")
        _sweep_unsupported_provisionals(cur, owner_id)
        item_id = _insert_raw_retrieval_item(
            cur, owner_id, entry["primary_entity_id"], source_entry_id, new_version_id, raw_text
        )
        _enqueue(
            cur, owner_id, "extract_source", f"extract:{new_version_id}",
            source_entry_id=source_entry_id, source_entry_version_id=new_version_id,
        )
        _enqueue(
            cur, owner_id, "embed_retrieval_item", f"embed:{item_id}",
            source_entry_id=source_entry_id, source_entry_version_id=new_version_id,
            payload={"retrieval_item_id": str(item_id)},
        )

    return {
        "status": "revised",
        "source_entry_id": str(source_entry_id),
        "source_entry_version_id": str(new_version_id),
        "raw_searchable": True,
        "request_id": request_id,
    }


def delete_source_entry(
    conn: psycopg.Connection,
    owner_id: uuid.UUID,
    *,
    source_entry_id: uuid.UUID,
) -> dict[str, Any]:
    request_id = new_request_id()
    with db.transaction(conn) as cur:
        cur.execute(
            """
            update haven_knowledge.source_entries
            set lifecycle_status = 'deleted', deleted_at = now(), updated_at = now()
            where id = %s and owner_id = %s and lifecycle_status = 'active'
            returning id
            """,
            (source_entry_id, owner_id),
        )
        if cur.fetchone() is None:
            raise ValueError("source entry not found for this owner")
        cur.execute(
            "select id from haven_knowledge.source_entry_versions where source_entry_id = %s and owner_id = %s",
            (source_entry_id, owner_id),
        )
        version_ids = [row["id"] for row in cur.fetchall()]
        for version_id in version_ids:
            _deactivate_version_derivations(cur, owner_id, version_id, "deleted")
        # Retrieval items for old versions were already superseded; deletion
        # must remove those from every surface too.
        cur.execute(
            """
            update haven_knowledge.retrieval_items
            set lifecycle_status = 'deleted', deleted_at = now(), updated_at = now()
            where owner_id = %s and source_entry_id = %s and lifecycle_status <> 'deleted'
            """,
            (owner_id, source_entry_id),
        )
        cur.execute(
            """
            update haven_knowledge.knowledge_claims
            set lifecycle_status = 'deleted', deleted_at = now()
            where owner_id = %s and source_entry_id = %s and lifecycle_status <> 'deleted'
            """,
            (owner_id, source_entry_id),
        )
        cur.execute(
            """
            update haven_knowledge.entity_relations r
            set lifecycle_status = 'deleted', deleted_at = now()
            from haven_knowledge.knowledge_claims c
            where r.source_claim_id = c.id and r.owner_id = %s
              and c.source_entry_id = %s and r.lifecycle_status <> 'deleted'
            """,
            (owner_id, source_entry_id),
        )
        swept = _sweep_unsupported_provisionals(cur, owner_id)
    return {
        "status": "deleted",
        "source_entry_id": str(source_entry_id),
        "provisional_entities_swept": swept,
        "request_id": request_id,
    }


def get_source_entry(
    conn: psycopg.Connection,
    owner_id: uuid.UUID,
    source_entry_id: uuid.UUID,
) -> dict[str, Any] | None:
    with conn.cursor() as cur:
        cur.execute(
            """
            select e.id, e.scope, e.primary_entity_id, e.source_type,
                   e.lifecycle_status, e.created_at, e.updated_at,
                   v.id as version_id, v.version_number, v.raw_text, v.captured_at
            from haven_knowledge.source_entries e
            left join haven_knowledge.source_entry_versions v on v.id = e.current_version_id
            where e.id = %s and e.owner_id = %s
            """,
            (source_entry_id, owner_id),
        )
        row = cur.fetchone()
        if row is None:
            return None
        if row["lifecycle_status"] == "deleted":
            return {"source_entry_id": str(row["id"]), "lifecycle_status": "deleted"}
        return {
            "source_entry_id": str(row["id"]),
            "scope": row["scope"],
            "primary_entity_id": str(row["primary_entity_id"]),
            "source_type": row["source_type"],
            "lifecycle_status": row["lifecycle_status"],
            "current_version": {
                "version_id": str(row["version_id"]),
                "version_number": row["version_number"],
                "raw_text": row["raw_text"],
                "captured_at": row["captured_at"].isoformat(),
            },
        }


def get_processing_status(
    conn: psycopg.Connection,
    owner_id: uuid.UUID,
    source_entry_id: uuid.UUID,
) -> dict[str, Any]:
    with conn.cursor() as cur:
        cur.execute(
            """
            select job_type, status, attempt_count, last_error_code, source_entry_version_id
            from haven_knowledge.knowledge_outbox
            where owner_id = %s and source_entry_id = %s
            order by created_at
            """,
            (owner_id, source_entry_id),
        )
        jobs = [
            {
                "job_type": r["job_type"],
                "status": r["status"],
                "attempts": r["attempt_count"],
                "error_code": r["last_error_code"],
                "version_id": str(r["source_entry_version_id"]) if r["source_entry_version_id"] else None,
            }
            for r in cur.fetchall()
        ]
        cur.execute(
            """
            select status, extraction_policy_version, model_name, error_code
            from haven_knowledge.extraction_runs
            where owner_id = %s and source_entry_id = %s
            order by created_at
            """,
            (owner_id, source_entry_id),
        )
        runs = [dict(r) for r in cur.fetchall()]
    return {"jobs": jobs, "extraction_runs": runs}
