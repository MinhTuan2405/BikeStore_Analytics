---
name: environment-strategy
description: Patterns for separating dev / staging / prod across a data platform — schema and warehouse isolation, role / permission models, data parity, promotion flows. Use when designing how environments differ, adding a new environment to an existing project, deciding what data lives where, or reviewing prod-bleeding-into-dev incidents. Touches every layer (compose / dbt / dagster / dlt / warehouse) — coordinates with `secrets-management` for credentials and `layer-conventions` for naming. Stays vendor-agnostic — describes the strategy, not a specific cloud setup.
---

# environment-strategy

## Overview

A data platform has at least two environments — dev and prod — and usually more (staging, CI, per-developer sandboxes). The cost of confusing them is unbounded: data loss when a dev script hits prod, leaked PII when prod data lands in dev, broken trust when a prod incident has unknown blast radius.

This skill encodes the patterns that keep environments separate at every layer of the stack, and the patterns that **deliberately bridge them** when data parity is needed.

## When to Use

- Designing the dev / staging / prod split for a new project
- Adding a per-developer sandbox layer
- Reviewing a project where prod and dev share infrastructure
- Debugging an incident where dev work touched prod (or vice versa)
- Planning the promotion flow for a new pipeline

Do **not** use for:
- Credential storage — coordinate with `secrets-management`
- Specific cloud network isolation (VPC, private endpoints) — outside data-platform scope
- Disaster recovery — separate concern (backup / restore, not environment design)

## Mental Model

Five axes define an environment. Two environments are properly separated when **all five** are isolated:

| Axis | What it covers |
|---|---|
| **Compute** | Which physical hosts / cloud accounts / warehouse instances run the jobs |
| **Storage** | Where data lives — database, schema, bucket, partition |
| **Identity** | Which credentials / roles / service accounts the jobs use |
| **Code** | Which branch / image tag the deployed code came from |
| **Data** | Which records / partitions the environment sees |

Partial isolation creates the worst incidents. A dev job using prod credentials, even briefly, can write to prod even when "everything else is dev". A prod job reading a dev schema (because someone tested with a hardcoded name) breaks silently when the dev schema disappears.

## Core Principles

1. **Names alone are not isolation.** A schema called `dev` in the same warehouse as `prod` is one typo from prod. Isolation must be enforced by permissions, not by naming hygiene.
2. **Identity is the load-bearing axis.** Get the identity model right (per-environment service accounts, scoped roles) and other isolation follows. Get it wrong and the other axes can't compensate.
3. **Production credentials touch only production.** A laptop with prod credentials in its env vars is a prod incident waiting to happen. Production credentials are reachable only from production runners.
4. **Data flows downward, never upward.** Prod data may seed dev (sampled, masked); dev data may **never** reach prod. This is asymmetric by design.
5. **Promotion is automated, not manual.** A human running `dbt run --target prod` from a laptop should be impossible by access design, not by discipline.
6. **Environments share code, not state.** All environments deploy from the same code. Their behavior differs only via configuration. A pattern that exists "only in prod" is a hidden bug.
7. **Per-developer sandboxes are temporary.** Long-lived per-dev schemas accumulate cruft and drift from the canonical layout. Recycle on a schedule.

## Environment Tiers

Most projects need three or four. More than five is a smell.

### `dev` — local-first iteration

- **Compute:** Developer's laptop (compose stack) or shared cloud dev account
- **Storage:** Local Postgres / MinIO, or per-developer prefixed schemas in a shared cloud DB
- **Identity:** Developer's personal credentials, scoped to their own schema / bucket
- **Code:** Whatever branch the developer is on
- **Data:** Sampled / synthetic, or a small slice of prod (masked)
- **Refresh:** On demand; can be wiped and rebuilt anytime

### `staging` (or `ci`) — pre-prod validation

- **Compute:** Shared cloud account / shared warehouse, isolated from prod
- **Storage:** Mirror of prod's schemas, separate namespace
- **Identity:** CI service account, scoped to staging namespace only
- **Code:** Main branch (or PR branch under test)
- **Data:** Production-shaped, refreshed nightly from prod (masked if needed)
- **Refresh:** Scheduled, predictable

### `prod`

- **Compute:** Production runners only; no human terminal access for routine ops
- **Storage:** Canonical schemas
- **Identity:** Production service accounts, principle-of-least-privilege; humans use break-glass procedures for emergencies
- **Code:** Tagged release from main
- **Data:** Real, full-fidelity
- **Refresh:** As the pipeline runs

### Optional: per-developer sandboxes

A common pattern in larger teams. Each developer gets a personal schema named after them (`dev_alice`, `dev_bob`). Trade-offs:

- ✓ Multiple devs iterate in parallel without stepping on each other
- ✗ Schemas drift from the canonical layout; old ones accumulate
- ✗ Cost: more compute, more storage

Mitigations: enforce a TTL (90 days of inactivity → wiped), template the schema setup so re-creation is one command.

### Optional: `qa` or `uat`

When non-engineers need to validate before prod. Usually shaped like staging with longer retention.

## Per-Layer Isolation

The patterns translate per stack component:

### Warehouse / database

- **Snowflake:** Separate accounts (best), or separate databases within one account (acceptable), or separate schemas (minimum). Always separate roles per environment.
- **Postgres:** Separate Postgres instances per environment, or at minimum separate databases. Avoid sharing instances across prod and dev.
- **Lake (Iceberg / Delta):** Separate buckets per environment. Catalog namespaces per environment. Cross-environment catalog access is a misconfiguration to fix immediately.

### dbt

- **Targets:** `dev`, `staging`, `prod` in `profiles.yml`. Each target points at a different schema (and ideally different warehouse / role).
- **Per-developer schemas:** dbt's `generate_schema_name` macro routed via `target.name == 'dev'` → `dev_<username>_<schema>`.
- **CI:** Runs against the staging target on every PR. Production runs only from the production runner with the prod target.

### Orchestrator (Dagster / Airflow)

- **Per-environment deployments:** Separate Dagster instances (one per environment) is cleanest. Single instance with environment-scoped resources is acceptable when budget is tight.
- **Code locations:** Same code, different resource configurations per environment.
- **Schedules and sensors:** Only enabled in prod. Dev / staging instances run on manual triggers.

### Ingestion (dlt / Sling / Airbyte)

- **Destinations differ per environment:** dlt's `destination` config picks the right warehouse per environment.
- **Source credentials may differ:** Dev points at a sample DB or a replica; prod at the real source.

### Compose stacks

- **Profiles per environment** are the wrong tool — compose profiles are for "sometimes-run", not "different-environment". Use separate compose files: `docker-compose.yml` + `docker-compose.dev.yml` vs. cloud deployment.
- Local compose is **always** dev. Don't try to deploy compose to prod — that's a different deployment model (Kubernetes, ECS, Nomad).

## Data Parity Strategies

Dev needs data that looks like prod without being prod. Pick the strategy that fits:

| Strategy | Method | Trade-off |
|---|---|---|
| **Synthetic** | Generated via Faker or similar | Safest; behavior may not match prod edge cases |
| **Sampled** | Random N rows from prod | Realistic; PII risk unless masked |
| **Masked** | Prod data with PII hashed / redacted | Realistic; masking has to be airtight |
| **Snapshot** | Periodic full copy with masking | Easiest to reason about; storage cost doubles |
| **None** | Empty dev, build up from synthetic inserts | Cheapest; least useful for testing complex queries |

Combine as needed: synthetic for new features (no real-data dependency), masked-sample for integration tests.

The masking step is the highest-risk part of any data-parity flow. Get it wrong and PII lands in dev / staging. Make masking automated, tested, and out of the developer's hands.

## Promotion Flow

How does code move dev → staging → prod?

1. **Dev work happens on a feature branch.** Developer uses their dev environment (local compose / personal schema).
2. **PR opens against main.** CI runs `dbt build` against staging target. Tests pass = merge candidate.
3. **Merge to main.** CI builds an artifact (Docker image, dbt-compiled manifest) tagged with the commit SHA.
4. **Staging deploy on merge.** The artifact deploys to staging automatically. Staging soaks for some agreed time (a few hours, overnight).
5. **Prod promotion.** Tag a release (`v2026.05.18`). Prod deployment picks up the tag automatically, or via a manual approval gate.
6. **Rollback.** Re-deploy the previous tag. If state changes are involved (schema migrations), have a documented rollback procedure per migration.

No developer's laptop touches prod in this flow. Prod credentials live only on the prod runner.

## Anti-patterns to Reject

- Prod and dev sharing a warehouse with only schema-based isolation
- The same service account having access to dev and prod
- Developers running `dbt run --target prod` locally
- "Just this once" data copies from dev to prod
- Schedules / sensors running in dev or staging (they should only fire in prod)
- A per-developer schema that has been idle for 6+ months but still exists
- Tests that pass in staging but break on prod-specific data — find prod-shape data for staging
- Hardcoded schema / bucket names in the project — every reference is config-driven

## What This Skill Does Not Decide

- Cloud networking (VPC peering, private endpoints) — coordinate with platform / infra team
- IAM / RBAC implementation details — depends on cloud provider
- Specific masking algorithms for PII — depends on data type and compliance requirements
- Backup / disaster recovery — separate concern

## References

- [`references/per-stack-isolation.md`](references/per-stack-isolation.md) — Concrete isolation patterns per tool (Snowflake, Postgres, Iceberg, Dagster, dbt, dlt, compose)
- [`references/promotion-pipelines.md`](references/promotion-pipelines.md) — Sample CI/CD pipeline shapes that enforce the dev → staging → prod flow
- [`references/data-parity-runbook.md`](references/data-parity-runbook.md) — Step-by-step for setting up sampled / masked refreshes from prod to staging
