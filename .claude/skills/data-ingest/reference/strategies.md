# Ingestion Strategies

## Full Load
Replace ALL data on every run. Truncate-and-insert pattern.

- **Use when**: Small tables, no watermark column, reference/lookup data
- **Pros**: Simple, always fully consistent with source
- **Cons**: Slow and expensive for large tables; no row-level history
- **State needed**: None

## Incremental (Watermark / Cursor)
Load only records newer than the last watermark value.

- **Requires**: A reliable `updated_at` timestamp or auto-increment `id` column
- **State**: Last watermark value stored in MinIO at `ingestion/state/{source}/{schema}/{table}/state.json`
- **Use when**: Large tables with a monotonically increasing, indexed watermark column
- **Pros**: Fast and efficient; low source load
- **Cons**: Misses hard deletes; watermark column must be indexed and trustworthy

## Append-Only
Always append new records; no deduplication.

- **Use when**: Immutable event or log data (clickstream, audit logs, webhook events)
- **Pros**: Simple, fast, naturally idempotent if records carry unique IDs
- **Cons**: Produces duplicates on retry if no dedup key; unsuitable for mutable tables

## Delete-Insert (Partition-Based)
Delete all records in a partition range, then reinsert fresh data for that partition.

- **Requires**: A well-defined partition key (date, month, region)
- **Use when**: Partitioned tables where late corrections may occur after initial load
- **Pros**: Idempotent, handles corrections and reruns cleanly
- **Cons**: Requires a partition key; cannot re-run without knowing the partition bounds

## CDC (Change Data Capture)
Capture INSERT / UPDATE / DELETE operations from the source system in real time.

- **Requires**: Database replication slot, Debezium, or a CDC-capable connector (e.g., `dagster-airbyte`)
- **Use when**: Near-real-time sync, need to replicate hard deletes
- **Pros**: Complete change history; captures deletes; low latency
- **Cons**: Complex setup; source database must support CDC; higher operational overhead

## Snapshot (SCD Type 2)
Record the full row state at each run with `valid_from` / `valid_to` columns.

- **Use when**: Slowly-changing dimensions, full historical state tracking is required
- **Pros**: Fully auditable; complete history of every attribute change
- **Cons**: Storage-heavy; more complex downstream consumption; requires merge logic

---

## Choosing a Strategy — Quick Guide

| Situation | Recommended Strategy |
|---|---|
| Small reference table (<1M rows, no updates) | Full Load |
| Large transactional table with `updated_at` | Incremental |
| Event log / audit trail (immutable) | Append-Only |
| Daily partition table with corrections | Delete-Insert |
| Need real-time sync + delete capture | CDC |
| Slowly-changing dimension | Snapshot |
| Unsure about watermark reliability | Full Load to start, migrate to Incremental |

---

## Default Schedule by Strategy

| Strategy | Recommended Schedule | Default Cron |
|----------|----------------------|--------------|
| `full_load` | Daily, off-peak | `0 2 * * *` |
| `incremental` | Hourly or daily (by volume) | `0 * * * *` / `0 3 * * *` |
| `append_only` | Match source event frequency | varies |
| `delete_insert` | Daily per partition window | `0 4 * * *` |
| `cdc` | Near-real-time — no batch schedule | — |
| `snapshot` | Daily or weekly | `0 1 * * *` / `0 1 * * 0` |
