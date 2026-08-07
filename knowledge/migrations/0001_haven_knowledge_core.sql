-- Haven Memory Knowledge Foundation v0: core schema.
-- Everything lives in the dedicated haven_knowledge schema; nothing here
-- touches public (network mirror), im_* (iMessage research), or platform
-- schemas. See docs/specs/haven-memory-knowledge-foundation-v0.md.

create schema if not exists haven_knowledge;

-- pgcrypto is preinstalled-available on the managed project; gen_random_uuid
-- is core in PG13+, so no extension statement is needed for UUIDs.
-- vector and pg_trgm are already installed at the database level.

-- ---------------------------------------------------------------- identity

create table haven_knowledge.haven_users (
    id uuid primary key default gen_random_uuid(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table haven_knowledge.auth_identities (
    id uuid primary key default gen_random_uuid(),
    haven_user_id uuid not null references haven_knowledge.haven_users(id),
    provider text not null,
    issuer text not null,
    provider_subject text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (provider, issuer, provider_subject)
);

create index auth_identities_user on haven_knowledge.auth_identities (haven_user_id);

-- ---------------------------------------------------------------- entities

create table haven_knowledge.knowledge_entities (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references haven_knowledge.haven_users(id),
    entity_type text not null check (entity_type in
        ('person', 'organization', 'event', 'place', 'project', 'community', 'topic')),
    entity_state text not null check (entity_state in ('canonical', 'provisional')),
    display_name text not null,
    normalized_name text not null,
    convex_person_id text,
    resolved_to_entity_id uuid references haven_knowledge.knowledge_entities(id),
    resolution_status text check (resolution_status in ('unresolved', 'confirmed')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    -- Canonical rows carry no resolution machinery; provisional rows carry no
    -- Convex mapping. The service validates that a resolved_to target is a
    -- same-owner canonical row; this row-level check prevents canonical rows
    -- from pointing onward.
    check (entity_state <> 'canonical' or (resolved_to_entity_id is null and resolution_status is null)),
    check (entity_state <> 'provisional' or (convex_person_id is null and resolution_status is not null))
);

create index knowledge_entities_owner on haven_knowledge.knowledge_entities (owner_id);
create index knowledge_entities_owner_state on haven_knowledge.knowledge_entities (owner_id, entity_state);
create index knowledge_entities_normalized on haven_knowledge.knowledge_entities (owner_id, normalized_name);
create unique index knowledge_entities_convex on haven_knowledge.knowledge_entities (owner_id, convex_person_id)
    where convex_person_id is not null and deleted_at is null;
create index knowledge_entities_unresolved on haven_knowledge.knowledge_entities (owner_id)
    where entity_state = 'provisional' and resolution_status = 'unresolved' and deleted_at is null;

-- ------------------------------------------------------------ source entries

create table haven_knowledge.source_entries (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references haven_knowledge.haven_users(id),
    scope text not null check (scope in ('person_anchored', 'global')),
    primary_entity_id uuid references haven_knowledge.knowledge_entities(id),
    -- Known values today: typed, dictated, imported, screenshot,
    -- legacy_convex_context, system_test. Deliberately not check-constrained
    -- so a new source type is a code change, not a migration.
    source_type text not null,
    current_version_id uuid,
    lifecycle_status text not null default 'active' check (lifecycle_status in ('active', 'deleted')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    check (scope <> 'person_anchored' or primary_entity_id is not null)
);

create index source_entries_owner on haven_knowledge.source_entries (owner_id);
create index source_entries_owner_status on haven_knowledge.source_entries (owner_id, lifecycle_status);
create index source_entries_owner_primary on haven_knowledge.source_entries (owner_id, primary_entity_id);

create table haven_knowledge.source_entry_versions (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references haven_knowledge.haven_users(id),
    source_entry_id uuid not null references haven_knowledge.source_entries(id),
    version_number integer not null check (version_number >= 1),
    raw_text text not null,
    captured_at timestamptz not null,
    supersedes_version_id uuid references haven_knowledge.source_entry_versions(id),
    content_hash text not null,
    created_at timestamptz not null default now(),
    unique (source_entry_id, version_number)
);

create index source_entry_versions_owner on haven_knowledge.source_entry_versions (owner_id);

alter table haven_knowledge.source_entries
    add constraint source_entries_current_version_fk
    foreign key (current_version_id) references haven_knowledge.source_entry_versions(id);

-- raw_text is evidence; offsets in mentions and claims are only meaningful
-- against an immutable string, so updates that touch it are refused outright.
create or replace function haven_knowledge.forbid_raw_text_mutation()
returns trigger language plpgsql as $$
begin
    if new.raw_text is distinct from old.raw_text
        or new.content_hash is distinct from old.content_hash
        or new.source_entry_id is distinct from old.source_entry_id
        or new.version_number is distinct from old.version_number then
        raise exception 'source_entry_versions rows are immutable';
    end if;
    return new;
end;
$$;

create trigger source_entry_versions_immutable
    before update on haven_knowledge.source_entry_versions
    for each row execute function haven_knowledge.forbid_raw_text_mutation();

-- ---------------------------------------------------------- extraction runs

create table haven_knowledge.extraction_runs (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references haven_knowledge.haven_users(id),
    source_entry_id uuid not null references haven_knowledge.source_entries(id),
    source_entry_version_id uuid not null references haven_knowledge.source_entry_versions(id),
    extraction_policy_version text not null,
    prompt_version text not null,
    model_provider text not null,
    model_name text not null,
    status text not null default 'pending' check (status in ('pending', 'running', 'succeeded', 'failed')),
    attempt_count integer not null default 0,
    started_at timestamptz,
    completed_at timestamptz,
    -- Machine code plus a user-safe message only. Raw provider payloads may
    -- quote the source text, so they must never land here.
    error_code text,
    safe_error_message text,
    created_at timestamptz not null default now()
);

create index extraction_runs_owner on haven_knowledge.extraction_runs (owner_id);
create index extraction_runs_version on haven_knowledge.extraction_runs (source_entry_version_id);

-- ---------------------------------------------------------------- mentions

create table haven_knowledge.entity_mentions (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references haven_knowledge.haven_users(id),
    source_entry_version_id uuid not null references haven_knowledge.source_entry_versions(id),
    entity_id uuid not null references haven_knowledge.knowledge_entities(id),
    surface_text text not null,
    normalized_surface_text text not null,
    evidence_start integer not null check (evidence_start >= 0),
    evidence_end integer not null check (evidence_end > evidence_start),
    mention_role text not null check (mention_role in ('primary', 'subject', 'object', 'contextual')),
    created_at timestamptz not null default now()
);

create index entity_mentions_owner on haven_knowledge.entity_mentions (owner_id);
create index entity_mentions_version on haven_knowledge.entity_mentions (source_entry_version_id);
create index entity_mentions_entity on haven_knowledge.entity_mentions (entity_id);

-- ------------------------------------------------------------------ claims

create table haven_knowledge.knowledge_claims (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references haven_knowledge.haven_users(id),
    source_entry_id uuid not null references haven_knowledge.source_entries(id),
    source_entry_version_id uuid not null references haven_knowledge.source_entry_versions(id),
    extraction_run_id uuid not null references haven_knowledge.extraction_runs(id),
    subject_entity_id uuid not null references haven_knowledge.knowledge_entities(id),
    predicate_key text not null,
    custom_predicate_label text,
    object_entity_id uuid references haven_knowledge.knowledge_entities(id),
    object_text text,
    object_value_json jsonb,
    polarity text not null check (polarity in ('positive', 'negative')),
    modality text not null check (modality in ('stated', 'uncertain', 'intended')),
    temporal_status text not null check (temporal_status in ('current', 'historical', 'future')),
    confidence real not null check (confidence >= 0 and confidence <= 1),
    evidence_quote text not null,
    evidence_start integer not null check (evidence_start >= 0),
    evidence_end integer not null check (evidence_end > evidence_start),
    derivation_kind text not null default 'direct_extraction' check (derivation_kind in
        ('direct_extraction', 'user_confirmed', 'deterministic_import', 'query_time_hypothesis')),
    lifecycle_status text not null default 'active' check (lifecycle_status in
        ('active', 'superseded', 'deleted', 'invalid')),
    created_at timestamptz not null default now(),
    superseded_at timestamptz,
    deleted_at timestamptz,
    check (object_entity_id is not null or object_text is not null or object_value_json is not null)
);

create index knowledge_claims_owner on haven_knowledge.knowledge_claims (owner_id);
create index knowledge_claims_owner_status on haven_knowledge.knowledge_claims (owner_id, lifecycle_status);
create index knowledge_claims_version on haven_knowledge.knowledge_claims (source_entry_version_id);
create index knowledge_claims_subject on haven_knowledge.knowledge_claims (subject_entity_id);
create index knowledge_claims_object on haven_knowledge.knowledge_claims (object_entity_id);

-- --------------------------------------------------------------- relations

create table haven_knowledge.entity_relations (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references haven_knowledge.haven_users(id),
    source_claim_id uuid not null references haven_knowledge.knowledge_claims(id),
    subject_entity_id uuid not null references haven_knowledge.knowledge_entities(id),
    predicate_key text not null,
    object_entity_id uuid not null references haven_knowledge.knowledge_entities(id),
    lifecycle_status text not null default 'active' check (lifecycle_status in
        ('active', 'superseded', 'deleted', 'invalid')),
    confidence real not null check (confidence >= 0 and confidence <= 1),
    created_at timestamptz not null default now(),
    deleted_at timestamptz
);

create index entity_relations_owner on haven_knowledge.entity_relations (owner_id);
create index entity_relations_owner_status on haven_knowledge.entity_relations (owner_id, lifecycle_status);
create index entity_relations_subject on haven_knowledge.entity_relations (subject_entity_id);
create index entity_relations_object on haven_knowledge.entity_relations (object_entity_id);
create index entity_relations_claim on haven_knowledge.entity_relations (source_claim_id);

-- ---------------------------------------------------------------- concepts

create table haven_knowledge.knowledge_concepts (
    id uuid primary key default gen_random_uuid(),
    concept_key text not null unique,
    display_name text not null,
    concept_type text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table haven_knowledge.concept_edges (
    id uuid primary key default gen_random_uuid(),
    source_concept_id uuid not null references haven_knowledge.knowledge_concepts(id),
    relationship_key text not null,
    target_concept_id uuid not null references haven_knowledge.knowledge_concepts(id),
    provenance text not null,
    created_at timestamptz not null default now(),
    unique (source_concept_id, relationship_key, target_concept_id)
);

create table haven_knowledge.claim_concepts (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references haven_knowledge.haven_users(id),
    claim_id uuid not null references haven_knowledge.knowledge_claims(id),
    concept_id uuid not null references haven_knowledge.knowledge_concepts(id),
    mapping_type text not null check (mapping_type in ('normalized', 'exact', 'taxonomy_parent')),
    confidence real not null check (confidence >= 0 and confidence <= 1),
    created_at timestamptz not null default now(),
    unique (claim_id, concept_id, mapping_type)
);

create index claim_concepts_owner on haven_knowledge.claim_concepts (owner_id);
create index claim_concepts_concept on haven_knowledge.claim_concepts (concept_id);

-- ---------------------------------------------------------- retrieval items

create table haven_knowledge.retrieval_items (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references haven_knowledge.haven_users(id),
    primary_entity_id uuid not null references haven_knowledge.knowledge_entities(id),
    item_kind text not null check (item_kind in
        ('raw_source', 'direct_claim', 'person_summary', 'need', 'offer', 'relationship_description')),
    source_entry_id uuid references haven_knowledge.source_entries(id),
    source_entry_version_id uuid references haven_knowledge.source_entry_versions(id),
    claim_id uuid references haven_knowledge.knowledge_claims(id),
    concept_id uuid references haven_knowledge.knowledge_concepts(id),
    retrieval_text text not null,
    text_hash text not null,
    -- Two generated tsvector columns on purpose, for the recorded
    -- simple-vs-english parser evaluation; the losing config gets dropped or
    -- ignored, the column is cheap at this scale. simple is the expected
    -- winner (names and mixed-language notes stem badly).
    retrieval_tsv tsvector generated always as (to_tsvector('simple', retrieval_text)) stored,
    retrieval_tsv_english tsvector generated always as (to_tsvector('english', retrieval_text)) stored,
    embedding vector(1536),
    embedding_model text,
    embedding_dimensions integer,
    embedding_input_hash text,
    embedding_status text not null default 'pending' check (embedding_status in
        ('pending', 'ready', 'failed', 'skipped')),
    lifecycle_status text not null default 'active' check (lifecycle_status in
        ('active', 'superseded', 'deleted')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz
);

create index retrieval_items_owner on haven_knowledge.retrieval_items (owner_id);
create index retrieval_items_owner_active on haven_knowledge.retrieval_items (owner_id)
    where lifecycle_status = 'active';
create index retrieval_items_owner_primary on haven_knowledge.retrieval_items (owner_id, primary_entity_id);
create index retrieval_items_entry on haven_knowledge.retrieval_items (source_entry_id);
create index retrieval_items_version on haven_knowledge.retrieval_items (source_entry_version_id);
create index retrieval_items_claim on haven_knowledge.retrieval_items (claim_id);
create index retrieval_items_tsv on haven_knowledge.retrieval_items using gin (retrieval_tsv);
create index retrieval_items_tsv_english on haven_knowledge.retrieval_items using gin (retrieval_tsv_english);

-- ------------------------------------------------------------------ outbox

create table haven_knowledge.knowledge_outbox (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references haven_knowledge.haven_users(id),
    job_type text not null check (job_type in
        ('extract_source', 'embed_retrieval_item', 'project_graph', 'deactivate_superseded_version')),
    source_entry_id uuid references haven_knowledge.source_entries(id),
    source_entry_version_id uuid references haven_knowledge.source_entry_versions(id),
    idempotency_key text not null unique,
    payload jsonb not null default '{}'::jsonb,
    status text not null default 'pending' check (status in
        ('pending', 'running', 'succeeded', 'failed', 'dead')),
    attempt_count integer not null default 0,
    available_at timestamptz not null default now(),
    locked_at timestamptz,
    locked_by text,
    completed_at timestamptz,
    last_error_code text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index knowledge_outbox_claimable on haven_knowledge.knowledge_outbox (status, available_at);
create index knowledge_outbox_owner on haven_knowledge.knowledge_outbox (owner_id);
create index knowledge_outbox_version on haven_knowledge.knowledge_outbox (source_entry_version_id);

-- ------------------------------------------------- reference resolution log

create table haven_knowledge.reference_candidate_decisions (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references haven_knowledge.haven_users(id),
    provisional_entity_id uuid not null references haven_knowledge.knowledge_entities(id),
    candidate_entity_id uuid not null references haven_knowledge.knowledge_entities(id),
    decision text not null check (decision in ('confirmed', 'rejected', 'not_sure')),
    candidate_context_hash text not null,
    decided_by text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (provisional_entity_id, candidate_entity_id)
);

create index reference_candidate_decisions_owner
    on haven_knowledge.reference_candidate_decisions (owner_id);
