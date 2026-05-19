---
name: secrets-management
description: Patterns for managing credentials across a data-platform stack — `.env` files, secrets blocks, vaults, SOPS, cloud KMS, per-environment separation. Use when wiring credentials for any service (warehouse, object store, orchestrator, ingestion, dbt), reviewing a stack for leaked secrets, designing rotation, or deciding which secret store fits the project. Cross-cutting — touches compose, dbt profiles, orchestrator resources, ingestion configs. Stays tool-agnostic — describes patterns and trade-offs, not specific vault setups.
---

# secrets-management

## Overview

A data platform has secrets everywhere: warehouse credentials, object-store keys, API tokens, encryption keys, service-account JSON. Each layer wants to read them differently — dbt looks in `profiles.yml`, Dagster looks in resources / env, dlt has its own conventions, compose interpolates from `.env`. The risk is uniform: any of these read paths can leak.

This skill encodes the patterns that keep secrets out of git, off shared logs, and out of the wrong environment. It does not pick a vault for the user — surfaces tradeoffs and writes the discipline.

## When to Use

- Wiring credentials for any new service in the stack
- Adding a new environment (dev / staging / prod) that needs its own secret set
- Reviewing the repo before a public-share or audit
- Rotation: replacing a leaked or expired credential
- Choosing a secret store (which vault / KMS / approach fits this project)

Do **not** use for:
- Application-level auth (user logins, OAuth flows) — different concern
- TLS certificates for public-facing endpoints — separate skill / tool

## Mental Model

Three orthogonal axes drive every secret decision:

| Axis | Question | Why it matters |
|---|---|---|
| **Sensitivity** | Could this credential reach a non-dev environment if leaked? | Drives storage choice (`.env` vs. vault) |
| **Audience** | Who needs to read it — humans, services, both? | Drives access pattern (file mount vs. API fetch) |
| **Lifetime** | Static (rotated on schedule) or dynamic (issued per session)? | Drives whether long-lived storage is acceptable |

A local Postgres password used only on a developer's laptop is low on all three — `.env` is fine. A Snowflake service-account password used in prod CI is high on all three — vault + rotation + audit log.

## Core Principles

1. **The repo is public until proven otherwise.** Treat every file under version control as if it'll be on a GitHub mirror tomorrow. No real credentials ever, regardless of repo visibility today.
2. **`.env.example` is the contract; `.env` is the secret.** Example file lists every variable with placeholder values, committed. Real file is gitignored and per-developer.
3. **Secrets are environment-scoped, never global.** Dev credentials cannot decrypt prod data, prod credentials cannot reach dev. Mixing these is the single most common cause of breach.
4. **Read at the latest possible moment.** Resolve secrets when the service starts, not when the config is parsed. Avoids logs / dumps containing the resolved value.
5. **Rotation is a workflow, not an event.** Plan how to rotate before you store, even if the actual rotation is months away. A secret you can't rotate is a permanent liability.
6. **Audit reads, not just writes.** "Who set this secret" is less important than "who read it last and why".
7. **Generate / scope, don't share.** Prefer per-service / per-environment credentials over shared "team" credentials. A leak should compromise one service in one environment, not all of them.

## Decision Flow

When wiring a new credential, ask in order:

1. **Where does this credential live in production?**
   - Local-only (laptop service password) → `.env` is acceptable.
   - Shared service (cloud DB, API token) → vault / cloud secret manager.
2. **Who consumes it?**
   - Humans typing CLI commands → CLI prompts or local `.env`.
   - Long-running service → mounted file or env var at start.
   - Short-lived job → fetched fresh from vault, never persisted.
3. **How is it rotated?**
   - Manual? Add a calendar reminder; document the procedure.
   - Automated? Plan the cutover (overlap window, rolling restart).
4. **What's the blast radius if leaked?**
   - One service in one environment → cheap to revoke and reissue.
   - Cross-environment or cross-service → upgrade storage immediately; this credential needs scoping work.

## Storage Tiers

Pick the lowest tier that fits the sensitivity:

| Tier | Mechanism | Use for | Stop at |
|---|---|---|---|
| **0** | Plain values in `.env` (gitignored) | Local-only dev credentials, default passwords for ephemeral local services | Anything that reaches a shared environment |
| **1** | `secrets:` block in compose, file mounts | Local services that read from a file path | Same — local only |
| **2** | SOPS / age / git-crypt — encrypted file in repo | Per-environment static secrets the team shares | Per-user secrets (use 0 or 4 instead) |
| **3** | Cloud secret manager (AWS Secrets Manager / GCP Secret Manager / Azure Key Vault) | Production credentials, shared between services in one cloud | Cross-cloud or cross-environment sharing |
| **4** | Vault / 1Password / OS keychain | Per-developer credentials, MFA-derived tokens, short-lived issuance | When team-shared static is required |

Mixing tiers is normal. A real project typically has tier-0 for `docker-compose.override.yml` dev settings, tier-2 for shared CI secrets, tier-3 for production cloud credentials.

## Where Each Layer Reads Secrets

When integrating, check the consumer's read path. The pattern is the same — env var or file — but the convention varies:

- **Compose** — `${VAR}` interpolation from `.env`; or `secrets:` block mounted at `/run/secrets/<name>`.
- **dbt** — `env_var('VAR')` in `profiles.yml`; never inline values.
- **Dagster** — `EnvVar("VAR")` in resource configs; or pluggable `SecretsResource`.
- **dlt** — `secrets.toml` (gitignored) or env vars matching `<SOURCE>__<KEY>` convention.
- **Snowflake CLI** — `--password $VAR` flag or named connection profile in gitignored `config.toml`.

The non-negotiable: every consumer reads from a variable / file path, **never** a literal in the committed config.

## Anti-patterns to Reject

- Real credentials in `docker-compose.yml` (even commented out — git history)
- Default passwords (`postgres`/`postgres`) reaching anything beyond local dev
- One `.env` for all environments — separate files (`.env.dev`, `.env.prod`) or separate stores
- Sharing the same credential between humans and services
- Service accounts with broader privileges than the service needs ("admin everywhere because debugging is easier")
- Hardcoded URLs containing credentials (`postgres://user:pass@host`) — split into separate vars
- Logging the resolved config object at startup (prints the credential into logs)
- Storing the encryption key in the same store as the encrypted data

## Rotation Discipline

Even tier-0 secrets eventually rotate. Document the procedure when you create the credential:

1. Where the credential is generated (which account, which UI, which CLI)
2. Where it must be updated (compose env, CI secrets, vault entry — list all)
3. How to verify the rotation worked (a smoke command per consumer)
4. The window during which old + new are both valid (zero-downtime needs overlap)

A rotation procedure that takes more than 15 minutes for a tier-0 secret means the credential is over-scoped or under-documented.

## What This Skill Does Not Do

- Pick a specific vault product
- Encrypt anything itself — relies on tools (SOPS, age, cloud KMS)
- Cover network-level secrets (TLS termination, mTLS) — outside data-platform scope
- Replace a security review for production

## References

- [`references/env-tiers.md`](references/env-tiers.md) — Detailed walkthrough of the five storage tiers with concrete tooling examples per cloud / on-prem
- [`references/per-tool-conventions.md`](references/per-tool-conventions.md) — Exact read patterns for compose, dbt, Dagster, dlt, Snowflake CLI, with idiomatic examples
- [`references/rotation-runbook.md`](references/rotation-runbook.md) — Template for documenting a credential's rotation procedure
