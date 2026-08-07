"""Conservative concept normalization. Claims about activities and domains
map to seeded concepts by normalized key match; taxonomy parents come from
concept_edges. Nothing here writes new concepts or edges: the taxonomy is
seed-only in v0, so concept coverage is exactly as conservative as the seed."""

from __future__ import annotations

import re
import uuid

import psycopg

from .identity import normalize_name

# Predicates whose text objects describe activities or domains worth
# normalizing. Relationship and location predicates are left alone. "custom"
# is included because models phrase activities through custom predicates
# ("runs marathons"); mapping stays safe because only seeded concept keys can
# match, so a location or organization object simply maps to nothing.
CONCEPT_BEARING_PREDICATES = {
    "interested_in", "exploring", "participates_in", "building",
    "skilled_at", "needs", "offers", "looking_for", "custom",
}


def concept_key(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", normalize_name(text)).strip("_")


def _singular(key: str) -> str:
    # "runs marathons" -> marathon; deliberately dumb: strip one trailing s
    # from each token. Conservative by construction: a miss means no mapping,
    # never a wrong one, because mapping requires an exact seeded key match.
    return "_".join(t[:-1] if t.endswith("s") and len(t) > 3 else t for t in key.split("_"))


# Tokens a concept key and a claim object may disagree on without changing
# meaning ("marathons" vs "marathon running"). Closed set on purpose: outside
# it, a loose match would generalize wrongly ("education" is not education
# startups), and a miss is always safer than a wrong mapping.
_FILLER_TOKENS = {"running", "sport", "sports"}

# Verb-form glue for the same closed activity family ("runs marathons" and
# "marathon running" must meet at marathon_running).
_GERUND_MAP = {"run": "running", "ran": "running"}


def match_concepts(
    cur: psycopg.Cursor, object_text: str
) -> list[tuple[uuid.UUID, str]]:
    """Exact and near-exact matches of a claim object against seeded
    concepts. Returns (concept_id, mapping_type)."""
    key = concept_key(object_text)
    singular = _singular(key)
    # Insert the normalized form first so an unchanged singular form retains
    # the exact classification rather than overwriting it.
    candidates = {singular: "normalized", key: "exact"}
    keys = [k for k in candidates if k]
    if not keys:
        return []
    cur.execute(
        "select id, concept_key from haven_knowledge.knowledge_concepts where concept_key = any(%s)",
        (keys,),
    )
    matches = [(row["id"], candidates[row["concept_key"]]) for row in cur.fetchall()]
    if matches:
        return matches
    # Token-set fallback: after gerund normalization, the claim and concept
    # may differ only by filler tokens, and must share at least one real one.
    claim_tokens = {_GERUND_MAP.get(t, t) for t in singular.split("_") if t}
    cur.execute("select id, concept_key from haven_knowledge.knowledge_concepts")
    for row in cur.fetchall():
        concept_tokens = set(row["concept_key"].split("_"))
        if not claim_tokens & concept_tokens:
            continue
        if (claim_tokens - concept_tokens) <= _FILLER_TOKENS and (
            concept_tokens - claim_tokens
        ) <= _FILLER_TOKENS:
            matches.append((row["id"], "normalized"))
    return matches


def taxonomy_parents(cur: psycopg.Cursor, concept_ids: list[uuid.UUID]) -> list[uuid.UUID]:
    """Transitive broader-than closure of the given concepts (bounded: the
    seed taxonomy is a small DAG; recursion capped at depth 4)."""
    if not concept_ids:
        return []
    cur.execute(
        """
        with recursive parents(id, depth) as (
            select target_concept_id, 1 from haven_knowledge.concept_edges
            where source_concept_id = any(%s) and relationship_key = 'broader'
            union
            select e.target_concept_id, p.depth + 1
            from haven_knowledge.concept_edges e
            join parents p on e.source_concept_id = p.id
            where p.depth < 4 and e.relationship_key = 'broader'
        )
        select distinct id from parents
        """,
        (concept_ids,),
    )
    return [row["id"] for row in cur.fetchall()]


def concept_display_names(cur: psycopg.Cursor, concept_ids: list[uuid.UUID]) -> list[str]:
    if not concept_ids:
        return []
    cur.execute(
        "select display_name from haven_knowledge.knowledge_concepts where id = any(%s) order by display_name",
        (concept_ids,),
    )
    return [row["display_name"] for row in cur.fetchall()]
