# Architecture - BSDP (Batch/Stream Data Platform)

## Overview

Local ingestion-testing platform. The stack runs with Docker Compose and is centered on Dagster orchestration, PostgreSQL instance storage, MinIO object storage, CloudBeaver, and dbt models executed through DuckDB.

## Component Map

```text
erp_network
|
|-- dagster-webserver (:3000)
|-- dagster-daemon
|-- bsdp_pipeline (:4000 internal)
|   |-- loads orchestration.definitions
|   |-- runs dbt_bsdp through dbt-duckdb
|   `-- writes DuckDB file to /opt/dagster/dagster_home/storage/dbt_bsdp.duckdb
|
|-- backend_storage (:5432)
|   `-- DB: dagster
|
|-- minio (:9000/:9001)
|   `-- bucket: lakehouse
|
`-- cloudbeaver (:8978)
```

## Services

### Dagster Webserver

| Key | Value |
|-----|-------|
| Image | `ingestion-testing-orchestration:local` |
| Port | `3000` |
| UI | http://localhost:3000 |
| Config | `orchestration/dagster.yaml` |

### Dagster Daemon

Runs schedules, sensors, and backfills. Same image as the webserver; no exposed port.

### bsdp_pipeline

| Key | Value |
|-----|-------|
| Port | `4000` internal |
| Module | `orchestration.definitions` |
| Source mount | `./orchestration/src:/opt/dagster/app/src:ro` |
| dbt mount | `./dbt_bsdp:/opt/dagster/dbt_bsdp` |
| DuckDB path | `/opt/dagster/dagster_home/storage/dbt_bsdp.duckdb` |

This is the Dagster gRPC code location. `workspace.yaml` points the webserver and daemon to `bsdp_pipeline:4000`.

### PostgreSQL

| Key | Value |
|-----|-------|
| Service | `backend_storage` |
| Image | `postgres:16-alpine` |
| Port | `${DAGSTER_POSTGRES_PORT_ON_HOST:-5432}` |
| DB | `dagster` |

PostgreSQL stores Dagster run history, schedules, sensors, and event logs.

### MinIO

| Key | Value |
|-----|-------|
| Image | `minio/minio:latest` |
| S3 API | http://localhost:9000 |
| Console | http://localhost:9001 |
| Bucket | `lakehouse`, created by `minio-init` |
| Default credentials | `minioadmin` / `minioadmin` |

### dbt + DuckDB

The `dbt_bsdp` project uses `dbt-duckdb`. Inside Docker, `DBT_DUCKDB_PATH` points at persisted Dagster storage. On the host, the default profile path is `target/dev.duckdb`.

### CloudBeaver

| Key | Value |
|-----|-------|
| Image | `dbeaver/cloudbeaver:latest` |
| Port | `${CLOUDBEAVER_PORT:-8978}` |
| UI | http://localhost:8978 |

CloudBeaver is optional and can be used to connect to PostgreSQL.

## Data Flow

```text
Source DB
   |
   | Dagster ingestion assets
   v
MinIO bucket: lakehouse
   |
   | dbt models via DuckDB
   v
DuckDB database file
   |
   v
Dagster assets / local analytics
```

## Directory Layout

```text
bsdp/
|-- docker-compose.yml
|-- .env.example
|-- README.md
|-- ARCHITECTURE.md
|
|-- orchestration/
|   |-- Dockerfile
|   |-- docker-entrypoint.sh
|   |-- pyproject.toml
|   |-- uv.lock
|   |-- workspace.yaml
|   |-- dagster.yaml
|   `-- src/orchestration/
|       |-- definitions.py
|       `-- defs/
|           `-- dbt_bsdp_assets.py
|
|-- dbt_bsdp/
|   |-- dbt_project.yml
|   |-- profiles.yml
|   |-- pyproject.toml
|   |-- uv.lock
|   `-- models/
|
`-- data/volume/
    |-- backend_storage/
    |-- minio/
    |-- dagster/storage/
    |-- dagster/compute_logs/
    `-- cloudbeaver/
```

## Environment

```bash
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin
LAKEHOUSE_BUCKET=lakehouse
AWS_DEFAULT_REGION=us-east-1

DAGSTER_POSTGRES_HOST=backend_storage
DAGSTER_POSTGRES_PORT=5432
DAGSTER_POSTGRES_PORT_ON_HOST=5432
DAGSTER_POSTGRES_USER=dagster
DAGSTER_POSTGRES_PASSWORD=dagster
DAGSTER_POSTGRES_DB=dagster
```

`bsdp_pipeline` also sets these runtime values for S3 and DuckDB:

```bash
AWS_ENDPOINT_URL=http://minio:9000
AWS_ENDPOINT_URL_S3=http://minio:9000
AWS_S3_FORCE_PATH_STYLE=true
S3_ENDPOINT_URL=http://minio:9000
DBT_DUCKDB_PATH=/opt/dagster/dagster_home/storage/dbt_bsdp.duckdb
```

## Common Operations

```bash
docker compose up --build
docker compose down
```

Regenerate the dbt manifest after model changes:

```bash
cd dbt_bsdp
uv run dbt parse
```

Wipe runtime data:

```bash
docker compose down
rm -rf ./data/volume/
```

## Network

All services share the `erp_network` bridge network. DNS resolves by service name:

- `backend_storage:5432` - PostgreSQL
- `minio:9000` - MinIO S3 API
- `bsdp_pipeline:4000` - Dagster gRPC

From the host machine, use `localhost:<exposed-port>`.
