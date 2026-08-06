"""Test wiring. Unit tests need nothing. Tests marked db/runtime/model skip
honestly (with a visible reason) when their environment is missing -- a skip
is never reported as a pass."""

from __future__ import annotations

import os
import uuid

import pytest


def _has_db() -> bool:
    return "@" in os.environ.get("DATABASE_URL", "") and ":" in os.environ.get(
        "DATABASE_URL", ""
    ).split("@")[0]


def _has_runtime() -> bool:
    return bool(os.environ.get("POLYGRES_API_KEY")) and bool(
        os.environ.get("POLYGRES_RUNTIME_URL")
    )


def _has_embeddings() -> bool:
    return bool(os.environ.get("VOYAGE_API_KEY") or os.environ.get("OPENAI_API_KEY"))


def _has_extraction() -> bool:
    return bool(os.environ.get("EXTRACTION_API_KEY") or os.environ.get("OPENAI_API_KEY"))


def pytest_collection_modifyitems(config, items):
    skip_db = pytest.mark.skip(reason="DATABASE_URL with credentials not set")
    skip_rt = pytest.mark.skip(reason="POLYGRES_API_KEY / POLYGRES_RUNTIME_URL not set")
    skip_model = pytest.mark.skip(reason="no model provider credentials")
    for item in items:
        if "db" in item.keywords and not _has_db():
            item.add_marker(skip_db)
        if "runtime" in item.keywords and not (_has_runtime() and _has_db()):
            item.add_marker(skip_rt)
        if "model" in item.keywords and not (_has_extraction() and _has_db()):
            item.add_marker(skip_model)


@pytest.fixture(autouse=True)
def knowledge_flags(monkeypatch):
    monkeypatch.setenv("HAVEN_KNOWLEDGE_V0_ENABLED", "1")
    monkeypatch.setenv("HAVEN_KNOWLEDGE_WRITE_MODE", "primary")
    monkeypatch.setenv("HAVEN_KNOWLEDGE_SEARCH_MODE", "primary")


@pytest.fixture
def db_conn():
    from haven_knowledge import db

    conn = db.connect()
    yield conn
    conn.close()


@pytest.fixture
def test_auth():
    """A unique identity per test, so tests never see each other's rows and
    cleanup is exact."""
    from haven_knowledge.identity import AuthContext

    return AuthContext(
        provider="clerk",
        issuer="https://test.havens.invalid",
        subject=f"test_{uuid.uuid4().hex}",
    )


@pytest.fixture
def cleanup_owner(db_conn):
    """Deletes every row belonging to owners registered during the test, in
    FK order, so the shared development schema stays clean."""
    owners: list[uuid.UUID] = []
    yield owners
    if not owners:
        return
    with db_conn.transaction():
        with db_conn.cursor() as cur:
            for table in [
                "reference_candidate_decisions",
                "knowledge_outbox",
                "retrieval_items",
                "claim_concepts",
                "entity_relations",
                "knowledge_claims",
                "entity_mentions",
                "extraction_runs",
            ]:
                cur.execute(
                    f"delete from haven_knowledge.{table} where owner_id = any(%s)",
                    (owners,),
                )
            cur.execute(
                "update haven_knowledge.source_entries set current_version_id = null where owner_id = any(%s)",
                (owners,),
            )
            cur.execute(
                "delete from haven_knowledge.source_entry_versions where owner_id = any(%s)",
                (owners,),
            )
            cur.execute(
                "delete from haven_knowledge.source_entries where owner_id = any(%s)",
                (owners,),
            )
            cur.execute(
                "delete from haven_knowledge.knowledge_entities where owner_id = any(%s)",
                (owners,),
            )
            cur.execute(
                "delete from haven_knowledge.auth_identities where haven_user_id = any(%s)",
                (owners,),
            )
            cur.execute(
                "delete from haven_knowledge.haven_users where id = any(%s)",
                (owners,),
            )
