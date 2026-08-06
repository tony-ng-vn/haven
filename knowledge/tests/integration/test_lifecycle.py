"""Database integration tests against the managed Polygres project. Each test
uses its own owner (unique identity) and cleans up completely, so runs are
isolated and repeatable. Extraction results are hand-built ValidatedExtraction
objects: the pipeline's transactional semantics are what is under test here,
not the model."""

from __future__ import annotations

import threading
import time
import uuid

import psycopg
import pytest

from haven_knowledge import db
from haven_knowledge.entities import mirror_convex_person
from haven_knowledge.extraction import ValidatedClaim, ValidatedExtraction, ValidatedMention
from haven_knowledge.pipeline import persist_extraction
from haven_knowledge.service import KnowledgeService
from haven_knowledge.worker import (
    MAX_ATTEMPTS,
    _process_extract,
    claim_next_job,
    reclaim_stale_jobs,
)

pytestmark = pytest.mark.db

RAW = "Met Sarah through Alex at YC Demo Day. She runs marathons."


def make_extraction() -> ValidatedExtraction:
    return ValidatedExtraction(
        mentions=[ValidatedMention("m1", "Alex", 18, 22)],
        claims=[
            ValidatedClaim(
                subject_ref="primary", predicate_key="met_through",
                custom_predicate_label=None, object_type="mention",
                object_text=None, object_mention_ref="m1",
                polarity="positive", modality="stated", temporal_status="historical",
                confidence=0.95, evidence_quote="Met Sarah through Alex",
                evidence_start=0, evidence_end=22,
            ),
            ValidatedClaim(
                subject_ref="primary", predicate_key="participates_in",
                custom_predicate_label=None, object_type="text",
                object_text="marathons", object_mention_ref=None,
                polarity="positive", modality="stated", temporal_status="current",
                confidence=0.9, evidence_quote="She runs marathons.",
                evidence_start=39, evidence_end=58,
            ),
        ],
    )


def run_fake_extraction(conn, owner, entry_id, version_id, primary_id, primary_name,
                        extraction=None):
    """Insert an extraction run and persist a hand-built extraction, marking
    the extract job succeeded the way the worker would."""
    run_id, job_id, lease_owner = prepare_fake_extraction(
        conn, owner, entry_id, version_id
    )
    return persist_extraction(
        conn, owner_id=owner, entry={"id": entry_id}, version_id=version_id,
        run_id=run_id, primary_entity_id=primary_id, primary_name=primary_name,
        extraction=extraction or make_extraction(), outbox_job_id=job_id,
        lease_owner=lease_owner,
    )


def prepare_fake_extraction(conn, owner, entry_id, version_id):
    """Create the running state that exists while the model call is in flight."""
    lease_owner = "test-worker"
    with db.transaction(conn) as cur:
        cur.execute(
            """
            insert into haven_knowledge.extraction_runs
                (owner_id, source_entry_id, source_entry_version_id,
                 extraction_policy_version, prompt_version, model_provider,
                 model_name, status, started_at)
            values (%s, %s, %s, 'extraction-policy-v1', 'test', 'test', 'fake',
                    'running', now())
            returning id
            """,
            (owner, entry_id, version_id),
        )
        run_id = cur.fetchone()["id"]
        cur.execute(
            "select id from haven_knowledge.knowledge_outbox where idempotency_key = %s",
            (f"extract:{version_id}",),
        )
        job_id = cur.fetchone()["id"]
        cur.execute(
            """
            update haven_knowledge.knowledge_outbox
            set status='running', locked_at=now(), locked_by=%s,
                attempt_count=attempt_count+1
            where id=%s
            """,
            (lease_owner, job_id),
        )
    return run_id, job_id, lease_owner


@pytest.fixture
def setup(db_conn, test_auth, cleanup_owner):
    service = KnowledgeService(db_conn)
    owner = service.ensure_owner(test_auth)
    cleanup_owner.append(owner)
    entity_id = mirror_convex_person(db_conn, owner, f"cx_{uuid.uuid4().hex[:8]}", "Sarah Tran")
    return service, test_auth, owner, entity_id


def q1(conn, sql, *args):
    with conn.cursor() as cur:
        cur.execute(sql, args)
        return cur.fetchone()


def qall(conn, sql, *args):
    with conn.cursor() as cur:
        cur.execute(sql, args)
        return cur.fetchall()


# --------------------------------------------------------------- creation

def test_capture_is_atomic_and_immediately_searchable(setup, db_conn):
    service, auth, owner, entity_id = setup
    result = service.create_source_entry(
        auth, raw_text=RAW, convex_person_id=None,
        primary_entity_id=str(entity_id), source_type="system_test",
    )
    assert result["status"] == "created"
    assert result["raw_searchable"] is True
    entry_id = uuid.UUID(result["source_entry_id"])
    row = q1(db_conn, "select count(*) as n from haven_knowledge.retrieval_items where source_entry_id=%s and item_kind='raw_source' and lifecycle_status='active'", entry_id)
    assert row["n"] == 1
    jobs = qall(db_conn, "select job_type, status from haven_knowledge.knowledge_outbox where source_entry_id=%s order by job_type", entry_id)
    assert [(j["job_type"], j["status"]) for j in jobs] == [
        ("embed_retrieval_item", "pending"), ("extract_source", "pending"),
    ]
    hit = q1(
        db_conn,
        "select count(*) as n from haven_knowledge.retrieval_items where owner_id=%s and lifecycle_status='active' and retrieval_tsv @@ websearch_to_tsquery('simple','marathons')",
        owner,
    )
    assert hit["n"] == 1


def test_create_is_idempotent_on_client_key(setup):
    service, auth, owner, entity_id = setup
    first = service.create_source_entry(
        auth, raw_text=RAW, primary_entity_id=str(entity_id),
        source_type="system_test", idempotency_key="k1",
    )
    second = service.create_source_entry(
        auth, raw_text=RAW, primary_entity_id=str(entity_id),
        source_type="system_test", idempotency_key="k1",
    )
    assert second["status"] == "already"
    assert second["source_entry_id"] == first["source_entry_id"]


def test_concurrent_create_is_idempotent_on_client_key(setup, db_conn):
    _, auth, owner, entity_id = setup
    barrier = threading.Barrier(2)
    outcomes: list[dict] = []
    errors: list[Exception] = []
    lock = threading.Lock()

    def create_once():
        conn = db.connect()
        try:
            service = KnowledgeService(conn)
            barrier.wait()
            outcome = service.create_source_entry(
                auth, raw_text=RAW, primary_entity_id=str(entity_id),
                source_type="system_test", idempotency_key="concurrent-key",
            )
            with lock:
                outcomes.append(outcome)
        except Exception as exc:
            with lock:
                errors.append(exc)
        finally:
            conn.close()

    threads = [threading.Thread(target=create_once) for _ in range(2)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    assert errors == []
    assert sorted(outcome["status"] for outcome in outcomes) == ["already", "created"]
    assert len({outcome["source_entry_id"] for outcome in outcomes}) == 1
    assert q1(
        db_conn,
        """
        select count(*) as n from haven_knowledge.source_entries
        where owner_id=%s and client_idempotency_key='concurrent-key'
        """,
        owner,
    )["n"] == 1


def test_create_rejects_foreign_and_provisional_primaries(setup, db_conn, test_auth):
    service, auth, owner, entity_id = setup
    from haven_knowledge.identity import AuthContext

    other_auth = AuthContext("clerk", "https://test.havens.invalid", f"other_{uuid.uuid4().hex}")
    with pytest.raises(ValueError, match="not found"):
        service.create_source_entry(
            other_auth, raw_text=RAW, primary_entity_id=str(entity_id),
            source_type="system_test",
        )
    # The other owner created above gets cleaned too.
    other_owner = service.ensure_owner(other_auth)
    with db_conn.cursor() as cur:
        cur.execute("delete from haven_knowledge.auth_identities where haven_user_id=%s", (other_owner,))
        cur.execute("delete from haven_knowledge.haven_users where id=%s", (other_owner,))


def test_versions_are_immutable(setup, db_conn):
    service, auth, owner, entity_id = setup
    result = service.create_source_entry(
        auth, raw_text=RAW, primary_entity_id=str(entity_id), source_type="system_test",
    )
    with pytest.raises(psycopg.errors.RaiseException, match="immutable"):
        with db_conn.cursor() as cur:
            cur.execute(
                "update haven_knowledge.source_entry_versions set raw_text='edited' where id=%s",
                (uuid.UUID(result["source_entry_version_id"]),),
            )


# ------------------------------------------------------------- extraction

def test_extraction_creates_provisional_claims_relations_items(setup, db_conn):
    service, auth, owner, entity_id = setup
    result = service.create_source_entry(
        auth, raw_text=RAW, primary_entity_id=str(entity_id), source_type="system_test",
    )
    entry_id = uuid.UUID(result["source_entry_id"])
    version_id = uuid.UUID(result["source_entry_version_id"])
    created = run_fake_extraction(db_conn, owner, entry_id, version_id, entity_id, "Sarah Tran")
    assert created["claims"] == 2 and created["relations"] == 1

    alex = q1(db_conn, "select * from haven_knowledge.knowledge_entities where owner_id=%s and normalized_name='alex'", owner)
    assert alex["entity_state"] == "provisional"
    assert alex["resolution_status"] == "unresolved"
    assert alex["convex_person_id"] is None

    relation = q1(db_conn, "select * from haven_knowledge.entity_relations where owner_id=%s", owner)
    assert relation["predicate_key"] == "met_through"
    assert relation["object_entity_id"] == alex["id"]

    # Concept mapping: marathons -> marathon_running (+ parents).
    concepts = qall(
        db_conn,
        """
        select k.concept_key, cc.mapping_type
        from haven_knowledge.claim_concepts cc
        join haven_knowledge.knowledge_concepts k on k.id = cc.concept_id
        where cc.owner_id = %s order by k.concept_key
        """,
        owner,
    )
    keys = {c["concept_key"] for c in concepts}
    assert "marathon_running" in keys
    assert "endurance_sport" in keys  # taxonomy parent

    # Retrieval item for the claim is searchable by the broader concept.
    hit = q1(
        db_conn,
        "select count(*) as n from haven_knowledge.retrieval_items where owner_id=%s and item_kind='direct_claim' and retrieval_tsv @@ websearch_to_tsquery('simple','endurance')",
        owner,
    )
    assert hit["n"] >= 1


def test_extraction_job_rerun_does_not_duplicate(setup, db_conn):
    service, auth, owner, entity_id = setup
    result = service.create_source_entry(
        auth, raw_text=RAW, primary_entity_id=str(entity_id), source_type="system_test",
    )
    entry_id = uuid.UUID(result["source_entry_id"])
    version_id = uuid.UUID(result["source_entry_version_id"])
    run_fake_extraction(db_conn, owner, entry_id, version_id, entity_id, "Sarah Tran")
    # Simulate a redelivered job: same run id path via a fresh run row would
    # be a new run; the guard is per-run, and the job is already succeeded.
    job = q1(db_conn, "select status from haven_knowledge.knowledge_outbox where idempotency_key=%s", f"extract:{version_id}")
    assert job["status"] == "succeeded"
    claims = q1(db_conn, "select count(*) as n from haven_knowledge.knowledge_claims where owner_id=%s", owner)
    assert claims["n"] == 2


@pytest.mark.parametrize("lifecycle_change", ["revise", "delete"])
def test_inflight_extraction_cannot_resurrect_inactive_version(
    setup, db_conn, lifecycle_change
):
    service, auth, owner, entity_id = setup
    result = service.create_source_entry(
        auth, raw_text=RAW, primary_entity_id=str(entity_id), source_type="system_test",
    )
    entry_id = uuid.UUID(result["source_entry_id"])
    version_id = uuid.UUID(result["source_entry_version_id"])
    run_id, job_id, lease_owner = prepare_fake_extraction(
        db_conn, owner, entry_id, version_id
    )

    if lifecycle_change == "revise":
        service.revise_source_entry(auth, str(entry_id), "Sarah moved to New York.")
    else:
        service.delete_source_entry(auth, str(entry_id))

    created = persist_extraction(
        db_conn, owner_id=owner, entry={"id": entry_id}, version_id=version_id,
        run_id=run_id, primary_entity_id=entity_id, primary_name="Sarah Tran",
        extraction=make_extraction(), outbox_job_id=job_id,
        lease_owner=lease_owner,
    )

    assert created == {
        "mentions": 0,
        "provisional_entities": 0,
        "claims": 0,
        "relations": 0,
        "items": 0,
    }
    active = q1(
        db_conn,
        """
        select count(*) as n from haven_knowledge.knowledge_claims
        where owner_id=%s and source_entry_version_id=%s and lifecycle_status='active'
        """,
        owner,
        version_id,
    )
    assert active["n"] == 0


def test_reclaimed_extraction_lease_cannot_persist(setup, db_conn):
    service, auth, owner, entity_id = setup
    result = service.create_source_entry(
        auth, raw_text=RAW, primary_entity_id=str(entity_id), source_type="system_test",
    )
    entry_id = uuid.UUID(result["source_entry_id"])
    version_id = uuid.UUID(result["source_entry_version_id"])
    run_id, job_id, old_lease = prepare_fake_extraction(
        db_conn, owner, entry_id, version_id
    )
    with db.transaction(db_conn) as cur:
        cur.execute(
            """
            update haven_knowledge.knowledge_outbox
            set locked_by='replacement-worker', locked_at=now(), attempt_count=attempt_count+1
            where id=%s
            """,
            (job_id,),
        )

    created = persist_extraction(
        db_conn, owner_id=owner, entry={"id": entry_id}, version_id=version_id,
        run_id=run_id, primary_entity_id=entity_id, primary_name="Sarah Tran",
        extraction=make_extraction(), outbox_job_id=job_id,
        lease_owner=old_lease,
    )

    assert created == {
        "mentions": 0,
        "provisional_entities": 0,
        "claims": 0,
        "relations": 0,
        "items": 0,
    }
    assert q1(
        db_conn,
        "select count(*) as n from haven_knowledge.knowledge_claims where owner_id=%s",
        owner,
    )["n"] == 0


def test_expired_lease_cannot_create_extraction_run(setup, db_conn, monkeypatch):
    service, auth, owner, entity_id = setup
    result = service.create_source_entry(
        auth, raw_text=RAW, primary_entity_id=str(entity_id), source_type="system_test",
    )
    job = claim_next_job(
        db_conn, "expired-worker", ["extract_source"], owner_ids=[owner]
    )
    assert job is not None
    with db.transaction(db_conn) as cur:
        cur.execute(
            """
            update haven_knowledge.knowledge_outbox
            set locked_by='replacement-worker', attempt_count=attempt_count+1
            where id=%s
            """,
            (job["id"],),
        )

    monkeypatch.setattr(
        "haven_knowledge.worker.config.extraction_provider",
        lambda: type(
            "TestProvider",
            (),
            {
                "label": "test",
                "base_url": "https://example.invalid",
                "api_key": "test-key",
                "model": "test-model",
            },
        )(),
    )
    monkeypatch.setattr(
        "haven_knowledge.worker.run_extraction",
        lambda *args, **kwargs: pytest.fail("expired lease reached the model call"),
    )
    _process_extract(db_conn, job)

    assert q1(
        db_conn,
        """
        select count(*) as n from haven_knowledge.extraction_runs
        where owner_id=%s and source_entry_version_id=%s
        """,
        owner,
        uuid.UUID(result["source_entry_version_id"]),
    )["n"] == 0


def test_reclaim_stale_extraction_marks_abandoned_run_failed(setup, db_conn):
    service, auth, owner, entity_id = setup
    result = service.create_source_entry(
        auth, raw_text=RAW, primary_entity_id=str(entity_id), source_type="system_test",
    )
    entry_id = uuid.UUID(result["source_entry_id"])
    version_id = uuid.UUID(result["source_entry_version_id"])
    run_id, job_id, _ = prepare_fake_extraction(
        db_conn, owner, entry_id, version_id
    )
    with db.transaction(db_conn) as cur:
        cur.execute(
            """
            update haven_knowledge.knowledge_outbox
            set locked_at=now() - interval '11 minutes'
            where id=%s
            """,
            (job_id,),
        )

    assert reclaim_stale_jobs(db_conn, owner_ids=[owner]) == 1
    run = q1(
        db_conn,
        """
        select status, completed_at, error_code, safe_error_message
        from haven_knowledge.extraction_runs where id=%s
        """,
        run_id,
    )
    assert run["status"] == "failed"
    assert run["completed_at"] is not None
    assert run["error_code"] == "worker_lease_expired"
    assert run["safe_error_message"] == "extraction worker lease expired; job will retry"


def test_reclaim_dead_letters_job_at_retry_limit(setup, db_conn):
    service, auth, owner, entity_id = setup
    result = service.create_source_entry(
        auth, raw_text=RAW, primary_entity_id=str(entity_id), source_type="system_test",
    )
    entry_id = uuid.UUID(result["source_entry_id"])
    version_id = uuid.UUID(result["source_entry_version_id"])
    run_id, job_id, _ = prepare_fake_extraction(
        db_conn, owner, entry_id, version_id
    )
    with db.transaction(db_conn) as cur:
        cur.execute(
            """
            update haven_knowledge.knowledge_outbox
            set attempt_count=%s, locked_at=now() - interval '11 minutes'
            where id=%s
            """,
            (MAX_ATTEMPTS, job_id),
        )

    assert reclaim_stale_jobs(db_conn, owner_ids=[owner]) == 1
    job = q1(
        db_conn,
        """
        select status, locked_at, locked_by, last_error_code
        from haven_knowledge.knowledge_outbox where id=%s
        """,
        job_id,
    )
    assert job == {
        "status": "dead",
        "locked_at": None,
        "locked_by": None,
        "last_error_code": "stale_lock_retry_limit",
    }
    run = q1(
        db_conn,
        """
        select status, error_code, safe_error_message
        from haven_knowledge.extraction_runs where id=%s
        """,
        run_id,
    )
    assert run == {
        "status": "failed",
        "error_code": "worker_lease_expired",
        "safe_error_message": "extraction worker lease expired; retry limit reached",
    }


def test_reclaim_lock_order_matches_extraction_completion(setup, db_conn):
    service, auth, owner, entity_id = setup
    result = service.create_source_entry(
        auth, raw_text=RAW, primary_entity_id=str(entity_id), source_type="system_test",
    )
    entry_id = uuid.UUID(result["source_entry_id"])
    version_id = uuid.UUID(result["source_entry_version_id"])
    run_id, job_id, _ = prepare_fake_extraction(
        db_conn, owner, entry_id, version_id
    )
    with db.transaction(db_conn) as cur:
        cur.execute(
            """
            update haven_knowledge.knowledge_outbox
            set locked_at=now() - interval '11 minutes'
            where id=%s
            """,
            (job_id,),
        )

    app_name = f"haven-reclaim-order-{uuid.uuid4().hex}"
    started = threading.Event()
    outcome: dict[str, object] = {}

    def reclaim_while_completion_holds_run():
        conn = db.connect()
        try:
            conn.execute("select set_config('application_name', %s, false)", (app_name,))
            conn.commit()
            started.set()
            outcome["reclaimed"] = reclaim_stale_jobs(conn, owner_ids=[owner])
        except Exception as exc:
            outcome["error"] = exc
        finally:
            conn.close()

    completion_conn = db.connect()
    thread = threading.Thread(target=reclaim_while_completion_holds_run)
    try:
        with completion_conn.transaction():
            with completion_conn.cursor() as cur:
                cur.execute(
                    "select id from haven_knowledge.extraction_runs where id=%s for update",
                    (run_id,),
                )
                thread.start()
                assert started.wait(timeout=2)

                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    waiter = q1(
                        db_conn,
                        """
                        select wait_event_type
                        from pg_stat_activity where application_name=%s
                        """,
                        app_name,
                    )
                    if waiter and waiter["wait_event_type"] == "Lock":
                        break
                    time.sleep(0.05)
                else:
                    pytest.fail("reclaimer did not wait on the extraction-run lock")

                # This is the same run -> outbox lock order used by
                # persist_extraction. Reclamation must not already hold the job.
                cur.execute(
                    """
                    update haven_knowledge.extraction_runs
                    set status='succeeded', completed_at=now() where id=%s
                    """,
                    (run_id,),
                )
                cur.execute(
                    """
                    update haven_knowledge.knowledge_outbox
                    set status='succeeded', completed_at=now(), locked_at=null,
                        locked_by=null, updated_at=now()
                    where id=%s
                    """,
                    (job_id,),
                )
    finally:
        completion_conn.close()
        thread.join(timeout=5)

    assert not thread.is_alive()
    assert "error" not in outcome
    assert outcome["reclaimed"] == 0


# --------------------------------------------------------------- revision

def test_revision_supersedes_and_reextracts(setup, db_conn):
    service, auth, owner, entity_id = setup
    result = service.create_source_entry(
        auth, raw_text="Sarah lives in San Francisco.",
        primary_entity_id=str(entity_id), source_type="system_test",
    )
    entry_id = uuid.UUID(result["source_entry_id"])
    v1 = uuid.UUID(result["source_entry_version_id"])
    sf_claim = ValidatedExtraction(claims=[ValidatedClaim(
        subject_ref="primary", predicate_key="lives_in", custom_predicate_label=None,
        object_type="text", object_text="San Francisco", object_mention_ref=None,
        polarity="positive", modality="stated", temporal_status="current",
        confidence=0.95, evidence_quote="Sarah lives in San Francisco.",
        evidence_start=0, evidence_end=29,
    )])
    run_fake_extraction(db_conn, owner, entry_id, v1, entity_id, "Sarah Tran", sf_claim)

    revised = service.revise_source_entry(auth, str(entry_id), "Sarah moved to New York.")
    v2 = uuid.UUID(revised["source_entry_version_id"])
    assert v2 != v1

    old_claim = q1(db_conn, "select lifecycle_status, superseded_at from haven_knowledge.knowledge_claims where source_entry_version_id=%s", v1)
    assert old_claim["lifecycle_status"] == "superseded"
    assert old_claim["superseded_at"] is not None

    versions = qall(
        db_conn,
        """
        select version_number, raw_text, lifecycle_status, superseded_at
        from haven_knowledge.source_entry_versions
        where source_entry_id=%s order by version_number
        """,
        entry_id,
    )
    assert [v["version_number"] for v in versions] == [1, 2]
    assert versions[0]["raw_text"] == "Sarah lives in San Francisco."  # audit history
    assert versions[0]["lifecycle_status"] == "superseded"
    assert versions[0]["superseded_at"] is not None
    assert versions[1]["lifecycle_status"] == "active"

    # Old content is out of active retrieval; new raw text is in.
    sf_hits = q1(db_conn, "select count(*) as n from haven_knowledge.retrieval_items where owner_id=%s and lifecycle_status='active' and retrieval_tsv @@ websearch_to_tsquery('simple','Francisco')", owner)
    assert sf_hits["n"] == 0
    ny_hits = q1(db_conn, "select count(*) as n from haven_knowledge.retrieval_items where owner_id=%s and lifecycle_status='active' and retrieval_tsv @@ websearch_to_tsquery('simple','York')", owner)
    assert ny_hits["n"] == 1

    # New extraction job queued for v2.
    job = q1(db_conn, "select status from haven_knowledge.knowledge_outbox where idempotency_key=%s", f"extract:{v2}")
    assert job["status"] == "pending"


# --------------------------------------------------------------- deletion

def test_deletion_deactivates_every_derived_row(setup, db_conn):
    service, auth, owner, entity_id = setup
    result = service.create_source_entry(
        auth, raw_text=RAW, primary_entity_id=str(entity_id), source_type="system_test",
    )
    entry_id = uuid.UUID(result["source_entry_id"])
    version_id = uuid.UUID(result["source_entry_version_id"])
    run_fake_extraction(db_conn, owner, entry_id, version_id, entity_id, "Sarah Tran")

    deleted = service.delete_source_entry(auth, str(entry_id))
    assert deleted["status"] == "deleted"

    for table, filt in [
        ("knowledge_claims", "source_entry_id"),
        ("retrieval_items", "source_entry_id"),
    ]:
        rows = qall(db_conn, f"select lifecycle_status from haven_knowledge.{table} where {filt}=%s", entry_id)
        assert rows and all(r["lifecycle_status"] == "deleted" for r in rows)
    relations = qall(db_conn, "select lifecycle_status from haven_knowledge.entity_relations where owner_id=%s", owner)
    assert relations and all(r["lifecycle_status"] == "deleted" for r in relations)
    versions = qall(
        db_conn,
        """
        select lifecycle_status, deleted_at
        from haven_knowledge.source_entry_versions where source_entry_id=%s
        """,
        entry_id,
    )
    assert versions and all(
        row["lifecycle_status"] == "deleted" and row["deleted_at"] is not None
        for row in versions
    )
    mentions = qall(
        db_conn,
        """
        select lifecycle_status, deleted_at
        from haven_knowledge.entity_mentions where owner_id=%s
        """,
        owner,
    )
    assert mentions and all(
        row["lifecycle_status"] == "deleted" and row["deleted_at"] is not None
        for row in mentions
    )

    # Provisional Alex lost its last support and is swept.
    alex = q1(db_conn, "select deleted_at from haven_knowledge.knowledge_entities where owner_id=%s and normalized_name='alex'", owner)
    assert alex["deleted_at"] is not None

    # Nothing about the deleted entry remains in active retrieval.
    hits = q1(db_conn, "select count(*) as n from haven_knowledge.retrieval_items where owner_id=%s and lifecycle_status='active'", owner)
    assert hits["n"] == 0

    # Search returns nothing (lexical SQL path; runtime path filtered the same way).
    found = service.search_network(auth, "marathons")
    assert found["results"] == []


# ------------------------------------------------------------- resolution

def test_reference_resolution_flow(setup, db_conn):
    service, auth, owner, entity_id = setup
    result = service.create_source_entry(
        auth, raw_text=RAW, primary_entity_id=str(entity_id), source_type="system_test",
    )
    run_fake_extraction(
        db_conn, owner, uuid.UUID(result["source_entry_id"]),
        uuid.UUID(result["source_entry_version_id"]), entity_id, "Sarah Tran",
    )
    # Two canonical Alexes exist; neither auto-resolves.
    chen = mirror_convex_person(db_conn, owner, f"cx_{uuid.uuid4().hex[:8]}", "Alex Chen")
    kim = mirror_convex_person(db_conn, owner, f"cx_{uuid.uuid4().hex[:8]}", "Alex Kim")

    alex = q1(db_conn, "select id from haven_knowledge.knowledge_entities where owner_id=%s and entity_state='provisional' and normalized_name='alex'", owner)
    provisional_id = str(alex["id"])

    listing = service.list_reference_candidates(auth, provisional_id)
    candidate_ids = {c["entity_id"] for c in listing["candidates"]}
    assert {str(chen), str(kim)} <= candidate_ids
    assert q1(db_conn, "select resolution_status from haven_knowledge.knowledge_entities where id=%s", alex["id"])["resolution_status"] == "unresolved"

    # Reject Kim: suppressed on identical evidence.
    service.reject_reference_candidate(auth, provisional_id, str(kim))
    listing2 = service.list_reference_candidates(auth, provisional_id)
    assert str(kim) not in {c["entity_id"] for c in listing2["candidates"]}

    # New evidence changes the context hash; Kim may be suggested again.
    r2 = service.create_source_entry(
        auth, raw_text="Alex also joined the climb.", primary_entity_id=str(entity_id),
        source_type="system_test",
    )
    climb = ValidatedExtraction(
        mentions=[ValidatedMention("m1", "Alex", 0, 4)],
        claims=[ValidatedClaim(
            subject_ref="primary", predicate_key="knows", custom_predicate_label=None,
            object_type="mention", object_text=None, object_mention_ref="m1",
            polarity="positive", modality="stated", temporal_status="current",
            confidence=0.7, evidence_quote="Alex also joined the climb.",
            evidence_start=0, evidence_end=27,
        )],
    )
    run_fake_extraction(
        db_conn, owner, uuid.UUID(r2["source_entry_id"]),
        uuid.UUID(r2["source_entry_version_id"]), entity_id, "Sarah Tran", climb,
    )
    listing3 = service.list_reference_candidates(auth, provisional_id)
    assert str(kim) in {c["entity_id"] for c in listing3["candidates"]}

    # Confirm Chen: provisional resolves but is preserved with its evidence.
    service.resolve_reference(auth, provisional_id, str(chen))
    resolved = q1(db_conn, "select resolution_status, resolved_to_entity_id, deleted_at from haven_knowledge.knowledge_entities where id=%s", alex["id"])
    assert resolved["resolution_status"] == "confirmed"
    assert resolved["resolved_to_entity_id"] == chen
    assert resolved["deleted_at"] is None
    claims_still = q1(db_conn, "select count(*) as n from haven_knowledge.knowledge_claims where object_entity_id=%s and lifecycle_status='active'", alex["id"])
    assert claims_still["n"] >= 1
    decision = q1(
        db_conn,
        """
        select decision from haven_knowledge.reference_candidate_decisions
        where owner_id=%s and provisional_entity_id=%s and candidate_entity_id=%s
        """,
        owner,
        alex["id"],
        chen,
    )
    assert decision["decision"] == "confirmed"

    with pytest.raises(ValueError, match="already confirmed"):
        service.reject_reference_candidate(auth, provisional_id, str(chen))
    with pytest.raises(ValueError, match="already confirmed"):
        service.mark_reference_not_sure(auth, provisional_id, str(chen))
    with pytest.raises(ValueError, match="already resolved"):
        service.resolve_reference(auth, provisional_id, str(kim))
    confirmed_count = q1(
        db_conn,
        """
        select count(*) as n from haven_knowledge.reference_candidate_decisions
        where owner_id=%s and provisional_entity_id=%s and decision='confirmed'
        """,
        owner,
        alex["id"],
    )
    assert confirmed_count["n"] == 1

    # A confirmed resolution remains as durable identity evidence even after
    # the last source that originally mentioned the provisional is deleted.
    service.delete_source_entry(auth, result["source_entry_id"])
    service.delete_source_entry(auth, r2["source_entry_id"])
    preserved = q1(
        db_conn,
        """
        select resolution_status, resolved_to_entity_id, deleted_at
        from haven_knowledge.knowledge_entities where id=%s
        """,
        alex["id"],
    )
    assert preserved["resolution_status"] == "confirmed"
    assert preserved["resolved_to_entity_id"] == chen
    assert preserved["deleted_at"] is None


def test_resolution_target_must_be_canonical(setup, db_conn):
    service, auth, owner, entity_id = setup
    result = service.create_source_entry(
        auth, raw_text=RAW, primary_entity_id=str(entity_id), source_type="system_test",
    )
    run_fake_extraction(
        db_conn, owner, uuid.UUID(result["source_entry_id"]),
        uuid.UUID(result["source_entry_version_id"]), entity_id, "Sarah Tran",
    )
    alex = q1(db_conn, "select id from haven_knowledge.knowledge_entities where owner_id=%s and entity_state='provisional'", owner)
    with pytest.raises(ValueError, match="canonical"):
        service.resolve_reference(auth, str(alex["id"]), str(alex["id"]))


@pytest.mark.parametrize("decision", ["reject", "not_sure"])
def test_reference_decisions_reject_cross_tenant_ids(
    setup, db_conn, cleanup_owner, decision
):
    from haven_knowledge.identity import AuthContext

    service, auth, owner, entity_id = setup
    result = service.create_source_entry(
        auth, raw_text=RAW, primary_entity_id=str(entity_id), source_type="system_test",
    )
    run_fake_extraction(
        db_conn, owner, uuid.UUID(result["source_entry_id"]),
        uuid.UUID(result["source_entry_version_id"]), entity_id, "Sarah Tran",
    )
    alex = q1(
        db_conn,
        """
        select id from haven_knowledge.knowledge_entities
        where owner_id=%s and entity_state='provisional'
        """,
        owner,
    )
    candidate = mirror_convex_person(
        db_conn, owner, f"cx_{uuid.uuid4().hex[:8]}", "Alex Chen"
    )

    attacker = AuthContext(
        "clerk", "https://test.havens.invalid", f"attacker_{uuid.uuid4().hex}"
    )
    attacker_owner = service.ensure_owner(attacker)
    cleanup_owner.append(attacker_owner)

    with pytest.raises(ValueError, match="this owner"):
        if decision == "reject":
            service.reject_reference_candidate(attacker, str(alex["id"]), str(candidate))
        else:
            service.mark_reference_not_sure(attacker, str(alex["id"]), str(candidate))

    leaked = q1(
        db_conn,
        """
        select count(*) as n from haven_knowledge.reference_candidate_decisions
        where owner_id=%s
        """,
        attacker_owner,
    )
    assert leaked["n"] == 0


# ---------------------------------------------------------------- tenancy

def test_cross_tenant_isolation(db_conn, cleanup_owner):
    from haven_knowledge.identity import AuthContext

    service = KnowledgeService(db_conn)
    auth_a = AuthContext("clerk", "https://test.havens.invalid", f"ta_{uuid.uuid4().hex}")
    auth_b = AuthContext("clerk", "https://test.havens.invalid", f"tb_{uuid.uuid4().hex}")
    owner_a = service.ensure_owner(auth_a)
    owner_b = service.ensure_owner(auth_b)
    cleanup_owner.extend([owner_a, owner_b])

    sarah_a = mirror_convex_person(db_conn, owner_a, "cxa_sarah", "Sarah Nguyen")
    sarah_b = mirror_convex_person(db_conn, owner_b, "cxb_sarah", "Sarah Nguyen")
    ra = service.create_source_entry(
        auth_a, raw_text="Sarah loves woodworking and joinery.",
        primary_entity_id=str(sarah_a), source_type="system_test",
    )
    run_fake_extraction(
        db_conn, owner_a, uuid.UUID(ra["source_entry_id"]),
        uuid.UUID(ra["source_entry_version_id"]), sarah_a, "Sarah Nguyen",
        ValidatedExtraction(claims=[ValidatedClaim(
            subject_ref="primary", predicate_key="interested_in", custom_predicate_label=None,
            object_type="text", object_text="woodworking", object_mention_ref=None,
            polarity="positive", modality="stated", temporal_status="current",
            confidence=0.9, evidence_quote="Sarah loves woodworking",
            evidence_start=0, evidence_end=23,
        )]),
    )

    # B searching A's content: zero results on every path.
    assert service.search_network(auth_b, "woodworking")["results"] == []
    assert service.search_network(auth_b, "Sarah Nguyen")["results"] != []  # own Sarah, fast path
    fast = service.search_network(auth_b, "Sarah Nguyen")
    assert all(r["entity_id"] == str(sarah_b) for r in fast["results"])

    # B cannot read A's entry or entity.
    assert service.get_source_entry(auth_b, ra["source_entry_id"]) is None
    with pytest.raises(ValueError):
        service.get_person_knowledge(auth_b, str(sarah_a))

    # B's candidate listing can never contain A's people: build a provisional
    # for B named like A's person.
    rb = service.create_source_entry(
        auth_b, raw_text="Met someone through Sarah.", primary_entity_id=str(sarah_b),
        source_type="system_test",
    )
    run_fake_extraction(
        db_conn, owner_b, uuid.UUID(rb["source_entry_id"]),
        uuid.UUID(rb["source_entry_version_id"]), sarah_b, "Sarah Nguyen",
        ValidatedExtraction(
            mentions=[ValidatedMention("m1", "Sarah", 20, 25)],
            claims=[ValidatedClaim(
                subject_ref="primary", predicate_key="met_through", custom_predicate_label=None,
                object_type="mention", object_text=None, object_mention_ref="m1",
                polarity="positive", modality="stated", temporal_status="historical",
                confidence=0.8, evidence_quote="Met someone through Sarah.",
                evidence_start=0, evidence_end=26,
            )],
        ),
    )
    prov = q1(db_conn, "select id from haven_knowledge.knowledge_entities where owner_id=%s and entity_state='provisional'", owner_b)
    listing = service.list_reference_candidates(auth_b, str(prov["id"]))
    for candidate in listing["candidates"]:
        assert candidate["entity_id"] != str(sarah_a)


# ------------------------------------------------------------------ outbox

def test_concurrent_job_claiming_is_disjoint(setup, db_conn):
    service, auth, owner, entity_id = setup
    for i in range(4):
        service.create_source_entry(
            auth, raw_text=f"{RAW} Note {i}.", primary_entity_id=str(entity_id),
            source_type="system_test",
        )
    claimed: list[str] = []
    lock = threading.Lock()

    def claim_two():
        conn = db.connect()
        try:
            for _ in range(2):
                job = claim_next_job(conn, f"w_{threading.get_ident()}", ["extract_source"])
                if job is not None:
                    with lock:
                        claimed.append(str(job["id"]))
        finally:
            conn.close()

    threads = [threading.Thread(target=claim_two) for _ in range(2)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert len(claimed) == len(set(claimed)) == 4


def test_job_claiming_can_be_scoped_to_eval_owners(
    setup, db_conn, cleanup_owner
):
    from haven_knowledge.identity import AuthContext

    service, auth_a, owner_a, entity_a = setup
    auth_b = AuthContext(
        "clerk", "https://test.havens.invalid", f"scoped_{uuid.uuid4().hex}"
    )
    owner_b = service.ensure_owner(auth_b)
    cleanup_owner.append(owner_b)
    entity_b = mirror_convex_person(
        db_conn, owner_b, f"cx_{uuid.uuid4().hex[:8]}", "Other Person"
    )
    service.create_source_entry(
        auth_a, raw_text=RAW, primary_entity_id=str(entity_a), source_type="system_test",
    )
    service.create_source_entry(
        auth_b, raw_text=RAW, primary_entity_id=str(entity_b), source_type="system_test",
    )

    claimed = claim_next_job(
        db_conn, "eval-worker", ["extract_source"], owner_ids=[owner_b]
    )
    assert claimed is not None
    assert claimed["owner_id"] == owner_b

    untouched = q1(
        db_conn,
        """
        select count(*) as n from haven_knowledge.knowledge_outbox
        where owner_id=%s and job_type='extract_source' and status='pending'
        """,
        owner_a,
    )
    assert untouched["n"] == 1
