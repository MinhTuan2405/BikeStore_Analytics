# Profiles & overrides

## Two mechanisms for "sometimes run"

### Profiles — tagged services

Profiles let services declare "I only run when explicitly requested". Base stack stays minimal.

```yaml
services:
  warehouse:    # always runs
    image: ...
  bucket-init:  # one-shot, runs on demand
    image: ...
    profiles: [init]
  dashboard:    # optional UI
    image: ...
    profiles: [ui]
```

Behavior:
- `docker compose up` → only `warehouse` (no profile)
- `docker compose --profile init up` → `warehouse` + `bucket-init`
- `docker compose --profile init --profile ui up` → all three

Good fits for profiles:
- One-shot init / seed services
- Optional dashboards (Superset, Metabase, Grafana)
- Heavy ML / analytics services not needed for core dev
- Debug sidecars (psql client, mc shell, network debugger)

### Override files — environment-specific deltas

`docker-compose.override.yml` is auto-loaded on top of `docker-compose.yml`. Use it for **local mutations** to the base stack:

```yaml
# docker-compose.override.yml — local dev tweaks
services:
  warehouse:
    ports: ["127.0.0.1:5432:5432"]  # expose for laptop access
  app:
    volumes:
      - ./src:/app/src              # hot reload
    environment:
      LOG_LEVEL: DEBUG
```

Behavior:
- Compose merges override on top of base file automatically
- Decide per project whether to commit the override (team-shared dev defaults) or gitignore it (personal tweaks)
- Multiple override files: `docker compose -f docker-compose.yml -f docker-compose.prod.yml up`

## When to use which

| Need | Mechanism |
|---|---|
| Service runs only on demand | Profile |
| Same service, different config per environment | Override file |
| Optional dependency another optional thing pulls in | Profile (chain via `depends_on`) |
| Dev wants port published, prod doesn't | Override file (dev tweak in `docker-compose.override.yml`) |

## Multi-file composition pattern

For projects with several environments:

```
docker-compose.yml             # base — service definitions, no env-specific config
docker-compose.dev.yml         # ports, mounts, debug
docker-compose.ci.yml          # CI-specific (no port publish, ephemeral volumes)
docker-compose.prod.yml        # rarely used for local prod, but possible
```

Invoke explicitly:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

Or set `COMPOSE_FILE` env var to a colon-separated list to make it default.

## Avoid profile sprawl

If you have >5 profiles, the base stack is probably wrong — too many "optional" services means the core isn't actually defined. Refactor: either accept some services as core, or split into multiple compose files.
