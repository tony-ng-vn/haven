"""Reference-candidate listing and deliberate resolution. Name similarity
suggests; only explicit confirmation (or, in the future, deterministic
identity evidence) resolves."""

from __future__ import annotations

import hashlib
import uuid
from typing import Any

import psycopg

from . import db
from .entities import entity_public_view


def _candidate_context_hash(
    cur: psycopg.Cursor, owner_id: uuid.UUID, provisional_id: uuid.UUID
) -> str:
    cur.execute(
        """
        select id from haven_knowledge.knowledge_claims
        where owner_id = %s and lifecycle_status = 'active'
          and (subject_entity_id = %s or object_entity_id = %s)
        order by id
        """,
        (owner_id, provisional_id, provisional_id),
    )
    claim_ids = ",".join(str(r["id"]) for r in cur.fetchall())
    return hashlib.sha256(claim_ids.encode()).hexdigest()


def candidate_context_hash(
    conn: psycopg.Connection, owner_id: uuid.UUID, provisional_id: uuid.UUID
) -> str:
    """Hash the active evidence that controls rejected-candidate suppression."""
    with conn.cursor() as cur:
        return _candidate_context_hash(cur, owner_id, provisional_id)


def list_reference_candidates(
    conn: psycopg.Connection, owner_id: uuid.UUID, provisional_id: uuid.UUID
) -> dict[str, Any]:
    with conn.cursor() as cur:
        cur.execute(
            """
            select * from haven_knowledge.knowledge_entities
            where id = %s and owner_id = %s and entity_state = 'provisional'
              and deleted_at is null
            """,
            (provisional_id, owner_id),
        )
        provisional = cur.fetchone()
        if provisional is None:
            raise ValueError("provisional entity not found for this owner")
        context_hash = _candidate_context_hash(cur, owner_id, provisional_id)
        # Similarity suggests candidates among canonical people only.
        cur.execute(
            """
            select e.*, similarity(e.normalized_name, %s) as name_similarity
            from haven_knowledge.knowledge_entities e
            where e.owner_id = %s and e.entity_state = 'canonical'
              and e.entity_type = 'person' and e.deleted_at is null
              and e.normalized_name %% %s
            order by name_similarity desc, e.id
            limit 10
            """,
            (provisional["normalized_name"], owner_id, provisional["normalized_name"]),
        )
        candidates = cur.fetchall()
        cur.execute(
            """
            select candidate_entity_id, decision, candidate_context_hash
            from haven_knowledge.reference_candidate_decisions
            where owner_id = %s and provisional_entity_id = %s
            """,
            (owner_id, provisional_id),
        )
        decisions = {r["candidate_entity_id"]: r for r in cur.fetchall()}

    visible = []
    for c in candidates:
        decision = decisions.get(c["id"])
        if decision is not None and decision["decision"] == "rejected" \
                and decision["candidate_context_hash"] == context_hash:
            continue  # suppressed: rejected and nothing new since
        visible.append(
            {
                **entity_public_view(c),
                "name_similarity": float(c["name_similarity"]),
                "reason": "name_similarity",
                "prior_decision": decision["decision"] if decision else None,
            }
        )
    return {
        "provisional": entity_public_view(provisional),
        "candidates": visible,
        "candidate_context_hash": context_hash,
        "actions": {
            "resolve": "resolve_reference(provisional_id, candidate_id)",
            "reject": "reject_reference_candidate(provisional_id, candidate_id)",
            "not_sure": "mark_reference_not_sure(provisional_id, candidate_id)",
        },
    }


def _record_decision_in_transaction(
    cur: psycopg.Cursor,
    owner_id: uuid.UUID,
    provisional_id: uuid.UUID,
    candidate_id: uuid.UUID,
    decision: str,
    decided_by: str,
) -> None:
    cur.execute(
        """
        select id, entity_state, resolution_status, resolved_to_entity_id
        from haven_knowledge.knowledge_entities
        where owner_id = %s and id = any(%s::uuid[]) and deleted_at is null
        for share
        """,
        (owner_id, [provisional_id, candidate_id]),
    )
    entities = {row["id"]: row for row in cur.fetchall()}
    provisional = entities.get(provisional_id)
    candidate = entities.get(candidate_id)
    if provisional is None or provisional["entity_state"] != "provisional":
        raise ValueError("provisional entity not found for this owner")
    if candidate is None or candidate["entity_state"] != "canonical":
        raise ValueError("candidate entity not found for this owner")
    if decision == "confirmed":
        if (
            provisional["resolution_status"] != "confirmed"
            or provisional["resolved_to_entity_id"] != candidate_id
        ):
            raise ValueError("confirmed decision must match the resolved reference")
    elif provisional["resolution_status"] == "confirmed":
        raise ValueError("reference is already confirmed")

    context_hash = _candidate_context_hash(cur, owner_id, provisional_id)
    cur.execute(
        """
        insert into haven_knowledge.reference_candidate_decisions
            (owner_id, provisional_entity_id, candidate_entity_id, decision,
             candidate_context_hash, decided_by)
        values (%s, %s, %s, %s, %s, %s)
        on conflict (provisional_entity_id, candidate_entity_id)
        do update set decision = excluded.decision,
                      candidate_context_hash = excluded.candidate_context_hash,
                      decided_by = excluded.decided_by,
                      updated_at = now()
        """,
        (owner_id, provisional_id, candidate_id, decision, context_hash, decided_by),
    )


def _record_decision(
    conn: psycopg.Connection,
    owner_id: uuid.UUID,
    provisional_id: uuid.UUID,
    candidate_id: uuid.UUID,
    decision: str,
    decided_by: str,
) -> None:
    with db.transaction(conn) as cur:
        _record_decision_in_transaction(
            cur, owner_id, provisional_id, candidate_id, decision, decided_by
        )


def resolve_reference(
    conn: psycopg.Connection,
    owner_id: uuid.UUID,
    provisional_id: uuid.UUID,
    candidate_id: uuid.UUID,
    decided_by: str = "user_confirmation",
) -> dict[str, Any]:
    with db.transaction(conn) as cur:
        cur.execute(
            """
            select resolution_status, resolved_to_entity_id
            from haven_knowledge.knowledge_entities
            where id = %s and owner_id = %s and deleted_at is null
              and entity_state = 'provisional'
            for update
            """,
            (provisional_id, owner_id),
        )
        provisional = cur.fetchone()
        if provisional is None:
            raise ValueError("provisional entity not found for this owner")
        if (
            provisional["resolution_status"] == "confirmed"
            and provisional["resolved_to_entity_id"] != candidate_id
        ):
            raise ValueError("reference is already resolved to another candidate")
        cur.execute(
            """
            select id from haven_knowledge.knowledge_entities
            where id = %s and owner_id = %s and entity_state = 'canonical'
              and deleted_at is null
            for share
            """,
            (candidate_id, owner_id),
        )
        if cur.fetchone() is None:
            raise ValueError("resolution target must be a canonical entity of this owner")
        cur.execute(
            """
            update haven_knowledge.knowledge_entities
            set resolved_to_entity_id = %s, resolution_status = 'confirmed', updated_at = now()
            where id = %s and owner_id = %s
            """,
            (candidate_id, provisional_id, owner_id),
        )
        # The pointer and its audit decision are one semantic write.
        _record_decision_in_transaction(
            cur, owner_id, provisional_id, candidate_id, "confirmed", decided_by
        )
    # The provisional row, its claims, and its evidence remain: reads follow
    # resolved_to_entity_id one hop to present the canonical identity.
    return {"status": "resolved", "provisional_id": str(provisional_id), "canonical_id": str(candidate_id)}


def reject_reference_candidate(
    conn: psycopg.Connection,
    owner_id: uuid.UUID,
    provisional_id: uuid.UUID,
    candidate_id: uuid.UUID,
    decided_by: str = "user",
) -> dict[str, Any]:
    _record_decision(conn, owner_id, provisional_id, candidate_id, "rejected", decided_by)
    return {"status": "rejected"}


def mark_reference_not_sure(
    conn: psycopg.Connection,
    owner_id: uuid.UUID,
    provisional_id: uuid.UUID,
    candidate_id: uuid.UUID,
    decided_by: str = "user",
) -> dict[str, Any]:
    _record_decision(conn, owner_id, provisional_id, candidate_id, "not_sure", decided_by)
    return {"status": "not_sure"}
