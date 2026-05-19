# Decision Questions — Phase 1 Interview

Five core questions cover most cases. Each has follow-ups based on the answer. Do not pick services for the user; surface their decision.

## Q1: Where does the data live?

Pick one (or a hybrid):

- **Lake** — object storage (S3 / MinIO / GCS) + open table format (Iceberg / Delta / Hudi). Open, decouples storage from compute, lower cost at scale.
- **Cloud DWH** — Snowflake / BigQuery / Redshift / Databricks SQL. Managed, fast for SQL, license cost.
- **Postgres warehouse** — Postgres tuned as a warehouse. Cheap, simple, scales modestly.
- **Hybrid** — DWH for production, lake for raw / cheap storage.

Follow-ups:
- Lake → which table format? Which catalog (Nessie / Glue / Polaris / REST)?
- DWH → which account exists? region? credit budget?
- Hybrid → which is the source of truth for marts?

## Q2: What feeds it?

For each source category, ask if applicable:

- **Operational databases (Postgres / MySQL / SQL Server)** — CDC or batch? Frequency?
- **REST / SaaS APIs** — auth model? Rate limits? Pagination?
- **Files in object storage** — format (CSV/Parquet/JSONL)? Schema stability?
- **Streaming (Kafka / Kinesis)** — throughput? Exactly-once required?
- **Already in the warehouse** — no ingestion layer needed; transformation-only project.

Follow-ups:
- More than 5 sources at once → consider managed ingestion (Fivetran / Airbyte) over hand-rolled.
- One source, simple schema → `dlt` or `sling`.
- CDC required → check destination supports it (Snowflake streams, Iceberg merge).

## Q3: Local-first or cloud-first?

- **Local-first** — Docker compose stack on a laptop, no cloud account needed for dev. Best for prototyping, demos, isolated learning.
- **Cloud-first** — Real Snowflake account, real S3 buckets, devs share a sandbox. Best when production parity matters.
- **Mixed** — Local stack for fast iteration, cloud account for integration / shared work.

Follow-ups:
- Local → which services run? Compose stack from `infra-docker-compose`.
- Cloud → who owns the account? IAM / role model? Cost guardrails?
- Mixed → how is data parity maintained between local and cloud?

## Q4: What's the scale and team shape?

- **Hobby / solo learner** — 1 person, no SLA. Optimize for clarity over robustness.
- **Team of 2–5** — Shared dev environment, basic CI, no on-call.
- **Production with users** — SLA, on-call, change review.
- **Regulated / audited** — Lineage, access logs, data retention.

Follow-ups:
- Production → CI/CD layer is mandatory; bootstrap should leave hooks for it.
- Regulated → secrets-management is non-negotiable; data masking from day one.
- Hobby → skip observability stack in bootstrap; revisit when it actually matters.

## Q5: What's already locked in?

Honor existing decisions. Re-litigating wastes time and erodes trust.

- Existing cloud accounts (which warehouse, which region)?
- Existing team skills (the team knows Dagster but not Airflow → pick Dagster)?
- Mandatory tools from policy (compliance requires a specific catalog)?
- Existing repos / code to integrate with?

Follow-up: If a locked-in tool conflicts with the natural archetype fit, note the friction explicitly and document the workaround rather than ignoring the constraint.

## After the interview

Summarize the decisions in 4–6 lines. Confirm explicitly:

> "Locking in: Lake storage on MinIO + Iceberg, dlt for ingestion from Postgres CDC and 2 REST APIs, dbt on the lake via Trino, Dagster orchestrating, local-first compose stack, team-of-3 with basic CI. Proceeding?"

Wait for confirmation before Phase 2.
