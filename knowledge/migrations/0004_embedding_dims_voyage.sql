-- Documented embedding-contract change: the repository's OpenAI embedding key
-- was dead at build time, so the knowledge domain embeds with Voyage
-- voyage-3.5 at 1024 dimensions. The column is empty at this point (no
-- vectors were ever written at 1536), so the retype was loss-free in the
-- validated development environment. Migration 0006 adds a permanent check
-- preventing ready rows from carrying a null or incomplete embedding. The
-- public schema's 1536-dim mirror configs are untouched.

alter table haven_knowledge.retrieval_items
    alter column embedding type vector(1024) using null;
