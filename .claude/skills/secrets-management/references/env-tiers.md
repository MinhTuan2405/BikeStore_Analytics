# Env Tiers — Detailed Tooling

Each tier is a class of solution, not a specific product. Within a tier, the choice depends on cloud / on-prem and existing team familiarity.

## Tier 0 — Plain `.env`

```ini
# .env (gitignored)
POSTGRES_PASSWORD=local-dev-only
MINIO_ROOT_PASSWORD=local-dev-only
```

Tooling: nothing. `python-dotenv`, `direnv`, or shell `source .env` to load.

When acceptable:
- Service is reachable only from `localhost` or the local compose network
- Credential cannot reach any non-local environment if leaked
- Repository's `.gitignore` lists `.env*` (with `!.env.example`)

Verify: `git check-ignore .env` returns the path. `grep -r "secret_value" .git/` finds nothing.

## Tier 1 — Compose `secrets:` blocks

```yaml
secrets:
  pg_password:
    file: ./secrets/pg_password.txt    # gitignored

services:
  postgres:
    secrets: [pg_password]
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/pg_password
```

Better than tier 0 because:
- The value never appears in `docker inspect` env vars (only the file mount)
- The container's read user is restricted

Use when local services already support `_FILE` env conventions (Postgres, Vault, Consul, several others do).

## Tier 2 — Encrypted in-repo (SOPS / age / git-crypt)

```bash
# Encrypt
sops -e -i secrets/staging.env

# Decrypt at runtime
sops -d secrets/staging.env > .env.staging
docker compose --env-file .env.staging up
```

Tooling:
- **SOPS** + age or KMS — most common, supports YAML / JSON / ENV / binary
- **git-crypt** — transparent encryption on git operations, simpler but coarser
- **age** alone — file encryption without the structured-edit features SOPS adds

When this fits:
- Team-shared secrets for a non-production environment
- CI needs the secrets and you don't want to maintain a cloud vault
- Per-environment files (`staging.env.sops`, `prod.env.sops`) committed encrypted

Stop at: dynamic / short-lived credentials. SOPS files are static; rotation means re-encrypting and re-committing.

## Tier 3 — Cloud secret manager

```python
# Example: AWS Secrets Manager
import boto3
client = boto3.client("secretsmanager", region_name="us-east-1")
secret = client.get_secret_value(SecretId="prod/snowflake/loader")["SecretString"]
```

Vendor mapping:
- AWS → Secrets Manager (full-featured), Systems Manager Parameter Store (cheaper, less features)
- GCP → Secret Manager
- Azure → Key Vault
- Cloudflare → Workers Secrets

When this fits:
- Production credentials in a single cloud
- Services have IAM identities that can read specific secrets (no shared "fetch all" credential)
- Audit logs of reads are a requirement

Patterns to follow:
- One secret per service per environment (no shared "team" secret)
- IAM grants `secretsmanager:GetSecretValue` on a specific ARN, not `*`
- Rotation Lambda / function configured where the credential lifecycle allows

## Tier 4 — Vault / 1Password / OS keychain

Used for:
- Per-developer credentials (a developer's Snowflake user)
- MFA-protected secrets (the OTP itself, derived tokens)
- Short-lived credentials issued by an identity broker (HashiCorp Vault dynamic credentials, AWS STS)

Patterns:
- Vault agent injects credentials as files into a sidecar
- 1Password CLI (`op`) fetches at command invocation: `op run --env-file=.env.tpl -- <cmd>`
- OS keychain (macOS Keychain, gnome-keyring, Windows Credential Manager) — fine for developer tools, not for services

When this fits:
- Compliance requires audit logging per read
- Team is willing to invest in identity-broker tooling
- Credential issuance is dynamic (short-lived, scoped)

Cost: operational complexity is non-trivial. Don't reach for this for a 3-person team unless required.

## Picking across tiers

Production credentials with audit needs → tier 3 minimum.
Team-shared CI secrets → tier 2 or tier 3.
Local dev → tier 0 or 1.
Developer's personal credentials → tier 4 (keychain) or tier 0 (their laptop's `.env`).

Mixing tiers across environments is normal; mixing them within an environment is a smell — pick the highest tier that environment requires.
