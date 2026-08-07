"""Stable Haven user identity. External identities (Clerk today) map to an
internal haven_users UUID; the client never supplies owner_id.

The AuthContext is constructed server-side from a verified identity. In this
v0 library the verification boundary is the caller (the dev harness uses a
designated development identity; a future HTTP transport verifies the Clerk
JWT against the instance JWKS before building the context)."""

from __future__ import annotations

import re
import unicodedata
import uuid
from dataclasses import dataclass

import psycopg

from . import db


@dataclass(frozen=True)
class AuthContext:
    provider: str
    issuer: str
    subject: str

    def __post_init__(self) -> None:
        for field in (self.provider, self.issuer, self.subject):
            if not field or not field.strip():
                raise ValueError("AuthContext fields must be non-empty")


def clerk_context(token_identifier: str) -> AuthContext:
    # Convex stores Clerk identity as "issuer|subject"; accept that shape so a
    # future bridge can hand it over unchanged.
    issuer, _, subject = token_identifier.partition("|")
    if not issuer or not subject:
        raise ValueError("expected 'issuer|subject'")
    return AuthContext(provider="clerk", issuer=issuer, subject=subject)


def ensure_owner(conn: psycopg.Connection, auth: AuthContext) -> uuid.UUID:
    """Resolve (and on first sight create) the Haven user for an identity.

    A transaction-scoped advisory lock serializes first sight of the same
    external identity, so a losing login cannot leave an orphan Haven user."""
    with db.transaction(conn) as cur:
        lock_key = "\x1f".join((auth.provider, auth.issuer, auth.subject))
        cur.execute("select pg_advisory_xact_lock(hashtextextended(%s, 0))", (lock_key,))
        cur.execute(
            """
            select haven_user_id from haven_knowledge.auth_identities
            where provider = %s and issuer = %s and provider_subject = %s
            """,
            (auth.provider, auth.issuer, auth.subject),
        )
        row = cur.fetchone()
        if row is not None:
            return row["haven_user_id"]
        cur.execute("insert into haven_knowledge.haven_users default values returning id")
        user_id = cur.fetchone()["id"]
        cur.execute(
            """
            insert into haven_knowledge.auth_identities
                (haven_user_id, provider, issuer, provider_subject)
            values (%s, %s, %s, %s)
            returning haven_user_id
            """,
            (user_id, auth.provider, auth.issuer, auth.subject),
        )
        inserted = cur.fetchone()
        if inserted is None:
            raise RuntimeError("identity creation returned no owner")
        return inserted["haven_user_id"]


def normalize_name(name: str) -> str:
    """Accent-folded, lowercased, whitespace-collapsed key, mirroring the
    intent of convex/nameSearch.ts normalizeName."""
    decomposed = unicodedata.normalize("NFKD", name)
    stripped = "".join(c for c in decomposed if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", stripped.lower().strip())
