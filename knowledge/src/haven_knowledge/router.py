"""Query routing: three deterministic paths, no model in the loop.

- fast: bare-name and id lookups (fuzzy included), zero model calls;
- relationship: predicate-shaped questions answered from claims or graph;
- standard: everything else, lexical + vector fused with RRF.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

RELATIONSHIP_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("who_introduced", re.compile(r"^who\s+introduced\s+(?:me\s+to\s+)?(?P<name>.+?)\??$", re.I)),
    ("how_do_i_know", re.compile(r"^how\s+do\s+i\s+know\s+(?P<name>.+?)\??$", re.I)),
    ("met_through", re.compile(r"^who\s+did\s+i\s+meet\s+through\s+(?P<name>.+?)\??$", re.I)),
]

# Words that mean the query is a need or a topic, not a person name.
_NON_NAME_TOKENS = re.compile(
    r"\b(who|what|which|where|when|how|do|does|did|know|works?|need|want|"
    r"looking|find|anyone|someone|help|intro|for|with|about|that|the)\b",
    re.I,
)


@dataclass(frozen=True)
class QueryPlan:
    path: str  # "fast" | "relationship" | "standard"
    relationship_kind: str | None = None
    target_name: str | None = None


def plan_query(query: str) -> QueryPlan:
    q = query.strip()
    for kind, pattern in RELATIONSHIP_PATTERNS:
        match = pattern.match(q)
        if match:
            return QueryPlan("relationship", kind, match.group("name").strip())
    tokens = q.split()
    if 0 < len(tokens) <= 3 and not _NON_NAME_TOKENS.search(q) and not q.endswith("?"):
        return QueryPlan("fast", target_name=q)
    return QueryPlan("standard")
