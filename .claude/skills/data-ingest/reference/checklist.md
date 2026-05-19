# Post-Ingestion Verification Checklist

Complete ALL items before declaring ingestion work done.
Mark each item `[x]` once verified.

---

## Dependencies
- [ ] If new packages were added to `orchestration/pyproject.toml`, Docker container has been rebuilt (`docker compose up --build`)
- [ ] New resource registered in `resources/__init__.py` under all deployment keys in `RESOURCES`

## Asset Registration
- [ ] New source sub-package folder (`assets/{source_name}/`) exists with an `__init__.py`
- [ ] `assets/__init__.py` imports the new module and adds it to `all_assets` via `load_assets_from_package_module`
- [ ] Job added to `all_jobs` in `jobs/__init__.py`
- [ ] Schedule added to `all_schedules` in `schedule/__init__.py`

## Code Quality
- [ ] Python code passes type checking (`dignified-python` verified)
- [ ] No hardcoded credentials — only `os.environ` or Dagster resources
- [ ] Structured `context.log` calls present at: start, fetch, write, complete
- [ ] `description` field on `@dg.asset` is meaningful and human-readable

## Asset Definition
- [ ] Key prefix follows 4-level convention: `["raw", source_name, schema_name, table_name]`
- [ ] `group_name` = `{source_name}_ingestion`
- [ ] `kinds` set correctly (e.g., `{"postgres", "parquet"}`)
- [ ] Tags applied per `metadata.md`: domain, source_type, source_name, schema_name, table_name, ingestion_strategy, owner
- [ ] `owner` tag is set to a team or person name

## Execution
- [ ] `launch` skill invoked to materialize the asset (do not skip — manual confirmation of success is required)
- [ ] Asset materializes without error in Dagster UI at `http://localhost:3000`
- [ ] Run logs show: row count fetched, MinIO path written, duration in seconds
- [ ] `MaterializeResult` metadata fields match the schema in `metadata.md`

## Storage
- [ ] Parquet file present in MinIO console (`http://localhost:9001`) at the correct path
- [ ] Metadata JSON present alongside Parquet file
- [ ] State file updated in MinIO (incremental strategy only)

## Automation (if configured)
- [ ] Schedule is visible in Dagster UI under Automation
- [ ] Cron expression matches the requested interval (verify with a cron validator)
- [ ] Backfill ran successfully for the configured date/partition range (if required)

## Data Quality
- [ ] Row count in the expected range (compare with source if possible)
- [ ] No unexpected nulls in primary key columns
- [ ] Watermark value advanced correctly after run (incremental strategy only)

## Multi-Table Sessions
- [ ] Each table has its own independent `@dg.asset` (no shared mutable state)
- [ ] Each asset can be materialized individually without affecting others
- [ ] `group_name` is consistent across all assets from the same source
