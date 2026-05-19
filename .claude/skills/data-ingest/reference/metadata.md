# Asset Metadata Schema

Every ingestion asset must carry standardized metadata for discoverability, ownership, and lineage.

---

## Tags on `@dg.asset`

Apply as the `tags=` parameter:

```python
@dg.asset(
    ...
    tags={
        "domain": "<domain>",                    # business domain — see table below
        "source_type": "<source_type>",          # technical source category
        "source_name": "<source_name>",          # datasource identifier, e.g. "supabase_prod"
        "schema_name": "<schema_name>",          # database schema or namespace, e.g. "public"
        "table_name": "<table_name>",            # table, endpoint, or file name
        "ingestion_strategy": "<strategy>",      # see strategies.md
        "owner": "<team_or_person>",             # e.g. "data-team", "analytics", "john.doe"
    },
)
```

### Valid `domain` Values
| Value | Description |
|-------|-------------|
| `sales` | Orders, revenue, quotes, pipelines |
| `marketing` | Campaigns, leads, attribution, email |
| `product` | Feature usage, events, sessions, experiments |
| `finance` | Payments, invoices, accounting, billing |
| `ops` | Operations, logistics, fulfillment, inventory |
| `hr` | People data, org structure, payroll |
| `platform` | Infrastructure, system metrics, audit logs |

### Valid `source_type` Values
`postgres`, `mysql`, `rest_api`, `csv`, `gsheet`, `mongodb`, `bigquery`, `snowflake`, `other`

### Valid `ingestion_strategy` Values
`full_load`, `incremental`, `append_only`, `delete_insert`, `cdc`, `snapshot`

---

## `MaterializeResult` Metadata

Return this from every asset's `@dg.asset` function:

```python
import time
import dagster as dg

return dg.MaterializeResult(
    metadata={
        "row_count": dg.MetadataValue.int(row_count),
        "s3_path": dg.MetadataValue.text(s3_path),
        "ingestion_strategy": dg.MetadataValue.text(strategy),
        "duration_seconds": dg.MetadataValue.float(round(elapsed, 2)),
        "run_id": dg.MetadataValue.text(context.run_id),
        "source": dg.MetadataValue.text(source_name),
        "schema": dg.MetadataValue.text(schema_name),
        "table": dg.MetadataValue.text(table_name),
    }
)
```

Where `elapsed = time.time() - start_time` and `start_time` is captured at the top of the asset function.

---

## State File Schema (incremental strategy)

Written to `ingestion/state/{source}/{schema}/{table}/state.json`:

```json
{
  "last_watermark": "<ISO timestamp or integer>",
  "last_run_id": "<dagster run_id>",
  "last_run_at": "<ISO timestamp>",
  "row_count": 12345
}
```
