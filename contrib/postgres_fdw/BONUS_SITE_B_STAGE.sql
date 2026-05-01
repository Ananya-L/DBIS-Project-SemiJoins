-- Bonus semijoin staging setup for the remote PostgreSQL site.
--
-- Run this on the remote database used by remote_server, for example:
--
--   ~/pg_custom/bin/psql -h localhost -p 5433 -d postgres -f BONUS_SITE_B_STAGE.sql
--
-- The local database maps this table through semijoin_keys_stage_ft.

CREATE TABLE IF NOT EXISTS public.semijoin_keys_stage (
    session_id text NOT NULL,
    join_key integer NOT NULL,
    PRIMARY KEY (session_id, join_key)
);

CREATE INDEX IF NOT EXISTS semijoin_keys_stage_join_key_idx
    ON public.semijoin_keys_stage (join_key);

