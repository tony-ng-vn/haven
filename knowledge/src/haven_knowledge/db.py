"""Postgres access. One pooled-endpoint connection per logical unit of work;
the worker holds its own. psycopg3, autocommit off, explicit transactions."""

from __future__ import annotations

import contextlib
from collections.abc import Iterator

import psycopg
from psycopg.rows import dict_row

from . import config


def connect() -> psycopg.Connection:
    # autocommit=True is the psycopg3 pattern that makes conn.transaction()
    # blocks real BEGIN/COMMIT units: without it, any plain read opens an
    # implicit transaction, transaction() degrades to a savepoint inside it,
    # and close() rolls the whole thing back.
    return psycopg.connect(
        config.database_url(), row_factory=dict_row, autocommit=True
    )


@contextlib.contextmanager
def transaction(conn: psycopg.Connection) -> Iterator[psycopg.Cursor]:
    with conn.transaction():
        with conn.cursor() as cur:
            yield cur


def vector_literal(embedding: list[float]) -> str:
    # pgvector's input format; values come from the embedding provider and are
    # validated finite floats before this point.
    return "[" + ",".join(f"{v:.8g}" for v in embedding) + "]"
