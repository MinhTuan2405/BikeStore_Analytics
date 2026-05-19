# Volumes

## Named volume vs. bind mount: pick by purpose

| Purpose | Use | Why |
|---|---|---|
| Persistent data (DB files, object store data, lake metadata) | **Named volume** | Engine manages lifecycle, permissions sane, portable across hosts |
| Source code mounted for hot reload | Bind mount | Host edits visible immediately |
| Config / init scripts read at startup | Bind mount (read-only) | Versioned with the repo, no copy step |
| Build artifacts shared between services | Named volume | Avoid host filesystem dependency |
| Logs (when you need them on host) | Bind mount | Inspect with grep/tail without entering container |

## Naming

Name volumes after the service that owns them, with the data role as suffix:

```yaml
volumes:
  pg_data:
  minio_data:
  dagster_home:
```

Avoid generic names (`data`, `vol1`) — they collide between projects on the same host.

## Init scripts

For services that support init via mounted scripts (Postgres, MySQL, MinIO via a sidecar), mount **read-only**:

```yaml
services:
  postgres:
    volumes:
      - pg_data:/var/lib/postgresql/data
      - ./init/postgres:/docker-entrypoint-initdb.d:ro
```

Init scripts run **only on first start** when the data directory is empty. Re-running them later requires wiping the volume — design them to be idempotent if you can, but assume one-shot.

For services without native init support (MinIO bucket creation, Kafka topic setup), use a separate **one-shot init service** under a profile or with `restart: no`:

```yaml
services:
  minio-init:
    image: minio/mc
    depends_on:
      minio: { condition: service_healthy }
    entrypoint: >
      sh -c "
        mc alias set local http://minio:9000 $$MINIO_ROOT_USER $$MINIO_ROOT_PASSWORD &&
        mc mb -p local/raw local/staging local/curated &&
        echo 'buckets ready'
      "
    restart: "no"
```

The init service exits on success — that's correct, `restart: "no"` keeps it from looping.

## Permissions gotcha

Bind-mounted directories inherit host UID/GID. If the container runs as a non-root user (e.g. Postgres image runs as UID 999), the host directory must be readable/writable by that UID — or the container fails with cryptic permission errors.

**Prefer named volumes for this reason.** Use bind mounts only when host visibility is needed and you've thought through the UID mapping.

## Wiping data

`docker compose down` keeps named volumes (data survives).
`docker compose down -v` deletes them (intentional reset).

Communicate this clearly in the README so a teammate doesn't lose work.

## Inspecting

```bash
docker volume ls
docker volume inspect <project>_pg_data
docker run --rm -v <project>_pg_data:/data alpine ls -lah /data
```
