# Migration Paths — Moving Between Archetypes

Archetypes are not permanent. Most projects evolve. These notes cover when to migrate, what changes, and what stays.

## `portable-duckdb` → `local-lake`

**Trigger:** More than one developer; data > 50 GB; want to learn lake patterns.

What changes:
- DuckDB tables → Iceberg / Delta tables on MinIO
- dbt profile switches from `duckdb` adapter to `trino` (or stays on `duckdb-attached` to Iceberg)
- Add catalog (Nessie / Polaris / REST)
- Add compose stack (was none)

What stays:
- Dagster project, dbt project structure, asset graph

What you lose: simplicity. Pick this only if the team needs lake semantics, not because it sounds cool.

## `portable-duckdb` → `snowflake-dwh`

**Trigger:** Moving to a real cloud DWH for production.

What changes:
- DuckDB → Snowflake. SQL dialect differences (DuckDB is closer to Postgres; Snowflake has its own dialect, `MERGE`, dynamic tables, etc.)
- Profiles, env vars, IAM
- Cost shifts from $0 to $$$

What stays:
- dbt project structure, Dagster orchestration logic, ingestion pipelines (`dlt` switches destinations)

Test the SQL dialect translation early; do not assume `dbt-duckdb` and `dbt-snowflake` are drop-in compatible.

## `postgres-warehouse` → `snowflake-dwh`

**Trigger:** Data > 1 TB; concurrent users > a few dozen; query performance ceiling hit.

What changes:
- Connection layer (Postgres → Snowflake)
- SQL dialect (mostly compatible, some functions differ)
- Vacuum / index logic disappears (Snowflake manages it)
- Operating model: stop managing the DB, start managing credits

What stays:
- dbt project, Dagster, most pipelines

Bridge strategy: run both in parallel for a month, materialize the same models in both, compare row-by-row before cutover.

## `local-lake` → `cloud-lake`

**Trigger:** Production deployment; shared team data; data > 1 TB.

What changes:
- MinIO → S3 / GCS / Azure Blob
- Catalog moves to managed (Glue / Polaris)
- IAM, networking, encryption-at-rest

What stays:
- Table format (Iceberg / Delta unchanged), dbt project, Dagster, ingestion logic

Easiest migration of the lot — open formats keep this clean.

## `snowflake-dwh` → `hybrid-snowflake-local`

**Trigger:** Dev cycle is slow; credit bill is climbing; team wants faster local iteration.

What changes:
- Add a local compose stack (Postgres + MinIO + Dagster + dbt) mirroring Snowflake structure
- dbt gets a second profile (`local` → Postgres, `prod` → Snowflake)
- Ingestion runs in both environments, against different destinations
- Devs work locally, CI / prod use Snowflake

What stays:
- Snowflake production setup, dbt model logic (with care: dialect differences bite)

The hidden cost: every model has to be testable on Postgres. Snowflake-specific features (dynamic tables, MERGE patterns, semi-structured access) need fallback paths or feature flags.

## Anything → `transformation-only`

**Trigger:** Ingestion is taken over by another team / managed service. Your project becomes modeling-only.

What changes:
- Ingestion code is deleted from the repo (or moved out)
- Orchestrator simplifies (no ingestion sensors / partitions)
- Data freshness becomes someone else's problem — but breaks your project when it goes wrong

What stays:
- dbt project, possibly Dagster scheduling

Negotiate the contract with the ingestion team explicitly: schema, freshness SLA, breaking-change notification. Without that contract, "transformation-only" means "broken every Monday".

## Anti-pattern: `streaming-first` as a starting archetype

Starting in streaming is almost always a mistake. Batch first, prove the model, only then add streaming where latency is genuinely required. The reverse migration (streaming → batch) is much harder than the forward one.

If business "needs real-time", check whether they actually need real-time, or whether they need *faster than daily*. Hourly batch covers 80% of "real-time" asks at 10% of the cost.
