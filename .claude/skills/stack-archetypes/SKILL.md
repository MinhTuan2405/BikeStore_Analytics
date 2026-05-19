---
name: stack-archetypes
description: Catalogue of common data-platform stack archetypes with their tradeoffs. Use when a user is deciding between stacks, asks "which stack should I use", or `platform-bootstrap` Phase 1 needs to match user answers to a known shape. Each archetype lists components, when to choose it, when to avoid it, and the per-layer skills/plugins that own it. Stops at "what fits and why" — does not scaffold; hands off to `platform-bootstrap`.
---

# stack-archetypes

## Overview

Most data platforms are variations on a handful of shapes. This skill is the catalogue. It exists so the user (or `platform-bootstrap`) doesn't re-invent the layer composition for every new project — pick a known archetype, customize, move on.

Each archetype describes:
- **Components** — which tool owns each layer
- **Strengths** — what it does well
- **Weaknesses** — what it does poorly
- **Choose when** — concrete triggers
- **Avoid when** — concrete anti-triggers
- **Layer owners** — which skill / plugin to load for each layer during scaffolding

The archetypes are not prescriptive. Compose, swap, hybridize as the project demands — but **name** the resulting shape so subsequent decisions reference the same thing.

## When to Use

- User asks "which stack do I pick for X"
- `platform-bootstrap` Phase 1 needs to match answers to a template
- Reviewing an existing project against alternatives
- Documenting a project's stack choice (cite the archetype by name)

## Mental Model

Archetypes vary along three axes:

| Axis | Options |
|---|---|
| **Storage shape** | Lake (object store + table format) · DWH (managed warehouse) · Postgres warehouse · Hybrid |
| **Compute locality** | Local (laptop / single host) · Cloud (managed services) · Mixed |
| **Source variety** | Single source · Few sources · Many sources (10+) · Streaming |

Most archetypes pick one option per axis. Hybrids exist but pay extra complexity for the flexibility.

## Decision Quickref

| User signal | First archetype to consider |
|---|---|
| "Quick demo on my laptop, no cloud accounts" | `portable-duckdb` or `local-lake` |
| "Production with Snowflake account already in place" | `snowflake-dwh` |
| "Open data, no vendor lock-in" | `local-lake` or `cloud-lake` |
| "We have Postgres and don't want anything else" | `postgres-warehouse` |
| "Snowflake for prod, want fast local iteration" | `hybrid-snowflake-local` |
| "Streaming data, sub-minute latency" | `streaming-first` (consider managed services) |
| "Transformation only — data is already in the warehouse" | `transformation-only` |

## The Archetypes

### 1. `portable-duckdb`

Single-binary embedded analytical DB. Whole platform fits on a laptop.

- **Components**: DuckDB (storage + compute) · dbt (transform) · Dagster (orchestrate) · Local files for ingestion · No object store
- **Strengths**: Zero infra, fast, great for tutorials and POCs, deterministic
- **Weaknesses**: Single-machine only, no concurrent writers, no real sharing
- **Choose when**: Solo learner, demo, prototype, < 50GB data, no multi-user requirement
- **Avoid when**: More than one developer, production data, anything > 100GB
- **Layer owners**: `infra-docker-compose` (optional — DuckDB can run without Docker) · `dagster-expert` · `dbt@dbt-agent-marketplace`

### 2. `local-lake`

Open lakehouse running entirely on the developer's machine.

- **Components**: MinIO (object store) · Iceberg or Delta (table format) · Catalog (Nessie / Polaris / REST) · Trino or DuckDB (query engine) · dbt (transform) · Dagster (orchestrate) · `dlt` or hand-rolled (ingestion)
- **Strengths**: Production-shaped patterns, vendor-neutral, lake semantics from day one
- **Weaknesses**: More moving parts than `portable-duckdb`, catalog setup is fiddly, query engine adds complexity
- **Choose when**: Want production parity locally, team is committed to lakehouse, learning Iceberg / Delta
- **Avoid when**: Team has < 1 person comfortable with infra, project deadline < 2 weeks
- **Layer owners**: `infra-docker-compose` · `dagster-expert` · `dbt@dbt-agent-marketplace` · `filesystem-pipeline@dlthub-ai-workbench`

### 3. `snowflake-dwh`

Managed cloud warehouse as the source of truth; no local storage.

- **Components**: Snowflake (storage + compute) · dbt (transform) · Dagster (orchestrate) · `dlt` or Fivetran / Airbyte (ingestion) · Optional Cortex AI features
- **Strengths**: Production-ready immediately, separation of storage/compute managed for you, mature ecosystem
- **Weaknesses**: Cost — credits add up fast in dev, lock-in to one vendor, local-dev parity is harder
- **Choose when**: Snowflake account already exists, team prefers SQL over engine ops, scale > a few hundred GB
- **Avoid when**: Budget-sensitive solo project, no cloud account, want open table format
- **Layer owners**: `dagster-expert` · `dbt@dbt-agent-marketplace` · `snowflake-cortex-code@claude-plugins-official` · `sql-database-pipeline@dlthub-ai-workbench`

### 4. `postgres-warehouse`

Postgres tuned for analytical workloads. Cheap, simple, scales modestly.

- **Components**: Postgres (storage + compute) · dbt (transform) · Dagster (orchestrate) · `dlt` or direct loads (ingestion)
- **Strengths**: Cheapest possible production stack, full SQL, mature tooling, fits a single VM
- **Weaknesses**: Analytical performance ceiling (low TBs), no separation of storage/compute, indexing strategy matters
- **Choose when**: < 1TB data, simple team, transactional Postgres already in play, cost is the deciding factor
- **Avoid when**: Data > 1TB, columnar scan performance matters, many concurrent analysts
- **Layer owners**: `infra-docker-compose` (if self-hosted) · `dagster-expert` · `dbt@dbt-agent-marketplace`

### 5. `hybrid-snowflake-local`

Snowflake for shared / prod data; local Postgres + MinIO for fast dev iteration.

- **Components**: Snowflake (prod) · Postgres + MinIO (local dev) · dbt with multiple profiles · Dagster · `dlt`
- **Strengths**: Fast dev cycle without burning credits, production parity at boundary points
- **Weaknesses**: Two stacks to maintain, data parity is constant work, profile sprawl in dbt
- **Choose when**: Team is hitting Snowflake credit limits in dev, schemas change often, want quick local iteration
- **Avoid when**: Team is small and one stack is enough, data has compliance requirements that block local copies
- **Layer owners**: `infra-docker-compose` · `dagster-expert` · `dbt@dbt-agent-marketplace` · `snowflake-cortex-code` (prod only)

### 6. `streaming-first`

Sub-minute latency, event-driven ingestion + compute.

- **Components**: Kafka or Kinesis (transport) · Flink / Spark Structured Streaming / Materialize (compute) · Iceberg or DWH (sink) · Schema registry
- **Strengths**: Real-time, scales horizontally, decoupled producers/consumers
- **Weaknesses**: Operational complexity is an order of magnitude higher, observability is non-trivial, exactly-once is hard
- **Choose when**: Sub-minute SLA is a real requirement (not aspirational), team has streaming experience
- **Avoid when**: Batch every hour is good enough, team is new to streaming, no on-call rotation
- **Layer owners**: Mostly out-of-scope for current plugins — bring in managed services or build custom skills

### 7. `transformation-only`

Data is already in the warehouse. No ingestion layer, sometimes no orchestrator.

- **Components**: Existing warehouse · dbt (transform) · Optional: Dagster for scheduling · CI for dbt PRs
- **Strengths**: Smallest project, fastest to ship, clear ownership boundary
- **Weaknesses**: Depends on upstream data quality you don't control; freshness debugging crosses team boundaries
- **Choose when**: An ingestion team / Fivetran / Stitch already lands data; your job is modeling
- **Avoid when**: You need to debug source data quality issues regularly (you'll be blocked on the ingestion team)
- **Layer owners**: `dbt@dbt-agent-marketplace` · optionally `dagster-expert`

## Composing Custom Archetypes

If none of the above fits exactly, **name your custom archetype** before scaffolding. Document the layer choices in a one-paragraph rationale, including:

- The axis values (storage / locality / source variety)
- Why no listed archetype fit
- The closest archetype, and what you changed

This keeps decisions reviewable instead of vibes-based.

## What This Skill Does Not Do

- Scaffold the stack — that's `platform-bootstrap`'s job, reading from here
- Recommend specific image versions or tags
- Compare cloud vendors in detail (use a vendor comparison reference, not this skill)
- Make the decision **for** the user — surfaces tradeoffs; the user picks

## References

- [`references/decision-matrix.md`](references/decision-matrix.md) — Side-by-side comparison of the seven archetypes on cost, complexity, vendor lock-in, scale ceiling
- [`references/migration-paths.md`](references/migration-paths.md) — When and how to move between archetypes (e.g. `postgres-warehouse` → `snowflake-dwh`, `local-lake` → `cloud-lake`)
