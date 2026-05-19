Materialize one or more Dagster assets locally.

Asset selection: $ARGUMENTS

## Steps

1. If $ARGUMENTS is empty, list available assets and ask the user which to run:
   ```bash
   cd orchestration && uv run dg list defs --json
   ```

2. Launch the asset(s). Use `+asset_key` to include downstream, `asset_key+` for upstream:
   ```bash
   cd orchestration && uv run dg launch --assets "$ARGUMENTS"
   ```

3. Report the final status (success / failure). If the run fails, read the relevant compute log and suggest a fix based on the error.
