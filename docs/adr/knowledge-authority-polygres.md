# ADR: Polygres owns the new knowledge domain

Date: 2026-08-06.
Status: accepted (locked founder decision, recorded here with its consequences).

## Decision

PostgreSQL inside the Polygres project `pa6ee1830f10557dcc9bfd0c` is authoritative for the new Haven knowledge domain: raw source entries, source-entry versions, extracted claims, provisional entity references, knowledge entities, entity relationships, normalized concepts, retrieval items, embeddings, extraction status, indexing status, and reference-resolution decisions.

Convex remains temporarily authoritative for the existing application shell: person and profile records, Clerk integration, the directory UI, captures and file storage, connections and shared notes, the offline queue, and live subscriptions.

## What crosses the boundary

A minimal representation of a Convex person may be mirrored into Polygres as a canonical `knowledge_entities` row carrying `convex_person_id`, so knowledge records have stable nodes to attach to.
The mirror is an external mapping, not a second profile system: the Convex person remains the thing the UI edits, and the knowledge entity only anchors claims.

Nothing in this ADR makes Convex authoritative for new source entries or claims, and nothing dual-writes synchronously across both stores.
A capture succeeds or fails against Polygres alone.

## Isolation from pre-existing data in the same database

The project already contains two unrelated datasets that this work must not touch:

- the July 2026 network read-model mirror in `public` (`app_users`, `people`, `person_handles`, `memories`, `connections`, `person_edges`), with its own vector configs (`people_embedding`, `memories_embedding`) and text configs (`people_search`, `memories_text`);
- the iMessage graph research tables (`im_nodes`, `im_edges`) with the `im_node_names` fuzzy config, whose charter (graph/GOAL.md) is owned by the user.

All knowledge tables live in a dedicated `haven_knowledge` schema.
No knowledge query joins into `public`, no knowledge retrieval config covers a `public` table, and no graph registration links the two datasets.
The Convex person id is carried as an opaque text column, never as a foreign key into the mirror tables.

## Why not Convex for the knowledge domain

- The knowledge domain is claim-shaped and evidence-shaped: many small immutable rows with foreign keys, lifecycle transitions, and cross-row integrity rules. That is relational modeling, which Convex's document model supports weakly (no foreign keys, no check constraints, no transactional DDL).
- Retrieval needs lexical, fuzzy, vector, and graph access joined at the source; Polygres provides all four against the same rows.
- Reprocessing (decision 3) means bulk rewrites of derived tables, which are ordinary SQL batch jobs in Postgres and awkward paginated mutations in Convex.

## Rollback path

The knowledge domain is additive and feature-flagged (`HAVEN_KNOWLEDGE_*`, default off).
Nothing in the existing application reads it yet.
Rollback is: turn the flags off, stop the worker, and optionally drop the `haven_knowledge` schema.
No Convex data is modified by any knowledge write path, so there is nothing to restore on the Convex side.
