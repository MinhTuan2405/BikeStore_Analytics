# Per-Stack Isolation Patterns

Concrete patterns for each tool. The principle is consistent — separate compute, storage, identity, code, data — but the mechanism varies.

## Snowflake

**Isolation primitive:** Roles + warehouses + databases.

Minimum acceptable:
- One **role** per environment: `dev_role`, `staging_role`, `prod_role`. No role has access to another environment.
- One **warehouse** per environment: `wh_dev`, `wh_staging`, `wh_prod`. Cost controls per-warehouse.
- One **database** per environment: `dev_db`, `staging_db`, `prod_db`. Schemas inside follow `layer-conventions`.

Better:
- Separate **accounts** per environment. Hard isolation at the network / API level. Used by orgs with strict compliance.

Grants pattern (per environment):

```sql
GRANT USAGE ON WAREHOUSE wh_prod TO ROLE prod_role;
GRANT USAGE, MONITOR ON DATABASE prod_db TO ROLE prod_role;
GRANT ALL ON SCHEMA prod_db.staging TO ROLE prod_role;
-- Repeat per environment with respective role/warehouse/database
```

Prod role grants are tightest; dev role can be more permissive within its own database.

Resource monitors per environment cap credit spend. Dev gets a low cap; prod whatever the budget allows.

## Postgres

**Isolation primitive:** Instances or databases + roles.

Strong isolation:
- Separate Postgres **instances** per environment. Network-isolated.

Acceptable for small teams:
- One instance, separate **databases** per environment (`dev`, `staging`, `prod`).
- Separate **roles**: prod role can only `CONNECT` to prod DB.

Avoid:
- Single instance, single database, schemas only. One typo from disaster.

Grants pattern:

```sql
CREATE ROLE prod_user LOGIN PASSWORD '...';
GRANT CONNECT ON DATABASE prod_db TO prod_user;
REVOKE ALL ON DATABASE dev_db FROM prod_user;
GRANT USAGE ON SCHEMA staging TO prod_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA staging TO prod_user;
```

## Lake (Iceberg / Delta / Hudi on object storage)

**Isolation primitive:** Buckets + catalog namespaces + IAM.

Pattern:
- Separate **buckets** per environment: `platform-dev`, `platform-staging`, `platform-prod`.
- Separate **catalog namespaces** per environment.
- IAM roles per environment, with cross-environment access denied explicitly.

A common shortcut — single bucket with per-environment prefixes — is acceptable only if IAM policies enforce the prefix boundary tightly. Most teams find this is harder than separate buckets.

## Dagster

**Isolation primitive:** Separate deployments or environment-scoped resources.

Cleanest:
- One Dagster deployment per environment (dev / staging / prod).
- Each deployment runs the same code; resources differ.

Acceptable when budget constrains:
- One Dagster deployment.
- Code locations carry a `deployment_name` config that resources read.
- Resource definitions branch on deployment name:

```python
import os
from dagster import EnvVar

def get_warehouse_resource():
    env = os.environ.get("DEPLOYMENT_ENV", "dev")
    if env == "prod":
        return SnowflakeResource(
            account=EnvVar("PROD_SNOWFLAKE_ACCOUNT"),
            user=EnvVar("PROD_SNOWFLAKE_USER"),
            ...,
        )
    return SnowflakeResource(
        account=EnvVar("DEV_SNOWFLAKE_ACCOUNT"),
        ...,
    )
```

Schedules / sensors should only be enabled in prod. Use code-location config to gate them.

## dbt

**Isolation primitive:** Targets in `profiles.yml`.

```yaml
warehouse:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: "{{ env_var('DEV_SF_ACCOUNT') }}"
      schema: dev_{{ env_var('DBT_USER', 'shared') }}
      threads: 4
    staging:
      type: snowflake
      account: "{{ env_var('STAGING_SF_ACCOUNT') }}"
      schema: staging
      threads: 8
    prod:
      type: snowflake
      account: "{{ env_var('PROD_SF_ACCOUNT') }}"
      schema: prod
      threads: 16
```

Per-developer schemas via `generate_schema_name.sql`:

```sql
{% macro generate_schema_name(custom_schema_name, node) %}
  {%- set default = target.schema -%}
  {%- if custom_schema_name is none -%}
    {{ default }}
  {%- elif target.name == 'dev' -%}
    {{ default }}_{{ custom_schema_name | trim }}
  {%- else -%}
    {{ custom_schema_name | trim }}
  {%- endif -%}
{% endmacro %}
```

Result: in dev, `{{ config(schema='finance') }}` writes to `dev_alice_finance`. In prod, writes to `finance` (clean prod schema).

Prod runs only from the prod runner. CI / dev never run `dbt --target prod`.

## dlt

**Isolation primitive:** Destination credentials.

`.dlt/secrets.toml` (per environment):

```toml
[destination.snowflake.credentials]
host = "..."        # env-specific
warehouse = "..."   # env-specific (wh_dev / wh_prod)
database = "..."    # env-specific
```

Source credentials may also differ — dev points at sample / replica, prod at real source.

dlt picks credentials by environment variable convention or by config profile. Set the convention up front in the project's bootstrap.

## Compose

Local compose stacks are **always** dev. Don't try to use one compose file across environments.

What may differ:
- Image tags (dev = `:latest`, staging = `:rc`, etc.)
- Resource limits
- Mounted directories

Use separate compose files (`docker-compose.yml` + `docker-compose.override.yml`) — see `infra-docker-compose` for the pattern. Never deploy compose to a production-grade environment without understanding what that means.

## CI runners

The CI runner is itself an "environment":
- Credentials in CI secrets (GitHub / GitLab / Bitbucket pipeline secrets)
- One CI service account per environment, scoped to that environment's resources
- Production deploys gated by manual approval or release-tag triggers
- Logs accessible to the team, not just one person

## The cross-cutting check

Pick any production credential and ask: which environments can read it? The answer must be "production only". If a dev or staging system can fetch a production credential, identity isolation has failed and other isolation is moot.
