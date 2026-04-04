CREATE TABLE IF NOT EXISTS a_local (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  join_key int NOT NULL,
  payload text NOT NULL
);

CREATE INDEX IF NOT EXISTS a_local_join_key_idx ON a_local(join_key);

INSERT INTO a_local (join_key, payload)
SELECT CASE
         WHEN g % 10 = 0 THEN 20000 + g
         ELSE (g % 10000) + 1
       END,
       'a_payload_' || g::text
FROM generate_series(1, 50000) AS g;
