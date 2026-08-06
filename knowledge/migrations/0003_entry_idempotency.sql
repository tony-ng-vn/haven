-- Client-supplied idempotency for source-entry creation: a retried create
-- with the same key returns the original entry instead of inserting twice.

alter table haven_knowledge.source_entries
    add column client_idempotency_key text;

create unique index source_entries_client_idempotency
    on haven_knowledge.source_entries (owner_id, client_idempotency_key)
    where client_idempotency_key is not null;
