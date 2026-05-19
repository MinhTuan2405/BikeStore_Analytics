#!/bin/sh
set -eu

python - <<'PY'
import os
import socket
import sys
import time

import psycopg


def wait_for_tcp(name: str, host: str, port: int, deadline: float) -> None:
    while True:
        try:
            with socket.create_connection((host, port), timeout=3):
                return
        except OSError as exc:
            if time.monotonic() > deadline:
                print(f"Timed out waiting for {name} at {host}:{port}: {exc}", file=sys.stderr)
                raise SystemExit(1) from exc
            print(f"Waiting for {name} at {host}:{port}...", flush=True)
            time.sleep(2)


def wait_for_postgres(deadline: float) -> None:
    host = os.getenv("DAGSTER_POSTGRES_HOST", "postgres")
    port = int(os.getenv("DAGSTER_POSTGRES_PORT", "5432"))
    user = os.getenv("DAGSTER_POSTGRES_USER", "dagster")
    password = os.getenv("DAGSTER_POSTGRES_PASSWORD", "dagster")
    dbname = os.getenv("DAGSTER_POSTGRES_DB", "dagster")

    while True:
        try:
            with psycopg.connect(
                host=host,
                port=port,
                user=user,
                password=password,
                dbname=dbname,
                connect_timeout=3,
            ) as conn:
                with conn.cursor() as cursor:
                    cursor.execute("SELECT 1")
                return
        except psycopg.OperationalError as exc:
            if time.monotonic() > deadline:
                print(f"Timed out waiting for postgres at {host}:{port}: {exc}", file=sys.stderr)
                raise SystemExit(1) from exc
            print(f"Waiting for postgres at {host}:{port}...", flush=True)
            time.sleep(2)


deadline = time.monotonic() + 120
wait_for_postgres(deadline)
wait_for_tcp("minio", os.getenv("MINIO_HOST", "minio"), int(os.getenv("MINIO_PORT", "9000")), deadline)
PY

exec "$@"
