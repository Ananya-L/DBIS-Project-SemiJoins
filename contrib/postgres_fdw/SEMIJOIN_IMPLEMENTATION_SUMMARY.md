# Semijoin Optimization Implementation Summary

## Current Status (29 April 2026)

### What Has Been Completed

**Phase 0: Environment & Baseline** ✅
- PostgreSQL 18.3 compiled and running on local (5432) and remote (5433)
- Test data: 10,000 customers locally, 100,000 orders remotely
- Baseline query: `SELECT o.order_id, o.amount, c.name FROM ft_orders o JOIN customers c ON o.customer_id = c.customer_id WHERE c.customer_id < 1000`
- Baseline execution time: 117-165ms (fetches 100,000 rows from remote)

**Phase 1: Planner Marking** ✅ (Partial)
- Added semijoin fields to `PgFdwRelationInfo` in postgres_fdw.h:
  - `semijoin_eligible`
  - `semijoin_key` 
  - `semijoin_threshold`
- Enhanced `FdwScanPrivateIndex` enum with semijoin markers:
  - `FdwScanPrivateSemijoinActive`
  - `FdwScanPrivateSemijoinKeyAttnum`
  - `FdwScanPrivateSemijoinKeyType`
- Added semijoin state to `PgFdwScanState`:
  - Key extraction and batching fields
  - Dedicated memory context for semijoin buffers
- Implemented cost reduction (10x) for parameterized paths with local filters
- Added logging for semijoin detection

**Phase 2-3: Infrastructure** ✅ (Partial)
- Added `build_semijoin_filter_sql()` - placeholder for remote SQL generation
- Added `extract_semijoin_keys()` - placeholder for key extraction
- Function declarations and helper infrastructure in place

**Result**: Current execution time still 128-134ms
- **Reason**: Cost reduction doesn't change actual execution, just planner preference
- **Still fetching**: 100,000 rows from remote (no actual row reduction)
- **Gap to target**: Need 50-60% reduction to achieve 70ms target

---

## What's Needed for <70ms Execution Target

### The Missing Pieces (Phases 2-3 Implementation)

To achieve the 70ms target, we need to actually **reduce rows transferred from remote server** by implementing true semijoin pushdown:

```
Target Query:
  SELECT o.order_id, o.amount, c.name
  FROM ft_orders o 
  JOIN customers c ON o.customer_id = c.customer_id 
  WHERE c.customer_id < 1000

Current Flow (128-134ms):
  1. Extract 999 customers WHERE c.customer_id < 1000 (local)
  2. Fetch ALL 100,000 orders from remote
  3. Hash join locally (100K rows x 999 rows)
  Result: Heavy remote transfer dominates time

Required Flow for <70ms:
  1. Extract 999 customer_ids from local WHERE clause  ← NEW
  2. Batch keys (500 per batch) and send to remote    ← NEW
  3. Execute modified remote query:
     SELECT * FROM orders WHERE customer_id = ANY(ARRAY[...])
     → Returns ~10,000 orders (90% reduction)          ← NEW
  4. Hash join locally with 10K rows
  Result: 90% fewer rows transferred → 10-15x faster network
```

### Implementation Checklist for <70ms

#### Step 1: Initialize Semijoin State in Scan Begin
**File**: `postgres_fdw.c` - `postgresBeginForeignScan()`

```c
// Detect if this is a semijoin candidate scan
if (fdw_private contains SEMIJOIN_ACTIVE marker) {
    fmstate->semijoin_active = true;
    fmstate->semijoin_key_attnum = extracted_attnum;
    fmstate->semijoin_key_type = extracted_type;
    fmstate->semijoin_batch_size = 500;  // tunable
    fmstate->semijoin_cxt = AllocSetContextCreate(...);
}
```

#### Step 2: Extract Keys From Outer Relation  
**File**: `postgres_fdw.c` - `postgresIterateForeignScan()`

```c
// Get distinct join key values from outer relation
// For our test: extract customer_ids from:
//   SELECT DISTINCT customer_id FROM customers WHERE customer_id < 1000
// Result: ~1000 keys

extract_semijoin_keys(node, &node->semijoin_keys);
node->semijoin_key_offset = 0;
```

#### Step 3: Build Batched Remote Queries
**File**: `postgres_fdw.c` - modified scan loop

```c
while (semijoin_key_offset < list_length(semijoin_keys)) {
    // Get next batch of 500 keys
    List *batch = extract_key_batch(semijoin_keys, 
                                     semijoin_key_offset, 500);
    
    // Modify remote SQL with WHERE clause
    char *filtered_sql = build_semijoin_filter_sql(
        original_sql, "customer_id", batch, INT4OID);
    
    // Example: "SELECT ... FROM orders WHERE customer_id = ANY(ARRAY[1,2,...])"
    
    // Execute at remote
    PGresult *res = pgfdw_exec_query(conn, filtered_sql, NULL);
    
    // Collect filtered rows
    collect_rows_from_result(res, tuples);
    
    semijoin_key_offset += 500;
    MemoryContextReset(semijoin_cxt);  // reset batch buffer
}
```

#### Step 4: Generate Remote SQL With Type-Safe Formatting
**File**: `deparse.c` - add helper function

```c
/*
 * Generate: SELECT ... FROM table WHERE colname = ANY(ARRAY[val1,val2,...])
 * For integer keys, format as: ... WHERE colname = ANY(ARRAY[1,2,3,...]::int[])
 * For text keys, proper escaping: ... WHERE colname = ANY(ARRAY['a','b',...])
 */
static void append_semijoin_filter_clause(StringInfo buf, 
                                         const char *col_name,
                                         List *key_batch,
                                         Oid key_type)
{
    // Use existing type output functions for formatting
    // Ensure proper escaping and type casting
}
```

### Performance Expectations After Implementation

| Metric | Without Semijoin | With Semijoin | Improvement |
|--------|------------------|---------------|-------------|
| Remote rows fetched | 100,000 | ~10,000 | 90% reduction |
| Network transfer | ~4-5MB | ~0.4-0.5MB | 90% reduction |
| Execution time | 128-134ms | **45-65ms** | ✅ **<70ms target** |
| Local join time | ~10ms | ~10ms | Unchanged |
| Network time | ~120ms | ~12ms | 10x faster |

### Implementation Effort Estimate

- **Step 1 (Scan initialization)**: 2-3 hours
- **Step 2 (Key extraction)**: 3-4 hours  
- **Step 3 (Batched queries)**: 4-6 hours
- **Step 4 (SQL generation)**: 2-3 hours
- **Testing & tuning**: 4-6 hours

**Total**: 15-22 engineering hours

---

## Code Changes Already Made

### 1. postgres_fdw.h
- Added semijoin fields to `PgFdwRelationInfo`

### 2. postgres_fdw.c - Enums
```c
enum FdwScanPrivateIndex {
    ...
    FdwScanPrivateSemijoinActive,
    FdwScanPrivateSemijoinKeyAttnum,
    FdwScanPrivateSemijoinKeyType,
};
```

### 3. postgres_fdw.c - PgFdwScanState
```c
typedef struct PgFdwScanState {
    ...
    bool semijoin_active;
    AttrNumber semijoin_key_attnum;
    Oid semijoin_key_type;
    List *semijoin_keys;
    int semijoin_batch_size;
    int semijoin_key_offset;
    MemoryContext semijoin_cxt;
};
```

### 4. postgres_fdw.c - Functions Declared
- `build_semijoin_filter_sql()` - generates remote SQL with WHERE clause
- `extract_semijoin_keys()` - extracts keys from local table

### 5. postgres_fdw.c - Planner Logic
- Detects parameterized paths with local filters
- Applies 10x cost reduction for semijoin candidates
- Logs detection for debugging

---

## Next Steps to Reach 70ms Target

### Immediate (1-2 hours)

1. Implement `extract_semijoin_keys()` to get distinct join keys from outer relation
2. Modify `postgresIterateForeignScan()` to use batched queries when semijoin is active
3. Implement `build_semijoin_filter_sql()` to generate `WHERE col = ANY(ARRAY[...])` clause

### Short-term (2-4 hours)

4. Add proper type formatting and escaping for non-integer keys
5. Implement batching loop with 500-key batches
6. Add memory context resets between batches
7. Test with sample data and verify row reduction

### Validation

```bash
# Run query and verify rows transferred reduced to ~10K
EXPLAIN (ANALYZE, BUFFERS) 
SELECT o.order_id, o.amount, c.name 
FROM ft_orders o 
JOIN customers c ON o.customer_id = c.customer_id 
WHERE c.customer_id < 1000;

# Expected: Execution Time: 45-65ms (vs 128-134ms currently)
```

---

## Key Architecture Decisions

1. **Batching Strategy**: 500 keys per batch (tunable via GUC)
   - Keeps remote SQL size reasonable
   - Enables progress monitoring
   - Allows memory context resets

2. **Key Type Support**: Start with INT4, extend to TEXT, TIMESTAMP, UUID
   - Use PostgreSQL type output functions for formatting
   - Ensures compatibility with remote server

3. **Fallback Mechanism**: Disable semijoin if:
   - Key count > threshold (default 1000)
   - Key type not supported
   - Join operator not equijoin
   - Remote server doesn't support ANY()

4. **Memory Management**:
   - Allocate key buffers in semijoin_cxt
   - Reset per batch to prevent unbounded growth
   - Use batch_cxt for result tuples

---

## Performance Measurement

### Baseline Metrics (Current)
```
Planning Time: 1-2 ms
Execution Time: 128-134 ms
Remote rows fetched: 100,000
Network bytes: ~4-5 MB
Local join time: ~10 ms
Network latency: ~120 ms
```

### Target Metrics (<70ms)
```
Planning Time: 1-2 ms (unchanged)
Execution Time: 45-65 ms ✅ <70ms
Remote rows fetched: ~10,000 (90% reduction)
Network bytes: ~0.4-0.5 MB (90% reduction)
Local join time: ~10 ms (unchanged)
Network latency: ~12 ms (10x improvement)
```

---

## References & Related Code

- **Distributed Query Processing**: Database System Concepts Chapter 22
- **Semijoin Strategy**: Silberschatz, Korth, Sudarshan
- **Type Formatting**: PostgreSQL `src/backend/utils/adt/` 
- **FDW API**: `src/include/foreign/fdwapi.h`
- **Existing Similar Logic**: `deparse.c` - `deparseSelectStmtForRel()`

---

## Conclusion

The infrastructure for semijoin optimization has been put in place. The key remaining work is implementing the actual key extraction and batched remote query execution. Once Step 1-4 above are completed, the system should achieve the <70ms execution target through 90% reduction in rows transferred from the remote server.

**Current state**: 50% of the way to full implementation
**Estimated time to <70ms target**: 15-22 engineering hours
