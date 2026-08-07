"""Versioned evaluation fixtures for the knowledge foundation, v1.

Synthetic people only. Each scenario carries its sources, the queries that
must find them, the evidence that must ride along, and the assertions that
must never be made. The forbidden lists are the inference-policy fence:
persisted knowledge may not contain them for these inputs."""

EVAL_VERSION = "memory-knowledge-eval-v1"

# Canonical people mirrored before any source is added.
PEOPLE = {
    "sarah": "Sarah Chen",
    "alex_chen": "Alex Chen",
    "alex_kim": "Alex Kim",
    "daniel": "Daniel Vo",
}

# scenario: (primary, sources, queries, forbidden_assertions)
SCENARIOS = [
    {
        "key": "f1_interest_and_need",
        "primary": "sarah",
        "sources": [
            "Sarah worked at Google, is exploring education startups, loves trail running, and wants to interview teachers."
        ],
        "queries": [
            {"q": "who worked at Google", "expect": ["sarah"], "why": "past employment is worked_at, retrievable"},
            {"q": "anyone exploring education startups", "expect": ["sarah"], "why": "exploring claim"},
            {"q": "who is into trail running", "expect": ["sarah"], "why": "interest claim"},
            {"q": "who wants to talk to teachers", "expect": ["sarah"], "why": "needs claim, phrased differently"},
        ],
        "forbidden": [],
    },
    {
        "key": "f2_provisional_reference",
        "primary": "sarah",
        "sources": ["Met Sarah through Alex at YC Demo Day."],
        "queries": [
            {"q": "who introduced me to Sarah?", "expect": ["sarah"],
             "relationship": True,
             "expect_unresolved_mention": "Alex",
             "why": "the answer must name Alex and qualify that Alex is unresolved"},
        ],
        "forbidden": [],
    },
    {
        "key": "f4_conservative_inference",
        "primary": "sarah",
        "sources": ["Sarah runs marathons."],
        "queries": [
            {"q": "marathon runner", "expect": ["sarah"], "why": "direct phrasing"},
            {"q": "endurance sport", "expect": ["sarah"], "why": "taxonomy expansion, not stored inference"},
            {"q": "long-distance running", "expect": ["sarah"], "why": "taxonomy expansion"},
        ],
        "forbidden": ["disciplined", "outdoorsy", "health-conscious", "hiking",
                      "exercises every day", "accountability partner"],
    },
    {
        "key": "f5_modality",
        "primary": "sarah",
        "sources": ["Sarah might be interested in education startups."],
        "queries": [
            {"q": "interested in education startups", "expect": ["sarah"],
             "expect_modality": "uncertain",
             "why": "uncertain interest is retrievable but must carry its modality"},
        ],
        "forbidden": [],
    },
    {
        "key": "f6_negation",
        "primary": "sarah",
        "sources": ["Sarah is not looking for startup introductions right now."],
        "queries": [
            {"q": "looking for startup introductions", "expect": [],
             "expect_negative_not_positive": "sarah",
             "why": "a negative claim must never satisfy the positive need"},
        ],
        "forbidden": [],
    },
    {
        "key": "f7_history",
        "primary": "daniel",
        "sources": ["Daniel used to work at Google."],
        "queries": [
            {"q": "who worked at Google in the past", "expect": ["daniel"],
             "expect_temporal": "historical",
             "why": "worked_at historical, never works_at current"},
        ],
        "forbidden": [],
    },
]

# Fixture 3 (multiple Alexes), 8 (revision), 9 (deletion), 10 (tenant
# isolation) are procedural and live in run_eval.py; their people and text:
F3_SOURCE = "Met Sarah through Alex."
F8_V1 = "Sarah lives in San Francisco."
F8_V2 = "Sarah moved to New York."
F9_SOURCE = "Sarah collects antique compasses."
F10_SOURCE = "Sarah paints miniature watercolors."
