---
name: pg-review
description: PostgreSQL query, schema, and index review — spotting sequential scans, missing indexes on join and filter columns, N+1 patterns, and schema/type problems. Use when analyzing a slow query, deciding on an index, or reviewing a PostgreSQL schema.
globs:
  - "**/*.sql"
alwaysApply: false
---

# PostgreSQL — Query & Schema Review

Production operations (migrations, vacuum, replication, backups) live in `db-operations`.

## Query analysis

- Identify queries likely to trigger a sequential scan on a large table
- Verify joins use indexed columns on both sides
- Detect N+1 patterns originating in the application layer
- Ask for `EXPLAIN (ANALYZE, BUFFERS)` on anything critical — plan estimates alone are
  not evidence

Reading a plan:
- `Seq Scan` on a large table inside a nested loop is usually the problem
- A large gap between estimated and actual rows means statistics are stale — `ANALYZE`
- `Rows Removed by Filter` in the thousands means the index is not selective enough

## Index recommendations

- Foreign key columns that are frequently joined should be indexed — PostgreSQL does
  **not** create these automatically
- Columns that appear regularly in `WHERE`
- Partial indexes for a specific recurring condition (`WHERE status = 'active'`)
- Composite index column order follows selectivity and the query's leading predicate
- Avoid over-indexing write-heavy tables — every index costs on insert and update
- Look for unused indexes before adding more:

```sql
SELECT relname, indexrelname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;
```

## Schema review

- Data types match the actual need — not `TEXT` for everything, not `bigint` for a boolean flag
- Constraints expressed in the schema: `NOT NULL`, `UNIQUE`, `CHECK`, foreign keys
- Consistent naming convention
- `timestamptz` rather than `timestamp` for anything representing a moment in time
- Natural vs surrogate keys chosen deliberately, not by habit

## Language server support

For `.sql` files, use the PostgreSQL language server (`postgrestools`, backed by the native
`libpg_query` parser) before manual review:

- Use its diagnostics to catch syntax errors and invalid statements — do not declare a
  query valid without checking
- Context-aware completion (table and column names) requires a `postgrestools.jsonc` with a
  connection string at the project root; without it you get syntax and keyword support only
- Setup details and limitations → `lsp-tooling`

## Output format

```
[SLOW]    Query likely to be slow — suggestion: ...
[INDEX]   Add an index on ... — reason: ...
[SCHEMA]  Suggested schema change — ...
[LSP]     Language server diagnostic — file:line — message
```
