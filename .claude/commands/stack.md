Manage the local Docker Compose stack (Dagster webserver + daemon, PostgreSQL, MinIO, CloudBeaver).

Action: $ARGUMENTS  (start | stop | reset — defaults to start if empty)

## start (default)

```bash
docker-compose up --build -d
```

Then poll until all services are healthy and report:
```bash
docker-compose ps
```

Services and their URLs once healthy:
- Dagster UI: http://localhost:3000
- MinIO console: http://localhost:9001
- MinIO S3 API: http://localhost:9000
- CloudBeaver: http://localhost:8978

## stop

```bash
docker-compose down
```

## reset

**Confirm with the user before proceeding** — this permanently deletes all Dagster run history, MinIO objects, and PostgreSQL data stored under `./data/volume/`.

```bash
docker-compose down
Remove-Item -Recurse -Force ./data/volume/
```

After reset, run `/stack start` to bring the stack back up with a clean state.
