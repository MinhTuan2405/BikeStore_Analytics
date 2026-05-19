---
name: dagster-orchestration-layout
description: MUST be invoked immediately after scaffolding a new Dagster project (e.g. via `create-dagster` / `dg scaffold project` from the `dagster-expert` plugin) to reshape the default layout into this project's convention; also use when adding a new ingestion source, wiring a new external system, or reviewing layout drift. Encodes: `assets/<source>/` per source, `resources/<system>_resource.py` per external system, `RESOURCES` dict keyed by deployment, asset-group-driven job selection (`AssetSelection.groups(...)`), and a concern-split `utils/`. This is the project's contract for organization — defers Dagster API specifics (decorators, partitions, sensor types) to the `dagster-expert` plugin.
---

# dagster-orchestration-layout

## Overview

A Dagster project's folder layout is its operating manual. Get it right and adding a new source is a copy-paste-tweak; get it wrong and every new pipeline becomes its own snowflake. This skill encodes a layout convention that scales to dozens of sources without restructuring.

The convention has five rules that hold regardless of which sources are wired in:

1. **One folder per source** under `assets/<source>/` — isolated.
2. **One Resource module per external system** under `resources/<source>_resource.py` — reusable.
3. **Resources bundled per deployment** in a `RESOURCES` dict keyed by deployment name (`local`, `cloud`, etc.).
4. **Asset groups drive job selection** — `group_name="<source>_<cadence>_ingestion"`, jobs use `AssetSelection.groups(...)`.
5. **Utilities live in `utils/`** split by concern, never inlined into asset code.

This skill does not teach Dagster the framework — that's the `dagster-expert` plugin's job. It teaches the project's **organization** of Dagster code.

## When to Use

- Scaffolding a new Dagster orchestration project
- Adding a new ingestion source / pipeline to an existing project
- Wiring a new external system (database, API, FTP, object store) as a reusable Resource
- Reviewing a Dagster project for layout drift (assets bypassing Resources, utils inlined, ad-hoc per-deployment config)
- Onboarding someone who needs the conventions in one place

Do **not** use for:
- Dagster framework concepts (`@asset` decorators, partition types, materialization semantics) — use `dagster-expert`
- Choosing whether to use Dagster vs. Airflow — use `stack-archetypes`
- Operational debugging — use `data-pipeline-debugging` or `dagster-graphql`

## Mental Model

A Dagster orchestration project has four kinds of code, each with its own folder:

| Folder | Owns | Boundary |
|---|---|---|
| `assets/` | What gets materialized (data) | One subfolder per source; assets only — no API clients, no shared helpers |
| `resources/` | How to reach external systems | One module per external system; defines a class + a `@resource` factory |
| `jobs/` / `schedule/` / `sensors/` | When work runs | Job groups assets; schedule fires the job on cron; sensor fires on events |
| `utils/` | Reusable helpers that aren't Dagster-specific | Split by concern (date utils, S3 utils, file save patterns) |

The `__init__.py` at project root assembles `Definitions(assets, jobs, schedules, sensors, resources)`. It is the only place where the wiring is centralized; everywhere else is local to its concern.

## The Five Rules

### Rule 1 — One folder per source

```
assets/
├── __init__.py                 # imports each source package, calls load_assets_from_package_module
├── paypal/
│   ├── __init__.py
│   └── paypal_data.py          # @asset functions
├── klarna/
│   ├── __init__.py
│   └── klarna_data.py
└── shopify/
    ├── __init__.py
    └── shopify_data.py
```

- Each `<source>/` package is self-contained.
- `__init__.py` of the source package is empty (or re-exports), and Dagster discovers assets via `load_assets_from_package_module`.
- The asset file's name reflects the dataset (`paypal_data.py`, `oracle_inventory.py`), not generic names like `assets.py`.

Why: adding a source is an additive operation. No existing source's code changes when a new one comes in.

### Rule 2 — One Resource module per external system

```python
# resources/paypal_resource.py
class PaypalAPIClient:
    def __init__(self, base_url, start_date, end_date):
        self.base_url = base_url
        self.token = os.getenv("PAYPAL_ENCODE")
        ...
    def get_transactions(self): ...
    def get_subscriptions(self): ...
```

```python
# assets/paypal/paypal_data.py
from ...resources.paypal_resource import PaypalAPIClient

@asset(group_name="paypal_daily_ingestion", ...)
def paypal_data(context):
    client = PaypalAPIClient(base_url="...", start_date=..., end_date=...)
    return client.get_transactions()
```

- The client class encapsulates auth, retries, pagination, rate limits for that one external system.
- Assets call **methods** on the client. They never re-implement HTTP / auth logic inline.
- Different endpoints of the same API → **methods on the same client**, not separate clients. (One Resource per **system**, not per **endpoint**.)

Why: when the API changes, you change one file. When you write a second pipeline against the same API, you reuse the client.

### Rule 3 — Warehouse / managed-system Resources use the `@resource` factory

For systems Dagster needs to **inject** (the warehouse, an S3 client, a secrets manager), use the `@resource` decorator so they participate in deployment-scoped resource bundles:

```python
# resources/snowpark_resource.py
from dagster import resource
from snowflake.snowpark.session import Session

class SnowparkResource:
    def __init__(self, snowpark_conf):
        self._session = Session.builder.configs(snowpark_conf).create()

    @property
    def snowpark_session(self):
        return self._session

@resource(config_schema={"snowpark_conf": dict})
def snowpark_resource(init_context):
    return SnowparkResource(init_context.resource_config["snowpark_conf"])
```

```python
# resources/__init__.py
from .snowpark_resource import snowpark_resource

DEV_SNOWFLAKE_CONF = {"snowpark_conf": {
    "account": os.getenv("SNOWFLAKE_ACCOUNT"),
    "user": os.getenv("DEV_SNOWFLAKE_USER"),
    ...
}}

PROD_SNOWFLAKE_CONF = {"snowpark_conf": { ...prod env vars... }}

RESOURCES = {
    "local": {
        "connect_snowflake": snowpark_resource.configured(DEV_SNOWFLAKE_CONF),
        "s3_client": S3DataPipeline(),
    },
    "cloud": {
        "connect_snowflake": snowpark_resource.configured(PROD_SNOWFLAKE_CONF),
        "s3_client": S3DataPipeline(),
    },
}
```

```python
# orchestration/__init__.py
deployment_name = os.getenv("DAGSTER_DEPLOYMENT", "local")
defs = Definitions(
    assets=all_assets,
    jobs=all_jobs,
    schedules=all_schedules,
    sensors=all_sensors,
    resources=RESOURCES[deployment_name],
)
```

- The `RESOURCES` dict is the single place where deployment differences live.
- Adding a new deployment (`staging`, `qa`) means adding a new key, not rewiring assets.
- API-client Resources (Rule 2) don't need the `@resource` factory unless you want Dagster to inject them; client-as-class-import is fine for per-asset instantiation.

Why: deployments are configuration, not code. Same code runs everywhere; the dict swap covers the difference.

### Rule 4 — Asset groups drive job selection

```python
# assets/paypal/paypal_data.py
@asset(group_name="paypal_daily_ingestion", ...)
def paypal_data(context): ...
```

```python
# jobs/__init__.py
paypal_daily_job = define_asset_job(
    name="paypal_daily_job",
    tags={"dagster/max_runtime": 180},
    selection=AssetSelection.groups("paypal_daily_ingestion"),
)
```

```python
# schedule/__init__.py
paypal_daily_schedule = build_schedule_from_partitioned_job(
    job=paypal_daily_job,
    hour_of_day=5,
    minute_of_hour=0,
)
```

- `group_name` is the contract between asset and job.
- Naming pattern: `<source>_<cadence>_ingestion` (`paypal_daily_ingestion`, `zendesk_monthly_ingestion`). Cadence makes the schedule obvious.
- Job names mirror the group: `paypal_daily_job`. Schedule name mirrors the job: `paypal_daily_schedule`.
- Selection by group keeps jobs declarative; you don't list assets explicitly in the job.

For complex schedules (multi-partition, custom backfill logic), use `@schedule` directly:

```python
@schedule(cron_schedule="0 5 * * *", job=impact_radius_click_daily_job)
def impact_radius_click_daily_schedule():
    partition_date = ...
    for brand in BRANDS:
        yield RunRequest(
            run_key=brand,
            partition_key=MultiPartitionKey({"date": partition_date, "brand": brand}),
        )
```

Sensors live in `sensors/__init__.py` and react to events across the platform:

- `@run_status_sensor` — react to other jobs' success / failure (downstream triggers, alerts)
- `@sensor` — poll-based (file landed, queue depth, external completion)

### Rule 5 — Utils split by concern

```
utils/
├── __init__.py
├── s3_utils.py          # date conversion, S3 file ops
└── utils.py             # save_data, generic file helpers
```

- Pure functions only. No Dagster decorators, no environment-dependent code.
- Split files by **concern**, not by source. `s3_utils.py` holds everything S3-related across all sources.
- Used by assets, schedules, sensors — anywhere the helper is needed.

Anti-pattern: a `utils.py` that grows to 2000 lines. Split before it gets there. New concern → new file.

## Decision Flow — Adding a New Source

When the user says "add a new source X to orchestration":

1. **Does X share an external system with an existing source?** If yes, reuse the existing Resource (add a method if needed). If no, create `resources/<x>_resource.py`.
2. **Create the asset package:** `assets/<x>/__init__.py` (empty), `assets/<x>/<x>_data.py` with `@asset` functions.
3. **Pick the group name:** `<x>_<cadence>_ingestion`.
4. **Register the package** in `assets/__init__.py`: import + `load_assets_from_package_module`.
5. **Add the asset list** to `all_assets` in root `__init__.py`.
6. **Define the job** in `jobs/__init__.py`: `define_asset_job(..., selection=AssetSelection.groups(...))`.
7. **Add to `all_jobs`**.
8. **Schedule the job** in `schedule/__init__.py` if cron-driven; or define a sensor if event-driven.
9. **Add to `all_schedules` / `all_sensors`**.
10. **Verify:** `dg dev` or equivalent loads the project; the new asset appears in the asset graph; a manual materialization succeeds.

Each step is small. If a step requires touching unrelated files, the convention has been violated somewhere.

## Decision Flow — Adding a New External System

When the user says "wire up a new system (e.g. a new database, a new API)":

1. **Is this system Dagster-injected (warehouse, infra)** or **per-asset-instantiated (API client)?**
   - Injected → use Rule 3 pattern (`@resource` factory, configured per deployment, registered in `RESOURCES`).
   - Per-asset → use Rule 2 pattern (client class, imported by assets).
2. **Create `resources/<system>_resource.py`** with the client class.
3. **Cover auth, retries, pagination, rate-limit logic inside the client** — never in assets.
4. **For injected resources**, add to each deployment's bundle in `RESOURCES`.
5. **Document the env vars** the resource reads in the project's `.env.example`.

## Anti-patterns to Reject

- API auth / pagination / retry logic inside `@asset` functions (belongs in a Resource)
- Resources scattered across asset folders (`assets/paypal/paypal_client.py`) — they belong in `resources/`
- One Resource per endpoint (Paypal transactions vs. Paypal subscriptions in separate modules) — collapse to one client with multiple methods
- Per-deployment branching inside asset code (`if deployment == 'prod': ...`) — that's what `RESOURCES` bundles solve
- Hardcoded warehouse / S3 / API credentials in resource modules — read from env, configured at deployment-bundle level
- A `utils.py` that imports Dagster — utils are framework-free
- Schedule cron logic duplicated across schedules — extract a helper in `utils/`
- Jobs that list assets by key (`AssetSelection.keys(...)`) when a group selection would do — use groups for stable contracts

## What This Skill Does Not Decide

- Asset partition strategy (daily vs. multi-partition vs. dynamic) — `dagster-expert` plugin
- Materialization (table / view / incremental) — depends on the downstream warehouse
- Specific API client patterns (async vs. sync, requests vs. httpx) — language / library choice
- Production deployment shape (Docker, Kubernetes, ECS) — `infra-docker-compose` + `environment-strategy`
- Credentials storage — `secrets-management`

## References

- [`references/per-source-asset-pattern.md`](references/per-source-asset-pattern.md) — Concrete `@asset` patterns with group names, partitions, IO managers; common variations per source type (API, FTP, DB, file)
- [`references/resource-patterns.md`](references/resource-patterns.md) — Side-by-side: API-client Resource (Rule 2) vs. `@resource`-factory Resource (Rule 3), when to pick which
- [`references/job-schedule-sensor-mapping.md`](references/job-schedule-sensor-mapping.md) — How groups, jobs, schedules, sensors compose for common cadence patterns (daily, monthly, backfill, multi-partition, run-status reactive)
- [`references/utils-organization.md`](references/utils-organization.md) — Conventions for splitting `utils/` by concern, what belongs there vs. in a Resource
