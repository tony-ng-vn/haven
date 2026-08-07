"""The stable domain facade. Every operation authenticates through an
AuthContext resolved server-side to an owner UUID; owner_id is never an
input. This is the surface a future HTTP transport or Convex bridge wraps."""

from __future__ import annotations

import datetime as dt
import uuid
from concurrent.futures import ThreadPoolExecutor
from typing import Any

import psycopg

from . import config, entries, references, retrieval
from .answers import relationship_answer
from .entities import entity_public_view, get_entity, mirror_convex_person
from .identity import AuthContext, ensure_owner
from .router import plan_query


class KnowledgeService:
    def __init__(self, conn: psycopg.Connection):
        self._conn = conn

    # ------------------------------------------------------------ identity

    def ensure_owner(self, auth: AuthContext) -> uuid.UUID:
        return ensure_owner(self._conn, auth)

    def mirror_convex_person(
        self, auth: AuthContext, convex_person_id: str, display_name: str
    ) -> dict[str, Any]:
        config.require_write()
        owner = self.ensure_owner(auth)
        entity_id = mirror_convex_person(self._conn, owner, convex_person_id, display_name)
        return {"entity_id": str(entity_id)}

    # -------------------------------------------------------- source entries

    def create_source_entry(
        self,
        auth: AuthContext,
        *,
        raw_text: str,
        source_type: str = "typed",
        convex_person_id: str | None = None,
        primary_entity_id: str | None = None,
        captured_at: dt.datetime | None = None,
        idempotency_key: str | None = None,
    ) -> dict[str, Any]:
        config.require_write()
        owner = self.ensure_owner(auth)
        entity_uuid = self._resolve_primary(owner, convex_person_id, primary_entity_id)
        return entries.create_source_entry(
            self._conn, owner,
            primary_entity_id=entity_uuid, raw_text=raw_text, source_type=source_type,
            captured_at=captured_at, idempotency_key=idempotency_key,
        )

    def revise_source_entry(
        self, auth: AuthContext, source_entry_id: str, raw_text: str
    ) -> dict[str, Any]:
        config.require_write()
        owner = self.ensure_owner(auth)
        return entries.revise_source_entry(
            self._conn, owner,
            source_entry_id=uuid.UUID(source_entry_id), raw_text=raw_text,
        )

    def delete_source_entry(self, auth: AuthContext, source_entry_id: str) -> dict[str, Any]:
        config.require_write()
        owner = self.ensure_owner(auth)
        return entries.delete_source_entry(
            self._conn, owner, source_entry_id=uuid.UUID(source_entry_id)
        )

    def get_source_entry(self, auth: AuthContext, source_entry_id: str) -> dict[str, Any] | None:
        owner = self.ensure_owner(auth)
        return entries.get_source_entry(self._conn, owner, uuid.UUID(source_entry_id))

    def get_processing_status(self, auth: AuthContext, source_entry_id: str) -> dict[str, Any]:
        owner = self.ensure_owner(auth)
        return entries.get_processing_status(self._conn, owner, uuid.UUID(source_entry_id))

    # ------------------------------------------------------------- knowledge

    def get_person_knowledge(self, auth: AuthContext, entity_id: str) -> dict[str, Any]:
        owner = self.ensure_owner(auth)
        requested_entity_id = uuid.UUID(entity_id)
        entity = get_entity(self._conn, owner, requested_entity_id)
        if entity is None:
            raise ValueError("entity not found for this owner")
        effective_entity_id = entity["resolved_to_entity_id"] or requested_entity_id
        public_entity = entity
        if effective_entity_id != requested_entity_id:
            public_entity = get_entity(self._conn, owner, effective_entity_id)
            if public_entity is None:
                raise ValueError("resolved entity not found for this owner")
        with self._conn.cursor() as cur:
            cur.execute(
                """
                select c.id, c.predicate_key, c.custom_predicate_label, c.object_text,
                       coalesce(o.resolved_to_entity_id, c.object_entity_id)
                           as object_entity_id,
                       coalesce(resolved_o.display_name, o.display_name) as object_name,
                       c.polarity, c.modality, c.temporal_status, c.confidence,
                       c.evidence_quote, c.source_entry_id, c.source_entry_version_id
                from haven_knowledge.knowledge_claims c
                join haven_knowledge.knowledge_entities s
                  on s.id = c.subject_entity_id and s.owner_id = c.owner_id
                left join haven_knowledge.knowledge_entities o
                  on o.id = c.object_entity_id and o.owner_id = c.owner_id
                left join haven_knowledge.knowledge_entities resolved_o
                  on resolved_o.id = o.resolved_to_entity_id
                 and resolved_o.owner_id = c.owner_id
                 and resolved_o.deleted_at is null
                where c.owner_id = %s
                  and (c.subject_entity_id = %s or s.resolved_to_entity_id = %s)
                  and c.lifecycle_status = 'active'
                order by c.created_at
                """,
                (owner, effective_entity_id, effective_entity_id),
            )
            claims = [
                {
                    "claim_id": str(r["id"]),
                    "predicate": r["predicate_key"],
                    "custom_label": r["custom_predicate_label"],
                    "object": r["object_name"] or r["object_text"],
                    "object_entity_id": str(r["object_entity_id"]) if r["object_entity_id"] else None,
                    "polarity": r["polarity"],
                    "modality": r["modality"],
                    "temporal_status": r["temporal_status"],
                    "confidence": r["confidence"],
                    "evidence_quote": r["evidence_quote"],
                    "source_entry_id": str(r["source_entry_id"]),
                }
                for r in cur.fetchall()
            ]
            cur.execute(
                """
                select e.id, v.raw_text, v.captured_at, e.source_type
                from haven_knowledge.source_entries e
                join haven_knowledge.source_entry_versions v on v.id = e.current_version_id
                where e.owner_id = %s and e.primary_entity_id = %s
                  and e.lifecycle_status = 'active'
                order by e.created_at
                """,
                (owner, effective_entity_id),
            )
            sources = [
                {
                    "source_entry_id": str(r["id"]),
                    "raw_text": r["raw_text"],
                    "captured_at": r["captured_at"].isoformat(),
                    "source_type": r["source_type"],
                }
                for r in cur.fetchall()
            ]
        return {
            "entity": entity_public_view(public_entity),
            "claims": claims,
            "sources": sources,
        }

    # ---------------------------------------------------------------- search

    def search_network(self, auth: AuthContext, query: str, limit: int = 10) -> dict[str, Any]:
        config.require_search()
        owner = self.ensure_owner(auth)
        request_id = config.new_request_id()
        plan = plan_query(query)

        if plan.path == "relationship":
            answer = relationship_answer(self._conn, owner, plan)
            return {"request_id": request_id, "path": "relationship", **answer}

        if plan.path == "fast":
            people = retrieval.fuzzy_person_lookup(self._conn, owner, plan.target_name or query)
            if people:
                return {
                    "request_id": request_id,
                    "path": "fast",
                    "results": [
                        {**entity_public_view(p), "result_type": "person_name_match"}
                        for p in people
                    ],
                    "warnings": [],
                }
            # A short query that matches nobody's name is a topic, not a
            # person; fall through to the standard path.

        # Standard path: lexical and vector concurrently, RRF fusion, entity
        # dedup, hydrated evidence, ownership re-checked in hydrate_items.
        warnings: list[str] = []
        with ThreadPoolExecutor(max_workers=2) as pool:
            # Each strategy gets its own connection where it needs SQL, so the
            # two never share a psycopg connection across threads.
            lexical_future = pool.submit(self._lexical_with_own_conn, owner, query)
            vector_future = pool.submit(retrieval.vector_search, owner, query)
            lexical = lexical_future.result()
            vector = vector_future.result()
        for strategy in (lexical, vector):
            if strategy.error:
                warnings.append(strategy.error)
        fused = retrieval.reciprocal_rank_fusion([lexical, vector])
        items = retrieval.hydrate_items(self._conn, owner, fused, limit * 3)

        by_entity: dict[str, dict[str, Any]] = {}
        for item in items:
            # Provisional entities resolved to a canonical one group under the
            # canonical identity; unresolved provisionals stay themselves,
            # explicitly qualified.
            group_id = str(item["resolved_to_entity_id"] or item["primary_entity_id"])
            group = by_entity.get(group_id)
            if group is None:
                group = by_entity[group_id] = {
                    "entity_id": group_id,
                    "display_name": item["display_name"],
                    "entity_state": item["entity_state"],
                    "convex_person_id": item["convex_person_id"],
                    "resolution_status": item["resolution_status"],
                    "unresolved_reference": (
                        item["entity_state"] == "provisional"
                        and item["resolution_status"] == "unresolved"
                    ),
                    "fused_score": 0.0,
                    "result_type": None,
                    "strategies": [],
                    "evidence": [],
                }
                if group["unresolved_reference"]:
                    group["qualification"] = (
                        f"\"{item['display_name']}\" is an unresolved reference; "
                        "Haven has not confirmed who this is."
                    )
            group["fused_score"] = max(group["fused_score"], item["fused_score"])
            for s in item["strategies"]:
                if s not in group["strategies"]:
                    group["strategies"].append(s)
            kind = item["item_kind"]
            if group["result_type"] is None or kind == "direct_claim":
                group["result_type"] = kind
            evidence: dict[str, Any] = {
                "kind": kind,
                "source_entry_id": str(item["source_entry_id"]),
                "claim_id": str(item["claim_id"]) if item["claim_id"] else None,
            }
            if kind == "direct_claim":
                evidence["quote"] = item["evidence_quote"]
                evidence["predicate"] = item["predicate_key"]
                evidence["polarity"] = item["polarity"]
                evidence["modality"] = item["modality"]
                evidence["temporal_status"] = item["temporal_status"]
            else:
                evidence["raw_text"] = item["raw_text"]
            group["evidence"].append(evidence)

        ranked = sorted(by_entity.values(), key=lambda g: -g["fused_score"])[:limit]
        if lexical.error and vector.error:
            warnings.append("all_retrieval_strategies_degraded")
        return {
            "request_id": request_id,
            "path": "standard",
            "results": ranked,
            "strategies_attempted": [lexical.strategy, vector.strategy],
            "warnings": warnings,
        }

    # ----------------------------------------------------------- references

    def list_reference_candidates(self, auth: AuthContext, provisional_id: str) -> dict[str, Any]:
        owner = self.ensure_owner(auth)
        return references.list_reference_candidates(self._conn, owner, uuid.UUID(provisional_id))

    def resolve_reference(self, auth: AuthContext, provisional_id: str, candidate_id: str) -> dict[str, Any]:
        config.require_write()
        owner = self.ensure_owner(auth)
        return references.resolve_reference(
            self._conn, owner, uuid.UUID(provisional_id), uuid.UUID(candidate_id)
        )

    def reject_reference_candidate(self, auth: AuthContext, provisional_id: str, candidate_id: str) -> dict[str, Any]:
        config.require_write()
        owner = self.ensure_owner(auth)
        return references.reject_reference_candidate(
            self._conn, owner, uuid.UUID(provisional_id), uuid.UUID(candidate_id)
        )

    def mark_reference_not_sure(self, auth: AuthContext, provisional_id: str, candidate_id: str) -> dict[str, Any]:
        config.require_write()
        owner = self.ensure_owner(auth)
        return references.mark_reference_not_sure(
            self._conn, owner, uuid.UUID(provisional_id), uuid.UUID(candidate_id)
        )

    # ------------------------------------------------------------- internals

    def _resolve_primary(
        self, owner: uuid.UUID, convex_person_id: str | None, primary_entity_id: str | None
    ) -> uuid.UUID:
        if primary_entity_id is not None:
            return uuid.UUID(primary_entity_id)
        if convex_person_id is None:
            raise ValueError("convex_person_id or primary_entity_id is required")
        with self._conn.cursor() as cur:
            cur.execute(
                """
                select id from haven_knowledge.knowledge_entities
                where owner_id = %s and convex_person_id = %s and deleted_at is null
                """,
                (owner, convex_person_id),
            )
            row = cur.fetchone()
        if row is None:
            raise ValueError("convex person is not mirrored; call mirror_convex_person first")
        return row["id"]

    def _lexical_with_own_conn(self, owner: uuid.UUID, query: str) -> retrieval.StrategyResult:
        from . import db as _db

        conn = _db.connect()
        try:
            return retrieval.lexical_search(conn, owner, query)
        finally:
            conn.close()
