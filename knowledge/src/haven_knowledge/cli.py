"""Developer vertical-slice CLI. This is the v0 stand-in for whatever
transport question 7 eventually picks; it exercises the whole flow without
touching the user-facing note UI.

Identity: HAVEN_DEV_IDENTITY as "issuer|subject" (Clerk-token shape), or the
synthetic default development identity. Clients never pass owner ids.

Usage examples (run from knowledge/ with .env.local sourced):
    python -m haven_knowledge.cli mirror-person --convex-id jd7abc --name "Sarah Tran"
    python -m haven_knowledge.cli add --convex-id jd7abc --text "Met Sarah through Alex."
    python -m haven_knowledge.cli worker --drain
    python -m haven_knowledge.cli person <entity-id>
    python -m haven_knowledge.cli search "endurance sport"
    python -m haven_knowledge.cli revise <entry-id> --text "Sarah moved to New York."
    python -m haven_knowledge.cli delete <entry-id>
    python -m haven_knowledge.cli candidates <provisional-id>
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from . import db
from .identity import AuthContext, clerk_context
from .service import KnowledgeService
from .worker import run_worker

DEFAULT_DEV_IDENTITY = "https://dev.havens.invalid|dev_user_vertical_slice"


def _auth() -> AuthContext:
    return clerk_context(os.environ.get("HAVEN_DEV_IDENTITY", DEFAULT_DEV_IDENTITY))


def _print(value: object) -> None:
    print(json.dumps(value, indent=2, default=str))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="haven-knowledge")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("mirror-person", help="mirror a Convex person as a canonical entity")
    p.add_argument("--convex-id", required=True)
    p.add_argument("--name", required=True)

    p = sub.add_parser("add", help="create a person-anchored source entry")
    p.add_argument("--convex-id")
    p.add_argument("--entity-id")
    p.add_argument("--text", required=True)
    p.add_argument("--source-type", default="typed")
    p.add_argument("--idempotency-key")

    p = sub.add_parser("show", help="show a source entry")
    p.add_argument("entry_id")

    p = sub.add_parser("status", help="processing status for an entry")
    p.add_argument("entry_id")

    p = sub.add_parser("person", help="claims and sources for an entity")
    p.add_argument("entity_id")

    p = sub.add_parser("search", help="search the network")
    p.add_argument("query")
    p.add_argument("--limit", type=int, default=10)

    p = sub.add_parser("revise", help="revise a source entry")
    p.add_argument("entry_id")
    p.add_argument("--text", required=True)

    p = sub.add_parser("delete", help="delete a source entry")
    p.add_argument("entry_id")

    p = sub.add_parser("candidates", help="list resolution candidates for a provisional entity")
    p.add_argument("provisional_id")

    p = sub.add_parser("resolve", help="confirm a candidate for a provisional entity")
    p.add_argument("provisional_id")
    p.add_argument("candidate_id")

    p = sub.add_parser("reject", help="reject a candidate")
    p.add_argument("provisional_id")
    p.add_argument("candidate_id")

    p = sub.add_parser("not-sure", help="mark a candidate not_sure")
    p.add_argument("provisional_id")
    p.add_argument("candidate_id")

    p = sub.add_parser("worker", help="run the outbox worker")
    p.add_argument("--drain", action="store_true", help="exit when the queue is empty")
    p.add_argument("--max-jobs", type=int)

    args = parser.parse_args(argv)

    if args.command == "worker":
        count = run_worker(max_jobs=args.max_jobs, idle_exit=args.drain)
        _print({"processed": count})
        return 0

    conn = db.connect()
    try:
        service = KnowledgeService(conn)
        auth = _auth()
        if args.command == "mirror-person":
            _print(service.mirror_convex_person(auth, args.convex_id, args.name))
        elif args.command == "add":
            _print(
                service.create_source_entry(
                    auth,
                    raw_text=args.text,
                    source_type=args.source_type,
                    convex_person_id=args.convex_id,
                    primary_entity_id=args.entity_id,
                    idempotency_key=args.idempotency_key,
                )
            )
        elif args.command == "show":
            _print(service.get_source_entry(auth, args.entry_id))
        elif args.command == "status":
            _print(service.get_processing_status(auth, args.entry_id))
        elif args.command == "person":
            _print(service.get_person_knowledge(auth, args.entity_id))
        elif args.command == "search":
            _print(service.search_network(auth, args.query, args.limit))
        elif args.command == "revise":
            _print(service.revise_source_entry(auth, args.entry_id, args.text))
        elif args.command == "delete":
            _print(service.delete_source_entry(auth, args.entry_id))
        elif args.command == "candidates":
            _print(service.list_reference_candidates(auth, args.provisional_id))
        elif args.command == "resolve":
            _print(service.resolve_reference(auth, args.provisional_id, args.candidate_id))
        elif args.command == "reject":
            _print(service.reject_reference_candidate(auth, args.provisional_id, args.candidate_id))
        elif args.command == "not-sure":
            _print(service.mark_reference_not_sure(auth, args.provisional_id, args.candidate_id))
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
