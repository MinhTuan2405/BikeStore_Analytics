# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repo is an **ingestion testing platform** built around Dagster for orchestration, PostgreSQL as Dagster's backend, MinIO as an S3-compatible lakehouse, and DuckDB for local dbt execution. The local stack runs entirely via Docker Compose.

## Repository Layout

```
bsdp/
├── docker-compose.yml          # Full local stack (Dagster, backend_storage, MinIO, CloudBeaver)
├── .env.example                # Shared env vars for docker-compose
├── dbt_bsdp/                   # dbt project using dbt-duckdb
├── orchestration/              # Dagster project, built into its own Docker image
│   ├── Dockerfile              # Uses uv on python3.12-bookworm-slim
│   ├── pyproject.toml          # orchestration package deps (dagster, boto3, psycopg)
│   ├── workspace.yaml          # Points Dagster at orchestration.definitions module
│   ├── dagster.yaml            # Dagster instance config (Postgres storage, local logs)
│   ├── .env.example            # Orchestration-specific env overrides
│   └── src/orchestration/
│       ├── definitions.py      # @definitions entry point using load_from_defs_folder
│       └── defs/               # Dagster defs folder (assets, jobs, resources go here)
└── experimental/ingestion-patterns/  # Retained ingestion design pattern notes
```

## Local Stack

Start:
```bash
docker-compose up --build
# or
docker compose up --build
```

Stop and remove containers:
```bash
docker-compose down
```

Wipe runtime data (Dagster storage, Postgres, MinIO):
```bash
docker-compose down
rm -rf ./data/volume/
```

Key URLs once running:
- Dagster UI: `http://localhost:3000`
- MinIO console: `http://localhost:9001`
- MinIO S3 API (from host): `http://localhost:9000`
- CloudBeaver: `http://localhost:8978`

## Environment Configuration

Copy `.env.example` to `.env` to override shared compose values. For orchestration-specific overrides, copy `orchestration/.env.example` to `orchestration/.env`.

To use real env files instead of the checked-in examples, set in your shell or root `.env`:
```bash
DAGSTER_SHARED_ENV_FILE=.env
DAGSTER_ORCHESTRATION_ENV_FILE=./orchestration/.env
```

The datasource variables in `.env.example` (prefixed `DATASOURCE_*`) define the source Postgres connection and are consumed by Dagster assets/resources in `orchestration/src`.

## Dagster Development

The `orchestration` package uses `uv` for dependency management. The Dockerfile does `uv sync --frozen --group dev`.

To add new Dagster definitions (assets, jobs, sensors, resources), place them inside `orchestration/src/orchestration/defs/`. The `load_from_defs_folder` call in `definitions.py` auto-discovers everything in that folder.

The `[tool.dg]` config in `orchestration/pyproject.toml` registers components under `orchestration.components.*` for use with the `dg` CLI.

## Dependency Management

The `orchestration/` sub-project has its own `pyproject.toml` with pinned Dagster packages and `dbt-duckdb`. The `dbt_bsdp/` sub-project also uses `uv` and `dbt-duckdb`.
