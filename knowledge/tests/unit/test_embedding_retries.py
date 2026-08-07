"""Embedding provider retry behavior."""

from types import SimpleNamespace

import httpx
import pytest

from haven_knowledge import config
from haven_knowledge.config import Provider
from haven_knowledge.embeddings import EmbeddingFailed, embed_text


def _response(status_code: int, embedding: list[float] | None = None):
    data = [{"embedding": embedding}] if embedding is not None else []
    return SimpleNamespace(status_code=status_code, json=lambda: {"data": data})


def test_rate_limit_retries_cover_a_full_three_rpm_window(monkeypatch):
    responses = iter([
        _response(429),
        _response(429),
        _response(429),
        _response(200, [0.1, 0.2, 0.3]),
    ])
    sleeps: list[float] = []
    monkeypatch.setattr("haven_knowledge.embeddings.httpx.post", lambda *args, **kwargs: next(responses))
    monkeypatch.setattr("haven_knowledge.embeddings.time.sleep", sleeps.append)
    monkeypatch.setattr("haven_knowledge.embeddings.config.embedding_dimensions", lambda: 3)

    provider = Provider("voyage", "https://example.invalid", "secret", "test-model")
    assert embed_text(provider, "hello", wait_on_rate_limit=True) == [0.1, 0.2, 0.3]
    assert sum(sleeps) >= 60


def test_rate_limit_exhaustion_returns_only_a_safe_code(monkeypatch):
    monkeypatch.setattr(
        "haven_knowledge.embeddings.httpx.post",
        lambda *args, **kwargs: _response(429),
    )
    monkeypatch.setattr("haven_knowledge.embeddings.time.sleep", lambda _: None)

    provider = Provider("voyage", "https://example.invalid", "secret", "test-model")
    with pytest.raises(EmbeddingFailed, match="^provider_status_429$"):
        embed_text(provider, "private memory text", wait_on_rate_limit=True)


def test_interactive_embedding_fails_fast_on_rate_limit(monkeypatch):
    calls = 0
    sleeps: list[float] = []

    def post(*args, **kwargs):
        nonlocal calls
        calls += 1
        return _response(429)

    monkeypatch.setattr("haven_knowledge.embeddings.httpx.post", post)
    monkeypatch.setattr("haven_knowledge.embeddings.time.sleep", sleeps.append)

    provider = Provider("voyage", "https://example.invalid", "secret", "test-model")
    with pytest.raises(EmbeddingFailed, match="^provider_status_429$"):
        embed_text(provider, "private memory text")
    assert calls == 1
    assert sleeps == []


def test_generic_openai_adapter_requests_the_schema_dimension(monkeypatch):
    requests: list[dict] = []

    def post(*args, **kwargs):
        requests.append(kwargs["json"])
        return _response(200, [0.1, 0.2, 0.3])

    monkeypatch.setattr("haven_knowledge.embeddings.httpx.post", post)
    monkeypatch.setattr("haven_knowledge.embeddings.config.embedding_dimensions", lambda: 3)

    provider = Provider("openai", "https://example.invalid", "secret", "text-embedding-3-small")
    assert embed_text(provider, "hello") == [0.1, 0.2, 0.3]
    assert requests == [
        {"model": "text-embedding-3-small", "input": ["hello"], "dimensions": 3}
    ]


def test_embedding_dimension_always_matches_the_polygres_schema(monkeypatch):
    assert config.embedding_dimensions() == 1024


def test_embedding_provider_does_not_fall_back_across_model_spaces(monkeypatch):
    monkeypatch.delenv("VOYAGE_API_KEY", raising=False)
    monkeypatch.setenv("OPENAI_API_KEY", "openai-secret")

    with pytest.raises(RuntimeError, match="VOYAGE_API_KEY is not set"):
        config.embedding_provider()


def test_embedding_transport_failure_returns_only_a_safe_code(monkeypatch):
    def post(*args, **kwargs):
        raise httpx.ConnectError("private provider failure")

    monkeypatch.setattr("haven_knowledge.embeddings.httpx.post", post)
    provider = Provider("voyage", "https://example.invalid", "secret", "test-model")

    with pytest.raises(EmbeddingFailed, match="^provider_unreachable$"):
        embed_text(provider, "private memory text")


def test_embedding_non_json_response_returns_only_a_safe_code(monkeypatch):
    response = SimpleNamespace(
        status_code=200,
        json=lambda: (_ for _ in ()).throw(ValueError("private response body")),
    )
    monkeypatch.setattr("haven_knowledge.embeddings.httpx.post", lambda *a, **k: response)
    provider = Provider("voyage", "https://example.invalid", "secret", "test-model")

    with pytest.raises(EmbeddingFailed, match="^provider_bad_json$"):
        embed_text(provider, "private memory text")


@pytest.mark.parametrize("data", [[None], ["not-an-object"], [{}]])
def test_embedding_malformed_data_item_returns_only_a_safe_code(monkeypatch, data):
    response = SimpleNamespace(status_code=200, json=lambda: {"data": data})
    monkeypatch.setattr("haven_knowledge.embeddings.httpx.post", lambda *a, **k: response)
    provider = Provider("voyage", "https://example.invalid", "secret", "test-model")

    with pytest.raises(EmbeddingFailed, match="^provider_bad_json$"):
        embed_text(provider, "private memory text")


@pytest.mark.parametrize("value", ["0.1", None, float("inf"), float("nan")])
def test_embedding_invalid_elements_return_bad_dimensions(monkeypatch, value):
    monkeypatch.setattr("haven_knowledge.embeddings.config.embedding_dimensions", lambda: 1)
    response = SimpleNamespace(
        status_code=200,
        json=lambda: {"data": [{"embedding": [value]}]},
    )
    monkeypatch.setattr("haven_knowledge.embeddings.httpx.post", lambda *a, **k: response)
    provider = Provider("voyage", "https://example.invalid", "secret", "test-model")

    with pytest.raises(EmbeddingFailed, match="^bad_dimensions$"):
        embed_text(provider, "private memory text")
