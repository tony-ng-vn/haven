"""Turns a validated extraction into persisted knowledge: mentions,
provisional entities, claims, entity relations, concept mappings, and
direct_claim retrieval items -- all in one transaction that also marks the
extraction run and outbox job done, so a crash reruns cleanly and a success
can never double-insert."""

from __future__ import annotations

import uuid
from typing import Any

import psycopg

from . import db
from .concepts import (
    CONCEPT_BEARING_PREDICATES,
    concept_display_names,
    match_concepts,
    taxonomy_parents,
)
from .entities import create_provisional_person
from .entries import content_hash
from .extraction import PERSON_OBJECT_PREDICATES, ValidatedExtraction
from .identity import normalize_name

PREDICATE_LABELS = {
    "works_at": "works at",
    "worked_at": "worked at",
    "lives_in": "lives in",
    "from_location": "is from",
    "knows": "knows",
    "introduced_by": "was introduced by",
    "met_at": "met at",
    "met_through": "met through",
    "attended": "attended",
    "member_of": "is a member of",
    "collaborated_with": "collaborated with",
    "interested_in": "is interested in",
    "exploring": "is exploring",
    "building": "is building",
    "skilled_at": "is skilled at",
    "participates_in": "participates in",
    "needs": "needs",
    "offers": "offers",
    "looking_for": "is looking for",
}


def claim_retrieval_text(
    subject_name: str,
    predicate_key: str,
    custom_label: str | None,
    object_repr: str,
    polarity: str,
    modality: str,
    temporal_status: str,
    concept_names: list[str],
) -> str:
    """The searchable rendering of one claim. Qualifiers are rendered into
    words so lexical search cannot mistake a negative claim for a positive
    one; concept names (with taxonomy parents) ride along for lexical recall
    of broader terms."""
    label = custom_label if predicate_key == "custom" else PREDICATE_LABELS[predicate_key]
    parts = [subject_name]
    if polarity == "negative":
        parts.append("does not")
        label = {"works at": "work at", "worked at": "work at"}.get(label, label)
        parts.append(label if not label.startswith("is ") else label.removeprefix("is "))
    else:
        parts.append(label)
    parts.append(object_repr)
    if modality == "uncertain":
        parts.append("(uncertain)")
    if temporal_status == "historical":
        parts.append("(in the past)")
    if temporal_status == "future":
        parts.append("(planned)")
    text = " ".join(parts)
    if concept_names:
        text += ". Topics: " + ", ".join(concept_names)
    return text


def _insert_entity_mention(
    cur: psycopg.Cursor,
    *,
    owner_id: uuid.UUID,
    version_id: uuid.UUID,
    entity_id: uuid.UUID,
    surface_text: str,
    evidence_start: int,
    evidence_end: int,
    mention_role: str,
) -> None:
    cur.execute(
        """
        insert into haven_knowledge.entity_mentions
            (owner_id, source_entry_version_id, entity_id, surface_text,
             normalized_surface_text, evidence_start, evidence_end, mention_role)
        values (%s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            owner_id, version_id, entity_id, surface_text,
            normalize_name(surface_text), evidence_start, evidence_end, mention_role,
        ),
    )


def persist_extraction(
    conn: psycopg.Connection,
    *,
    owner_id: uuid.UUID,
    entry: dict[str, Any],
    version_id: uuid.UUID,
    run_id: uuid.UUID,
    primary_entity_id: uuid.UUID,
    primary_name: str,
    extraction: ValidatedExtraction,
    outbox_job_id: uuid.UUID,
    lease_owner: str,
) -> dict[str, int]:
    """The one atomic write. `entry` is the source_entries row."""
    created = {"mentions": 0, "provisional_entities": 0, "claims": 0, "relations": 0, "items": 0}
    with db.transaction(conn) as cur:
        # Exactly-once guard: if this run already succeeded (crash between
        # commit and job ack is impossible since they share this transaction,
        # but a duplicate job row could exist), do nothing.
        cur.execute(
            "select status from haven_knowledge.extraction_runs where id = %s for update",
            (run_id,),
        )
        run = cur.fetchone()
        if run is None or run["status"] == "succeeded":
            return created

        cur.execute(
            """
            select status, locked_by
            from haven_knowledge.knowledge_outbox
            where id = %s and owner_id = %s
            for update
            """,
            (outbox_job_id, owner_id),
        )
        lease = cur.fetchone()
        if (
            lease is None
            or lease["status"] != "running"
            or lease["locked_by"] != lease_owner
        ):
            cur.execute(
                """
                update haven_knowledge.extraction_runs
                set status = 'failed', completed_at = now(), error_code = 'lease_lost',
                    safe_error_message = 'worker lease expired before extraction completed'
                where id = %s and status = 'running'
                """,
                (run_id,),
            )
            return created

        # The model call happens outside a transaction. Lock and recheck the
        # source now so a concurrent revision or deletion cannot finish first
        # and then have this obsolete result recreate active evidence.
        cur.execute(
            """
            select lifecycle_status, current_version_id
            from haven_knowledge.source_entries
            where id = %s and owner_id = %s
            for update
            """,
            (entry["id"], owner_id),
        )
        source = cur.fetchone()
        if (
            source is None
            or source["lifecycle_status"] != "active"
            or source["current_version_id"] != version_id
        ):
            cur.execute(
                """
                update haven_knowledge.extraction_runs
                set status = 'succeeded', completed_at = now()
                where id = %s
                """,
                (run_id,),
            )
            cur.execute(
                """
                update haven_knowledge.knowledge_outbox
                set status = 'succeeded', completed_at = now(), updated_at = now()
                where id = %s and status = 'running' and locked_by = %s
                """,
                (outbox_job_id, lease_owner),
            )
            return created

        # Primary mention row: the primary person's role in this version.
        mention_entity: dict[str, uuid.UUID] = {}
        mention_surface: dict[str, str] = {}
        for m in extraction.mentions:
            entity_id = create_provisional_person(cur, owner_id, m.surface_text)
            created["provisional_entities"] += 1
            mention_entity[m.local_id] = entity_id
            mention_surface[m.local_id] = m.surface_text
            _insert_entity_mention(
                cur,
                owner_id=owner_id,
                version_id=version_id,
                entity_id=entity_id,
                surface_text=m.surface_text,
                evidence_start=m.start,
                evidence_end=m.end,
                mention_role="contextual",
            )
            created["mentions"] += 1

        embed_item_ids: list[uuid.UUID] = []
        for c in extraction.claims:
            subject_id = (
                primary_entity_id if c.subject_ref == "primary" else mention_entity[c.subject_ref]
            )
            object_entity_id = None
            object_entity_surface = None
            object_text = c.object_text
            if c.object_type == "mention":
                object_entity_id = mention_entity[c.object_mention_ref]
                object_entity_surface = mention_surface[c.object_mention_ref]
            elif (
                c.predicate_key in PERSON_OBJECT_PREDICATES
                and object_text is not None
                and len(object_text.split()) <= 3
                and (object_offset := c.evidence_quote.find(object_text)) >= 0
            ):
                # The predicate makes the object a person; a short text object
                # that is anchored in the validated evidence is a mention the
                # model failed to structure. Unanchored or long objects stay
                # text so model output cannot fabricate a person or relation.
                object_entity_surface = object_text
                object_entity_id = create_provisional_person(
                    cur, owner_id, object_entity_surface
                )
                created["provisional_entities"] += 1
                mention_start = c.evidence_start + object_offset
                _insert_entity_mention(
                    cur,
                    owner_id=owner_id,
                    version_id=version_id,
                    entity_id=object_entity_id,
                    surface_text=object_entity_surface,
                    evidence_start=mention_start,
                    evidence_end=mention_start + len(object_entity_surface),
                    mention_role="object",
                )
                created["mentions"] += 1
                object_text = None
            cur.execute(
                """
                insert into haven_knowledge.knowledge_claims
                    (owner_id, source_entry_id, source_entry_version_id, extraction_run_id,
                     subject_entity_id, predicate_key, custom_predicate_label,
                     object_entity_id, object_text, polarity, modality, temporal_status,
                     confidence, evidence_quote, evidence_start, evidence_end)
                values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                returning id
                """,
                (
                    owner_id, entry["id"], version_id, run_id,
                    subject_id, c.predicate_key, c.custom_predicate_label,
                    object_entity_id, object_text, c.polarity, c.modality,
                    c.temporal_status, c.confidence, c.evidence_quote,
                    c.evidence_start, c.evidence_end,
                ),
            )
            claim_id = cur.fetchone()["id"]
            created["claims"] += 1

            # Graph projection: entity-to-entity claims only, pointing back at
            # the claim so lifecycle rides along.
            if object_entity_id is not None:
                cur.execute(
                    """
                    insert into haven_knowledge.entity_relations
                        (owner_id, source_claim_id, subject_entity_id, predicate_key,
                         object_entity_id, confidence)
                    values (%s, %s, %s, %s, %s, %s)
                    """,
                    (owner_id, claim_id, subject_id, c.predicate_key, object_entity_id, c.confidence),
                )
                created["relations"] += 1

            # Concept mapping for concept-bearing text objects.
            concept_names: list[str] = []
            if c.object_type == "text" and c.predicate_key in CONCEPT_BEARING_PREDICATES:
                matches = match_concepts(cur, object_text or "")
                direct_ids = [cid for cid, _ in matches]
                for cid, mapping in matches:
                    cur.execute(
                        """
                        insert into haven_knowledge.claim_concepts
                            (owner_id, claim_id, concept_id, mapping_type, confidence)
                        values (%s, %s, %s, %s, %s)
                        on conflict (claim_id, concept_id, mapping_type) do nothing
                        """,
                        (owner_id, claim_id, cid, mapping, c.confidence),
                    )
                parent_ids = taxonomy_parents(cur, direct_ids)
                for pid in parent_ids:
                    cur.execute(
                        """
                        insert into haven_knowledge.claim_concepts
                            (owner_id, claim_id, concept_id, mapping_type, confidence)
                        values (%s, %s, %s, 'taxonomy_parent', %s)
                        on conflict (claim_id, concept_id, mapping_type) do nothing
                        """,
                        (owner_id, claim_id, pid, c.confidence),
                    )
                concept_names = concept_display_names(cur, direct_ids + parent_ids)

            # The searchable projection of the claim. Anchored to the claim's
            # SUBJECT so searching finds the person the fact is about; claims
            # about a provisional subject anchor to that provisional entity.
            object_repr = (
                object_text if object_text is not None else object_entity_surface or ""
            )
            subject_display = (
                primary_name
                if c.subject_ref == "primary"
                else mention_surface[c.subject_ref]
            )
            text = claim_retrieval_text(
                subject_display, c.predicate_key, c.custom_predicate_label,
                object_repr, c.polarity, c.modality, c.temporal_status, concept_names,
            )
            cur.execute(
                """
                insert into haven_knowledge.retrieval_items
                    (owner_id, primary_entity_id, item_kind, source_entry_id,
                     source_entry_version_id, claim_id, retrieval_text, text_hash)
                values (%s, %s, 'direct_claim', %s, %s, %s, %s, %s)
                returning id
                """,
                (
                    owner_id, subject_id, entry["id"], version_id, claim_id,
                    text, content_hash(text),
                ),
            )
            item_id = cur.fetchone()["id"]
            embed_item_ids.append(item_id)
            created["items"] += 1

        for item_id in embed_item_ids:
            cur.execute(
                """
                insert into haven_knowledge.knowledge_outbox
                    (owner_id, job_type, source_entry_id, source_entry_version_id,
                     idempotency_key, payload)
                values (%s, 'embed_retrieval_item', %s, %s, %s, %s)
                on conflict (idempotency_key) do nothing
                """,
                (
                    owner_id, entry["id"], version_id, f"embed:{item_id}",
                    psycopg.types.json.Jsonb({"retrieval_item_id": str(item_id)}),
                ),
            )

        cur.execute(
            """
            update haven_knowledge.extraction_runs
            set status = 'succeeded', completed_at = now()
            where id = %s
            """,
            (run_id,),
        )
        cur.execute(
            """
            update haven_knowledge.knowledge_outbox
            set status = 'succeeded', completed_at = now(), updated_at = now()
            where id = %s and status = 'running' and locked_by = %s
            """,
            (outbox_job_id, lease_owner),
        )
    return created
