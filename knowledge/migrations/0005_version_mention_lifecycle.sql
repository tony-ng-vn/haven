-- Make the ADR's deletion contract explicit on immutable source versions and
-- mentions instead of relying on joins through the parent entry.

alter table haven_knowledge.source_entry_versions
    add column lifecycle_status text not null default 'active',
    add column superseded_at timestamptz,
    add column deleted_at timestamptz,
    add constraint source_entry_versions_lifecycle_status_check
        check (lifecycle_status in ('active', 'superseded', 'deleted'));

update haven_knowledge.source_entry_versions v
set lifecycle_status = case
        when e.lifecycle_status = 'deleted' then 'deleted'
        when v.id = e.current_version_id then 'active'
        else 'superseded'
    end,
    superseded_at = case
        when e.lifecycle_status = 'active' and v.id <> e.current_version_id
        then coalesce(
            (select min(next_v.created_at)
             from haven_knowledge.source_entry_versions next_v
             where next_v.supersedes_version_id = v.id),
            e.updated_at
        )
        else null
    end,
    deleted_at = case
        when e.lifecycle_status = 'deleted' then e.deleted_at
        else null
    end
from haven_knowledge.source_entries e
where e.id = v.source_entry_id;

create index source_entry_versions_owner_status
    on haven_knowledge.source_entry_versions (owner_id, lifecycle_status);

alter table haven_knowledge.entity_mentions
    add column lifecycle_status text not null default 'active',
    add column superseded_at timestamptz,
    add column deleted_at timestamptz,
    add constraint entity_mentions_lifecycle_status_check
        check (lifecycle_status in ('active', 'superseded', 'deleted'));

update haven_knowledge.entity_mentions m
set lifecycle_status = v.lifecycle_status,
    superseded_at = v.superseded_at,
    deleted_at = v.deleted_at
from haven_knowledge.source_entry_versions v
where v.id = m.source_entry_version_id;

create index entity_mentions_owner_status
    on haven_knowledge.entity_mentions (owner_id, lifecycle_status);
