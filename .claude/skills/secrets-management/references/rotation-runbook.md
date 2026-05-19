# Rotation Runbook — Template

Every credential gets a rotation entry. The template below is per-credential. Even tier-0 secrets get a stub — "manual, every 12 months, re-run init script" is a valid procedure.

## Template

```markdown
# Rotation: <credential name>

## Description
<one line — what this credential authenticates>

## Storage tier
<0–4 — see env-tiers.md>

## Location of truth
<where the canonical value lives — vault path, KMS, file path, etc.>

## Consumers
<list every place that reads this credential>
- compose service `warehouse` (env `PG_PASSWORD`)
- dbt profile `dev` (env `PG_PASSWORD`)
- dagster resource `warehouse_db` (env `PG_PASSWORD`)
- CI workflow `prod-deploy.yml` (secret `PG_PASSWORD`)

## Generation
<how to obtain a new value — UI clicks, CLI command, API call>

## Rotation procedure
1. Generate new value (see above)
2. Update all consumer stores (vault / CI secrets / SOPS file)
3. Verify each consumer can read the new value: <list smoke tests>
4. Trigger rolling restart of long-running services that cached the old value
5. Once all consumers confirmed, revoke / delete the old value at the source

## Overlap window
<can old and new be valid simultaneously? for how long?>

## Verification
<one command per consumer that proves the new credential works>

## Last rotated
<date — update on each rotation>

## Next planned rotation
<date — usually +N months, where N is the team's standard cadence>
```

## Putting runbooks in the repo

A `secrets/ROTATION.md` document holding one entry per credential is the simplest. Keep it next to (not inside) the secrets themselves.

Cross-reference from the project README so a new joiner knows it exists.

## Anti-patterns

- A rotation procedure that exists only in someone's head
- A credential consumed in N places but only updated in N–1 — the last consumer breaks at midnight on rotation day
- "Rotation" that means "issue a new credential and leave the old one valid forever" — the old one is a permanent liability
- No verification step → "rotated" but actually broken; discovered when the next nightly job fails
- A rotation that requires bringing down production → that's not rotation, that's a migration; design for overlap

## When the credential is leaked

Skip the planned procedure; execute the emergency revoke:

1. Revoke the leaked credential at the source immediately
2. Issue a new credential
3. Update consumers (yes, services will fail in the interim — that's acceptable; the alternative is leaving the leak active)
4. Audit logs: what did the leaked credential touch between exposure and revocation?
5. Post-mortem: how did it leak? Add the discovery to the secrets review checklist
