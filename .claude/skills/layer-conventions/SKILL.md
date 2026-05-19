---
name: layer-conventions
description: Naming and structure conventions for data layers in a platform — `staging` / `intermediate` / `marts` (dbt) and `bronze` / `silver` / `gold` (lakehouse). Use when designing a new project's layer taxonomy, naming a schema / table / model, deciding which layer a piece of logic belongs in, or reviewing a project for convention drift. Reconciles dbt's analytics-engineering conventions with the medallion-architecture vocabulary so the same project can use both without contradiction. Stays project-agnostic — describes the layer shapes and decision rules, not the project's specific subject area.
---

# layer-conventions

## Overview

Two vocabularies dominate data-platform layering:

- **dbt convention** — `staging` → `intermediate` → `marts`. Analytics-engineering lens; each layer has a transformation role.
- **Medallion** — `bronze` → `silver` → `gold`. Lakehouse lens; each layer has a quality / curation level.

These describe the same idea from different angles. A platform that uses both (lakehouse storage + dbt for transformation) needs a reconciled vocabulary, or every PR review descends into "which layer does this belong in?" debates.

This skill provides the reconciliation, the per-layer rules, and the decision criteria for placing logic. It does not name the project's specific tables — sets the grammar, not the words.

## When to Use

- Designing a new project's layer / schema taxonomy
- Naming a new model, table, or schema
- Reviewing where logic belongs (a transformation drifting between layers)
- Reconciling a project that already mixes vocabularies inconsistently
- Onboarding a new contributor who needs the project's conventions in one place

Do **not** use for:
- Choosing the transformation tool (`dbt`, `SQLMesh`) — that's stack-archetype work
- Detailed dbt patterns (incremental strategies, materialization choices) — owned by `dbt@dbt-agent-marketplace`

## Reconciled Layer Model

Same idea, three names. Pick the row most natural for the storage shape; the **role** is identical.

| dbt name | Medallion | Storage shape | Role |
|---|---|---|---|
| `raw` (sources) | `bronze` | Lake / object store / external schema | Loaded as-is from source. No transformation. Per-source schemas. Append-only or full-refresh, never edited. |
| `staging` | (within `silver`) | Warehouse / lake | One-to-one with sources. Rename, recast, deduplicate, light-clean. No joins across sources. |
| `intermediate` | (within `silver`) | Warehouse / lake | Reusable joins and business-logic building blocks. Not exposed to end consumers. |
| `marts` | `gold` | Warehouse | End-consumer tables — facts, dimensions, aggregates, metrics. Stable contract with BI / API. |

A project using lake storage natively can say "bronze / silver / gold" and map staging+intermediate into silver subsystems. A pure-warehouse project says "raw / staging / intermediate / marts" and may have no bronze concept at all. Both are correct — pick one set per project and use it consistently.

## Per-Layer Rules

### Raw / Bronze — the immutable record of source

- **Inputs:** Source systems.
- **Transformations:** None. Loaders write, nothing else writes.
- **Schema:** Per-source (`raw_stripe`, `raw_postgres_app`, `bronze_stripe`).
- **Tables:** Named after the source object, not the business meaning. `raw_stripe.charges`, not `raw.payments`.
- **Materialization:** Append, full-refresh, or external (in a lake). Never `incremental` with diffs.
- **Tests:** Existence and freshness only — don't test source semantics here; that's staging's job.
- **Loaders:** dlt, Sling, Fivetran, hand-rolled — all write here.

The smell: editing a raw table to "fix" a source issue. Don't. Either fix at the source, or absorb the fix in staging.

### Staging — one-to-one with source, light cleanup

- **Inputs:** Exactly one raw table per staging model.
- **Transformations:** Column renames (snake_case, consistent prefixes), type casts, light deduplication, surface-level null handling.
- **Schema:** `staging` (one schema for the whole layer) or per-source (`staging_stripe`).
- **Tables:** Prefix `stg_<source>__<entity>` — e.g. `stg_stripe__charges`, `stg_postgres_app__users`. Double-underscore separates source from entity.
- **Materialization:** Usually `view` (cheap, reflects raw immediately) unless the table is huge.
- **Tests:** Column-level constraints — primary key uniqueness, not-null, basic enum acceptance.
- **What it does NOT do:** Joins, aggregations, complex business logic. Each staging model touches one raw table.

The smell: a staging model that joins two sources. That belongs in intermediate.

### Intermediate — reusable joins and building blocks

- **Inputs:** Staging models, possibly other intermediate models.
- **Transformations:** Joins across sources, derived columns, deduplication that requires context, slowly-changing-dimension prep.
- **Schema:** `intermediate` (or `int`).
- **Tables:** Prefix `int_<noun>__<verb>` — e.g. `int_orders__joined_with_payments`, `int_users__deduplicated`. Verbs describe the transformation.
- **Materialization:** `view` for cheap joins, `table` or `incremental` for expensive ones.
- **Tests:** Joins are tested for fan-out (no unexpected duplication), key integrity.
- **What it does NOT do:** Expose to BI / consumers. Intermediate is internal scaffolding.

The smell: intermediate models that a BI tool queries directly. That model belongs in marts.

### Marts / Gold — end-consumer tables

- **Inputs:** Staging, intermediate, occasionally other marts (rare).
- **Transformations:** Aggregations, metric calculations, slowly-changing-dimension finalization, final naming.
- **Schema:** `marts` plus a sub-namespace per domain — `marts_finance.fct_revenue`, `marts_product.dim_users`. Or per-project conventions like `marts.<domain>__<entity>`.
- **Tables:** Prefix by Kimball role — `fct_<event>` for fact tables, `dim_<entity>` for dimensions, `agg_<metric>` for aggregates, `mtr_<metric>` for metric exposures. Or use no prefix and rely on schema / domain.
- **Materialization:** `table` or `incremental`. Marts are read often; pay the materialization cost.
- **Tests:** Business-logic tests — metric reconciliation, completeness, referential integrity.
- **What it does NOT do:** Source-specific cleanup. By the time data reaches marts, source idiosyncrasies are gone.

The smell: a mart that breaks because a source schema changed. The source change should be absorbed in staging, never bubble up.

## Decision Rules — Where Does This Logic Belong?

When in doubt, ask in order:

1. **Does this logic touch exactly one source?**
   - Yes, and it's renames / casts / light cleanup → **staging**
   - Yes, and it's reusable across multiple downstream consumers → **intermediate**
   - Yes, and it's the final shape a consumer reads → **marts**

2. **Does this logic touch more than one source?**
   - Yes, and the joined result is consumed once → consider whether the join itself should be intermediate
   - Yes, and the joined result is consumed many times → **intermediate** for sure

3. **Does this logic compute a metric, KPI, or aggregate consumers read?**
   - Yes → **marts**, regardless of complexity

4. **Does this logic exist to repair source data?**
   - Yes → **staging** (absorb the repair) — never edit raw

5. **Is the logic a "one-off" view used only for analyst ad-hoc?**
   - Yes → keep it out of the layered project. A separate `ad_hoc` schema or notebook layer keeps marts clean.

## Naming Atoms

Pick one convention per project and stick to it. Mixing styles is the convention-debt that hurts most.

- **Schemas:** lowercase, underscored, layer-prefixed: `staging`, `intermediate_finance`, `marts_product`.
- **Tables:** `<prefix>_<source-or-domain>__<entity>` — the double-underscore is load-bearing; it separates the "category" from the "thing". Single-underscore-only names lose readability fast.
- **Columns:** snake_case, no abbreviations unless universally known. `user_id`, `created_at`, not `usrId` or `crtd`.
- **Time columns:** `<event>_at` for timestamps (`created_at`, `paid_at`), `<event>_date` for dates only.
- **Keys:** `<entity>_id` for natural / business keys, `<entity>_sk` for surrogate keys.

## Mapping to Storage

| Project shape | Where each layer lives |
|---|---|
| Pure Snowflake | All layers in Snowflake; `raw` may be an external stage to S3 |
| Pure local Postgres | All layers in Postgres, separate schemas |
| Local lake (MinIO + Iceberg) | `bronze` on MinIO, `silver` + `gold` in Iceberg tables or DuckDB-attached views |
| Hybrid (Snowflake + lake) | `raw`/`bronze` in lake, `staging`+ in Snowflake. Or the inverse — pick deliberately, document why |

## Anti-patterns to Reject

- Editing raw / bronze tables to fix source issues
- Joining across sources in staging
- Exposing intermediate models to BI tools
- Marts that re-implement logic already in intermediate
- Schema name without layer prefix (`stripe_charges` — which layer?)
- Mixing naming conventions inside one project
- Marts in the same schema as ad-hoc / experimental tables

## What This Skill Does Not Decide

- Specific table names or domains for this project — those are subject-matter decisions
- Materialization strategies — owned by `dbt` plugin or per-engine docs
- Permissions / RBAC across layers — coordinate with `secrets-management` and `environment-strategy`
- BI semantic layer (Cube, dbt Semantic Layer, LookML) — separate concern

## References

- [`references/dbt-layer-mapping.md`](references/dbt-layer-mapping.md) — Exact dbt directory layout, model file naming, schema config patterns
- [`references/medallion-mapping.md`](references/medallion-mapping.md) — Bronze / silver / gold on a lake, with Iceberg / Delta examples
- [`references/refactor-checklist.md`](references/refactor-checklist.md) — Step-by-step for cleaning up a project that mixed conventions
