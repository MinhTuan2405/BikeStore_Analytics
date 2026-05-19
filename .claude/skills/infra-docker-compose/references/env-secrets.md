# Env vars & secrets

## File layout

```
docker-compose.yml         ← committed, no secrets
docker-compose.override.yml ← committed (or gitignored, per project)
.env                       ← gitignored, real values
.env.example               ← committed, placeholder values
```

Compose auto-loads `.env` from the working directory. Variables in `.env` interpolate into `docker-compose.yml` as `${VAR_NAME}`.

## .env discipline

`.env.example` is the contract:

```ini
# .env.example — copy to .env and fill in
POSTGRES_PASSWORD=changeme
MINIO_ROOT_PASSWORD=changeme
SNOWFLAKE_ACCOUNT=
AWS_ACCESS_KEY_ID=
```

Rules:
- Every var the compose file references must appear in `.env.example`
- Real values **never** committed; `.env` is in `.gitignore`
- Placeholders (`changeme`, empty string) signal "must override"
- A teammate cloning the repo runs `cp .env.example .env` and fills in — nothing else

## Env vs. secrets block

Use **env vars** for:
- Low-sensitivity config (ports, sizes, feature flags)
- Local-only dev credentials that cannot reach a non-dev system
- Anything the service reads via `os.environ`

Use **secrets** (`secrets:` block) for:
- Real credentials (production keys, API tokens) even in dev compose
- Anything you'd be uncomfortable seeing in `docker inspect` output (env vars are visible there)

```yaml
secrets:
  snowflake_pk:
    file: ./secrets/snowflake_pk.p8

services:
  loader:
    secrets: [snowflake_pk]
    environment:
      SNOWFLAKE_PRIVATE_KEY_PATH: /run/secrets/snowflake_pk
```

The file mounts at `/run/secrets/<name>`, readable only by the container's user.

## Interpolation gotchas

- `${VAR}` expands at compose-parse time. If `VAR` is unset, the value is empty string (silent). Use `${VAR:?error message}` to force failure:
  ```yaml
  environment:
    DATABASE_URL: ${DATABASE_URL:?DATABASE_URL must be set}
  ```
- Default values: `${VAR:-default}` uses `default` if `VAR` is empty or unset.
- Dollar signs in literal strings need doubling: `$$` to escape compose interpolation when you want the value `$` in the container.

## CI environments

In CI, set env vars via the runner (GitHub secrets, GitLab variables) — don't ship a `.env` file. Compose still picks them up from the process environment.
