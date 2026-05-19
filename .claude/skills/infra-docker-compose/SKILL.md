---
name: infra-docker-compose
description: Compose-driven local infrastructure for data platforms. Use when scaffolding, extending, or debugging a `docker-compose.yml` that hosts data services (any combination of databases, object stores, orchestrators, message queues, dashboards). Stays stack-agnostic — encodes patterns (networks, volumes, healthchecks, env, profiles) without prescribing which services to run. Reach for it when a user says "spin up infra", "add a service to compose", "stack won't start", "wire X to talk to Y locally". Distinct from cloud IaC (Terraform) and from per-service skills (Postgres/Snowflake/Dagster) — those decide what runs; this skill decides how the runtime is shaped.
---

# infra-docker-compose

## Overview

Local data platforms are assembled from interchangeable parts: one orchestrator, one or two storage layers, a transformation runtime, sometimes a catalog or a BI front-end. The pieces vary per project; the **shape of the compose file does not**. This skill encodes that shape so any service can be slotted in without re-deriving the patterns each time.

Think of it as guidance for **how to compose**, not **what to compose**. When the user says "add MinIO", "swap Postgres for DuckDB", or "the orchestrator can't reach the warehouse" — you decide the services; this skill decides how they're wired.

## When to Use

- Bootstrapping a new project's `docker-compose.yml` from scratch
- Adding or replacing a service in an existing compose stack
- Debugging cross-service connectivity (DNS, ports, healthcheck timing)
- Reviewing a compose file before commit (volumes, secrets, profile hygiene)
- Splitting a monolithic compose file into layered files (`docker-compose.yml` + `docker-compose.override.yml` + per-profile files)

Do **not** use for:
- Choosing **which** database / orchestrator / lake format to adopt — that's an architecture decision the user owns
- Production deployment (Kubernetes, ECS, Nomad)
- Provisioning managed cloud resources — use Terraform / cloud IaC instead

## Mental Model

A data platform compose stack has four kinds of moving parts. Treat them as separate concerns even when they appear in the same file:

| Concern | What it covers | Signals it's wrong |
|---|---|---|
| **Topology** | Networks, service-to-service DNS, exposed ports | "Can't connect to host", clashing ports, services reach each other only via host IP |
| **State** | Volumes, bind mounts, initialization scripts | Data lost on `down`, init script runs every restart, host permissions break the volume |
| **Lifecycle** | `depends_on` + healthchecks, restart policies, startup order | One service starts before its dependency is ready; cascading restarts on a single failure |
| **Config** | Env vars, secrets, profiles, override files | Secrets in the committed file, profile sprawl, dev tweaks bleeding into base file |

Most "stack won't start" problems are a lifecycle or topology issue mislabeled as a service bug. Diagnose at the compose layer before suspecting the service image.

## Core Principles

These hold regardless of which services run:

1. **One project network, named explicitly.** Default bridge networks work but are unnamed and hard to attach external containers to. Declare `networks: { <project>_net: }` and put every service on it. Service DNS is the service key; no host IPs, no `network_mode: host`.

2. **Volumes outlive containers.** Anything stateful (databases, object stores, lake metadata) must use a **named volume**, not a bind mount, unless the user explicitly wants host visibility. Name the volume after the service (`pg_data`, `minio_data`). Bind mounts are for code / config / init scripts, not data.

3. **Healthchecks gate startup, `depends_on` alone does not.** `depends_on` waits for *container start*, not *service ready*. For anything another service connects to, define a `healthcheck` and use `depends_on: condition: service_healthy` on consumers. Without this, the orchestrator races the database on cold start and the stack appears broken.

4. **Secrets never live in the committed file.** Use `.env` (gitignored) or `secrets:` blocks. The compose file should be safe to publish. Default passwords for local dev are fine *only* if they cannot reach a non-local environment.

5. **Profiles separate "always run" from "sometimes run".** Marker services (one-shot bucket creation, schema seed, optional dashboards) belong in a `profiles:` group. Base stack stays minimal; opt-in services join with `--profile`.

6. **Initialization is idempotent and explicit.** A bucket-creation step, a Postgres role grant, a Dagster code-location registration — these are separate services or `command:` overrides, not assumptions baked into the base image. Idempotent so re-running `up` is safe.

7. **Override file owns local mutations.** `docker-compose.override.yml` (auto-loaded) is where developers tweak ports, mount source code, enable debug. Base `docker-compose.yml` stays reproducible.

## Decision Points

When extending or scaffolding, ask these in order. Each answer narrows the next:

1. **What is this service's role?** Stateful store / stateless compute / one-shot init / sidecar. Drives volume strategy and healthcheck shape.
2. **Who depends on it?** Determines whether a healthcheck is mandatory and what it should test (a TCP probe is rarely enough — prefer a domain-level check: `pg_isready`, `mc ready`, `curl /health`).
3. **Is it always-on or opt-in?** Always-on → no profile. Opt-in → profile.
4. **Does it need persistence across `down`?** Yes → named volume. No → tmpfs or no volume.
5. **Does it expose anything to the host?** If only other services use it, do **not** publish ports (keeps host port space clean and avoids accidental remote exposure on misconfigured firewalls).
6. **What credentials does it need?** Env vars (low-sensitivity, local-only) vs. secrets (anything that could escape the host).

## Workflow

### Scaffolding from scratch

1. Confirm the user's stack list — every service, plus their role.
2. Sketch the topology on paper first: which services talk to which? That dictates network and dependency edges.
3. Write the base `docker-compose.yml` with: one named network, named volumes per stateful service, healthchecks on every service another service depends on, `.env.example` checked in (real `.env` gitignored).
4. Add a `docker-compose.override.yml` skeleton for dev conveniences (port publishes, source mounts).
5. Verify the stack: `docker compose config` (catches syntax + interpolation issues), `docker compose up -d`, `docker compose ps` (every service `healthy`), then a connectivity smoke test from one service to another via service DNS.

### Extending an existing stack

1. Read the current file end-to-end before editing. Don't bolt a service onto a stack whose patterns you haven't matched.
2. New service goes on the same network, follows the same volume / healthcheck conventions.
3. Update any consumer's `depends_on` block.
4. If the new service introduces secrets, add them to `.env.example` (placeholder) and document in the project README.

### Debugging

- **"Service won't start":** `docker compose logs <svc>` — read the actual exit. Compose errors and image errors look similar in the UI.
- **"X can't reach Y":** Resolve from inside the consumer container: `docker compose exec X getent hosts Y`. If DNS works but the connection fails, the issue is in Y (not ready yet — check the healthcheck) or in the port (publishing to host doesn't make it reachable from sibling containers; use the internal port).
- **"Data disappeared on restart":** Almost always a bind mount with wrong permissions, or a named volume the user forgot to declare and the engine reaped on `down -v`.

## References

Load these on demand — `SKILL.md` stays minimal.

- [`references/networks.md`](references/networks.md) — Network declaration patterns, service DNS, attaching external containers, when to publish ports
- [`references/volumes.md`](references/volumes.md) — Named volumes vs. bind mounts, init-script mounts, permission gotchas
- [`references/healthchecks.md`](references/healthchecks.md) — Healthcheck shapes per service type, timing parameters, `depends_on` conditions
- [`references/env-secrets.md`](references/env-secrets.md) — `.env` discipline, `secrets:` block, `.env.example` convention
- [`references/profiles-overrides.md`](references/profiles-overrides.md) — `profiles:` vs. `docker-compose.override.yml`, multi-file composition

## What This Skill Does Not Decide

- Which database, lake format, orchestrator, or BI tool to use
- Image versions or tags
- Resource limits (CPU/memory) — those are environment-specific
- Production hardening (TLS termination, auth proxies, log shipping)

Bring those decisions in from the user or from per-service skills. This skill arranges what they pick.
