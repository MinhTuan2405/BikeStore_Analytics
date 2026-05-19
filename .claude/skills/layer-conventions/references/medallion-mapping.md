# Medallion Mapping — Bronze / Silver / Gold on a Lake

Same layer roles as the dbt convention, expressed in lakehouse vocabulary. Use this reference when the platform stores data on object storage with an open table format (Iceberg / Delta / Hudi).

## Layer mapping recap

| Medallion | dbt equivalent | Storage shape |
|---|---|---|
| `bronze` | `raw` (sources) | Object store: append-only, source-shaped, loaded as-is |
| `silver` | `staging` + `intermediate` | Object store: cleaned, conformed, joined building blocks |
| `gold` | `marts` | Object store or DWH: final consumer tables |

A project may have multiple silver "sub-layers" (e.g. `silver_staging` and `silver_intermediate`) — this is a naming convention, not a separate medallion tier.

## Bronze conventions

- **Location:** A dedicated bucket / prefix per source: `s3://platform-bronze/stripe/`, `s3://platform-bronze/postgres_app/`.
- **Format:** Whatever the loader writes natively. Parquet preferred for columnar scan; Avro / JSONL acceptable when schemas drift.
- **Partitioning:** By load date (`_dlt_load_id` or equivalent) or source-native key. Avoid clever partitioning at bronze — it's the raw record.
- **Schema evolution:** Lenient. Bronze accepts what the source produces; silver handles the cleanup.
- **Retention:** Long. Bronze is the audit log — drop only when storage cost outweighs replay-from-source cost.

## Silver conventions

- **Location:** `s3://platform-silver/<source-or-domain>/`. Iceberg / Delta tables, not raw files.
- **Catalog:** Registered in a catalog (Nessie, Polaris, Glue, REST) — silver tables are queryable by name.
- **Partitioning:** Driven by query patterns. Daily partitioning on the most-filtered timestamp is a safe default.
- **Format:** Iceberg or Delta with native compaction enabled. Don't roll your own compaction.
- **Schema evolution:** Strict at column-add level; breaking changes (renames, type changes) go through a versioning process.
- **Time travel:** Keep enabled (Iceberg snapshots, Delta time travel) — debugging silver-layer issues without history is painful.

## Gold conventions

- **Location:** Depends on consumption:
  - BI dashboards / API → in the DWH (Snowflake reads from external Iceberg, or materializes natively)
  - Lake-native consumers → `s3://platform-gold/`, same catalog as silver
- **Partitioning:** Aligned with consumer query patterns, not source-shape
- **Format:** Iceberg / Delta, optimized for read (compaction, bloom filters, z-ordering)
- **Refresh:** Triggered by orchestrator after silver-layer assets materialize
- **Stability:** Gold tables have public contracts; breaking changes go through a deprecation cycle

## Catalog hygiene

A lakehouse without catalog discipline becomes a swamp. Rules:

- One catalog namespace per medallion tier: `bronze`, `silver`, `gold`. Or per-domain: `silver_finance`, `gold_finance`.
- Table names match the dbt convention even when there's no dbt — `stg_stripe__charges`, `fct_revenue`. Cross-tool readability matters.
- Every table has a description in the catalog. An undocumented table in a lakehouse is approximately as useful as an undocumented variable in code.

## When the project uses dbt + lakehouse

Common pattern: dbt writes to silver and gold; bronze is ingestion-loader-owned. Two consequences:

- dbt sources point at the catalog's bronze namespace
- dbt project's schema config maps to silver / gold catalog namespaces
- `staging` and `intermediate` both live in silver — the dbt directory structure still reflects the layer, but the storage schema is `silver_<source>` for staging and `silver_intermediate_<domain>` for intermediate

This works. The dbt vocabulary describes the role; the medallion vocabulary describes the storage tier. Use both — they don't conflict if you're explicit about which is which.

## Compute engine considerations

Lakehouse storage is engine-neutral, but each engine has personality:

- **Trino / Starburst** — strong joins, mature, multi-engine queries. Heavy infra footprint.
- **DuckDB on Iceberg** — single-machine, very fast on local lakes, limited concurrent writers.
- **Spark on Iceberg / Delta** — most production-tested combo; resource-heavy.
- **Snowflake on external Iceberg** — managed compute over open storage; cost model bridges DWH and lake.

The convention applies regardless of engine. The engine choice is a separate decision under `stack-archetypes`.

## What this reference does not cover

- Engine-specific tuning (Trino node sizing, Spark partitioning)
- Vendor catalog setup (Glue vs. Polaris vs. Nessie installation)
- Compaction scheduling specifics — handled at the table-format layer (Iceberg `expire_snapshots`, Delta `OPTIMIZE`)

For those, consult engine and table-format docs directly.
