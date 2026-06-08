# BikeStore Analyst Data Platform (BSDP)

A local analytics engineering platform that ingests BikeStore transactional data from Supabase PostgreSQL, stores it in a MinIO lakehouse, and transforms it into a Kimball-style star schema using dbt + DuckDB — all orchestrated by Dagster and running entirely in Docker.

## Authors

| No. | Name | Student ID | Faculty | Email |
|-----|------|------------|---------|-------|
| 1 | Nguyễn Hà Minh Tuấn | 23521718 | CNTT | 23521718@gm.uit.edu.vn |
| 2 | Mô Văn Tùng | 23521741 | CNTT | 23521741@gm.uit.edu.vn |

---

## What This Project Does

The platform covers the full data engineering lifecycle for a fictional multi-store bicycle retailer:

1. **Ingest** — Dagster assets perform full-load extractions from a Supabase PostgreSQL source (9 tables across `sales` and `production` schemas) and write Hive-partitioned Parquet files to MinIO under `s3://lakehouse/raw/`.

2. **Transform** — dbt (backed by DuckDB + httpfs) reads those raw Parquet files and produces two transformation layers:
   - **Staging** (`s3://lakehouse/staging/`) — 9 `stg_supabase__*` models that clean, cast, and normalise raw records. Each model filters to the latest ingestion partition via the `latest_full_load` macro to avoid duplicates from the full-load strategy.
   - **Conformed warehouse** (`s3://lakehouse/common_bs/`) — 4 conformed dimensions, a date spine, and 2 atomic fact tables following Kimball/EDM conventions.

3. **Test** — 120 dbt schema tests (unique, not_null, accepted_values, relationships) run after every build to enforce data quality at all layers.

4. **Orchestrate** — Dagster materialises every dbt model as a software-defined asset, groups them under `BikeStore_Analytics`, and exposes lineage in the Dagster UI.

### Star Schema (common_bs layer)

```
                    dim_date
                       │
dim_customer ──── fct_sales ──── dim_product
                       │
                    dim_store
                       │
                    dim_staff
                    (manager self-join)

dim_store ──── fct_inventory ──── dim_product
                    │
                 dim_date
```

| Model | Grain | Key facts |
|-------|-------|-----------|
| `fct_sales` | order line item | line_total, quantity, discount |
| `fct_inventory` | store × product snapshot | quantity, inventory_value |
| `dim_customer` | customer | Type 1, missing-member row |
| `dim_product` | product | enriched with brand + category |
| `dim_store` | store | Type 1, missing-member row |
| `dim_staff` | staff member | manager hierarchy flattened via self-join |
| `dim_date` | calendar day | spine 2015-01-01 → 2034-12-31 |

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Docker Compose stack                │
│                                                      │
│  ┌──────────────┐   gRPC    ┌──────────────────────┐│
│  │ dagster-      │◄────────►│ bsdp_pipeline        ││
│  │ webserver     │          │ (Dagster code server) ││
│  │ :3000         │          │ :4000                 ││
│  └──────────────┘           │  - Dagster assets     ││
│  ┌──────────────┐           │  - dbt build          ││
│  │ dagster-      │◄────────►│  - DuckDB + httpfs    ││
│  │ daemon        │          └──────────────────────┘│
│  └──────────────┘                    │               │
│                                      │ S3 API        │
│  ┌──────────────┐           ┌────────▼─────────────┐│
│  │ backend_      │           │ MinIO                ││
│  │ storage       │           │ :9000 (API)          ││
│  │ (PostgreSQL)  │           │ :9001 (console)      ││
│  │ :5432         │           │                      ││
│  └──────────────┘           │  raw/      (Bronze)  ││
│                              │  staging/  (Silver)  ││
│  ┌──────────────┐           │  common_bs/(Gold)    ││
│  │ CloudBeaver  │           └──────────────────────┘│
│  │ :8978        │                                    │
│  └──────────────┘                                    │
└─────────────────────────────────────────────────────┘

Source: Supabase PostgreSQL (external)
  └── sales:      customers, orders, order_items, staffs, stores
  └── production: brands, categories, products, stocks
```

### Repository layout

```
BikeStoreAnalyst/
├── README.md
├── docker-compose.yml           # Full local stack
├── .env.example                 # Shared environment variables
├── BSAnalyse/                   # BI analysis and dashboard assets
│   ├── analyse.md
│   ├── requirements.md
│   ├── PowerBI/                 # Power BI report and exported PDF
│   ├── model/                   # BI model artifacts
│   └── wireframe/               # Dashboard wireframes
├── dbt_bsdp/                    # dbt project (DuckDB adapter)
│   ├── dbt_project.yml
│   ├── profiles.yml             # DuckDB + MinIO S3 connection
│   ├── packages.yml             # dbt_utils
│   ├── pyproject.toml
│   ├── macros/
│   │   ├── latest_full_load.sql   # Filters to max(ingestion_date)
│   │   └── get_keyed_nulls.sql    # Null FK → missing-member SK
│   └── models/
│       ├── source/             # Bronze — external MinIO declarations
│       │   └── sources.yml
│       ├── staging/            # Silver — 9 stg_supabase__* models
│       │   ├── schema.yml
│       │   └── stg_supabase__*.sql
│       └── common_bs/          # Gold — 4 dims + dim_date + 2 facts
│           ├── schema.yml
│           ├── dim_*.sql
│           └── fct_*.sql
└── orchestration/              # Dagster project
    ├── Dockerfile
    ├── docker-entrypoint.sh
    ├── pyproject.toml          # dagster, dagster-dbt, dbt-duckdb
    ├── workspace.yaml
    ├── dagster.yaml
    ├── orchestration_tests/
    │   └── test_assets.py
    └── orchestration/
        ├── definitions.py
        ├── assets/
        │   ├── dbt/
        │   │   └── dbt_bsdp_assets.py
        │   └── supabase/
        │       ├── supabase_sales.py
        │       └── supabase_production.py
        ├── resources/
        │   ├── dbt_resource.py
        │   └── supabase_resource.py
        └── utils/
            ├── s3_utils.py
            └── utils.py
```

Generated/runtime folders such as `data/`, `logs/`, `.venv/`, `target/`, `dbt_packages/`, `.pytest_cache/`, and `__pycache__/` are intentionally omitted.

### Technology stack

| Layer | Technology |
|-------|-----------|
| Orchestration | Dagster 1.13 |
| Transformation | dbt-core 1.11 + dbt-duckdb |
| Query engine | DuckDB (in-process, httpfs extension) |
| Lakehouse storage | MinIO (S3-compatible) |
| Serialisation | Apache Parquet (via dbt external materialization) |
| Dagster backend | PostgreSQL 16 |
| SQL client | CloudBeaver |
| Package manager | uv |
| Runtime | Docker Compose |

---

## Installation

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or Docker Engine + Compose plugin)
- A Supabase PostgreSQL connection string for the source database
- Git

### 1. Clone the repository

```bash
git clone <repo-url>
cd BikeStoreAnalyst
```

### 2. Configure environment variables

```bash
cp .env.example .env
```

Edit `.env` and fill in your Supabase connection details:

```bash
DATASOURCE_HOST=<your-supabase-host>
DATASOURCE_USER=<your-supabase-user>
DATASOURCE_PASSWORD=<your-supabase-password>
```

All other defaults (`minioadmin`, `dagster`, etc.) work as-is for local development.

### 3. Start the stack

```bash
docker compose up --build
```

This builds the orchestration image, starts all services, and creates the MinIO `lakehouse` bucket automatically via the `minio-init` service.

### 4. Open the Dagster UI

Navigate to **http://localhost:3000**. You should see the `BikeStore_Analytics` asset group with all ingestion and dbt assets.

### 5. Materialise the pipeline

In the Dagster UI, select all assets and click **Materialise all**. The run will:
1. Extract all 9 source tables from Supabase → `s3://lakehouse/raw/`
2. Run `dbt build` to produce staging and warehouse layers → `s3://lakehouse/staging/` and `s3://lakehouse/common_bs/`
3. Execute all 120 dbt schema tests

### Useful URLs

| Service | URL |
|---------|-----|
| Dagster UI | http://localhost:3000 |
| MinIO console | http://localhost:9001 |
| MinIO S3 API | http://localhost:9000 |
| CloudBeaver | http://localhost:8978 |
| Dagster PostgreSQL | `localhost:5432` |

### Stopping and resetting

```bash
# Stop containers
docker compose down

# Wipe all runtime data (Dagster storage, MinIO objects, PostgreSQL)
docker compose down
rm -rf ./data/volume/
```

---

## Contributing

### Development setup

The `orchestration` package uses `uv` for dependency management.

```bash
cd orchestration
uv sync --group dev
```

For the dbt project:

```bash
cd dbt_bsdp
uv sync
```

### Running dbt locally

```bash
cd dbt_bsdp
.venv/Scripts/dbt parse          # validate manifest
.venv/Scripts/dbt build --select staging    # run staging layer
.venv/Scripts/dbt build --select common_bs  # run gold layer
```

Set `MINIO_HOST=localhost` and `MINIO_PORT=9000` in your shell (or `.env`) when running dbt against a locally exposed MinIO instance.

### Adding a new dbt model

1. Create the SQL file in the appropriate layer folder (`staging/` or `common_bs/`).
2. Add the model config block with `materialized='external'`, `location`, and `format='parquet'`.
3. Document all columns in the layer's `schema.yml`.
4. Run `dbt parse` to validate, then `dbt build --select <model_name>+` to test.

### Adding a new Dagster asset

Place the asset definition inside `orchestration/src/orchestration/defs/`. The `load_from_defs_folder` call in `definitions.py` auto-discovers everything in that directory.

### Code style

- dbt SQL: CTEs over subqueries, `{{ ref() }}` and `{{ source() }}` exclusively — no hardcoded table names.
- Dagster: typed resources via `ConfigurableResource`; assets consume resources via function arguments.
- Commits: concise imperative subject line, reference the affected layer in the body.
