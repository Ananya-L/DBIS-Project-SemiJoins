# Quick Implementation Guide: Semijoin Phases 2-3

## TL;DR: What Needs to Be Done

Current problem: Fetching 100K rows, taking 128ms. Need to fetch 10K rows to hit 70ms target.

### The 4 Steps to 70ms

**Step 1: Initialize semijoin in scan begin**
- Check if semijoin metadata is in fdw_private
- Allocate memory context for key buffers
- Set up batching parameters (batch_size=500)

**Step 2: Extract join keys from local table**
- Get distinct values of join column (customer_id)
- From WHERE clause result set (~1000 values)
- Store in semijoin_keys list

**Step 3: Batch and send to remote**
- Loop through keys in 500-key batches
- For each batch: modify remote SQL
  - Original: `SELECT * FROM orders`
  - Modified: `SELECT * FROM orders WHERE customer_id = ANY(ARRAY[1,2,3,...])`
- Execute at remote (returns ~10K rows vs 100K)

**Step 4: Type-safe SQL generation**
- Format keys using PostgreSQL type output functions
- Proper escaping and type casting
- Handle INT4, TEXT, TIMESTAMP, UUID

---

## Files to Modify

### 1. postgres_fdw.c - postgresBeginForeignScan()

Around line 1550, after `fmstate` is created:

```c
// NEW CODE: Initialize semijoin state
if (fdw_private != NIL && list_length(fdw_private) > FdwScanPrivateSemijoinActive)
{
    bool semijoin_active = boolVal(list_nth(fdw_private, 
                                             FdwScanPrivateSemijoinActive));
    
    if (semijoin_active)
    {
        fmstate->semijoin_active = true;
        fmstate->semijoin_key_attnum = 
            intVal(list_nth(fdw_private, FdwScanPrivateSemijoinKeyAttnum));
        fmstate->semijoin_key_type = 
            intVal(list_nth(fdw_private, FdwScanPrivateSemijoinKeyType));
        fmstate->semijoin_batch_size = 500;
        fmstate->semijoin_key_offset = 0;
        
        // Allocate dedicated context for key buffers
        fmstate->semijoin_cxt = AllocSetContextCreate(
            fmstate->batch_cxt,
            "Semijoin key buffer",
            ALLOCSET_DEFAULT_SIZES);
        
        elog(LOG, "Semijoin initialized: batch_size=%d", 
             fmstate->semijoin_batch_size);
    }
}
```

### 2. postgres_fdw.c - postgresIterateForeignScan()

Around line 1650, in the main fetch loop:

```c
// NEW CODE: Handle semijoin batched execution
if (fscan->fmstate->semijoin_active && 
    fscan->fmstate->semijoin_key_offset == 0)
{
    // First time: extract keys from outer relation
    extract_semijoin_keys(node, &fscan->fmstate->semijoin_keys);
    
    elog(LOG, "Extracted %d semijoin keys", 
         list_length(fscan->fmstate->semijoin_keys));
}

// Fetch next batch if needed
if (fscan->fmstate->semijoin_active && 
    fscan->fmstate->semijoin_key_offset < 
    list_length(fscan->fmstate->semijoin_keys))
{
    List *batch = extract_key_batch(
        fscan->fmstate->semijoin_keys,
        fscan->fmstate->semijoin_key_offset,
        fscan->fmstate->semijoin_batch_size);
    
    // Generate modified SQL with WHERE clause
    char *modified_sql = build_semijoin_filter_sql(
        fscan->fmstate->query,           // original SELECT
        "customer_id",                    // join column (TODO: get dynamically)
        batch,
        INT4OID);                        // key type
    
    // Execute at remote
    pgfdw_exec_query(fscan->fmstate->conn, modified_sql, NULL);
    
    // Collect results...
    
    fscan->fmstate->semijoin_key_offset += 
        fscan->fmstate->semijoin_batch_size;
    
    // Reset batch memory
    MemoryContextReset(fscan->fmstate->semijoin_cxt);
}
```

### 3. postgres_fdw.c - Helper Implementation

Around line 8100 (end of file), implement placeholders:

```c
/*
 * Extract key values from outer relation
 * For test query: get customer_ids from (customers WHERE customer_id < 1000)
 */
static void
extract_semijoin_keys(ForeignScanState *node, List **out_keys)
{
    // TODO: Execute query on outer relation to get distinct keys
    // For now, this is a placeholder
    *out_keys = NIL;
}

/*
 * Build remote SQL with semijoin filter
 * Input:  "SELECT order_id, customer_id, amount FROM orders"
 * Output: "SELECT order_id, customer_id, amount FROM orders WHERE customer_id = ANY(ARRAY[1,2,3,...])"
 */
static char *
build_semijoin_filter_sql(char *base_sql, const char *col_name, 
                         List *key_batch, Oid key_type)
{
    StringInfoData buf;
    ListCell *lc;
    bool first = true;
    
    initStringInfo(&buf);
    appendStringInfoString(&buf, base_sql);
    appendStringInfoString(&buf, " WHERE ");
    appendStringInfoString(&buf, col_name);
    appendStringInfoString(&buf, " = ANY(ARRAY[");
    
    foreach(lc, key_batch)
    {
        Datum key_val = PointerGetDatum(lfirst(lc));
        
        if (!first) appendStringInfoString(&buf, ",");
        
        // Format based on key type
        if (key_type == INT4OID)
        {
            int32 ival = DatumGetInt32(key_val);
            appendStringInfo(&buf, "%d", ival);
        }
        // TODO: Add TEXT, TIMESTAMP, UUID support
        
        first = false;
    }
    
    appendStringInfoString(&buf, "]::int4[])");
    return buf.data;
}

/*
 * Extract a batch of keys from the keys list
 */
static List *
extract_key_batch(List *all_keys, int offset, int batch_size)
{
    List *batch = NIL;
    int i;
    
    for (i = 0; i < batch_size && (offset + i) < list_length(all_keys); i++)
    {
        batch = lappend(batch, list_nth(all_keys, offset + i));
    }
    
    return batch;
}
```

---

## Testing Steps

1. **Compile and install**
   ```bash
   cd ~/Desktop/postgresql-18.3/contrib/postgres_fdw
   make clean && make
   sudo make install
   ~/pg_custom/bin/pg_ctl -D ~/pg_local restart
   ```

2. **Run test query**
   ```bash
   ~/pg_custom/bin/psql -h localhost -p 5432 -d postgres << 'EOF'
   EXPLAIN (ANALYZE, BUFFERS) 
   SELECT o.order_id, o.amount, c.name
   FROM ft_orders o
   JOIN customers c ON o.customer_id = c.customer_id
   WHERE c.customer_id < 1000;
   EOF
   ```

3. **Check logs for semijoin messages**
   ```bash
   tail ~/pg_local/logfile | grep -i semijoin
   ```

4. **Verify metrics**
   - Execution Time should drop from 128ms to 45-65ms
   - Remote rows should reduce from 100K to ~10K

---

## Debugging Tips

- Set `log_min_messages = DEBUG2` in PostgreSQL config to see more details
- Check `remote_sqlstmt` in EXPLAIN output to see if semijoin filter is applied
- Monitor remote server logs to verify filtered queries are being executed
- Use `strace` or `pg_stat_statements` to track query execution

---

## Key Insights from Project Overview

1. **Semijoin reduces data transfer**
   - Local: 1,000 keys × ~10 bytes = 10KB
   - Remote fetch: 100K rows × 400 bytes = 40MB → 10K rows = 4MB (10x better!)
   - Time savings: network latency dominates, 10x fewer rows = ~10x faster

2. **Batching prevents SQL explosion**
   - 500 keys per batch = 10KB SQL
   - Multiple batches instead of 1 huge query
   - Fits in PostgreSQL's statement size limits

3. **Type support progression**
   - Phase 1: INT4 only (our test case)
   - Phase 2: TEXT with escaping
   - Phase 3: Timestamp, UUID, etc.

4. **Fallback strategy**
   - If >1000 keys, skip semijoin (not selective enough)
   - If unsupported type, use regular join
   - GUC to tune threshold per deployment

---

## Expected Result

```
BEFORE: Execution Time: 128 ms
  - Hash Join 100K remote rows + 1K local rows
  - Network transfer: ~40MB
  
AFTER:  Execution Time: 55 ms  ✅ <70ms target
  - Hash Join 10K remote rows + 1K local rows  (90% fewer)
  - Network transfer: ~4MB (90% reduction)
```

---

## References

- Chapter 22 of Database System Concepts (Semijoin strategy)
- PostgreSQL FDW documentation
- postgres_fdw.c existing code for patterns
- deparse.c for SQL generation examples
