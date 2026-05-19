---
name: platform-bootstrap
description: Orchestrator for bootstrapping a data platform from zero. Use when the user wants to "scaffold a new platform", "set up a data project from scratch", "start a new data pipeline project", or describes a green-field project that needs storage + transformation + orchestration. Drives a decision flow that picks an archetype, then routes to per-layer skills and plugins (`infra-docker-compose`, `dagster-expert`, `dbt`, `dlt`, `snowflake-cortex-code`) in order. Does not implement any layer itself — coordinates the layers other skills provide. Distinct from `infra-docker-compose` (shapes the runtime), `stack-archetypes` (catalogue of templates), and the per-tool plugins (Dagster, dbt, dlt).
---

# platform-bootstrap

## Overview

A data platform is several layers stacked together: storage, ingestion, transformation, orchestration, observability. Each layer has good tooling — but the **order**, the **glue**, and the **decisions** between them are project-specific. This skill drives that flow.

Reach for it when you have nothing yet and want a runnable platform. It does not pick services for the user; it walks them through picking, then sequences the work so the platform comes up in a verifiable state.

## When to Use

- User says "I need to set up a data platform" / "scaffold a data project" / "start from scratch"
- Empty repo, no `docker-compose.yml`, no orchestrator project, no dbt project
- Existing project but adding a fundamentally new layer (e.g. introducing object storage to a DWH-only stack)
- Replanning after a stack archetype change

Do **not** use for:
- Adding a single asset / model / pipeline to an existing platform — those go directly to the per-tool skills
- Operational issues (a failing run, a broken model) — use `data-pipeline-debugging` or per-tool debug skills
- Pure infra changes inside an existing compose file — use `infra-docker-compose`

## Mental Model

Bootstrapping has four ordered phases. Skipping forward almost always wastes work later:

1. **Decide** — Surface the project's shape from the user, settle on an archetype.
2. **Plan** — Sketch the layer map and identify which skills/plugins own which layer.
3. **Scaffold** — Build the project layer by layer, bottom-up. Storage before orchestration, orchestration before transformation, transformation before ingestion.
4. **Verify** — End-to-end smoke test. A bootstrap that hasn't been verified end-to-end isn't done.

The order matters: each layer depends on the one below being addressable. If you scaffold dbt before the warehouse is reachable, dbt setup spins on connection errors. If you scaffold Dagster before dbt artifacts exist, the dbt asset factory has nothing to load.

## Phase 1 — Decide

Run a short interview. These five questions cover 90% of the decision space; settle each before moving on:

1. **What is the data target?** Lake (object store + open table format), DWH (Snowflake / BigQuery / Redshift), Postgres warehouse, or hybrid? Drives storage layer + later layer choices.
2. **What are the sources?** Databases (CDC), APIs, files in object storage, streaming? Drives ingestion approach (`dlt` / `sling` / `kafka`).
3. **Local-first or cloud-first?** Local Docker stack vs. managed cloud services. Drives infra layer (compose vs. cloud IaC).
4. **Scale and team shape?** Hobby / team-of-2 / production-with-SLA? Drives observability + CI/CD ambition.
5. **What's already decided?** Existing accounts, existing skills on the team, mandatory tools? Honor these — don't re-litigate.

Confirm answers explicitly before proceeding. Do **not** pick services unilaterally.

Once answered, consult [`stack-archetypes`](../stack-archetypes/) to match the answers to a known archetype, or compose a new one. Name the archetype out loud so subsequent phases reference the same shape.

## Phase 2 — Plan

Write the **layer map** in the project README or a planning doc. One row per layer, one column per concern:

| Layer | Tool | Owned by skill / plugin | Notes |
|---|---|---|---|
| Infra runtime | (docker compose / cloud) | `infra-docker-compose` | Networks, volumes, profiles |
| Storage | (the user's choice) | per-service init | Bucket layout, schema names |
| Orchestration | (Dagster / Airflow) | `dagster-expert` or `astronomer-data-agents` | Project structure, code locations |
| Transformation | (dbt / SQLMesh) | `dbt@dbt-agent-marketplace` | Layer convention (staging/intermediate/marts) |
| Ingestion | (dlt / Sling / Airbyte) | dlthub plugins | One pipeline per source |
| Quality | (dbt tests / asset checks / GE) | per-tool | Where each test type lives |
| Secrets | (.env / vault / cloud KMS) | `secrets-management` | Single source of truth |

The plan is the contract. Subsequent phases execute it; deviations need to be flagged, not silently absorbed.

## Phase 3 — Scaffold

Bottom-up, in this order. Each step ends with a check that gates the next:

1. **Infra runtime.** Hand to `infra-docker-compose`. Result: `docker compose up -d` brings every base service to `healthy`. Stop here until that's true.
2. **Storage init.** Create databases / schemas / buckets the rest of the platform expects. Idempotent scripts only — see `infra-docker-compose` references on init patterns. Result: connection from a sibling container succeeds.
3. **Orchestrator.** Scaffold the orchestrator project (Dagster: `dg create-dagster`, Airflow: Astronomer skills). **For Dagster: immediately after the scaffold succeeds, load the `dagster-orchestration-layout` skill and reshape the default layout into this project's convention before moving on** (assets/<source>/, resources/<system>_resource.py, RESOURCES dict per deployment, asset-group-driven jobs, utils/ split by concern). Wire its metadata store to the storage layer. Result: orchestrator UI loads and shows a workspace using the conventional layout.
4. **Transformation.** Scaffold the transformation project (dbt: `dbt init`). Wire its profile to the warehouse. Run a no-op `dbt debug`. Result: connection succeeds, project compiles.
5. **Ingestion.** Add one (and only one) representative pipeline first. Don't try to scaffold five sources before any has loaded. Result: one source loads end-to-end into the storage layer.
6. **Glue.** Register the dbt project as a Dagster code location (or equivalent). Register ingestion runs as upstream assets. Result: Dagster asset graph shows ingestion → transformation lineage.
7. **Quality.** Add one example test per type the project will use (a dbt test, an asset check, a freshness check). Don't aim for full coverage on bootstrap. Result: tests run and pass.

Skip any step that the user's archetype doesn't need (e.g. no ingestion if data is already in the warehouse).

## Phase 4 — Verify

Do **not** mark bootstrap complete on "everything compiles". Run a full end-to-end:

1. `docker compose down -v && docker compose up -d` from a clean state — proves init is idempotent.
2. Trigger the representative ingestion pipeline from the orchestrator UI.
3. Run the dbt project's first model that consumes the ingested data.
4. Verify the model's output in the warehouse / lake.
5. Tear down again and confirm clean exit.

Document the verify steps in the project README so the next person (or you, in two months) can re-validate.

## What This Skill Routes To

This is a coordinator skill. Each phase delegates to:

- **`infra-docker-compose`** — runtime topology, volumes, healthchecks
- **`stack-archetypes`** — catalogue of known stack templates
- **`dagster-expert`** plugin — Dagster project structure, asset patterns
- **`dbt@dbt-agent-marketplace`** plugin — dbt project, tests, semantic layer
- **`dlt` / `sling` plugins** — ingestion pipelines
- **`snowflake-cortex-code`** plugin — Snowflake-specific operations
- **`secrets-management`** skill (planned) — credential discipline across the stack
- **`layer-conventions`** skill (planned) — schema / table / model naming taxonomy

When you reach a phase, **load the relevant skill / plugin's instructions** rather than acting from memory. Each layer's owner knows its own corner better than this skill does.

## What This Skill Does Not Decide

- Specific tool choices (warehouse engine, table format, orchestrator) — comes from the user via Phase 1
- Code-level patterns inside any layer — owned by per-tool skills
- Production deployment (this skill bootstraps **a runnable platform**, not a hardened one)
- CI/CD pipelines, observability stack, disaster recovery — those layer in after bootstrap completes

## References

- [`references/decision-questions.md`](references/decision-questions.md) — Full question bank for Phase 1, with follow-ups per answer
- [`references/layer-dependencies.md`](references/layer-dependencies.md) — Why the scaffold order is what it is; what breaks when reordered
- [`references/verify-checklists.md`](references/verify-checklists.md) — Per-archetype smoke-test checklists for Phase 4
