# Per-Tool Read Conventions

Every consumer in the stack reads secrets through one of two paths: **env var** or **file mount**. The convention varies; the principle is the same — never inline literals.

## Docker Compose

```yaml
# Env-var path
services:
  warehouse:
    environment:
      PG_PASSWORD: ${PG_PASSWORD:?PG_PASSWORD must be set}

# File-mount path
secrets:
  pg_password:
    file: ./secrets/pg_password.txt
services:
  warehouse:
    secrets: [pg_password]
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/pg_password
```

Notes:
- `${VAR:?msg}` forces a startup failure when `VAR` is unset (good — fails loud)
- `${VAR:-default}` provides a default (use for non-secrets only)
- `${VAR}` silently substitutes empty string when unset (avoid for secrets)

## dbt — `profiles.yml`

```yaml
warehouse:
  outputs:
    dev:
      type: snowflake
      account: "{{ env_var('SNOWFLAKE_ACCOUNT') }}"
      user: "{{ env_var('SNOWFLAKE_USER') }}"
      password: "{{ env_var('SNOWFLAKE_PASSWORD') }}"
      warehouse: "{{ env_var('SNOWFLAKE_WAREHOUSE') }}"
      role: "{{ env_var('SNOWFLAKE_ROLE') }}"
```

Notes:
- `env_var('NAME')` raises at runtime if unset → fails loud, good
- `env_var('NAME', 'default')` provides default → for non-secrets only
- Never put real values in `profiles.yml`, even for the `dev` target — gitignore the secrets-bearing version if it's committed at all
- Key-pair auth: `private_key_path: "{{ env_var('SNOWFLAKE_PRIVATE_KEY_PATH') }}"` plus a mounted PEM file

## Dagster — Resources

```python
from dagster import EnvVar, Definitions
from dagster_snowflake import SnowflakeResource

defs = Definitions(
    resources={
        "snowflake": SnowflakeResource(
            account=EnvVar("SNOWFLAKE_ACCOUNT"),
            user=EnvVar("SNOWFLAKE_USER"),
            password=EnvVar("SNOWFLAKE_PASSWORD"),
            warehouse=EnvVar("SNOWFLAKE_WAREHOUSE"),
            role=EnvVar("SNOWFLAKE_ROLE"),
        ),
    },
)
```

Notes:
- `EnvVar("NAME")` defers resolution to runtime, never stores the resolved value in the asset definition (so logs / repr don't leak it)
- Avoid passing literal strings even temporarily — easy to commit by accident
- For pluggable vaults, write a custom `ConfigurableResource` that fetches at construction time

## dlt — `secrets.toml` or env vars

```toml
# .dlt/secrets.toml (gitignored)
[sources.sql_database.credentials]
drivername = "postgresql"
database = "warehouse"
username = "loader"
password = "..."
host = "warehouse"
port = 5432

[destination.snowflake.credentials]
host = "..."
user = "..."
password = "..."
warehouse = "..."
```

Or env vars with the dlt convention:

```
SOURCES__SQL_DATABASE__CREDENTIALS__PASSWORD=...
DESTINATION__SNOWFLAKE__CREDENTIALS__PASSWORD=...
```

Notes:
- `secrets.toml` lives at `.dlt/secrets.toml` and is gitignored by default in `dlt init`
- Env vars use double-underscore separators
- dlt also supports cloud secret managers via plugins — see dlt docs for current options

## Snowflake CLI (`snow`)

```bash
# Flag form
snow sql --account "$SNOWFLAKE_ACCOUNT" \
         --user "$SNOWFLAKE_USER" \
         --password "$SNOWFLAKE_PASSWORD" \
         --warehouse "$SNOWFLAKE_WAREHOUSE" \
         -q "SELECT current_user();"

# Named connection (config.toml — gitignored if it has real values)
snow connection add --connection-name corsair
snow sql --connection corsair -q "SELECT ..."
```

Notes:
- `~/.snowflake/config.toml` is per-user — keep it out of any committed location
- Key-pair auth via `--private-key-path` reads from a file, never inline
- Pre-existing env vars `SNOWFLAKE_*` are picked up automatically — no flags needed when set

## MinIO / S3 clients (`mc`, `boto3`, `aws`)

```bash
# mc — alias stored in ~/.mc/config.json
mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"

# boto3 — picks up standard env vars
AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... python script.py
```

Notes:
- For MinIO local, env vars in compose `.env` are fine (tier 0)
- For real S3, prefer IAM roles (instance profile, IRSA on EKS) over long-lived keys — no secret to manage
- `~/.aws/credentials` is per-user; never check into a repo

## The common rule across all tools

Every config file in the repo references secrets by **name** (env var or vault key). The actual secret never lives in the repo, in container images, or in shell history. Grep the repo for the value of any production secret — if grep returns a hit, that's a finding.
