"""Retrieval: lexical (Runtime API tsvector, SQL fallback), vector, fuzzy
person lookup, and deterministic reciprocal-rank fusion. Polygres filters
narrow candidates; ownership is re-verified during hydration, always."""

from __future__ import annotations

import logging
import re
import uuid
from dataclasses import dataclass, field
from typing import Any

import psycopg

from . import config, db
from .embeddings import active_embedding_models, embed_text

log = logging.getLogger("haven_knowledge.retrieval")

TEXT_CONFIG = "haven_retrieval_text"
VECTOR_CONFIG = "haven_retrieval_embedding"
FUZZY_CONFIG = "haven_entity_name_fuzzy"

RRF_K = 60


@dataclass
class StrategyResult:
    strategy: str
    ranked_item_ids: list[str]
    error: str | None = None


@dataclass
class FusedItem:
    item_id: str
    score: float
    strategies: list[str] = field(default_factory=list)


def reciprocal_rank_fusion(results: list[StrategyResult], k: int = RRF_K) -> list[FusedItem]:
    scores: dict[str, FusedItem] = {}
    for result in results:
        for rank, item_id in enumerate(result.ranked_item_ids, start=1):
            fused = scores.setdefault(item_id, FusedItem(item_id, 0.0))
            fused.score += 1.0 / (k + rank)
            if result.strategy not in fused.strategies:
                fused.strategies.append(result.strategy)
    return sorted(scores.values(), key=lambda f: (-f.score, f.item_id))


def _sdk_project():
    from polygres import Polygres

    key, url = config.runtime_api_env()
    client = Polygres(api_key=key, runtime_url=url)
    return client, client.project()


_QUERY_STOPWORDS = {
    "who", "what", "which", "where", "when", "how", "the", "for", "and",
    "with", "into", "about", "does", "did", "has", "have", "any", "anyone",
    "someone", "know", "knows",
}


def _meaningful_terms(query: str, cap: int = 4) -> list[str]:
    terms = [
        t for t in re.findall(r"[\w'-]+", query.lower())
        if len(t) > 2 and t not in _QUERY_STOPWORDS
    ]
    return terms[:cap]


def _or_variant(query: str) -> str | None:
    """AND semantics miss when any query word is absent from the text
    ("who runs marathons" fails on "who"). The retry ORs the meaningful
    terms; deterministic, no model involved."""
    terms = _meaningful_terms(query)
    if len(terms) < 2:
        return None
    return " OR ".join(terms)


def lexical_search(
    conn: psycopg.Connection, owner_id: uuid.UUID, query: str, limit: int = 24
) -> StrategyResult:
    """Runtime API tsvector first; direct SQL over the same generated column
    when the API is unavailable, so lexical recall never silently disappears."""
    try:
        client, project = _sdk_project()
        try:
            filters = {"owner_id": str(owner_id), "lifecycle_status": "active"}
            page = project.text.tsvector(
                query, config=TEXT_CONFIG, filters=filters, limit=limit
            )
            ids = [str(r.id) for r in page.results]
            if not ids:
                # The runtime's query parser is AND-shaped, so the OR retry
                # runs one query per meaningful term and RRF-merges locally.
                per_term = [
                    StrategyResult(
                        f"lexical:{term}",
                        [
                            str(r.id)
                            for r in project.text.tsvector(
                                term, config=TEXT_CONFIG, filters=filters, limit=limit
                            ).results
                        ],
                    )
                    for term in _meaningful_terms(query)
                ]
                ids = [f.item_id for f in reciprocal_rank_fusion(per_term)][:limit]
            if ids:
                return StrategyResult("lexical", ids)
        finally:
            client.close()
    except Exception as exc:
        log.warning("runtime lexical failed (%s); using SQL fallback", type(exc).__name__)
    try:
        with conn.cursor() as cur:
            for q in [query, _or_variant(query)]:
                if q is None:
                    continue
                cur.execute(
                    """
                    select id from haven_knowledge.retrieval_items
                    where owner_id = %s and lifecycle_status = 'active'
                      and retrieval_tsv @@ websearch_to_tsquery('simple', %s)
                    order by ts_rank(retrieval_tsv, websearch_to_tsquery('simple', %s)) desc, id
                    limit %s
                    """,
                    (owner_id, q, q, limit),
                )
                ids = [str(r["id"]) for r in cur.fetchall()]
                if ids:
                    return StrategyResult("lexical_sql_fallback", ids)
            return StrategyResult("lexical_sql_fallback", [])
    except Exception:
        log.exception("lexical SQL fallback failed")
        return StrategyResult("lexical", [], error="lexical_unavailable")


def vector_search(owner_id: uuid.UUID, query: str, limit: int = 24) -> StrategyResult:
    try:
        provider = config.embedding_provider()
        conn = db.connect()
        try:
            models = active_embedding_models(conn, owner_id)
        finally:
            conn.close()
        if models and models != {provider.model}:
            log.error("active embedding model does not match configured query model")
            return StrategyResult("vector", [], error="embedding_model_mismatch")
        embedding = embed_text(
            provider,
            query,
            wait_on_rate_limit=config.wait_on_embedding_rate_limit(),
        )
    except Exception as exc:
        log.warning("query embedding failed (%s)", type(exc).__name__)
        return StrategyResult("vector", [], error="embedding_unavailable")
    try:
        client, project = _sdk_project()
        try:
            page = project.vector.search(
                embedding,
                config=VECTOR_CONFIG,
                filters={"owner_id": str(owner_id), "lifecycle_status": "active"},
                limit=limit,
            )
            return StrategyResult("vector", [str(r.id) for r in page.results])
        finally:
            client.close()
    except Exception as exc:
        log.warning("vector search failed (%s)", type(exc).__name__)
        return StrategyResult("vector", [], error="vector_unavailable")


def fuzzy_person_lookup(
    conn: psycopg.Connection, owner_id: uuid.UUID, name: str, limit: int = 10
) -> list[dict[str, Any]]:
    """Entity candidates by approximate name. Runtime API fuzzy config first,
    trigram SQL as fallback; both re-checked against Postgres for ownership."""
    def sql_fallback_ids() -> list[str]:
        try:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    select id from haven_knowledge.knowledge_entities
                    where owner_id = %s and deleted_at is null
                      and normalized_name %% %s
                    order by similarity(normalized_name, %s) desc, id
                    limit %s
                    """,
                    (owner_id, name.lower(), name.lower(), limit),
                )
                return [str(r["id"]) for r in cur.fetchall()]
        except Exception:
            log.exception("fuzzy SQL fallback failed")
            return []

    runtime_ids: list[str] = []
    try:
        client, project = _sdk_project()
        try:
            page = project.text.fuzzy(
                name,
                config=FUZZY_CONFIG,
                filters={"owner_id": str(owner_id)},
                limit=limit,
            )
            runtime_ids = [str(r.id) for r in page.results]
        finally:
            client.close()
    except Exception as exc:
        log.warning("runtime fuzzy failed (%s); using SQL fallback", type(exc).__name__)

    def visible_rows(entity_ids: list[str]) -> list[dict[str, Any]]:
        if not entity_ids:
            return []
        with conn.cursor() as cur:
            cur.execute(
                """
                select e.*,
                       resolved.id as canonical_id,
                       resolved.entity_type as canonical_entity_type,
                       resolved.display_name as canonical_display_name,
                       resolved.normalized_name as canonical_normalized_name,
                       resolved.convex_person_id as canonical_convex_person_id,
                       resolved.created_at as canonical_created_at,
                       resolved.updated_at as canonical_updated_at
                from haven_knowledge.knowledge_entities e
                left join haven_knowledge.knowledge_entities resolved
                  on resolved.id = e.resolved_to_entity_id
                 and resolved.owner_id = e.owner_id
                 and resolved.entity_state = 'canonical'
                 and resolved.deleted_at is null
                where e.id = any(%s::uuid[]) and e.owner_id = %s
                  and e.deleted_at is null
                """,
                (entity_ids, owner_id),
            )
            rows = {str(r["id"]): r for r in cur.fetchall()}
        # Preserve fuzzy rank order through the ownership re-check. Confirmed
        # provisionals collapse to their canonical person so fast and relationship
        # reads cannot expose two identities for the same resolved reference.
        visible: list[dict[str, Any]] = []
        seen: set[uuid.UUID] = set()
        for entity_id in entity_ids:
            row = rows.get(entity_id)
            if row is None:
                continue
            if row["canonical_id"] is not None:
                row = {
                    **row,
                    "id": row["canonical_id"],
                    "entity_type": row["canonical_entity_type"],
                    "entity_state": "canonical",
                    "display_name": row["canonical_display_name"],
                    "normalized_name": row["canonical_normalized_name"],
                    "convex_person_id": row["canonical_convex_person_id"],
                    "resolved_to_entity_id": None,
                    "resolution_status": None,
                    "created_at": row["canonical_created_at"],
                    "updated_at": row["canonical_updated_at"],
                }
            if row["id"] in seen:
                continue
            seen.add(row["id"])
            visible.append(row)
        return visible

    visible = visible_rows(runtime_ids)
    if visible:
        return visible
    return visible_rows(sql_fallback_ids())


def hydrate_items(
    conn: psycopg.Connection, owner_id: uuid.UUID, fused: list[FusedItem], limit: int
) -> list[dict[str, Any]]:
    """Fetch active retrieval items with their entity and evidence context.
    Ownership and lifecycle are enforced here regardless of what any index
    returned."""
    ids = [f.item_id for f in fused]
    if not ids:
        return []
    with conn.cursor() as cur:
        cur.execute(
            """
            select i.id, i.item_kind, i.retrieval_text, i.source_entry_id,
                   i.source_entry_version_id, i.claim_id, i.primary_entity_id,
                   coalesce(resolved.entity_state, e.entity_state) as entity_state,
                   coalesce(resolved.display_name, e.display_name) as display_name,
                   coalesce(resolved.convex_person_id, e.convex_person_id)
                       as convex_person_id,
                   case when resolved.id is not null
                        then resolved.resolution_status
                        else e.resolution_status
                   end as resolution_status,
                   resolved.id as resolved_to_entity_id,
                   c.evidence_quote, c.predicate_key, c.custom_predicate_label,
                   c.polarity, c.modality, c.temporal_status, c.confidence,
                   v.raw_text
            from haven_knowledge.retrieval_items i
            join haven_knowledge.knowledge_entities e
              on e.id = i.primary_entity_id and e.owner_id = i.owner_id
            left join haven_knowledge.knowledge_entities resolved
              on resolved.id = e.resolved_to_entity_id
             and resolved.owner_id = i.owner_id
             and resolved.entity_state = 'canonical'
             and resolved.deleted_at is null
            left join haven_knowledge.knowledge_claims c
              on c.id = i.claim_id and c.owner_id = i.owner_id
             and c.lifecycle_status = 'active'
            left join haven_knowledge.source_entry_versions v
              on v.id = i.source_entry_version_id and v.owner_id = i.owner_id
            where i.id = any(%s::uuid[]) and i.owner_id = %s
              and i.lifecycle_status = 'active' and e.deleted_at is null
            """,
            (ids, owner_id),
        )
        rows = {str(r["id"]): r for r in cur.fetchall()}
    hydrated = []
    by_id = {f.item_id: f for f in fused}
    for item_id in ids:
        row = rows.get(item_id)
        if row is None:
            continue
        if row["item_kind"] == "direct_claim" and row["evidence_quote"] is None:
            # The claim behind this item is no longer active; the item is
            # stale evidence and must not surface.
            continue
        fusedinfo = by_id[item_id]
        hydrated.append({**row, "fused_score": fusedinfo.score, "strategies": fusedinfo.strategies})
        if len(hydrated) >= limit:
            break
    return hydrated
