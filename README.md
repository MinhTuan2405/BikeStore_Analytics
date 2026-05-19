# Ingestion Testing

## Local Dagster Stack

The root `docker-compose.yml` runs Dagster, PostgreSQL for Dagster's backend storage, MinIO as an S3-compatible lakehouse target, and CloudBeaver as an optional SQL client. dbt uses DuckDB in-process for local execution.

Start the stack with the legacy `docker-compose` CLI or the newer plugin:

```bash
docker-compose up --build
# or
docker compose up --build
```

Useful URLs:

- Dagster UI: http://localhost:3000
- Dagster PostgreSQL backend: `localhost:5432`
- MinIO S3 endpoint from host: http://localhost:9000
- MinIO console: http://localhost:9001
- MinIO S3 endpoint from Dagster containers: `http://minio:9000`
- CloudBeaver: http://localhost:8978
- Docker network: `erp_network`

Runtime data is stored under `./data/volume/`:

- Backend storage data: `./data/volume/backend_storage` (PostgreSQL data for Dagster DB)
- MinIO data: `./data/volume/minio`
- Dagster artifacts: `./data/volume/dagster/storage`
- Dagster compute logs: `./data/volume/dagster/compute_logs`

The `bsdp_pipeline` container sets `DBT_DUCKDB_PATH=/opt/dagster/dagster_home/storage/dbt_bsdp.duckdb`, so dbt writes its local DuckDB database into the persisted Dagster storage volume. When running dbt directly from `dbt_bsdp/`, the profile defaults to `target/dev.duckdb`.

Default local credentials are defined in `.env.example`:

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

Create a root `.env` from `.env.example` if you want to override these compose-level values. The `minio-init` service creates the `LAKEHOUSE_BUCKET` bucket automatically.

Dagster's instance storage is configured in `orchestration/dagster.yaml` and uses the `backend_storage` service via `dagster-postgres`.

Dagster containers receive these lakehouse environment variables:

```bash
AWS_ACCESS_KEY_ID=${MINIO_ROOT_USER}
AWS_SECRET_ACCESS_KEY=${MINIO_ROOT_PASSWORD}
AWS_ENDPOINT_URL=http://minio:9000
AWS_ENDPOINT_URL_S3=http://minio:9000
AWS_S3_FORCE_PATH_STYLE=true
S3_ENDPOINT_URL=http://minio:9000
LAKEHOUSE_BUCKET=${LAKEHOUSE_BUCKET}
DAGSTER_POSTGRES_HOST=backend_storage
DAGSTER_POSTGRES_PORT=5432
DAGSTER_POSTGRES_USER=${DAGSTER_POSTGRES_USER}
DAGSTER_POSTGRES_PASSWORD=${DAGSTER_POSTGRES_PASSWORD}
DAGSTER_POSTGRES_DB=${DAGSTER_POSTGRES_DB}
```

This compose file uses legacy-compatible `env_file` syntax. Because legacy Compose cannot mark env files as optional, it defaults to checked-in example files:

- `DAGSTER_SHARED_ENV_FILE`, default `.env.example`
- `DAGSTER_ORCHESTRATION_ENV_FILE`, default `./orchestration/.env.example`

To load real local env files, set these in your shell or root `.env`:

```bash
DAGSTER_SHARED_ENV_FILE=.env
DAGSTER_ORCHESTRATION_ENV_FILE=./orchestration/.env
```

Values listed directly under `environment:` in `docker-compose.yml` override values from `env_file`.

The compose file defines healthchecks for `backend_storage`, `minio`, `dagster-webserver`, `dagster-daemon`, and the Dagster gRPC code location. Because this is legacy Compose style, `depends_on` controls startup order only; the Dagster image also waits for PostgreSQL and MinIO ports before launching.

Stop the stack:

```bash
docker-compose down
# or
docker compose down
```

Delete local Dagster, PostgreSQL, and MinIO containers:

```bash
docker-compose down -v
# or
docker compose down -v
```

Because this stack uses bind mounts under `./data/volume/`, `down -v` does not delete runtime data. Remove `./data/volume/` manually when you want a clean local state.
