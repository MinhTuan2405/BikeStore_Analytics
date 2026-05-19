# Data Team Coding Conventions
<!-- TEMPORARY — Will be updated by the team -->

## Orchestration Directory Layout

All Dagster source lives under `orchestration/orchestration/`. The sub-folders are fixed:

```
orchestration/orchestration/
├── assets/
│   ├── __init__.py              # loads all source modules via load_assets_from_package_module
│   └── {source_name}/           # one sub-package per datasource (e.g. supabase/, mysql_crm/)
│       ├── __init__.py          # empty or re-exports
│       └── {source_name}_{schema_name}.py  # asset file (see naming rules below)
├── jobs/
│   └── __init__.py              # defines all jobs; exports all_jobs list
├── schedule/
│   └── __init__.py              # defines all schedules; exports all_schedules list
├── sensors/
│   └── __init__.py              # defines all sensors; exports all_sensors list
├── resources/
│   └── {source_name}_resource.py  # one resource per datasource
├── utils/
└── definitions.py               # imports all_assets, all_jobs, all_schedules, all_sensors, RESOURCES
```

Place **assets** in `assets/{source_name}/`, **jobs** in `jobs/__init__.py`, **schedules** in
`schedule/__init__.py`, **sensors** in `sensors/__init__.py`, **resources** in `resources/`.

## Asset File Name

The file name reflects the scope of the asset, which differs by asset type:

| Asset type | File name pattern | Example |
|---|---|---|
| Static partition (database source — one file covers all tables in a schema via partitions) | `{source_name}_{schema_name}.py` | `supabase_sales.py` |
| Normal asset (single table, REST endpoint, or file) | `{source_name}_{schema_name}_{object_name}.py` | `stripe_api_events.py` |

Rationale: a static partition asset partitions over `table_name`, so it represents the **schema**, not
a single table. Naming it after one table (e.g. `supabase_sales_orders.py`) is misleading and implies
only orders are ingested. The datasource prefix (`supabase_`) is mandatory so the file is immediately
recognisable as an ingestion asset in any IDE.

## Asset Key Structure

- 4-level: `["raw", "{source_name}", "{schema_name}", "{table_name}"]`
- `source_name`: datasource identifier in snake_case (e.g., `supabase`, `mysql_crm`)

## Asset `name` Parameter

The `name` field on `@dg.asset`, combined with `key_prefix`, forms the full asset key:

| Asset type | `name` value |
|---|---|
| Static partition | `{schema_name}` (the schema, e.g. `"sales"`) — the partition key resolves the table |
| Normal asset | `{schema_name}_{table_name}` (e.g. `"public_orders"`) |

Do **not** use `{schema_name}_{table_name}` as `name` for a static partition asset — combined with the
4-level `key_prefix` it would place `schema_name` in the path twice.

## Group Name

- Format: `{source_name}_ingestion`
- Example: `supabase_ingestion`, `mysql_crm_ingestion`

## Python Conventions

- `snake_case` for all variables, functions, modules
- `UPPER_SNAKE_CASE` for module-level constants (e.g., `MINIO_BUCKET = "raw"`)
- Type annotations required on all function signatures
- No hardcoded credentials — use `os.environ` or Dagster resources
- Import order: stdlib → third-party (dagster, boto3, ...) → local project

## MinIO Paths

```
Data:     raw/{source}/{schema}/{table}/ingestion_date={YYYY-MM-DD}/run_id={run_id}/data.parquet
Metadata: raw/{source}/{schema}/{table}/ingestion_date={YYYY-MM-DD}/run_id={run_id}/metadata.json
Log:      ingestion/logs/{source}/{schema}/{table}/{run_id}.json
State:    ingestion/state/{source}/{schema}/{table}/state.json
```

- `{source}` = `source_name` (e.g., `supabase`)
- `{schema}` = schema or namespace (e.g., `public`, `sales`)
- `{table}` = table or endpoint name
- `{run_id}` = `context.run_id` from Dagster

## Logging Style

Use `context.log` — not `print()`, not the root `logging` module:

```python
context.log.info("message")
context.log.warning("message")
context.log.error("message")
```

### Mandatory Log Calls (required in every asset)

```python
context.log.info(f"Starting ingestion: {table_name}, strategy={strategy}")
context.log.info(f"Fetched {row_count} rows from source")
context.log.info(f"Written to MinIO: s3://{bucket_name}/{s3_key}")
context.log.info(f"Ingestion complete. Duration: {time.time() - start_time:.1f}s")
```

## Resource Structure

Place at: `orchestration/orchestration/resources/{source_name}_resource.py`

```python
from dagster import ConfigurableResource, InputContext, OutputContext

class {SourceName}Resource(ConfigurableResource):
    # connection config from env vars only

    def load_input(self, context: InputContext) -> ...:
        ...

    def handle_output(self, context: OutputContext, obj: ...) -> None:
        ...
```

Register the new resource in `orchestration/orchestration/resources/__init__.py` under every deployment key in `RESOURCES`.

## Asset Registration

When adding a new datasource sub-package, update `orchestration/orchestration/assets/__init__.py`:

```python
from orchestration.assets import {source_name}

{source_name}_assets = load_assets_from_package_module({source_name})
all_assets = [..., *{source_name}_assets]
```

The new folder `orchestration/orchestration/assets/{source_name}/` must contain an `__init__.py` (can be empty).

## Job and Schedule Registration

Jobs are defined in `orchestration/orchestration/jobs/__init__.py` and added to `all_jobs`.
Schedules are defined in `orchestration/orchestration/schedule/__init__.py` and added to `all_schedules`.
Sensors are defined in `orchestration/orchestration/sensors/__init__.py` and added to `all_sensors`.

```python
# jobs/__init__.py
{source_name}_ingestion_job = dg.define_asset_job(
    name="{source_name}_ingestion_job",
    selection=dg.AssetSelection.groups("{source_name}_ingestion"),
)
all_jobs = [..., {source_name}_ingestion_job]

# schedule/__init__.py
{source_name}_ingestion_schedule = dg.ScheduleDefinition(
    job={source_name}_ingestion_job,
    cron_schedule="...",
    default_status=dg.DefaultScheduleStatus.RUNNING,
    description="...",
)
all_schedules = [..., {source_name}_ingestion_schedule]
```

## Write Pattern (MinIO Parquet)

```python
s3_key = (
    f"raw/{source_name}/{schema_name}/{table_name}/"
    f"ingestion_date={date.today().isoformat()}/"
    f"run_id={context.run_id}/data.parquet"
)
parquet_buffer = io.BytesIO()
df.to_parquet(parquet_buffer, index=False, engine="pyarrow")
s3_client.put_object(Bucket=bucket_name, Key=s3_key, Body=parquet_buffer.getvalue())
```

## Package Installation

When adding new dependencies to `orchestration/pyproject.toml`, the Docker container must be **rebuilt**
(not just restarted) so the new packages are installed into the container image:

```bash
docker compose up --build
```

A plain `docker compose restart` will not install new packages.
