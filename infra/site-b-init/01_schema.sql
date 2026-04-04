CREATE TABLE IF NOT EXISTS b_remote (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  join_key int NOT NULL,
  payload text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS b_remote_join_key_idx ON b_remote(join_key);

INSERT INTO b_remote (join_key, payload)
SELECT (g % 10000) + 1,
       'b_payload_' || g::text
FROM generate_series(1, 200000) AS g;
