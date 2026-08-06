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


def _worker_id() -> str:
    return f"{socket.gethostname()}:{uuid.uuid4().hex[:8]}"


def claim_next_job(conn: psycopg.Connection, worker_id: str, job_types: list[str]) -> dict[str, Any] | None:
    with db.transaction(conn) as cur:
        cur.execute(
            """
            select * from haven_knowledge.knowledge_outbox
            where status = 'pending' and available_at <= now() and job_type = any(%s)
            order by available_at
            for update skip locked
            limit 1
            """,
            (job_types,),
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
            where id = %s
            """,
            (status, error_code, delay, delay or 0, job["id"]),
        )
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
        _mark_noop_success(conn, job["id"])
        return

    provider = config.extraction_provider()
    with db.transaction(conn) as cur:
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
    )


def _process_embed(conn: psycopg.Connection, job: dict[str, Any]) -> None:
    item_id = uuid.UUID(job["payload"]["retrieval_item_id"])
    embed_retrieval_item(
        conn,
        config.embedding_provider(),
        owner_id=job["owner_id"],
        retrieval_item_id=item_id,
        outbox_job_id=job["id"],
    )


def _mark_noop_success(conn: psycopg.Connection, job_id: uuid.UUID) -> None:
    with db.transaction(conn) as cur:
        cur.execute(
            "update haven_knowledge.knowledge_outbox set status='succeeded', completed_at=now(), updated_at=now() where id = %s",
            (job_id,),
        )


HANDLERS = {
    "extract_source": _process_extract,
    "embed_retrieval_item": _process_embed,
    # Relations are graph-registered tables, so projection is a schema-level
    # concern in v0; the job types stay reserved for a future incremental
    # projector and an async supersession path.
    "project_graph": lambda conn, job: _mark_noop_success(conn, job["id"]),
    "deactivate_superseded_version": lambda conn, job: _mark_noop_success(conn, job["id"]),
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
            job = claim_next_job(conn, worker_id, types)
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
