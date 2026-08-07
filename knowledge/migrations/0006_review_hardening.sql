-- Review hardening for invariants enforced by the application from the first
-- migration but not yet protected against direct database writes.

begin;

alter table haven_knowledge.knowledge_claims
    add constraint knowledge_claims_custom_predicate_label
    check ((predicate_key = 'custom') = (custom_predicate_label is not null))
    not valid;

alter table haven_knowledge.retrieval_items
    add constraint retrieval_items_ready_embedding_complete
    check (
        embedding_status <> 'ready'
        or (
            embedding is not null
            and embedding_model is not null
            and embedding_dimensions = 1024
            and embedding_input_hash is not null
        )
    )
    not valid;

alter table haven_knowledge.knowledge_claims
    validate constraint knowledge_claims_custom_predicate_label;

alter table haven_knowledge.retrieval_items
    validate constraint retrieval_items_ready_embedding_complete;

commit;
