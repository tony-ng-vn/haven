"""The validator is the policy boundary: whatever the model emits, only
well-evidenced claims survive."""

import pytest

from haven_knowledge.extraction import (
    ExtractionInvalid,
    validate_output,
)

RAW = "Met Sarah through Alex at YC Demo Day. She runs marathons."


def claim(**overrides):
    base = {
        "subject": "primary",
        "predicate": "participates_in",
        "custom_predicate_label": None,
        "object_type": "text",
        "object_text": "marathons",
        "object_mention_id": None,
        "polarity": "positive",
        "modality": "stated",
        "temporal_status": "current",
        "confidence": 0.9,
        "evidence_quote": "She runs marathons.",
        "evidence_start": 39,
        "evidence_end": 58,
    }
    base.update(overrides)
    return base


def out(mentions=None, claims=None):
    return {"mentions": mentions or [], "claims": claims or []}


def test_valid_claim_passes():
    result = validate_output(RAW, "Sarah", out(claims=[claim()]))
    assert len(result.claims) == 1
    assert result.claims[0].evidence_quote == "She runs marathons."


def test_wrong_offsets_relocated_deterministically():
    result = validate_output(RAW, "Sarah", out(claims=[claim(evidence_start=0, evidence_end=5)]))
    c = result.claims[0]
    assert RAW[c.evidence_start:c.evidence_end] == "She runs marathons."


def test_fabricated_quote_rejected():
    result = validate_output(RAW, "Sarah", out(claims=[claim(evidence_quote="Sarah is disciplined")]))
    assert result.claims == []
    assert "claim_evidence_not_in_source" in result.dropped


def test_unknown_subject_rejected():
    result = validate_output(RAW, "Sarah", out(claims=[claim(subject="m99")]))
    assert result.claims == []
    assert "claim_unknown_subject" in result.dropped


def test_unknown_predicate_rejected():
    result = validate_output(RAW, "Sarah", out(claims=[claim(predicate="is_disciplined")]))
    assert result.claims == []
    assert "claim_unknown_predicate" in result.dropped


def test_custom_predicate_requires_label():
    bad = validate_output(RAW, "Sarah", out(claims=[claim(predicate="custom")]))
    assert bad.claims == []
    good = validate_output(
        RAW, "Sarah", out(claims=[claim(predicate="custom", custom_predicate_label="ran a race with")])
    )
    assert good.claims[0].custom_predicate_label == "ran a race with"


def test_confidence_out_of_range_rejected():
    result = validate_output(RAW, "Sarah", out(claims=[claim(confidence=1.5)]))
    assert result.claims == []


def test_duplicate_claims_collapse():
    result = validate_output(RAW, "Sarah", out(claims=[claim(), claim()]))
    assert len(result.claims) == 1
    assert "claim_duplicate" in result.dropped


def test_mention_and_mention_object():
    mentions = [{"id": "m1", "surface_text": "Alex", "start": 18, "end": 22}]
    claims = [
        claim(
            predicate="met_through",
            object_type="mention",
            object_text=None,
            object_mention_id="m1",
            evidence_quote="Met Sarah through Alex",
            evidence_start=0,
            evidence_end=22,
        )
    ]
    result = validate_output(RAW, "Sarah", out(mentions=mentions, claims=claims))
    assert result.mentions[0].surface_text == "Alex"
    assert result.claims[0].object_mention_ref == "m1"


def test_mention_not_in_source_rejected():
    mentions = [{"id": "m1", "surface_text": "Bob", "start": 0, "end": 3}]
    result = validate_output(RAW, "Sarah", out(mentions=mentions))
    assert result.mentions == []
    assert "mention_not_in_source" in result.dropped


def test_bad_qualifiers_rejected():
    result = validate_output(RAW, "Sarah", out(claims=[claim(modality="probably")]))
    assert result.claims == []
    assert "claim_bad_qualifiers" in result.dropped


def test_negation_and_history_preserved():
    text = "Sarah is not looking for startup introductions right now."
    c = claim(
        predicate="looking_for",
        object_text="startup introductions",
        polarity="negative",
        evidence_quote=text,
        evidence_start=0,
        evidence_end=len(text),
    )
    result = validate_output(text, "Sarah", out(claims=[c]))
    assert result.claims[0].polarity == "negative"


def test_malformed_top_level_raises():
    with pytest.raises(ExtractionInvalid):
        validate_output(RAW, "Sarah", ["not", "an", "object"])
    with pytest.raises(ExtractionInvalid):
        validate_output(RAW, "Sarah", {"claims": []})


def test_model_output_cannot_reach_protected_fields():
    """The schema has no owner/lifecycle/derivation/resolution fields; even if
    the model smuggles them in, the validated claim carries none."""
    result = validate_output(
        RAW, "Sarah",
        out(claims=[{**claim(), "owner_id": "attacker", "lifecycle_status": "deleted"}]),
    )
    validated = result.claims[0]
    assert not hasattr(validated, "owner_id")
    assert not hasattr(validated, "lifecycle_status")
