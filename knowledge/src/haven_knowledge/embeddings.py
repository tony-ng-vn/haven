"""Embedding generation for retrieval items. Haven populates the vector
column; Polygres only indexes it. Input hash is the idempotency key, matching
the Convex embeddedText contract in spirit."""

from __future__ import annotations

import hashlib
import math
import uuid

import httpx
import psycopg

from . import config, db
from .config import Provider


class EmbeddingFailed(Exception):
    """Safe code only; never carries the input text."""


def embed_text(provider: Provider, text: str) -> list[float]:
    # Voyage and OpenAI share the request shape closely enough: POST
    # /v1/embeddings {model, input} -> data[0].embedding. Voyage takes input
    # as a list; OpenAI accepts both.
    response = httpx.post(
        f"{provider.base_url}/v1/embeddings",
        headers={"Authorization": f"Bearer {provider.api_key}"},
        json={"model": provider.model, "input": [text[:8000]]},
        timeout=60,
    )
    if response.status_code != 200:
        raise EmbeddingFailed(f"provider_status_{response.status_code}")
    data = response.json().get("data", [])
    embedding = data[0].get("embedding") if data else None
    expected = config.embedding_dimensions()
    if not isinstance(embedding, list) or len(embedding) != expected:
        raise EmbeddingFailed("bad_dimensions")
    if any(not math.isfinite(v) for v in embedding):
        raise EmbeddingFailed("non_finite_values")
    return embedding


def input_hash(model: str, text: str) -> str:
    return hashlib.sha256(f"{model}\x00{text}".encode("utf-8")).hexdigest()


def embed_retrieval_item(
    conn: psycopg.Connection,
    provider: Provider,
    *,
    owner_id: uuid.UUID,
    retrieval_item_id: uuid.UUID,
    outbox_job_id: uuid.UUID,
) -> str:
    """Returns a status string: embedded | skipped_unchanged | skipped_inactive."""
    with conn.cursor() as cur:
        cur.execute(
            """
            select retrieval_text, lifecycle_status, embedding_status, embedding_input_hash
            from haven_knowledge.retrieval_items
            where id = %s and owner_id = %s
            """,
            (retrieval_item_id, owner_id),
        )
        row = cur.fetchone()
    if row is None or row["lifecycle_status"] != "active":
        outcome = "skipped_inactive"
    else:
        text = row["retrieval_text"]
        digest = input_hash(provider.model, text)
        if row["embedding_status"] == "ready" and row["embedding_input_hash"] == digest:
            outcome = "skipped_unchanged"
        else:
            embedding = embed_text(provider, text)  # outside any transaction
            with db.transaction(conn) as cur:
                cur.execute(
                    """
                    update haven_knowledge.retrieval_items
                    set embedding = %s::vector, embedding_model = %s,
                        embedding_dimensions = %s, embedding_input_hash = %s,
                        embedding_status = 'ready', updated_at = now()
                    where id = %s and owner_id = %s and lifecycle_status = 'active'
                    """,
                    (
                        db.vector_literal(embedding), provider.model,
                        len(embedding), digest, retrieval_item_id, owner_id,
                    ),
                )
            outcome = "embedded"
    with db.transaction(conn) as cur:
        cur.execute(
            """
            update haven_knowledge.knowledge_outbox
            set status = 'succeeded', completed_at = now(), updated_at = now()
            where id = %s
            """,
            (outbox_job_id,),
        )
    return outcome
