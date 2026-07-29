---
name: db-operations
description: PostgreSQL operations beyond query tuning — zero-downtime migrations (lock-safe DDL), bloat and autovacuum, replication lag, backup/PITR, and connection pooling (PgBouncer). Use when writing or reviewing migration files, when production queries suddenly slow down, when discussing backup/restore/replication, when the connection pool is exhausted, or when planning a schema change on a large table.
globs:
  - "**/migrations/**"
  - "**/migration/**"
  - "**/db/**"
  - "**/flyway/**"
  - "**/liquibase/**"
  - "**/*.sql"
alwaysApply: false
---

# PostgreSQL — Operations

Query and index tuning lives in `pg-review`. This module is about running the database
in production.

## Zero-downtime migrations

**Core rule:** DDL that takes an `ACCESS EXCLUSIVE` lock blocks every query on that table.
On a large, hot table that is an outage.

Always start a migration with:

```sql
SET lock_timeout = '3s';        -- fail fast instead of queueing and blocking traffic
SET statement_timeout = '5min';
```

| Operation | Safe? | Safe approach |
|---|---|---|
| `ADD COLUMN` nullable | Yes | Direct |
| `ADD COLUMN ... DEFAULT x` | Yes, PG11+ | Below PG11: add nullable → backfill → set default |
| `ADD COLUMN NOT NULL` | No, rewrites | Add nullable → backfill → `ADD CONSTRAINT ... NOT VALID` → `VALIDATE` |
| `CREATE INDEX` | No, blocks writes | `CREATE INDEX CONCURRENTLY` (outside a transaction) |
| `DROP INDEX` | No | `DROP INDEX CONCURRENTLY` |
| `ALTER COLUMN TYPE` | No, full rewrite | New column → backfill → swap names |
| `ADD FOREIGN KEY` | No, full scan | `NOT VALID` first, then `VALIDATE CONSTRAINT` |
| `RENAME COLUMN` | Risky | Requires expand-contract; the old app version breaks immediately |

**Expand-contract** for changes that are not backward compatible:

1. *Expand* — add the new structure, write to both (dual-write)
2. *Migrate* — backfill old data in batches
3. *Contract* — switch reads to the new structure, drop the old one (separate deploy)

`CREATE INDEX CONCURRENTLY` can fail and leave an `INVALID` index behind. Always check
`pg_index.indisvalid` afterwards.

## Bloat and autovacuum

```sql
SELECT relname, n_live_tup, n_dead_tup,
       round(n_dead_tup::numeric / NULLIF(n_live_tup, 0) * 100, 1) AS dead_pct,
       last_autovacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 10000
ORDER BY n_dead_tup DESC;
```

- Dead ratio above 20% on a hot table means autovacuum is falling behind — lower
  `autovacuum_vacuum_scale_factor` for that table specifically
- `VACUUM FULL` takes `ACCESS EXCLUSIVE` — **never run it in production**; use `pg_repack`
- Long `idle in transaction` sessions prevent vacuum from reclaiming tuples. Check
  `pg_stat_activity` for `state = 'idle in transaction'`

## Replication

```sql
SELECT client_addr, state, sent_lsn, replay_lsn,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;
```

- **Orphaned replication slots** retain WAL until the disk fills. This is a classic outage
  cause. Check `pg_replication_slots` for entries with `active = false`
- Read replica lag means read-after-write can serve stale data

## Backup and PITR

- [ ] WAL archiving enabled (`archive_mode`, `archive_command`) — without it there is no PITR
- [ ] **A restore drill has actually been performed** — an untested backup is not a backup
- [ ] RPO/RTO written down and verified, not assumed
- [ ] Backups stored outside the database host and region
- [ ] Backups encrypted; access to the backup bucket restricted and logged

## Connection pooling

- Raising `max_connections` is not a fix — each PostgreSQL connection is an OS process
- **PgBouncer modes**: `transaction` is the common, efficient choice but is **incompatible**
  with server-side prepared statements, session-level `SET`, advisory locks, and `LISTEN/NOTIFY`
- HikariCP: `maximumPoolSize` × instance count must stay below `max_connections` minus the
  superuser reserve
- Pool exhaustion is usually a symptom — look for slow queries or transactions that never commit

## Migration review checklist

- [ ] `lock_timeout` is set
- [ ] No rewriting DDL on a large table without an expand-contract strategy
- [ ] Indexes created `CONCURRENTLY`
- [ ] A rollback plan exists, and the rollback itself is not destructive
- [ ] Backfills are batched, not one giant `UPDATE`
- [ ] The migration is idempotent or guarded against re-runs
