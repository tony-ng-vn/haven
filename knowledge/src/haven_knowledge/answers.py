"""Deterministic relationship answers. Evidence is rendered directly; no
generative model sits between retrieval and the response. Unresolved
references answer with explicit qualification, never as confirmed identity
and never as a bare "I don't know"."""

from __future__ import annotations

import uuid
from typing import Any

import psycopg

from .entities import entity_public_view
from .references import list_reference_candidates
from .retrieval import fuzzy_person_lookup
from .router import QueryPlan

RELATIONSHIP_PREDICATES = ("introduced_by", "met_through", "met_at", "knows", "collaborated_with")


def _active_relationship_claims(
    conn: psycopg.Connection, owner_id: uuid.UUID, entity_id: uuid.UUID
) -> list[dict[str, Any]]:
    with conn.cursor() as cur:
        cur.execute(
            """
            select c.*, s.display_name as subject_name, s.entity_state as subject_state,
                   s.resolution_status as subject_resolution,
                   s.resolved_to_entity_id as subject_resolved_to,
                   resolved_s.display_name as subject_resolved_name,
                   resolved_s.convex_person_id as subject_resolved_convex_person_id,
                   o.display_name as object_name, o.entity_state as object_state,
                   o.resolution_status as object_resolution,
                   o.resolved_to_entity_id as object_resolved_to,
                   resolved_o.display_name as object_resolved_name,
                   resolved_o.convex_person_id as object_resolved_convex_person_id,
                   s.id as s_id, o.id as o_id
            from haven_knowledge.knowledge_claims c
            join haven_knowledge.knowledge_entities s
              on s.id = c.subject_entity_id and s.owner_id = c.owner_id
            left join haven_knowledge.knowledge_entities resolved_s
              on resolved_s.id = s.resolved_to_entity_id
             and resolved_s.owner_id = c.owner_id
             and resolved_s.entity_state = 'canonical'
             and resolved_s.deleted_at is null
            left join haven_knowledge.knowledge_entities o
              on o.id = c.object_entity_id and o.owner_id = c.owner_id
            left join haven_knowledge.knowledge_entities resolved_o
              on resolved_o.id = o.resolved_to_entity_id
             and resolved_o.owner_id = c.owner_id
             and resolved_o.entity_state = 'canonical'
             and resolved_o.deleted_at is null
            where c.owner_id = %s and c.lifecycle_status = 'active'
              and c.predicate_key = any(%s)
              and (c.subject_entity_id = %s or s.resolved_to_entity_id = %s
                   or c.object_entity_id = %s or o.resolved_to_entity_id = %s)
            order by c.created_at
            """,
            (
                owner_id, list(RELATIONSHIP_PREDICATES), entity_id, entity_id,
                entity_id, entity_id,
            ),
        )
        return cur.fetchall()


def _qualified_person(conn: psycopg.Connection, owner_id: uuid.UUID, claim_row: dict[str, Any], side: str) -> dict[str, Any]:
    """Present one endpoint of a relationship claim, qualified when it is an
    unresolved provisional, including the resolution action contract."""
    name = claim_row[f"{side}_name"]
    state = claim_row[f"{side}_state"]
    entity_id = claim_row["s_id" if side == "subject" else "o_id"]
    resolution = claim_row[f"{side}_resolution"]
    resolved_to = claim_row[f"{side}_resolved_to"]
    if state == "provisional" and resolution == "confirmed" and resolved_to:
        return {
            "entity_id": str(resolved_to),
            "display_name": claim_row[f"{side}_resolved_name"] or name,
            "entity_state": "canonical",
            "convex_person_id": claim_row[f"{side}_resolved_convex_person_id"],
            "resolution_status": "confirmed",
            "source_provisional_entity_id": str(entity_id),
        }
    out: dict[str, Any] = {
        "entity_id": str(entity_id),
        "display_name": name,
        "entity_state": state,
    }
    if state == "provisional":
        out["resolution_status"] = "unresolved"
        candidates = list_reference_candidates(conn, owner_id, entity_id)
        out["candidates"] = candidates["candidates"]
        out["actions"] = candidates["actions"]
    return out


def _endpoint_matches(
    claim_row: dict[str, Any], side: str, entity_id: uuid.UUID
) -> bool:
    direct_id = claim_row["s_id" if side == "subject" else "o_id"]
    resolved_id = claim_row[f"{side}_resolved_to"]
    return entity_id in (direct_id, resolved_id)


def relationship_answer(
    conn: psycopg.Connection, owner_id: uuid.UUID, plan: QueryPlan
) -> dict[str, Any]:
    matches = fuzzy_person_lookup(conn, owner_id, plan.target_name or "")
    if not matches:
        return {
            "kind": plan.relationship_kind,
            "answer": f"Haven has no person matching \"{plan.target_name}\".",
            "results": [],
        }
    target = matches[0]
    claims = _active_relationship_claims(conn, owner_id, target["id"])

    results = []
    for c in claims:
        entry: dict[str, Any] = {
            "predicate": c["predicate_key"],
            "polarity": c["polarity"],
            "modality": c["modality"],
            "temporal_status": c["temporal_status"],
            "evidence": {
                "quote": c["evidence_quote"],
                "source_entry_id": str(c["source_entry_id"]),
                "source_entry_version_id": str(c["source_entry_version_id"]),
                "claim_id": str(c["id"]),
            },
        }
        if (
            plan.relationship_kind == "who_introduced"
            and _endpoint_matches(c, "subject", target["id"])
            and c["predicate_key"] in ("introduced_by", "met_through")
        ):
            person = _qualified_person(conn, owner_id, c, "object")
            entry["person"] = person
            if person.get("resolution_status") == "unresolved":
                entry["answer"] = (
                    f"{person['display_name']} introduced you to {target['display_name']}. "
                    f"Haven has not yet identified which {person['display_name']} you meant."
                )
            else:
                entry["answer"] = (
                    f"{person['display_name']} introduced you to {target['display_name']}."
                )
            results.append(entry)
        elif (
            plan.relationship_kind == "met_through"
            and c["predicate_key"] in ("met_through", "introduced_by")
            and c["object_entity_id"] is not None
            and _endpoint_matches(c, "object", target["id"])
        ):
            person = _qualified_person(conn, owner_id, c, "subject")
            entry["person"] = person
            entry["answer"] = f"You met {person['display_name']} through {target['display_name']}."
            results.append(entry)
        elif plan.relationship_kind == "how_do_i_know":
            other_side = (
                "object" if _endpoint_matches(c, "subject", target["id"]) else "subject"
            )
            if c["object_entity_id"] is None and other_side == "object":
                entry["answer"] = f"{c['subject_name']} {c['predicate_key'].replace('_', ' ')} {c['object_text']}."
            else:
                person = _qualified_person(conn, owner_id, c, other_side)
                entry["person"] = person
                entry["answer"] = (
                    f"{c['subject_name']} {c['predicate_key'].replace('_', ' ')} "
                    f"{c['object_name'] or c['object_text']}."
                )
            results.append(entry)

    if not results:
        return {
            "kind": plan.relationship_kind,
            "target": entity_public_view(target),
            "answer": (
                f"Haven found {target['display_name']} but has no recorded "
                f"relationship evidence answering this question."
            ),
            "results": [],
        }
    return {
        "kind": plan.relationship_kind,
        "target": entity_public_view(target),
        "answer": results[0].get("answer"),
        "results": results,
    }
