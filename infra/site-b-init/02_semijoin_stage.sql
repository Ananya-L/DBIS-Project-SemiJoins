CREATE TABLE IF NOT EXISTS semijoin_keys_stage (
  session_id text NOT NULL,
  join_key int NOT NULL,
  PRIMARY KEY (session_id, join_key)
);

CREATE INDEX IF NOT EXISTS semijoin_keys_stage_join_key_idx
  ON semijoin_keys_stage(join_key);
