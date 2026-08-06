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
                   o.display_name as object_name, o.entity_state as object_state,
                   o.resolution_status as object_resolution,
                   o.resolved_to_entity_id as object_resolved_to,
                   s.id as s_id, o.id as o_id
            from haven_knowledge.knowledge_claims c
            join haven_knowledge.knowledge_entities s on s.id = c.subject_entity_id
            left join haven_knowledge.knowledge_entities o on o.id = c.object_entity_id
            where c.owner_id = %s and c.lifecycle_status = 'active'
              and c.predicate_key = any(%s)
              and (c.subject_entity_id = %s or c.object_entity_id = %s)
            order by c.created_at
            """,
            (owner_id, list(RELATIONSHIP_PREDICATES), entity_id, entity_id),
        )
        return cur.fetchall()


def _qualified_person(conn: psycopg.Connection, owner_id: uuid.UUID, claim_row: dict[str, Any], side: str) -> dict[str, Any]:
    """Present one endpoint of a relationship claim, qualified when it is an
    unresolved provisional, including the resolution action contract."""
    name = claim_row[f"{side}_name"]
    state = claim_row[f"{side}_state"]
    entity_id = claim_row["s_id" if side == "subject" else "o_id"]
    out: dict[str, Any] = {
        "entity_id": str(entity_id),
        "display_name": name,
        "entity_state": state,
    }
    if state == "provisional":
        resolved_to = claim_row.get(f"{'object' if side == 'object' else side}_resolved_to")
        if side == "object" and claim_row["object_resolution"] == "confirmed" and resolved_to:
            out["resolved_to_entity_id"] = str(resolved_to)
            out["resolution_status"] = "confirmed"
        else:
            out["resolution_status"] = "unresolved"
            candidates = list_reference_candidates(conn, owner_id, entity_id)
            out["candidates"] = candidates["candidates"]
            out["actions"] = candidates["actions"]
    return out


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
        if plan.relationship_kind == "who_introduced" and str(c["s_id"]) == str(target["id"]) \
                and c["predicate_key"] in ("introduced_by", "met_through"):
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
        elif plan.relationship_kind == "met_through" and c["predicate_key"] in ("met_through", "introduced_by") \
                and c["object_entity_id"] is not None and str(c["o_id"]) == str(target["id"]):
            entry["person"] = {"entity_id": str(c["s_id"]), "display_name": c["subject_name"],
                              "entity_state": c["subject_state"]}
            entry["answer"] = f"You met {c['subject_name']} through {target['display_name']}."
            results.append(entry)
        elif plan.relationship_kind == "how_do_i_know":
            other_side = "object" if str(c["s_id"]) == str(target["id"]) else "subject"
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
