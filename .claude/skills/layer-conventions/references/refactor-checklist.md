# Refactor Checklist — Cleaning Up a Project with Convention Drift

A project that has grown without discipline typically shows: staging models doing joins, marts reading from raw, schema names without layer prefixes, inconsistent table naming. This checklist sequences the cleanup so the project keeps working at every step.

## Phase 1 — Inventory

Before touching anything:

1. List every schema and how many tables it contains.
2. List every model file and grep for the layer prefix (`stg_`, `int_`, no prefix).
3. Map each model's actual layer by reading its `from` clauses, not just its filename:
   - Reads from `source()` only → staging
   - Reads from staging models → intermediate
   - Reads from intermediate / staging → marts
   - Reads from marts → ad-hoc or misplaced
4. Identify the **mismatches**: model named `stg_*` but doing intermediate work, model in `marts/` reading from sources, etc.

Output: a spreadsheet with one row per model — current location, true layer (inferred from references), planned new location.

## Phase 2 — Stop the bleeding

Make sure new work follows the convention before fixing old:

1. Add a `.sqlfluff` or `dbt-coves` rule that enforces the naming pattern (`stg_<source>__*`, `int_<domain>__*`, `fct_*` / `dim_*`).
2. Add a CI check: any new model in `models/staging/` that contains a `join` fails the build.
3. Document the conventions in a `CONTRIBUTING.md` so PRs are reviewable against the rule.

Until these are in place, refactoring is a treadmill.

## Phase 3 — Move models, layer by layer

Order matters. Fix the deepest dependency first.

1. **Sources first.** Define source freshness, generate `sources.yml` for every raw table. This is non-breaking — adds metadata, doesn't move data.
2. **Staging next.** For each misplaced model:
   - If it does joins, extract the join into an intermediate model first, then convert the original to a thin staging view.
   - If it does aggregation, move it to marts.
   - Rename to the convention (`stg_<source>__<entity>`).
   - Schema config moves to `staging`.
3. **Intermediate.** Models that exist but live in marts: move them, rename, mark as `view` / `ephemeral`.
4. **Marts.** Final stop. Rename to Kimball conventions if not already.

Each move is a single PR. Don't try to land the refactor in one commit — the diff is unreviewable and bisecting a regression takes forever.

## Phase 4 — Schema renames

Schema renames break consumers. Treat them as breaking changes:

1. Announce the rename — schema `analytics` → `marts_finance`, two-week deprecation window.
2. Create the new schema; populate via materialization.
3. Create views in the old schema pointing at the new schema's tables.
4. Update BI / API consumers to the new schema.
5. Drop the old-schema views after the deprecation window closes.

Never rename schemas without overlap. Anything that queries by hard-coded schema name will silently fail.

## Phase 5 — Documentation backfill

Once the structure is right, document:

- Each schema's purpose (one line)
- Each mart's contract (input layer, refresh schedule, downstream consumers)
- The layer-naming rules in `CONTRIBUTING.md` so this drift doesn't recur

## Anti-patterns when refactoring

- **Big-bang refactor in one PR.** Unreviewable; rollbacks are nightmarish. Move one layer per PR.
- **Renaming without the staging period.** Consumers break overnight; you lose trust.
- **Adding "TODO" comments instead of doing the move.** Drift accumulates; the rule erodes.
- **Skipping the lint / CI rules in Phase 2.** New drift will out-pace cleanup.

## Signs the refactor is done

- Every model file matches its layer's naming convention.
- `dbt ls --resource-type model` grouped by directory matches the layer breakdown.
- A new contributor reading `CONTRIBUTING.md` can place a new model in the right layer without asking.
- Schema names carry their layer.
- No `fct_*` reads from `raw_*`; no `stg_*` does a join.

When the inventory spreadsheet has zero mismatches, the refactor is done. Lock the conventions in CI and move on.
