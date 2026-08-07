-- Conservative objective concept taxonomy, v1 seed. Only objective
-- broader-than relationships between activities and domains; nothing here is
-- a judgment about a person. Idempotent: on conflict do nothing.

insert into haven_knowledge.knowledge_concepts (concept_key, display_name, concept_type) values
    ('marathon_running', 'marathon running', 'activity'),
    ('trail_running', 'trail running', 'activity'),
    ('long_distance_running', 'long-distance running', 'activity'),
    ('running', 'running', 'activity'),
    ('endurance_sport', 'endurance sport', 'activity'),
    ('education_startups', 'education startups', 'domain'),
    ('education', 'education', 'domain'),
    ('startups', 'startups', 'domain'),
    ('teaching', 'teaching', 'domain')
on conflict (concept_key) do nothing;

insert into haven_knowledge.concept_edges (source_concept_id, relationship_key, target_concept_id, provenance)
select s.id, e.rel, t.id, 'seed_taxonomy_v1'
from (values
    ('marathon_running', 'broader', 'long_distance_running'),
    ('trail_running', 'broader', 'long_distance_running'),
    ('long_distance_running', 'broader', 'running'),
    ('long_distance_running', 'broader', 'endurance_sport'),
    ('education_startups', 'broader', 'startups'),
    ('education_startups', 'broader', 'education'),
    ('teaching', 'broader', 'education')
) as e(src, rel, tgt)
join haven_knowledge.knowledge_concepts s on s.concept_key = e.src
join haven_knowledge.knowledge_concepts t on t.concept_key = e.tgt
on conflict (source_concept_id, relationship_key, target_concept_id) do nothing;
