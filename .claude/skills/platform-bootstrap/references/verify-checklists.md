# Verify Checklists — Phase 4 End-to-End

The bootstrap is **not done** until end-to-end works from a clean state. "Everything compiles" or "every service is healthy" is not enough. These checklists are per-archetype.

## Universal checks (apply to every archetype)

1. **Clean-state reproducibility**
   - `docker compose down -v` (or cloud equivalent: drop the dev schema/bucket).
   - Re-bootstrap from scratch (init scripts run, schemas re-created, orchestrator workspace loads empty).
   - Re-trigger one ingestion + one transformation run.
   - Confirm output matches the first run. **If this fails, init is not idempotent — fix before declaring done.**

2. **Secrets discipline**
   - `.env` is gitignored. `.env.example` is committed and complete.
   - Run `git status` and `git log -p .env*` — no real credential has ever been committed.

3. **README runnable instructions**
   - A teammate following the README from scratch can stand up the platform without asking.
   - Setup time is measured in minutes (local) or under an hour (cloud), not days.

## Per-archetype checks

Pick the relevant section based on the stack chosen in Phase 1. The bootstrap-time goal is a **runnable** platform, not a hardened one.

### Local lake (MinIO + Iceberg + dbt-on-Trino + Dagster)

- Object store is reachable from sibling containers via service DNS.
- Iceberg catalog has at least one namespace; `mc ls` from a sidecar shows the expected bucket layout (raw/staging/curated or equivalent).
- dbt profile points at Trino with a working `dbt debug`.
- Dagster asset graph shows: ingestion asset → Trino-backed staging model → curated model.
- A clean re-bootstrap produces identical lineage in Dagster.

### Snowflake DWH (Snowflake + dbt + Dagster)

- Snowflake account/role/warehouse env vars resolve in every component (dbt, Dagster, ingestion).
- `snow connection test` (or equivalent) passes from the orchestrator container.
- Dev schema separate from prod. RBAC matches the team's separation policy.
- Dagster runs a dbt model that materializes a real table in the dev schema; query the table directly from Snowsight to confirm.
- Cost guardrails active: warehouse auto-suspend ≤ 60s, statement timeout set, resource monitor on the dev warehouse.

### Postgres warehouse (Postgres + dbt + Dagster + optional dlt)

- Postgres compose service is `healthy` and persistent across `down`.
- `psql` from sibling container reaches it; expected DBs (dagster metadata, warehouse) exist.
- dbt profile uses a non-superuser role with explicit grants.
- One ingestion pipeline writes a real table; one staging model reads it.
- Vacuum / autovacuum config is sane for the data size you expect.

### Hybrid (cloud DWH + local lake for raw)

- Local lake holds raw; DWH holds curated.
- Promotion path (lake → DWH) is automated through orchestrator, not a manual `COPY INTO`.
- Cleanup story: how long does data live in raw before TTL? Documented.
- Dev parity: a dev can run the full pipeline against local lake + dev DWH schema.

### Transformation-only (no ingestion, no infra)

- dbt profile reaches the existing warehouse.
- One example mart model materializes and matches expected row count.
- Optional orchestrator runs the dbt project on a schedule.
- CI for dbt PRs is in place (dbt test on PR open).

## Sign-off

Once the universal checks pass and the archetype checks pass, the bootstrap is **done**. Add a `BOOTSTRAP.md` note in the repo recording:

- Archetype name
- Date and version of each major tool
- The verify steps (copy from this file)
- Known gaps deferred to later (CI/CD, observability, hardening)

The next layer of work (CI/CD, observability, etc.) starts from this verified baseline.
