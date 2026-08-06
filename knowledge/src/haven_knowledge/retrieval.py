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

from . import config
from .embeddings import embed_text

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
        embedding = embed_text(
            config.embedding_provider(),
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
    entity_ids: list[str] = []
    try:
        client, project = _sdk_project()
        try:
            page = project.text.fuzzy(
                name,
                config=FUZZY_CONFIG,
                filters={"owner_id": str(owner_id)},
                limit=limit,
            )
            entity_ids = [str(r.id) for r in page.results]
        finally:
            client.close()
    except Exception as exc:
        log.warning("runtime fuzzy failed (%s); using SQL fallback", type(exc).__name__)
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
            entity_ids = [str(r["id"]) for r in cur.fetchall()]
    if not entity_ids:
        return []
    with conn.cursor() as cur:
        cur.execute(
            """
            select * from haven_knowledge.knowledge_entities
            where id = any(%s::uuid[]) and owner_id = %s and deleted_at is null
            """,
            (entity_ids, owner_id),
        )
        rows = {str(r["id"]): r for r in cur.fetchall()}
    # Preserve fuzzy rank order through the ownership re-check.
    return [rows[eid] for eid in entity_ids if eid in rows]


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
                   e.entity_state, e.display_name, e.convex_person_id,
                   e.resolution_status, e.resolved_to_entity_id,
                   c.evidence_quote, c.predicate_key, c.custom_predicate_label,
                   c.polarity, c.modality, c.temporal_status, c.confidence,
                   v.raw_text
            from haven_knowledge.retrieval_items i
            join haven_knowledge.knowledge_entities e on e.id = i.primary_entity_id
            left join haven_knowledge.knowledge_claims c
                   on c.id = i.claim_id and c.lifecycle_status = 'active'
            left join haven_knowledge.source_entry_versions v
                   on v.id = i.source_entry_version_id
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
