# Resource Patterns — Two Shapes

Resources come in two shapes. Pick by how Dagster interacts with the system.

## Shape 1 — API client (per-asset instantiated)

Used for external APIs / FTPs / file sources where each asset call wants a fresh client (different date ranges, different auth scopes, different rate-limit budgets).

```python
# resources/paypal_resource.py
import os
import requests
from dagster import get_dagster_logger

logger = get_dagster_logger()

class PaypalAPIClient:
    def __init__(self, base_url, start_date, end_date):
        self.base_url = base_url
        self.encode = os.getenv("PAYPAL_ENCODE")
        self.start_date = start_date
        self.end_date = end_date

    def _get_access_token(self):
        url = f"{self.base_url}/v1/oauth2/token"
        headers = {"Authorization": f"Basic {self.encode}", ...}
        resp = requests.post(url, headers=headers, data="...")
        return resp.json()["access_token"]

    def _api_call(self, endpoint):
        token = self._get_access_token()
        resp = requests.get(f"{self.base_url}/{endpoint}", headers={"Authorization": f"Bearer {token}"})
        resp.raise_for_status()
        return resp.json()

    def get_transactions(self):
        return self._api_call(f"v1/reporting/transactions?start_date={self.start_date}&end_date={self.end_date}")

    def get_subscriptions(self):
        return self._api_call("v1/billing/subscriptions")
```

Usage from an asset:

```python
from ...resources.paypal_resource import PaypalAPIClient

@asset(group_name="paypal_daily_ingestion", ...)
def paypal_data(context):
    client = PaypalAPIClient(base_url="https://api-m.paypal.com", start_date=..., end_date=...)
    return client.get_transactions()
```

Characteristics:
- Class with `__init__` parameters that the asset passes in (date range, brand, endpoint scope)
- Auth handled inside the class (env vars, token refresh)
- Multiple methods for multiple endpoints on the **same system**
- No Dagster decoration — Dagster doesn't manage its lifecycle
- Imported directly by asset modules

When to pick: API / FTP / file-source clients. The common case.

## Shape 2 — `@resource` factory (Dagster-injected)

Used for systems Dagster should inject into every asset that needs them — typically the warehouse, an object-store client, a secrets manager. Lifecycle is per-process, configuration per-deployment.

```python
# resources/snowpark_resource.py
import dagster._check as check
from dagster import resource
from snowflake.snowpark.session import Session

class SnowparkResource:
    def __init__(self, snowpark_conf):
        self._session = Session.builder.configs(snowpark_conf).create()

    @property
    def snowpark_session(self):
        return self._session

@resource(config_schema={"snowpark_conf": dict})
def snowpark_resource(init_context):
    return SnowparkResource(init_context.resource_config["snowpark_conf"])
```

Usage from an asset:

```python
@asset(required_resource_keys={"connect_snowflake"}, group_name="...")
def my_asset(context):
    session = context.resources.connect_snowflake.snowpark_session
    df = session.table("RAW.PAYPAL").to_pandas()
    ...
```

Registered per deployment in `resources/__init__.py`:

```python
RESOURCES = {
    "local": {"connect_snowflake": snowpark_resource.configured(DEV_SNOWFLAKE_CONF)},
    "cloud": {"connect_snowflake": snowpark_resource.configured(PROD_SNOWFLAKE_CONF)},
}
```

Characteristics:
- `@resource` decorator + factory function
- Configured via `.configured({...})` per deployment
- Asset declares `required_resource_keys={"name"}`; Dagster injects at runtime
- One instance per process (Dagster manages lifecycle)
- Cross-cutting — many assets share the same instance

When to pick:
- Warehouse session / connection
- Object-store / S3 / MinIO client (when the client is heavy to construct)
- IO managers
- Cross-asset secrets / config readers

## Picking between the two shapes

| Signal | Use Shape 1 (class) | Use Shape 2 (`@resource`) |
|---|---|---|
| Different parameters per asset call | ✓ | ✗ |
| Heavy to construct, shared across assets | ✗ | ✓ |
| One instance for the whole deployment | ✗ | ✓ |
| Needs deployment-specific config | Possible via env vars | Built-in via `.configured` |
| Cleanup on process shutdown matters | Manual | Dagster manages |

Most projects have **one or two** Shape-2 Resources (warehouse, S3) and **many** Shape-1 clients (one per API).

## Anti-patterns

- One Resource per API endpoint — collapse to one Resource per system, one method per endpoint
- API client as Shape 2 with `partitions_def` baked in — that belongs in the asset, not the resource
- Hardcoded credentials in the Resource — read from env, configure via `RESOURCES` dict
- Shape-2 Resource with no asset depending on it — dead code, remove from the bundle
- Shape-1 client that fetches credentials from a network call on every instantiation — cache the token at module level if appropriate, or use Shape 2
