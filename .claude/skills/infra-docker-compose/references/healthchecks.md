# Healthchecks

## Why healthchecks beat `depends_on` alone

`depends_on` without `condition: service_healthy` only waits for the container's main process to start — not for the service inside to accept connections. The orchestrator launches, races the warehouse, fails to connect, dies. Looks like a bug; it's a missing healthcheck.

Use this pattern for any service that another service connects to:

```yaml
services:
  warehouse:
    image: ...
    healthcheck:
      test: ["CMD-SHELL", "<domain-level readiness probe>"]
      interval: 5s
      timeout: 3s
      retries: 10
      start_period: 10s

  orchestrator:
    depends_on:
      warehouse: { condition: service_healthy }
```

## Probe shapes by service category

The probe must test **service readiness**, not just "process exists". A TCP probe (`nc -z`) tells you the port is open, which is often before the service can answer queries.

| Category | Good probe | Bad probe |
|---|---|---|
| Relational DB | Built-in readiness command (`pg_isready`, `mysqladmin ping`) | TCP probe — port opens before recovery finishes |
| Object store (S3-compatible) | HTTP `/minio/health/ready` or equivalent endpoint | Connect to port 9000 — open during startup |
| HTTP API service | `curl -fsS http://localhost:<port>/health` | TCP — opens before app initializes |
| Message broker | Broker-specific readiness CLI | TCP — listening doesn't mean partitions are ready |
| Orchestrator UI | `curl /healthz` on the webserver | Process running ≠ workspace loaded |

When no domain probe exists, fall back to TCP but lengthen `start_period` and `retries` generously.

## Timing parameters

- **`interval`**: How often the probe runs. Default 30s is too slow for dev — use 5s for fast feedback.
- **`timeout`**: Per-probe limit. 3s is usually enough; longer probes signal a stuck service, not slow probe.
- **`retries`**: How many failures before marking unhealthy. 5–10 covers transient startup hiccups.
- **`start_period`**: Grace window during which failures don't count toward `retries`. Crucial for heavy services (DBs, lake engines) that take 20–60s to come up. Default 0s; use 10–60s based on the service.

A first-cold-start pattern that works for most stateful services:

```yaml
healthcheck:
  test: ["CMD-SHELL", "<probe>"]
  interval: 5s
  timeout: 3s
  retries: 12
  start_period: 30s
```

## Cascading dependencies

```yaml
services:
  warehouse:
    healthcheck: { ... }
  catalog:
    depends_on:
      warehouse: { condition: service_healthy }
    healthcheck: { ... }
  orchestrator:
    depends_on:
      warehouse: { condition: service_healthy }
      catalog: { condition: service_healthy }
```

The orchestrator waits for both. If either is unhealthy, the orchestrator never starts — that's correct: it cannot work without them.

## Self-healing

`restart: unless-stopped` plus a healthcheck means a service that becomes unhealthy after running won't auto-recover unless the container itself crashes. For local dev this is usually fine; in CI, prefer `restart: "no"` so failures surface loudly.
