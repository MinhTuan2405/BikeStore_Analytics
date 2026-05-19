# Promotion Pipelines — Sample Shapes

Two reference pipeline shapes that enforce dev → staging → prod. Adapt to the specific CI vendor — the structure matters more than the syntax.

## Shape 1 — Trunk-based, single main branch

Suits small-to-medium teams where main is always deployable.

```
Feature branch
   │
   ├── PR opens
   │     │
   │     ▼
   │  ┌──────────────────────────────┐
   │  │  CI: lint + dbt parse + tests│
   │  │  against `staging` target    │
   │  └──────────────────────────────┘
   │
   ├── Merge to main
   │     │
   │     ▼
   │  ┌──────────────────────────────┐
   │  │  Build artifact (image tag)  │
   │  │  Deploy to staging           │
   │  │  Run staging smoke tests     │
   │  └──────────────────────────────┘
   │
   └── Promote to prod (manual approval or release tag)
         │
         ▼
      ┌──────────────────────────────┐
      │  Deploy to prod              │
      │  Run prod smoke tests        │
      │  Notify on success / failure │
      └──────────────────────────────┘
```

Trade-offs:
- ✓ Simple, one branch model
- ✓ Staging soak time before prod
- ✗ Hot-fix flow needs care — can't bypass staging without a deliberate hot-fix branch pattern

## Shape 2 — Branch-per-environment

Suits regulated environments where audit trails per environment matter.

```
main ──→ deploy to dev
  │
  ▼
staging ──→ deploy to staging  (merged from main when ready)
  │
  ▼
production ──→ deploy to prod  (merged from staging after sign-off)
```

Each environment has a branch. Promotion is a merge / fast-forward.

Trade-offs:
- ✓ Audit trail is explicit (the merge to `production` is the deploy record)
- ✓ Different environments can sit on different versions if needed
- ✗ Merge conflicts accumulate; promotion friction grows with branch divergence
- ✗ Easy to drift between branches if discipline lapses

## What every promotion pipeline must enforce

Regardless of shape:

1. **No human credentials in the prod flow.** The prod deploy uses a service account configured in the CI vendor; no individual developer has prod credentials.
2. **Same artifact across environments.** The image tag / dbt manifest deployed to staging is bit-identical to the one deployed to prod. If they differ, you're testing a different artifact than you ship.
3. **Tests against staging block prod.** Failed staging tests prevent the prod deploy from running.
4. **Rollback is one step.** Re-deploy the previous artifact. If the pipeline can deploy forward, it must deploy backward with the same machinery.
5. **Schema migrations are reversible or gated.** A `DROP COLUMN` migration is irreversible — gate behind manual approval, and have a rebuild-from-backup plan.

## Smoke tests after deploy

Don't trust "deploy succeeded" as proof. Run smoke tests after each environment's deploy:

- **dbt smoke:** A handful of `--select` clauses on representative models. They build, they test, the manifest is queryable.
- **Orchestrator smoke:** Launch one canary asset / DAG. Confirm it materializes and reports success.
- **Ingestion smoke:** Trigger one ingestion against a known-tiny source. Verify destination row count.
- **End-to-end smoke:** A query against a final mart that hits a small known value (e.g. yesterday's revenue total exists and is non-null).

Failed smoke = automatic rollback or alert, depending on severity.

## CI secrets management

Where credentials live:
- CI vendor's secret store (GitHub Actions secrets, GitLab CI variables, Bitbucket pipelines variables).
- One secret per environment per service. No "team-wide" secrets.
- Environment-specific deployment jobs scoped to their own secret set; the staging job cannot read prod secrets.

Production deploys often add a **protected environment** layer in the CI vendor — requires approval from designated reviewers, locks the secrets behind that approval.

## Approval gates

A production deploy with no human approval is fine for small projects. For larger ones, gate explicitly:

- Required reviewers on the merge / tag
- Slack / chat notification on approve / deny
- An audit log of who approved each prod deploy

The gate is not a substitute for tests — it's a checkpoint for context the tests can't know (timing, communication, ongoing incidents).

## What a good promotion pipeline does NOT do

- Run dbt against multiple environments in parallel (race conditions, doubled cost)
- Deploy to prod from a feature branch ("just this one time" — never)
- Skip staging for "quick fixes" — a fix that bypasses the pipeline is a fix that bypasses the safety net
- Allow developers to override the pipeline manually — the pipeline IS the deployment mechanism, not a checklist
