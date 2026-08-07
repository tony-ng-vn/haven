"""Environment configuration and feature flags for the knowledge service.

Secrets are read from the process environment only; nothing here logs or
returns a credential. The .env.local convention is the caller's job (the dev
harness and test conftest source it before importing us).
"""

from __future__ import annotations

import os
import uuid
from dataclasses import dataclass


class FeatureDisabled(Exception):
    """Raised when a knowledge operation runs while its flag is off."""


@dataclass(frozen=True)
class Flags:
    enabled: bool
    write_mode: str
    search_mode: str


def flags() -> Flags:
    return Flags(
        enabled=os.environ.get("HAVEN_KNOWLEDGE_V0_ENABLED", "") == "1",
        write_mode=os.environ.get("HAVEN_KNOWLEDGE_WRITE_MODE", "off"),
        search_mode=os.environ.get("HAVEN_KNOWLEDGE_SEARCH_MODE", "off"),
    )


def require_write() -> None:
    f = flags()
    if not f.enabled or f.write_mode == "off":
        raise FeatureDisabled("knowledge writes are disabled (HAVEN_KNOWLEDGE_WRITE_MODE)")


def require_search() -> None:
    f = flags()
    if not f.enabled or f.search_mode == "off":
        raise FeatureDisabled("knowledge search is disabled (HAVEN_KNOWLEDGE_SEARCH_MODE)")


def database_url() -> str:
    url = os.environ.get("DATABASE_URL", "")
    if "@" not in url:
        raise RuntimeError("DATABASE_URL with credentials is required")
    return url


def runtime_api_env() -> tuple[str, str]:
    key = os.environ.get("POLYGRES_API_KEY", "")
    url = os.environ.get("POLYGRES_RUNTIME_URL", "")
    if not key or not url:
        raise RuntimeError("POLYGRES_API_KEY and POLYGRES_RUNTIME_URL are required")
    return key, url


def new_request_id() -> str:
    return f"know_{uuid.uuid4().hex[:20]}"


# Provider configuration mirrors convex/openaiClient.ts: OPENAI_* is the
# default, EXTRACTION_* overrides all-or-nothing for the extraction model.
@dataclass(frozen=True)
class Provider:
    label: str
    base_url: str
    api_key: str
    model: str


def _require(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        raise RuntimeError(f"{name} is not set")
    return value


def extraction_provider() -> Provider:
    base = os.environ.get("EXTRACTION_BASE_URL", "")
    if base:
        return Provider(
            label="extraction",
            base_url=base,
            api_key=_require("EXTRACTION_API_KEY"),
            model=_require("EXTRACTION_MODEL"),
        )
    return Provider(
        label="openai",
        base_url=os.environ.get("OPENAI_BASE_URL", "https://api.openai.com"),
        api_key=_require("OPENAI_API_KEY"),
        model=os.environ.get("EXTRACTION_MODEL", "gpt-4o-mini"),
    )


def embedding_provider() -> Provider:
    # Vector similarity is meaningful only when queries and indexed rows use
    # one model. V0 pins that contract to Voyage rather than silently falling
    # back to a different 1024-dimension embedding space.
    return Provider(
        label="voyage",
        base_url="https://api.voyageai.com",
        api_key=_require("VOYAGE_API_KEY"),
        model="voyage-3.5",
    )


def embedding_dimensions() -> int:
    # Migration 0004 and the Polygres Runtime vector config are both fixed at
    # 1024, matching the pinned Voyage model.
    return 1024


def wait_on_embedding_rate_limit() -> bool:
    """Long waits are for workers and evals, never interactive requests."""
    return os.environ.get("HAVEN_EMBEDDING_WAIT_ON_RATE_LIMIT", "") == "1"
