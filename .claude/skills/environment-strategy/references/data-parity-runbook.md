# Data Parity Runbook — Refresh Strategies

How prod-like data gets into non-prod environments without leaking real data. Pick a strategy per environment per source.

## Strategy menu

| Strategy | Speed | Realism | PII risk | Cost |
|---|---|---|---|---|
| **Synthetic** | Fast | Low–medium | None | Lowest |
| **Sampled** | Fast | High | High if unmasked | Low |
| **Masked sample** | Medium | High | Low | Medium |
| **Full masked snapshot** | Slow | Highest | Low | High |
| **Real replica with VPN-only access** | Fast read | Highest | Inherits prod | Medium |
| **None / empty** | Trivial | None | None | Lowest |

## Per-environment recommendations

| Environment | Default strategy | Notes |
|---|---|---|
| Local dev (laptop) | Synthetic or empty | Real data on laptops is a leak vector |
| Per-developer cloud sandbox | Masked sample | Realistic enough; bounded blast radius |
| Staging / CI | Full masked snapshot | Catch real-data edge cases before prod |
| QA / UAT | Full masked snapshot | Business users need realistic data |
| Prod | n/a | Prod has prod data |

## Masking discipline

Masking is the highest-risk step. Get it wrong and PII lands somewhere it shouldn't. Rules:

1. **Mask at the source-or-snapshot boundary**, not after data has landed in dev. A masking step that happens "later" is a masking step that doesn't happen.
2. **List PII columns by name in a config**, not by heuristic. Auto-detection (regex on column names) misses fields and creates false confidence.
3. **Mask irreversibly**. Hash with salt for join-keys; replace with synthetic values for everything else. Encryption that an attacker could reverse is not masking.
4. **Audit the masking output**. Periodically grep the dev environment for real email patterns, real phone numbers, real names from a known list. Anything found is a masking gap.
5. **Mask in a place the source team controls**, not in the dev environment. Dev should never see the unmasked data, even transiently.

## A sample refresh procedure (staging from prod)

The principle: prod → masking job → staging. Run on a schedule (nightly is typical).

```
┌──────────────────────────┐
│ Prod source              │
└──────────┬───────────────┘
           │ Triggered by orchestrator
           ▼
┌──────────────────────────┐
│ Masking job              │
│ • Reads prod (read-only) │
│ • Applies masking rules  │
│ • Writes to staging      │
│   destination            │
└──────────┬───────────────┘
           │
           ▼
┌──────────────────────────┐
│ Staging                  │
│ • Used by CI, devs       │
│ • Refreshed nightly      │
└──────────────────────────┘
```

The masking job runs with prod-read + staging-write credentials. No other component sees both.

## Sampling strategy

Random sampling is rarely what you want — it destroys join consistency (a user_id in one table won't match the sampled user_id in another).

Better:
1. Sample a population (e.g. random 1% of `users`).
2. Filter all related tables to records linked to that population.
3. Repeat the cascade as needed.

This produces a referentially intact small slice. Snowflake / Postgres support this directly with CTEs and IN clauses; for very large datasets, materialize the sampled-population once and reuse.

## Cost watch

A nightly masked snapshot of a large prod system can be expensive — compute, storage, transfer. Mitigations:

- Snapshot only the tables actually used in non-prod. Don't mirror what nobody queries.
- Differential refresh: only re-write rows that changed since the last refresh.
- TTL the snapshot: retain N days only; older history isn't useful in staging.

Track the cost. A parity flow that doubles the warehouse bill needs review.

## Anti-patterns

- Letting devs run `COPY` from prod themselves "just this once"
- Masking with `REPLACE(col, '@', '_')` style — trivially reversible
- Masking job runs in dev (so dev has access to prod read-only)
- Snapshots that are weeks stale, used as "fresh enough" — dev develops on data that doesn't match prod
- No audit of the masking output — discover the gap during a compliance review
- Per-developer un-masked copies for "debugging" — the worst case

## When parity isn't needed

Some projects don't need data parity:

- New projects with no prod yet — work from synthetic only
- Models that operate on fully synthetic / generated data
- Stress / load tests — generate synthetic at scale; real prod-sized data is rarely needed

Don't build a parity flow just because other projects have one. Start with synthetic; add parity when a specific class of bug shows it's needed.
