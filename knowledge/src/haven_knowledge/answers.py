"""Deterministic relationship answers. Evidence is rendered directly; no
generative model sits between retrieval and the response. Unresolved
references answer with explicit qualification, never as confirmed identity
and never as a bare "I don't know"."""

from __future__ import annotations

import uuid
from typing import Any

import psycopg
from psycopg import sql

from .entities import entity_public_view
from .references import list_reference_candidates
from .retrieval import fuzzy_person_lookup
from .router import QueryPlan

RELATIONSHIP_PREDICATES = ("introduced_by", "met_through", "met_at", "knows", "collaborated_with")


def _active_relationship_claims(
    conn: psycopg.Connection,
    owner_id: uuid.UUID,
    entity_id: uuid.UUID,
    relationship_kind: str | None,
    limit: int,
) -> list[dict[str, Any]]:
    if relationship_kind == "who_introduced":
        predicates = ("introduced_by", "met_through")
        endpoint_scope = sql.SQL(
            "and (c.subject_entity_id = %s or s.resolved_to_entity_id = %s)"
        )
        endpoint_params = (entity_id, entity_id)
    elif relationship_kind == "met_through":
        predicates = ("met_through", "introduced_by")
        endpoint_scope = sql.SQL(
            "and (c.object_entity_id = %s or o.resolved_to_entity_id = %s)"
        )
        endpoint_params = (entity_id, entity_id)
    elif relationship_kind == "how_do_i_know":
        predicates = RELATIONSHIP_PREDICATES
        endpoint_scope = sql.SQL(
            "and (c.subject_entity_id = %s or s.resolved_to_entity_id = %s "
            "or c.object_entity_id = %s or o.resolved_to_entity_id = %s)"
        )
        endpoint_params = (entity_id, entity_id, entity_id, entity_id)
    else:
        raise ValueError(f"unsupported relationship kind {relationship_kind!r}")

    with conn.cursor() as cur:
        cur.execute(
            sql.SQL("""
            select c.*, s.display_name as subject_name, s.entity_state as subject_state,
                   s.resolution_status as subject_resolution,
                   s.resolved_to_entity_id as subject_resolved_to,
                   resolved_s.id as subject_resolved_id,
                   resolved_s.display_name as subject_resolved_name,
                   resolved_s.convex_person_id as subject_resolved_convex_person_id,
                   o.display_name as object_name, o.entity_state as object_state,
                   o.resolution_status as object_resolution,
                   o.resolved_to_entity_id as object_resolved_to,
                   resolved_o.id as object_resolved_id,
                   resolved_o.display_name as object_resolved_name,
                   resolved_o.convex_person_id as object_resolved_convex_person_id,
                   s.id as s_id, o.id as o_id
            from haven_knowledge.knowledge_claims c
            join haven_knowledge.knowledge_entities s
              on s.id = c.subject_entity_id and s.owner_id = c.owner_id
             and s.deleted_at is null
            left join haven_knowledge.knowledge_entities resolved_s
              on resolved_s.id = s.resolved_to_entity_id
             and resolved_s.owner_id = c.owner_id
             and resolved_s.entity_state = 'canonical'
             and resolved_s.deleted_at is null
            left join haven_knowledge.knowledge_entities o
              on o.id = c.object_entity_id and o.owner_id = c.owner_id
             and o.deleted_at is null
            left join haven_knowledge.knowledge_entities resolved_o
              on resolved_o.id = o.resolved_to_entity_id
             and resolved_o.owner_id = c.owner_id
             and resolved_o.entity_state = 'canonical'
             and resolved_o.deleted_at is null
            where c.owner_id = %s and c.lifecycle_status = 'active'
              and c.predicate_key = any(%s)
              {endpoint_scope}
              and (c.object_entity_id is null or o.id is not null)
            order by c.created_at
            limit %s
            """).format(endpoint_scope=endpoint_scope),
            (owner_id, list(predicates), *endpoint_params, limit),
        )
        return cur.fetchall()


def _qualified_person(conn: psycopg.Connection, owner_id: uuid.UUID, claim_row: dict[str, Any], side: str) -> dict[str, Any]:
    """Present one endpoint of a relationship claim, qualified when it is an
    unresolved provisional, including the resolution action contract."""
    name = claim_row[f"{side}_name"]
    state = claim_row[f"{side}_state"]
    entity_id = claim_row["s_id" if side == "subject" else "o_id"]
    resolution = claim_row[f"{side}_resolution"]
    resolved_id = claim_row[f"{side}_resolved_id"]
    if state == "provisional" and resolution == "confirmed" and resolved_id:
        return {
            "entity_id": str(resolved_id),
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
        if resolution == "confirmed":
            out["qualification"] = (
                "The previously confirmed person is no longer available."
            )
            return out
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
    conn: psycopg.Connection, owner_id: uuid.UUID, plan: QueryPlan, limit: int = 10
) -> dict[str, Any]:
    matches = fuzzy_person_lookup(conn, owner_id, plan.target_name or "")
    if not matches:
        return {
            "kind": plan.relationship_kind,
            "answer": f"Haven has no person matching \"{plan.target_name}\".",
            "results": [],
        }
    target = matches[0]
    claims = _active_relationship_claims(
        conn, owner_id, target["id"], plan.relationship_kind, limit
    )

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
                subject = _qualified_person(conn, owner_id, c, "subject")
                entry["person"] = subject
                entry["answer"] = (
                    f"{subject['display_name']} {c['predicate_key'].replace('_', ' ')} "
                    f"{c['object_text']}."
                )
                if subject.get("resolution_status") == "unresolved":
                    entry["answer"] += (
                        f" Haven has not yet identified which "
                        f"{subject['display_name']} you meant."
                    )
            else:
                subject = _qualified_person(conn, owner_id, c, "subject")
                object_person = _qualified_person(conn, owner_id, c, "object")
                person = object_person if other_side == "object" else subject
                entry["person"] = person
                entry["answer"] = (
                    f"{subject['display_name']} {c['predicate_key'].replace('_', ' ')} "
                    f"{object_person['display_name']}."
                )
                for endpoint in (subject, object_person):
                    if endpoint.get("resolution_status") == "unresolved":
                        entry["answer"] += (
                            f" Haven has not yet identified which "
                            f"{endpoint['display_name']} you meant."
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
