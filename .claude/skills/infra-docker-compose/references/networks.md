# Networks

## Declare explicitly, name after the project

```yaml
networks:
  platform_net:
    driver: bridge
    name: ${COMPOSE_PROJECT_NAME:-platform}_net
```

Reasons to name explicitly:
- External containers (e.g. a one-off `psql` client) can join by name
- Logs / `docker network inspect` are readable
- Multiple stacks on the same host don't collide on the default `<project>_default`

## Every service on the same network

Unless there's a deliberate isolation boundary (rare in dev), put all services on one network. Service DNS works automatically: a service named `postgres` is reachable from any other service at `postgres:<port>`.

```yaml
services:
  warehouse:
    image: ...
    networks: [platform_net]
  orchestrator:
    image: ...
    networks: [platform_net]
```

## Service-to-service uses internal ports; host uses published ports

If service A connects to service B, it uses **B's internal port**. The `ports:` block is only for **host → container** traffic.

```yaml
services:
  postgres:
    image: postgres:16
    # No `ports:` here — only sibling services need it
  app:
    environment:
      DATABASE_URL: postgres://user:pass@postgres:5432/db  # internal port
```

Publish to the host only when a developer needs direct access (psql from the laptop, browser hitting a dashboard):

```yaml
ports:
  - "127.0.0.1:5432:5432"   # bind to loopback unless remote access is intended
```

Default to `127.0.0.1:` — exposing on `0.0.0.0:` makes the service reachable from anywhere the host is, which is rarely what local dev needs.

## Multiple networks (when needed)

A service can sit on multiple networks. Useful for:
- Front-end / back-end split (DB only on `backend_net`)
- A shared `monitoring_net` consumed by metrics scrapers

```yaml
services:
  warehouse:
    networks: [backend_net, monitoring_net]
```

Most data platforms don't need this — one network is fine.

## Attaching an external container

To run a one-shot client against the stack from the host:

```bash
docker run --rm -it \
  --network ${COMPOSE_PROJECT_NAME}_net \
  postgres:16 psql -h postgres -U user db
```

The container resolves `postgres` via the same DNS the stack uses.
