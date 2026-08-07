"""Unit coverage for the pure pieces: hashing, routing, fusion, rendering,
identity, concepts."""

import uuid

import pytest

from haven_knowledge.concepts import concept_key, match_concepts, _singular
from haven_knowledge.entries import content_hash, validate_raw_text
from haven_knowledge.embeddings import input_hash
from haven_knowledge.identity import AuthContext, clerk_context, normalize_name
from haven_knowledge.pipeline import claim_retrieval_text
from haven_knowledge.retrieval import StrategyResult, reciprocal_rank_fusion, vector_search
from haven_knowledge.router import plan_query


# ------------------------------------------------------------------ hashing

def test_content_hash_stable_and_distinct():
    assert content_hash("a") == content_hash("a")
    assert content_hash("a") != content_hash("b")


def test_input_hash_binds_model_and_text():
    assert input_hash("m1", "t") != input_hash("m2", "t")
    assert input_hash("m1", "t") != input_hash("m1", "u")


def test_raw_text_validation():
    with pytest.raises(ValueError):
        validate_raw_text("   ")
    with pytest.raises(ValueError):
        validate_raw_text("x" * 20_001)
    assert validate_raw_text("ok") == "ok"


# ----------------------------------------------------------------- identity

def test_clerk_context_parses_token_identifier():
    ctx = clerk_context("https://clerk.example.com|user_123")
    assert ctx.issuer == "https://clerk.example.com"
    assert ctx.subject == "user_123"
    with pytest.raises(ValueError):
        clerk_context("no-separator")


def test_auth_context_rejects_empty_fields():
    with pytest.raises(ValueError):
        AuthContext(provider="clerk", issuer=" ", subject="s")


def test_normalize_name_folds_accents_and_case():
    assert normalize_name("  S\u00c1RAH   Tr\u1ea7n ") == "sarah tran"


# ------------------------------------------------------------------- router

@pytest.mark.parametrize(
    "query,path",
    [
        ("Sarah Tran", "fast"),
        ("sarah", "fast"),
        ("who introduced me to Sarah?", "relationship"),
        ("Who introduced Sarah", "relationship"),
        ("how do i know Daniel?", "relationship"),
        ("who did I meet through Maya?", "relationship"),
        ("anyone into endurance sports?", "standard"),
        ("who runs marathons", "standard"),
        ("looking for a designer", "standard"),
    ],
)
def test_query_routing(query, path):
    assert plan_query(query).path == path


def test_relationship_target_extracted():
    plan = plan_query("who introduced me to Sarah?")
    assert plan.target_name == "Sarah"


# --------------------------------------------------------------------- RRF

def test_rrf_is_deterministic_and_merges_strategies():
    lexical = StrategyResult("lexical", ["a", "b", "c"])
    vector = StrategyResult("vector", ["b", "a", "d"])
    fused = reciprocal_rank_fusion([lexical, vector])
    ids = [f.item_id for f in fused]
    assert ids[0] in ("a", "b") and set(ids) == {"a", "b", "c", "d"}
    top = fused[0]
    assert sorted(top.strategies) == ["lexical", "vector"]
    again = reciprocal_rank_fusion([lexical, vector])
    assert [f.item_id for f in again] == ids


def test_rrf_double_hit_beats_single_hit():
    fused = reciprocal_rank_fusion(
        [StrategyResult("lexical", ["only_lex", "both"]), StrategyResult("vector", ["both"])]
    )
    assert fused[0].item_id == "both"


def test_rrf_tie_breaks_by_id():
    fused = reciprocal_rank_fusion([StrategyResult("lexical", ["b"]), StrategyResult("vector", ["a"])])
    assert [f.item_id for f in fused] == ["a", "b"]


def test_vector_search_rejects_a_mixed_or_changed_embedding_model(monkeypatch):
    class Connection:
        def close(self):
            pass

    monkeypatch.setattr("haven_knowledge.retrieval.db.connect", Connection)
    monkeypatch.setattr(
        "haven_knowledge.retrieval.active_embedding_models",
        lambda _conn, _owner: {"older-model"},
    )
    monkeypatch.setattr(
        "haven_knowledge.retrieval.config.embedding_provider",
        lambda: type("Provider", (), {"model": "configured-model"})(),
    )
    result = vector_search(uuid.uuid4(), "query")

    assert result.ranked_item_ids == []
    assert result.error == "embedding_model_mismatch"


# ------------------------------------------------------- claim text rendering

def test_negative_claim_renders_negation():
    text = claim_retrieval_text(
        "Sarah", "looking_for", None, "startup introductions",
        "negative", "stated", "current", [],
    )
    assert "not" in text or "does not" in text
    assert "startup introductions" in text


def test_uncertain_and_historical_render_qualifiers():
    text = claim_retrieval_text(
        "Sarah", "interested_in", None, "education startups",
        "positive", "uncertain", "current", [],
    )
    assert "(uncertain)" in text
    text2 = claim_retrieval_text(
        "Sarah", "worked_at", None, "Google", "positive", "stated", "historical", [],
    )
    assert "(in the past)" in text2


def test_concepts_ride_along_for_lexical_recall():
    text = claim_retrieval_text(
        "Sarah", "participates_in", None, "marathons",
        "positive", "stated", "current",
        ["marathon running", "endurance sport"],
    )
    assert "endurance sport" in text


# ----------------------------------------------------------------- concepts

def test_concept_key_normalizes():
    assert concept_key("Marathon Running!") == "marathon_running"


def test_singularization_is_conservative():
    assert _singular("marathons") == "marathon"
    assert _singular("runs") == "run"
    # Three-letter tokens are left alone rather than mangled ("gas", "des").
    assert _singular("gas") == "gas"


def test_exact_concept_match_is_not_mislabeled_as_normalized():
    concept_id = uuid.uuid4()

    class Cursor:
        def execute(self, _query, _params=None):
            pass

        def fetchall(self):
            return [{"id": concept_id, "concept_key": "running"}]

    assert match_concepts(Cursor(), "running") == [(concept_id, "exact")]
