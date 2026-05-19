Scaffold a new Dagster software-defined asset into `orchestration/src/orchestration/defs/`.

Asset name or description from the user: $ARGUMENTS

## Steps

1. If $ARGUMENTS is empty, ask the user for the asset name (snake_case) and what it produces (table, file, model).

2. Check available component types:
   ```bash
   cd orchestration && uv run dg list components --json
   ```

3. Scaffold the new definitions using the appropriate component type:
   ```bash
   cd orchestration && uv run dg scaffold defs <ComponentType> <asset_name>
   ```
   For a plain Python asset with no integration component, use the closest matching type or create a bare asset file directly under `defs/`.

4. Show the generated files to the user. Explain any config values they need to fill in.

5. Ask if the asset needs: upstream dependencies, partitions, group name, or tags. Apply those to the scaffolded code.

6. Verify the new definition is registered:
   ```bash
   cd orchestration && uv run dg list defs --json
   ```
