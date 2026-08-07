"""Durable outbox worker. Claims jobs with FOR UPDATE SKIP LOCKED, retries
with bounded exponential backoff, parks permanent failures as dead, and never
logs raw memory text -- job ids and safe codes only."""

from __future__ import annotations

import datetime as dt
import logging
import socket
import time
import uuid
from typing import Any

import psycopg

from . import config, db
from .embeddings import EmbeddingFailed, embed_retrieval_item
from .extraction import (
    EXTRACTION_POLICY_VERSION,
    PROMPT_VERSION,
    ExtractionInvalid,
    run_extraction,
)
from .pipeline import persist_extraction

log = logging.getLogger("haven_knowledge.worker")

MAX_ATTEMPTS = 4
BACKOFF_BASE_SECONDS = 30
STALE_LOCK_SECONDS = 10 * 60


def _worker_id() -> str:
    return f"{socket.gethostname()}:{uuid.uuid4().hex[:8]}"


def reclaim_stale_jobs(
    conn: psycopg.Connection,
    *,
    stale_after_seconds: int = STALE_LOCK_SECONDS,
    owner_ids: list[uuid.UUID] | None = None,
) -> int:
    """Return jobs abandoned by a crashed worker to the durable queue."""
    with db.transaction(conn) as cur:
        # Discover candidates without taking an outbox lock. Extraction
        # completion locks its run before its job, so reclamation must use the
        # same order to avoid a lock cycle.
        cur.execute(
            """
            select id
            from haven_knowledge.knowledge_outbox
            where status = 'running' and locked_at is not null
              and locked_at <= now() - make_interval(secs => %s)
              and (%s::uuid[] is null or owner_id = any(%s::uuid[]))
            """,
            (stale_after_seconds, owner_ids, owner_ids),
        )
        candidate_ids = [row["id"] for row in cur.fetchall()]
        if not candidate_ids:
            return 0

        cur.execute(
            """
            select r.id
            from haven_knowledge.extraction_runs r
            join haven_knowledge.knowledge_outbox o
              on o.owner_id = r.owner_id
             and o.source_entry_version_id = r.source_entry_version_id
            where o.id = any(%s::uuid[]) and o.job_type = 'extract_source'
              and r.status = 'running'
            order by r.id
            for update of r
            """,
            (candidate_ids,),
        )
        cur.fetchall()
        cur.execute(
            """
            select id, attempt_count
            from haven_knowledge.knowledge_outbox
            where id = any(%s::uuid[]) and status = 'running'
              and locked_at is not null
              and locked_at <= now() - make_interval(secs => %s)
              and (%s::uuid[] is null or owner_id = any(%s::uuid[]))
            order by id
            for update
            """,
            (candidate_ids, stale_after_seconds, owner_ids, owner_ids),
        )
        stale_jobs = cur.fetchall()
        stale_job_ids = [row["id"] for row in stale_jobs]
        if not stale_job_ids:
            return 0

        # Extraction status is user-visible. Close any run abandoned with the
        # stale lease before making the durable job available for a new try.
        cur.execute(
            """
            update haven_knowledge.extraction_runs r
            set status = 'failed', completed_at = now(),
                error_code = 'worker_lease_expired',
                safe_error_message = case
                    when o.attempt_count >= %s
                    then 'extraction worker lease expired; retry limit reached'
                    else 'extraction worker lease expired; job will retry'
                end
            from haven_knowledge.knowledge_outbox o
            where o.id = any(%s::uuid[]) and o.job_type = 'extract_source'
              and r.owner_id = o.owner_id
              and r.source_entry_version_id = o.source_entry_version_id
              and r.status = 'running'
            """,
            (MAX_ATTEMPTS, stale_job_ids),
        )
        cur.execute(
            """
            update haven_knowledge.knowledge_outbox
            set status = case when attempt_count >= %s then 'dead' else 'pending' end,
                locked_at = null, locked_by = null,
                available_at = case when attempt_count >= %s then available_at else now() end,
                completed_at = case when attempt_count >= %s then now() else null end,
                last_error_code = case
                    when attempt_count >= %s then 'stale_lock_retry_limit'
                    else 'stale_lock_reclaimed'
                end,
                updated_at = now()
            where id = any(%s::uuid[])
            """,
            (MAX_ATTEMPTS, MAX_ATTEMPTS, MAX_ATTEMPTS, MAX_ATTEMPTS, stale_job_ids),
        )
        return len(stale_job_ids)


def claim_next_job(
    conn: psycopg.Connection,
    worker_id: str,
    job_types: list[str],
    *,
    owner_ids: list[uuid.UUID] | None = None,
) -> dict[str, Any] | None:
    with db.transaction(conn) as cur:
        cur.execute(
            """
            select * from haven_knowledge.knowledge_outbox
            where status = 'pending' and available_at <= now() and job_type = any(%s)
              and (%s::uuid[] is null or owner_id = any(%s::uuid[]))
            order by available_at
            for update skip locked
            limit 1
            """,
            (job_types, owner_ids, owner_ids),
        )
        job = cur.fetchone()
        if job is None:
            return None
        cur.execute(
            """
            update haven_knowledge.knowledge_outbox
            set status = 'running', locked_at = now(), locked_by = %s,
                attempt_count = attempt_count + 1, updated_at = now()
            where id = %s
            """,
            (worker_id, job["id"]),
        )
        job["attempt_count"] = job["attempt_count"] + 1
        job["locked_by"] = worker_id
        return job


def _record_failure(conn: psycopg.Connection, job: dict[str, Any], error_code: str) -> None:
    attempts = job["attempt_count"]
    if attempts >= MAX_ATTEMPTS:
        status, delay = "dead", None
    else:
        status = "pending"
        delay = BACKOFF_BASE_SECONDS * (2 ** (attempts - 1))
    with db.transaction(conn) as cur:
        cur.execute(
            """
            update haven_knowledge.knowledge_outbox
            set status = %s, last_error_code = %s, locked_at = null, locked_by = null,
                available_at = case when %s::int is null then available_at
                                    else now() + make_interval(secs => %s) end,
                updated_at = now()
            where id = %s and status = 'running' and locked_by = %s
            """,
            (status, error_code, delay, delay or 0, job["id"], job["locked_by"]),
        )
        updated = cur.rowcount
    if updated == 0:
        log.warning("job %s lost its worker lease before failure handling", job["id"])
        return
    log.warning(
        "job %s (%s) failed with %s; status now %s",
        job["id"], job["job_type"], error_code, status,
    )


def _process_extract(conn: psycopg.Connection, job: dict[str, Any]) -> None:
    owner_id = job["owner_id"]
    version_id = job["source_entry_version_id"]
    with conn.cursor() as cur:
        cur.execute(
            """
            select v.id as version_id, v.raw_text, v.captured_at,
                   e.id, e.owner_id, e.primary_entity_id, e.lifecycle_status,
                   e.current_version_id,
                   ent.display_name as primary_name
            from haven_knowledge.source_entry_versions v
            join haven_knowledge.source_entries e on e.id = v.source_entry_id
            join haven_knowledge.knowledge_entities ent on ent.id = e.primary_entity_id
            where v.id = %s and v.owner_id = %s
            """,
            (version_id, owner_id),
        )
        row = cur.fetchone()
    if row is None or row["lifecycle_status"] != "active" or row["current_version_id"] != version_id:
        # Deleted or already-superseded before extraction ran: succeed as no-op.
        _mark_noop_success(conn, job)
        return

    with db.transaction(conn) as cur:
        cur.execute(
            """
            select status, locked_by
            from haven_knowledge.knowledge_outbox
            where id = %s and owner_id = %s
            for update
            """,
            (job["id"], owner_id),
        )
        lease = cur.fetchone()
        if (
            lease is None
            or lease["status"] != "running"
            or lease["locked_by"] != job["locked_by"]
        ):
            return
        provider = config.extraction_provider()
        cur.execute(
            """
            insert into haven_knowledge.extraction_runs
                (owner_id, source_entry_id, source_entry_version_id,
                 extraction_policy_version, prompt_version, model_provider,
                 model_name, status, attempt_count, started_at)
            values (%s, %s, %s, %s, %s, %s, %s, 'running', %s, now())
            returning id
            """,
            (
                owner_id, row["id"], version_id, EXTRACTION_POLICY_VERSION,
                PROMPT_VERSION, provider.label, provider.model, job["attempt_count"],
            ),
        )
        run_id = cur.fetchone()["id"]

    try:
        extraction = run_extraction(
            provider,
            primary_name=row["primary_name"],
            raw_text=row["raw_text"],
            captured_at_iso=row["captured_at"].isoformat(),
        )
    except Exception as exc:
        code = str(exc) if isinstance(exc, ExtractionInvalid) else "provider_error"
        with db.transaction(conn) as cur:
            cur.execute(
                """
                update haven_knowledge.extraction_runs
                set status = 'failed', completed_at = now(), error_code = %s,
                    safe_error_message = 'extraction failed; raw source remains searchable'
                where id = %s
                """,
                (code, run_id),
            )
        raise

    persist_extraction(
        conn,
        owner_id=owner_id,
        entry={"id": row["id"]},
        version_id=version_id,
        run_id=run_id,
        primary_entity_id=row["primary_entity_id"],
        primary_name=row["primary_name"],
        extraction=extraction,
        outbox_job_id=job["id"],
        lease_owner=job["locked_by"],
    )


def _process_embed(conn: psycopg.Connection, job: dict[str, Any]) -> None:
    item_id = uuid.UUID(job["payload"]["retrieval_item_id"])
    embed_retrieval_item(
        conn,
        config.embedding_provider(),
        owner_id=job["owner_id"],
        retrieval_item_id=item_id,
        outbox_job_id=job["id"],
        lease_owner=job["locked_by"],
    )


def _mark_noop_success(conn: psycopg.Connection, job: dict[str, Any]) -> None:
    with db.transaction(conn) as cur:
        cur.execute(
            """
            update haven_knowledge.knowledge_outbox
            set status='succeeded', completed_at=now(), updated_at=now()
            where id = %s and status='running' and locked_by=%s
            """,
            (job["id"], job["locked_by"]),
        )


HANDLERS = {
    "extract_source": _process_extract,
    "embed_retrieval_item": _process_embed,
    # Relations are graph-registered tables, so projection is a schema-level
    # concern in v0; the job types stay reserved for a future incremental
    # projector and an async supersession path.
    "project_graph": _mark_noop_success,
    "deactivate_superseded_version": _mark_noop_success,
}


def process_one(conn: psycopg.Connection, job: dict[str, Any]) -> bool:
    try:
        HANDLERS[job["job_type"]](conn, job)
        return True
    except EmbeddingFailed as exc:
        _record_failure(conn, job, str(exc))
    except ExtractionInvalid as exc:
        _record_failure(conn, job, str(exc))
    except Exception:
        log.exception("job %s (%s) crashed", job["id"], job["job_type"])
        _record_failure(conn, job, "internal_error")
    return False


def run_worker(
    *,
    job_types: list[str] | None = None,
    max_jobs: int | None = None,
    idle_exit: bool = False,
    poll_seconds: float = 2.0,
    owner_ids: list[uuid.UUID] | None = None,
) -> int:
    """Run until stopped (or the queue drains, with idle_exit). Separate
    invocations with different job_types give each stage its own concurrency
    lane, keeping bulk extraction from starving embeds and vice versa."""
    config.require_write()
    worker_id = _worker_id()
    types = job_types or list(HANDLERS.keys())
    processed = 0
    conn = db.connect()
    try:
        while max_jobs is None or processed < max_jobs:
            reclaimed = reclaim_stale_jobs(conn, owner_ids=owner_ids)
            if reclaimed:
                log.warning("reclaimed %s stale outbox job(s)", reclaimed)
            job = claim_next_job(conn, worker_id, types, owner_ids=owner_ids)
            if job is None:
                if idle_exit:
                    break
                time.sleep(poll_seconds)
                continue
            process_one(conn, job)
            processed += 1
    finally:
        conn.close()
    return processed
