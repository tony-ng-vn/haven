"""Repeatable retrieval evaluation for the knowledge foundation.

Creates a fresh throwaway owner, feeds the versioned fixtures through the
real pipeline (real extraction; real embeddings when a credential exists),
measures, and cleans up. Prints one JSON report.

Run: scripts/knowledge/eval.sh
"""

from __future__ import annotations

import json
import statistics
import sys
import time
import uuid

from haven_knowledge import config, db
from haven_knowledge.embeddings import EmbeddingFailed, embed_text
from haven_knowledge.entities import mirror_convex_person
from haven_knowledge.identity import AuthContext
from haven_knowledge.service import KnowledgeService
from haven_knowledge.worker import run_worker

from fixtures import (
    EVAL_VERSION, F3_SOURCE, F8_V1, F8_V2, F9_SOURCE, F10_SOURCE,
    PEOPLE, SCENARIOS,
)


def pct(values: list[float], p: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = min(len(ordered) - 1, int(round(p * (len(ordered) - 1))))
    return ordered[idx]


def timed(fn):
    start = time.monotonic()
    result = fn()
    return result, (time.monotonic() - start) * 1000


def main() -> int:
    conn = db.connect()
    service = KnowledgeService(conn)
    auth = AuthContext("clerk", "https://eval.havens.invalid", f"eval_{uuid.uuid4().hex}")
    auth_b = AuthContext("clerk", "https://eval.havens.invalid", f"evalb_{uuid.uuid4().hex}")
    owner = service.ensure_owner(auth)
    owner_b = service.ensure_owner(auth_b)

    embeddings_available = True
    try:
        embed_text(config.embedding_provider(), "credential probe")
    except Exception:
        embeddings_available = False

    report: dict = {
        "eval_version": EVAL_VERSION,
        "embeddings_available": embeddings_available,
        "extraction_model": config.extraction_provider().model,
    }
    lat: dict[str, list[float]] = {
        "raw_write_ms": [], "text_available_ms": [], "extraction_ms": [],
        "embedding_ms": [], "query_ms": [], "relationship_ms": [],
    }

    try:
        entities = {
            key: mirror_convex_person(conn, owner, f"eval_{key}", name)
            for key, name in PEOPLE.items()
        }
        entity_to_key = {str(v): k for k, v in entities.items()}

        # ---- ingest scenario sources
        entry_ids: dict[str, list[str]] = {}
        for scenario in SCENARIOS:
            entry_ids[scenario["key"]] = []
            for text in scenario["sources"]:
                result, ms = timed(lambda t=text, s=scenario: service.create_source_entry(
                    auth, raw_text=t, primary_entity_id=str(entities[s["primary"]]),
                    source_type="system_test",
                ))
                lat["raw_write_ms"].append(ms)
                entry_ids[scenario["key"]].append(result["source_entry_id"])
                # Text availability: immediate lexical probe via the service's
                # own SQL path (marker word = last word of the source).
                probe = text.rstrip(".").split()[-1]
                _, pms = timed(lambda p=probe: service.search_network(auth, p))
                lat["text_available_ms"].append(pms)

        # Fixture 3 people already exist (two Alexes); its source:
        f3 = service.create_source_entry(
            auth, raw_text=F3_SOURCE, primary_entity_id=str(entities["sarah"]),
            source_type="system_test",
        )
        # Fixtures 8 and 9 sources:
        f8 = service.create_source_entry(
            auth, raw_text=F8_V1, primary_entity_id=str(entities["sarah"]),
            source_type="system_test",
        )
        f9 = service.create_source_entry(
            auth, raw_text=F9_SOURCE, primary_entity_id=str(entities["sarah"]),
            source_type="system_test",
        )
        # Fixture 10: tenant B with an identically named person and a source.
        sarah_b = mirror_convex_person(conn, owner_b, "eval_b_sarah", "Sarah Chen")
        service.create_source_entry(
            auth_b, raw_text=F10_SOURCE, primary_entity_id=str(sarah_b),
            source_type="system_test",
        )

        # ---- drain pipeline (extraction; embeddings if available)
        t0 = time.monotonic()
        run_worker(job_types=["extract_source"], idle_exit=True)
        extraction_wall_ms = (time.monotonic() - t0) * 1000
        with conn.cursor() as cur:
            cur.execute(
                """
                select extract(epoch from (completed_at - started_at)) * 1000 as ms, status
                from haven_knowledge.extraction_runs where owner_id in (%s, %s)
                """,
                (owner, owner_b),
            )
            runs = cur.fetchall()
        lat["extraction_ms"] = [r["ms"] for r in runs if r["ms"] is not None]
        report["extraction_runs"] = {
            "total": len(runs),
            "succeeded": sum(1 for r in runs if r["status"] == "succeeded"),
            "wall_clock_ms": round(extraction_wall_ms),
        }
        if embeddings_available:
            t0 = time.monotonic()
            run_worker(job_types=["embed_retrieval_item"], idle_exit=True)
            lat["embedding_ms"].append((time.monotonic() - t0) * 1000)

        # ---- scenario queries
        results = []
        recall_hits = 0
        recall_total = 0
        mrr_values: list[float] = []
        evidence_ok = 0
        evidence_total = 0
        unsupported_assertions = 0
        modality_ok = True
        negation_ok = True
        temporal_ok = True

        for scenario in SCENARIOS:
            for query in scenario["queries"]:
                is_rel = query.get("relationship", False)
                out, ms = timed(lambda q=query: service.search_network(auth, q["q"]))
                lat["relationship_ms" if is_rel else "query_ms"].append(ms)
                row = {"scenario": scenario["key"], "query": query["q"], "ms": round(ms)}

                if is_rel:
                    mention = query.get("expect_unresolved_mention")
                    answer = out.get("answer") or ""
                    row["answer"] = answer
                    ok = (
                        mention in answer
                        and "not yet identified" in answer
                        and any(
                            r.get("person", {}).get("resolution_status") == "unresolved"
                            for r in out.get("results", [])
                        )
                    )
                    row["hit"] = ok
                    recall_total += 1
                    recall_hits += 1 if ok else 0
                    mrr_values.append(1.0 if ok else 0.0)
                    if ok:
                        evidence_total += 1
                        quote = out["results"][0]["evidence"]["quote"]
                        evidence_ok += 1 if quote in scenario["sources"][0] else 0
                else:
                    got = [entity_to_key.get(r["entity_id"]) for r in out.get("results", [])][:5]
                    expected = query["expect"]
                    if expected:
                        recall_total += 1
                        hit = expected[0] in got
                        recall_hits += 1 if hit else 0
                        mrr_values.append(1.0 / (got.index(expected[0]) + 1) if hit else 0.0)
                        row["hit"] = hit
                        row["got"] = got
                        if hit:
                            evidence_total += 1
                            top = out["results"][got.index(expected[0])]
                            quotes = [
                                e.get("quote") or e.get("raw_text") or ""
                                for e in top["evidence"]
                            ]
                            evidence_ok += 1 if any(
                                q and any(q in s for s in scenario["sources"]) for q in quotes
                            ) else 0
                    if "expect_negative_not_positive" in query:
                        person_key = query["expect_negative_not_positive"]
                        for r in out.get("results", []):
                            if entity_to_key.get(r["entity_id"]) == person_key:
                                claims = [e for e in r["evidence"] if e["kind"] == "direct_claim"]
                                if any(c.get("polarity") == "positive" for c in claims):
                                    negation_ok = False
                                # Appearing WITH visible negative polarity is
                                # acceptable evidence, not a false positive.
                        row["hit"] = negation_ok
                    if "expect_modality" in query:
                        found = [
                            e for r in out.get("results", [])
                            if entity_to_key.get(r["entity_id"]) == query["expect"][0]
                            for e in r["evidence"] if e["kind"] == "direct_claim"
                        ]
                        if found and not any(e.get("modality") == query["expect_modality"] for e in found):
                            modality_ok = False
                    if "expect_temporal" in query:
                        found = [
                            e for r in out.get("results", [])
                            if entity_to_key.get(r["entity_id"]) == query["expect"][0]
                            for e in r["evidence"] if e["kind"] == "direct_claim"
                        ]
                        if found and not any(e.get("temporal_status") == query["expect_temporal"] for e in found):
                            temporal_ok = False
                results.append(row)

            # Forbidden assertions: nothing persisted for this owner may
            # contain them (claims, relations, retrieval items).
            for phrase in scenario["forbidden"]:
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        select count(*) as n from haven_knowledge.retrieval_items
                        where owner_id = %s and retrieval_text ilike %s
                        """,
                        (owner, f"%{phrase}%"),
                    )
                    n = cur.fetchone()["n"]
                    cur.execute(
                        """
                        select count(*) as n from haven_knowledge.knowledge_claims
                        where owner_id = %s and (object_text ilike %s or evidence_quote ilike %s)
                        """,
                        (owner, f"%{phrase}%", f"%{phrase}%"),
                    )
                    n += cur.fetchone()["n"]
                unsupported_assertions += n

        # ---- fixture 3: multiple Alexes stay unresolved with both candidates
        with conn.cursor() as cur:
            cur.execute(
                """
                select id from haven_knowledge.knowledge_entities
                where owner_id = %s and entity_state = 'provisional'
                  and normalized_name = 'alex' and deleted_at is null
                """,
                (owner,),
            )
            prov = cur.fetchone()
        f3_ok = False
        if prov:
            listing = service.list_reference_candidates(auth, str(prov["id"]))
            ids = {c["entity_id"] for c in listing["candidates"]}
            f3_ok = (
                listing["provisional"]["resolution_status"] == "unresolved"
                and str(entities["alex_chen"]) in ids
                and str(entities["alex_kim"]) in ids
            )
        report["f3_multiple_alexes_unresolved_with_candidates"] = f3_ok

        # ---- fixture 8: revision
        service.revise_source_entry(auth, f8["source_entry_id"], F8_V2)
        run_worker(job_types=["extract_source"], idle_exit=True)
        if embeddings_available:
            run_worker(job_types=["embed_retrieval_item"], idle_exit=True)
        sf = service.search_network(auth, "San Francisco")
        f8_stale = any(
            entity_to_key.get(r["entity_id"]) == "sarah" for r in sf.get("results", [])
        )
        ny = service.search_network(auth, "New York")
        f8_fresh = any(
            entity_to_key.get(r["entity_id"]) == "sarah" for r in ny.get("results", [])
        )
        report["f8_revision"] = {"stale_visible": f8_stale, "new_visible": f8_fresh,
                                "ok": (not f8_stale) and f8_fresh}

        # ---- fixture 9: deletion
        service.delete_source_entry(auth, f9["source_entry_id"])
        deleted_hits = service.search_network(auth, "antique compasses")
        f9_leaks = sum(
            1 for r in deleted_hits.get("results", [])
            if any("compass" in json.dumps(e).lower() for e in r["evidence"])
        )
        report["f9_deleted_content_hits"] = f9_leaks

        # ---- fixture 10: tenant isolation
        leakage = 0
        cross = service.search_network(auth, "miniature watercolors")
        leakage += len(cross.get("results", []))
        cross_b = service.search_network(auth_b, "antique compasses")
        leakage += len(cross_b.get("results", []))
        fast_b = service.search_network(auth_b, "Sarah Chen")
        leakage += sum(1 for r in fast_b.get("results", []) if r["entity_id"] != str(sarah_b))
        report["tenant_leakage_count"] = leakage

        # ---- debug snapshot (before cleanup): what was actually persisted,
        # so an eval miss is diagnosable after the rows are gone.
        with conn.cursor() as cur:
            cur.execute(
                """
                select c.predicate_key, c.object_text, c.polarity, c.modality,
                       c.temporal_status, o.display_name as object_entity
                from haven_knowledge.knowledge_claims c
                left join haven_knowledge.knowledge_entities o on o.id = c.object_entity_id
                where c.owner_id = %s and c.lifecycle_status = 'active'
                order by c.created_at
                """,
                (owner,),
            )
            report["debug_claims"] = [dict(r) for r in cur.fetchall()]
            cur.execute(
                "select item_kind, retrieval_text from haven_knowledge.retrieval_items where owner_id=%s and lifecycle_status='active' and item_kind='direct_claim' order by created_at",
                (owner,),
            )
            report["debug_claim_items"] = [r["retrieval_text"] for r in cur.fetchall()]

        # ---- metrics
        report["recall_at_5"] = round(recall_hits / recall_total, 3) if recall_total else None
        report["mrr"] = round(statistics.mean(mrr_values), 3) if mrr_values else None
        report["evidence_correctness"] = (
            round(evidence_ok / evidence_total, 3) if evidence_total else None
        )
        report["unsupported_assertion_count"] = unsupported_assertions
        report["negation_never_positive"] = negation_ok
        report["modality_preserved"] = modality_ok
        report["temporal_preserved"] = temporal_ok
        report["latency_ms"] = {
            name: {
                "avg": round(statistics.mean(vals)) if vals else None,
                "p95": round(pct(vals, 0.95)) if vals else None,
                "n": len(vals),
            }
            for name, vals in lat.items()
        }
        report["queries"] = results
        print(json.dumps(report, indent=2))
        healthy = (
            (report["recall_at_5"] or 0) >= 0.5
            and unsupported_assertions == 0
            and leakage == 0
            and f9_leaks == 0
        )
        return 0 if healthy else 1
    finally:
        # Full cleanup of both eval owners.
        with db.transaction(conn) as cur:
            for table in [
                "reference_candidate_decisions", "knowledge_outbox", "retrieval_items",
                "claim_concepts", "entity_relations", "knowledge_claims",
                "entity_mentions", "extraction_runs",
            ]:
                cur.execute(
                    f"delete from haven_knowledge.{table} where owner_id in (%s, %s)",
                    (owner, owner_b),
                )
            cur.execute("update haven_knowledge.source_entries set current_version_id=null where owner_id in (%s,%s)", (owner, owner_b))
            cur.execute("delete from haven_knowledge.source_entry_versions where owner_id in (%s,%s)", (owner, owner_b))
            cur.execute("delete from haven_knowledge.source_entries where owner_id in (%s,%s)", (owner, owner_b))
            cur.execute("delete from haven_knowledge.knowledge_entities where owner_id in (%s,%s)", (owner, owner_b))
            cur.execute("delete from haven_knowledge.auth_identities where haven_user_id in (%s,%s)", (owner, owner_b))
            cur.execute("delete from haven_knowledge.haven_users where id in (%s,%s)", (owner, owner_b))
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
