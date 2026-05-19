---
name: data-ingest
description: MUST be invoked when building any new Dagster ingestion asset that writes Parquet to MinIO, for any datasource type (PostgreSQL, MySQL, REST API, CSV, BigQuery, Snowflake, etc.). Encodes: required references to load before writing code, fact-gathering protocol, adapter selection rules (built-in over raw), exploration gates, asset type decision logic, storage and metadata patterns, and mandatory schedule/job creation. This is the project's contract for production-grade ingestion — defers Dagster API specifics (decorators, partitions, sensor types) to `dagster-expert`, code quality to `dignified-python`, and all naming/path details to `convention.md`.
---

# data-ingester

## Overview

A Dagster ingestion asset is more than a function that reads and writes data. It is a contract: reproducible, observable, schema-consistent, and automatable. Get the structure right and adding a new table is a copy-paste-tweak; get it wrong and every new pipeline becomes its own snowflake. This skill encodes the protocol for producing a correct, production-grade ingestion asset from any datasource.

Six rules hold regardless of datasource type or ingestion strategy:

1. **Authoritative references consulted at each decision point** — `convention.md`, `strategies.md`, `metadata.md`, `checklist.md`, `dagster-expert`, and `dignified-python` each own a specific set of decisions; consult each when it applies.
2. **Required facts gathered first** — datasource type, source name, target tables, strategy, domain, and owner must all be known. Ask one question at a time.
3. **Adapters over raw connection code** — built-in adapters are used when available. Raw `psycopg2`, `pymysql`, or `requests` calls inside assets are forbidden when an adapter exists.
4. **Exploration gates verified** — env vars present, connection test passes, schema known, watermark indexed (incremental). Surface and resolve any failure before proceeding.
5. **Asset type decided explicitly** — for multiple tables, always ask the question. Never decide silently.
6. **Every asset gets a schedule and job** — automation is not optional and not user-triggered. No asset ships without both.

This skill does not teach Dagster the framework — that is `dagster-expert`'s job. It teaches the **protocol** for producing a correct, production-grade ingestion asset.

## When to Use

- Building a new Dagster ingestion asset for any datasource (PostgreSQL, MySQL, REST API, CSV, BigQuery, Snowflake, etc.)
- Adding incremental, CDC, full-refresh, or delete-insert ingestion to an existing source
- Adding a new table to an existing ingestion pipeline
- Designing the `ConfigurableResource` for a new external system
- Reviewing an existing ingestion asset for convention compliance

Do **not** use for:
- Dagster API concepts (`@dg.asset` decorator options, partition types, sensor configuration) — use `dagster-expert`
- dbt transformation models downstream of raw ingestion — use `add-dbt-project`
- Infrastructure setup or Docker Compose changes — use `infra-docker-compose`
- Which cron schedule is correct for the domain — consult `strategies.md` (loaded as a required reference)
- Multi-environment resource configuration — use `environment-strategy`

## Mental Model

An ingestion pipeline has four responsibilities, each isolated from the others:

| Responsibility | Where it lives | Boundary |
|---|---|---|
| Connection logic | `resources/{source_name}_resource.py` | Auth, retries, pagination — no data logic; credentials from `os.environ` only |
| Data fetch + write | `assets/{source_name}/{source_name}_{schema_name}.py` | Calls resource methods; owns `MaterializeResult` and Parquet write — no connection code |
| State tracking | State file at the path from `convention.md` | Read before fetch; written after write — both mandatory for incremental |
| Automation | `jobs/__init__.py` + `schedule/__init__.py` | One job per asset group, one schedule per job — never optional |

The `ConfigurableResource` at `resources/<source_name>_resource.py` is the single place where the external system is understood. Assets call methods on it. They never re-implement connection, auth, or retry logic inline.

## The Six Rules

### Rule 1 — Consult the right reference for each decision

These files are authoritative references — consult them when the relevant decision arises, not all upfront:

| Reference | Consult when |
|------|---------|
| `./reference/convention.md` | Deciding any name, path, filename, resource structure, or write pattern |
| `./reference/strategies.md` | Choosing or validating an ingestion strategy or default schedule |
| `./reference/metadata.md` | Writing tags, `MaterializeResult` fields, or state file structure |
| `./reference/checklist.md` | Verifying the asset is complete before marking the task done |
| `dagster-expert` skill | Creating assets, schedules, jobs, or partitions |
| `dignified-python` skill | Reviewing type hints and code quality before presenting code |

Every name, path, and filename must follow `convention.md` exactly. There are no exceptions.

Why: conventions enforced at decision-time prevent drift before it occurs. Fixing a naming violation after assets are in production requires touching state files, MinIO paths, and downstream references simultaneously.

### Rule 2 — Gather required facts before writing code

Collect all of the following, asking **one question at a time**:

| Fact | Example |
|------|---------|
| `datasource_type` | `postgres`, `mysql`, `rest_api`, `csv`, `bigquery` |
| `source_name` | `supabase_prod`, `mysql_crm`, `stripe_api` |
| `target_tables` | `["public.orders", "public.customers"]` |
| `ingestion_strategy` | one valid strategy from `strategies.md` |
| `domain` | one valid value from `metadata.md` |
| `owner` | `data-team`, `analytics`, `john.doe` |

**Conditional facts** — required when the strategy demands them:

| Condition | Additional Fact Required |
|-----------|--------------------------|
| strategy = `incremental` | Watermark column name and type |
| strategy = `delete_insert` | Partition key and bounds |
| strategy = `cdc` | Replication slot or CDC connector details |
| backfill requested | Date range or partition range |

If the strategy is uncertain, explore the schema first, then recommend with reasoning and wait for user confirmation before proceeding.

Why: incomplete facts produce incorrect code. Discovering mid-implementation that the watermark column does not exist or is unindexed requires rewriting the asset and its state logic.

### Rule 3 — Use adapters; no raw connection code in assets

Consult `dagster-expert` for a built-in adapter matching `datasource_type` before writing any connection code.

| Adapter available? | Action |
|--------------------|--------|
| Yes | Use it. Raw connection code (`psycopg2`, `pymysql`, `requests`) is **forbidden** inside assets. |
| No | Ask user for credentials, then build a `ConfigurableResource` using the appropriate low-level library. |

The resource lives at `orchestration/src/orchestration/resources/<source_name>_resource.py` — see `convention.md` for the required structure. All credential values come from `os.environ` only. No hardcoded values anywhere in the file.

Why: raw connection code in assets cannot be reused, tested independently, or reconfigured per deployment. A `ConfigurableResource` solves all three.

### Rule 4 — Pass all exploration gates before writing code

Verify ALL four gates before writing any asset code:

1. Required env vars present in `.env` or `orchestration/.env`
2. Lightweight connection test passes (`SELECT 1`, `HEAD` request, read first line)
3. Schema of every target table known (columns, types, nullable flags)
4. Watermark column exists and is indexed (incremental strategy only)

If any gate fails, surface the exact error and resolve it before proceeding. If env vars are missing, list them explicitly and stop until the user provides them.

Why: code written against an assumed schema fails at materialization time, not authoring time. Gate verification shifts failures left by minutes to hours.

### Rule 5 — Decide asset type explicitly; never silently

| Datasource | Default |
|------------|---------|
| Database (PostgreSQL, MySQL, etc.) or multiple CSVs | **Static partition** — always, even for a single requested table |
| REST API or API-like source | Normal assets |
| Unsure | Normal assets — migrate to static partition later |

**For database sources:** During schema exploration, list all tables present in the schema. Even if the user only requests 1 table, create a **static partition asset** with `table_name` as the partition key and include all discovered tables as partition values. The user's requested table is the first partition to materialize; the rest are available without any code change.

**File naming for static partition assets:** The file must be named `{source_name}_{schema_name}.py` (e.g., `supabase_sales.py`), never `{source_name}_{schema_name}_{table_name}.py`. The file represents the **schema**, not a single table. Naming it after one table (e.g., `supabase_sales_orders.py`) falsely implies only that table is ingested. The `name` parameter on `@dg.asset` must be the schema name (e.g., `"sales"`), not `{schema_name}_{table_name}` — see `convention.md` for the reason.

Rationale: adding a table later is adding a partition value (one line); changing a normal asset to a static partition after the fact requires rewriting the asset, its state logic, and any downstream references.

Present the recommendation with reasoning — show the full table list discovered and explain that only the requested table will be materialized first. Wait for user confirmation. Confirm the partition key (`table_name`) before writing. Extract all per-table logic into a factory function — copy-paste across partition values is forbidden.

Why: wrong asset type requires an architecture change to undo. Static partition from day one keeps the door open; normal asset forecloses it.

### Rule 6 — Every asset gets a schedule and job

No asset ships without automation. The steps are always:

1. Use `strategies.md` for the default schedule recommendation
2. Present the cron expression with reasoning, validate it before presenting
3. Wait for user confirmation
4. Use `dagster-expert` for all schedule and job creation

Asset creation fields must follow `convention.md` exactly for every `@dg.asset`:

- `name` = `{schema_name}` for static partition assets; `{schema_name}_{table_name}` for normal assets
- `key_prefix` = `["raw", "{source_name}", "{schema_name}"]`
- `group_name` = `{source_name}_ingestion`
- `kinds` = `{"{datasource_type}", "parquet"}`
- `description` = meaningful, human-readable (no placeholders)
- `tags` = all 7 required fields per `metadata.md`

Each table is its own independent `@dg.asset` with no shared mutable state. The `group_name` must be identical across all assets from the same source, and each asset must be materializable independently without affecting others.

After generating any asset code, run `dignified-python` verification and fix ALL issues before presenting to the user.

Why: unscheduled assets accumulate silently. Enforcing automation at authoring time ensures every asset is observable and operationally complete from day one.

## Decision Flow — Building a New Ingestion Asset

When the user says "build a new ingestion asset" or "ingest table X from source Y":

1. **Know your references** — `convention.md`, `strategies.md`, `metadata.md`, `checklist.md`, `dagster-expert`, and `dignified-python` are the authoritative sources for each decision. Consult each one when the relevant decision arises.
2. **Gather facts** — collect `datasource_type`, `source_name`, `target_tables`, `ingestion_strategy`, `domain`, and `owner` one question at a time. Gather conditional facts if the strategy requires them.
3. **Check for an existing resource** — does `resources/<source_name>_resource.py` already exist? If yes, reuse it (add a method if needed). If no, proceed to the next step.
4. **Check for a built-in adapter** — consult `dagster-expert`. If one exists, use it. If not, build a `ConfigurableResource` following `convention.md`.
5. **Pass exploration gates** — verify env vars, connection test, schema, and watermark (incremental). Stop and surface errors if any gate fails.
6. **Decide asset type** — for database sources, always propose static partition with `table_name` as the partition key, listing all tables discovered in the schema regardless of how many the user requested. Present recommendation with reasoning and wait for confirmation.
7. **Write the resource** — create `orchestration/orchestration/resources/{source_name}_resource.py` following `convention.md`. All credentials from `os.environ`. Register it in `resources/__init__.py` under every deployment key in `RESOURCES`.
8. **Write the asset(s)** — follow `convention.md` exactly for file path (`assets/{source_name}/{source_name}_{schema_name}.py`), `name`, `key_prefix`, group name, kinds, tags. Write Parquet at the path from `convention.md`. Return `MaterializeResult` with all 8 fields from `metadata.md`. For incremental: read state before fetch, write state after write — both mandatory.
9. **Register the asset module** — if this is a new datasource, create `assets/{source_name}/__init__.py` and update `assets/__init__.py` to import and load the new package module (see `convention.md` for the exact pattern).
10. **Run `dignified-python` verification** — fix all issues before presenting code to the user.
11. **Define the job and schedule** — add the job to `jobs/__init__.py` and the schedule to `schedule/__init__.py` following `convention.md`. Present the cron expression with reasoning, wait for confirmation, then write both.
12. **Rebuild the container if packages changed** — if any new dependency was added to `orchestration/pyproject.toml`, run `docker compose up --build` before attempting materialization. A plain restart will not install new packages.
13. **Auto-run and verify** — invoke the `launch` skill to materialize the asset. Do not declare success without observing the run complete in Dagster UI. Confirm: run logs show row count, MinIO path, and duration; Parquet file visible at the correct path in MinIO console (`http://localhost:9001`).
14. **Verify done criteria** — go through every item in `checklist.md` one by one, explicitly.

Each step is small. If a step requires touching unrelated code, a convention has been violated somewhere.

## Decision Flow — Adding a Table to an Existing Source

When the user says "add table X to existing source Y":

1. **Does the new table require a new method on the existing resource?** If yes, add it to `resources/<source_name>_resource.py`. If no, the asset calls an existing method.
2. **Gather missing facts** — strategy, domain, watermark column (if incremental). Confirm with user.
3. **Pass exploration gates** — schema of the new table must be known; watermark must be verified as indexed.
4. **Write the new asset** — same `group_name` as other assets from this source (`{source_name}_ingestion`). Same resource, same Parquet path pattern from `convention.md`.
5. **Verify the group job covers the new asset** — if `AssetSelection.groups("{source_name}_ingestion")` is already defined, the new asset is automatically included. Confirm this rather than creating a duplicate job.
6. **Verify done criteria** for the new asset only. Other assets from the same source must still materialize without error.

## Anti-patterns to Reject

- Connection, auth, retry, or pagination logic inside `@dg.asset` functions — belongs in the resource
- Resources scattered across asset folders (`assets/postgres/postgres_client.py`) — they belong in `resources/`
- Raw `psycopg2`, `pymysql`, or `requests` calls inside assets when a built-in adapter exists
- One resource per endpoint (e.g. separate modules for `/orders` and `/customers` of the same API) — collapse to one client with multiple methods
- Credentials hardcoded anywhere in the codebase — all values from `os.environ` only
- Copy-paste asset code across tables instead of a factory function when the pattern is identical
- Assets shipped without a job and schedule
- `MaterializeResult` returned with fewer than all 8 required fields from `metadata.md`
- Incremental assets where state read or state write is skipped
- Presenting code to the user before running `dignified-python` verification
- Deciding asset type (normal vs. static partition) without asking the user first
- Naming a static partition asset file after a single table (e.g. `supabase_sales_orders.py`) when it covers a whole schema — use `{source_name}_{schema_name}.py`
- Using `{schema_name}_{table_name}` as the `name` on a static partition `@dg.asset` — this embeds the schema name twice in the 4-level asset key
- Forgetting to register a new source module in `assets/__init__.py` — the asset will be silently absent from Dagster
- Forgetting to register a new resource in `resources/__init__.py` under all deployment keys in `RESOURCES` — materialization will fail at runtime
- Running `docker compose restart` after adding packages to `pyproject.toml` instead of `docker compose up --build` — new packages are never installed
- Declaring the task complete without invoking the `launch` skill to verify actual materialization

## What This Skill Does Not Decide

- Dagster API specifics (`@dg.asset` decorator options, partition types, sensor configuration) — `dagster-expert`
- Code quality standards beyond the `dignified-python` verification step — `dignified-python`
- Which cron schedule is correct for the business domain — `strategies.md` (loaded as a required reference)
- All naming and path details — `convention.md` (loaded as a required reference)
- dbt transformation models downstream of raw ingestion — `add-dbt-project`
- Infrastructure changes to Docker Compose or service definitions — `infra-docker-compose`
- Multi-environment resource configuration (local vs. cloud credentials) — `environment-strategy`
- Credential storage strategy — `secrets-management`

## References

- [`./reference/convention.md`](./reference/convention.md) — Naming, paths, logging, resource structure, Parquet write pattern; always in force for every asset
- [`./reference/strategies.md`](./reference/strategies.md) — Ingestion strategies (full-refresh, incremental, CDC, delete-insert) and default schedule recommendations
- [`./reference/metadata.md`](./reference/metadata.md) — Required tags, all 8 `MaterializeResult` fields, state file schema; required for every asset
- [`./reference/checklist.md`](./reference/checklist.md) — Verification checklist; every item must pass before the task is complete
