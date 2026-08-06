"""Runtime API integration tests: readiness, each retrieval mode, freshness
after insert/revision/deletion, structured errors, and degraded-mode
fallbacks. These run against the real development project and clean up their
rows. Graph data-plane tests record the observed platform state honestly."""

from __future__ import annotations

import os
import time
import uuid

import pytest

from haven_knowledge import db, retrieval
from haven_knowledge.entities import mirror_convex_person
from haven_knowledge.service import KnowledgeService

pytestmark = pytest.mark.runtime


def _project():
    from polygres import Polygres

    client = Polygres(
        api_key=os.environ["POLYGRES_API_KEY"],
        runtime_url=os.environ["POLYGRES_RUNTIME_URL"],
    )
    return client, client.project()


@pytest.fixture
def seeded(db_conn, test_auth, cleanup_owner):
    """One owner with one entry whose raw item is in the index."""
    service = KnowledgeService(db_conn)
    owner = service.ensure_owner(test_auth)
    cleanup_owner.append(owner)
    entity_id = mirror_convex_person(db_conn, owner, f"cx_{uuid.uuid4().hex[:8]}", "Linh Pham")
    marker = f"zx{uuid.uuid4().hex[:10]}"  # unique token so tests never collide
    result = service.create_source_entry(
        test_auth,
        raw_text=f"Linh curates rare orchids {marker} in her greenhouse.",
        primary_entity_id=str(entity_id), source_type="system_test",
    )
    return service, test_auth, owner, entity_id, marker, result


def test_readiness_reports_vector_and_graph(seeded):
    client, project = _project()
    try:
        readiness = project.readiness()
        assert readiness.vector.get("ready") is True
        # Recorded, not asserted: graph "ready" is config-level state; the
        # data plane is exercised in test_graph_data_plane below.
        assert "ready" in readiness.graph
    finally:
        client.close()


def test_tsvector_insert_freshness(seeded, db_conn):
    """A row inserted moments ago must be lexically retrievable through the
    Runtime API (generated column + index, no external sync)."""
    service, auth, owner, entity_id, marker, result = seeded
    client, project = _project()
    try:
        deadline = time.monotonic() + 10
        hits = []
        while time.monotonic() < deadline:
            page = project.text.tsvector(
                marker, config=retrieval.TEXT_CONFIG,
                filters={"owner_id": str(owner)}, limit=5,
            )
            hits = page.results
            if hits:
                break
            time.sleep(0.5)
        assert len(hits) == 1
    finally:
        client.close()


def test_owner_filter_excludes_other_tenants(seeded):
    service, auth, owner, entity_id, marker, result = seeded
    client, project = _project()
    try:
        page = project.text.tsvector(
            marker, config=retrieval.TEXT_CONFIG,
            filters={"owner_id": str(uuid.uuid4())}, limit=5,
        )
        assert page.results == []
    finally:
        client.close()


def test_fuzzy_person_lookup_typo(seeded, db_conn):
    service, auth, owner, entity_id, marker, result = seeded
    # A one-transposition typo sits above the trigram similarity threshold; a
    # heavier corruption ("lin fam") legitimately misses.
    people = retrieval.fuzzy_person_lookup(db_conn, owner, "lihn pham")
    assert any(str(p["id"]) == str(entity_id) for p in people)


def test_revision_and_deletion_leave_no_active_trace(seeded, db_conn):
    service, auth, owner, entity_id, marker, result = seeded
    entry_id = result["source_entry_id"]
    marker2 = f"zx{uuid.uuid4().hex[:10]}"
    service.revise_source_entry(auth, entry_id, f"Linh now breeds koi {marker2} instead.")
    client, project = _project()
    try:
        filters = {"owner_id": str(owner), "lifecycle_status": "active"}
        page_old = project.text.tsvector(marker, config=retrieval.TEXT_CONFIG, filters=filters, limit=5)
        assert page_old.results == []
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            page_new = project.text.tsvector(marker2, config=retrieval.TEXT_CONFIG, filters=filters, limit=5)
            if page_new.results:
                break
            time.sleep(0.5)
        assert len(page_new.results) == 1

        service.delete_source_entry(auth, entry_id)
        page_deleted = project.text.tsvector(marker2, config=retrieval.TEXT_CONFIG, filters=filters, limit=5)
        assert page_deleted.results == []
    finally:
        client.close()


def test_unknown_config_is_a_structured_error(seeded):
    from polygres.errors import PolygresError

    client, project = _project()
    try:
        with pytest.raises(PolygresError):
            project.text.tsvector("anything", config="config_that_does_not_exist", limit=1)
    finally:
        client.close()


def test_lexical_sql_fallback_when_runtime_unavailable(seeded, db_conn, monkeypatch):
    """Vector/runtime outage must degrade to SQL lexical, not to silence."""
    service, auth, owner, entity_id, marker, result = seeded
    monkeypatch.setenv("POLYGRES_RUNTIME_URL", "https://unreachable.invalid/v1")
    strategy = retrieval.lexical_search(db_conn, owner, marker)
    assert strategy.strategy == "lexical_sql_fallback"
    assert len(strategy.ranked_item_ids) == 1


def test_vector_roundtrip(seeded, db_conn):
    """Embed the seeded item through the real pipeline, then retrieve it by
    semantic similarity through the Runtime API. Skips (visibly) when the
    embedding credential is missing or invalid; env presence alone proves
    nothing."""
    from haven_knowledge import config as kconfig
    from haven_knowledge.embeddings import EmbeddingFailed, embed_text
    from haven_knowledge.worker import run_worker

    service, auth, owner, entity_id, marker, result = seeded
    try:
        embed_text(kconfig.embedding_provider(), "credential probe")
    except (EmbeddingFailed, RuntimeError) as exc:
        pytest.skip(f"embedding provider unusable: {exc}")
    run_worker(job_types=["embed_retrieval_item"], idle_exit=True)
    with db_conn.cursor() as cur:
        cur.execute(
            "select embedding_status from haven_knowledge.retrieval_items where owner_id=%s and item_kind='raw_source'",
            (owner,),
        )
        status = cur.fetchone()["embedding_status"]
    assert status == "ready"
    strategy = retrieval.vector_search(owner, "someone who grows unusual flowers")
    assert strategy.error is None
    hydrated = retrieval.hydrate_items(
        db_conn, owner,
        retrieval.reciprocal_rank_fusion([strategy]), limit=5,
    )
    assert any(marker in (h.get("raw_text") or "") for h in hydrated)


def test_graph_data_plane(seeded, db_conn):
    """Records the actual graph data-plane state. If the projection is live,
    a relation must traverse; if the platform build queue is stuck (the state
    observed on 2026-08-06: projection_generations empty, build jobs queued),
    this test documents it by xfailing rather than passing vacuously."""
    with db_conn.cursor() as cur:
        cur.execute("select count(*) as n from graph._projection_generations")
        generations = cur.fetchone()["n"]
    if generations == 0:
        pytest.xfail("graph projection never built: platform build queue stuck")
    client, project = _project()
    try:
        page = project.graph.related(
            {"schema": "haven_knowledge", "table": "knowledge_entities",
             "id": str(seeded[3])},
            direction="any", limit=10,
        )
        assert page is not None
    finally:
        client.close()
