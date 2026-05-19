# Per-Source Asset Pattern

The `assets/<source>/` package is the unit of "a thing we ingest". Same pattern, every source.

## Minimal package

```
assets/paypal/
├── __init__.py           # empty or re-exports
└── paypal_data.py        # @asset functions
```

`__init__.py` can be empty — Dagster's `load_assets_from_package_module` walks the package and picks up every `@asset`. Add re-exports only if it improves IDE navigation.

## Anatomy of an asset file

```python
# assets/paypal/paypal_data.py
from dagster import asset, DailyPartitionsDefinition, MetadataValue, Output, get_dagster_logger
from ...resources.paypal_resource import PaypalAPIClient
from ...utils import s3_utils, utils

logger = get_dagster_logger()

@asset(
    description="PayPal daily transactions",
    io_manager_key="io_manager",
    compute_kind="python",
    partitions_def=DailyPartitionsDefinition(start_date="2026-02-01"),
    group_name="paypal_daily_ingestion",
)
def paypal_data(context):
    partition_date = context.asset_partition_key_for_output()
    start = s3_utils.convert_date(partition_date, "%Y-%m-%dT00:00:00Z")
    end = s3_utils.convert_date(partition_date, "%Y-%m-%dT23:59:59Z")

    client = PaypalAPIClient(base_url="https://api-m.paypal.com", start_date=start, end_date=end)
    transactions = client.get_transactions()

    file_names = utils.save_data(
        result_final=transactions,
        date=start,
        output_dir="orchestration/assets/paypal/tmp_paypal",
        type="daily",
        ...
    )

    return Output(
        value=file_names,
        metadata={
            "num_records": len(transactions),
            "preview": MetadataValue.md(...),
        },
    )
```

Pattern points (mandatory):
- `group_name` = `<source>_<cadence>_ingestion`. Drives job selection.
- `description` describes what the asset is, not how it works.
- The **client comes from `resources/`** (Rule 2). Never instantiate API auth / pagination logic in the asset.
- Date / file helpers come from `utils/` (Rule 5).
- Return `Output(value=..., metadata={...})` so the UI shows record counts, previews, schema info.
- Use `get_dagster_logger()` — Dagster's logger has run/asset context for free.

## Variations by source type

### API source

```python
@asset(group_name="paypal_daily_ingestion", partitions_def=DailyPartitionsDefinition(...))
def paypal_data(context):
    client = PaypalAPIClient(...)
    return Output(value=client.get_transactions(), metadata={...})
```

### FTP / SFTP source

```python
@asset(group_name="akamai_fw_daily_ingestion", partitions_def=DailyPartitionsDefinition(...))
def akamai_fw_data(context):
    client = FTPClient(project="akamai_fw", dirname="logs")  # from resources/akamai_resource.py
    files = client.download_files_after(date=context.asset_partition_key_for_output())
    return Output(value=files, metadata={"file_count": len(files)})
```

### Database CDC / SQL source

```python
@asset(group_name="oracle_inventory_daily_ingestion", partitions_def=...)
def oracle_inventory(context):
    client = OracleClient(...)  # from resources/oracle_resource.py
    df = client.fetch_inventory_for(date=context.asset_partition_key_for_output())
    return Output(value=df, metadata={"row_count": len(df)})
```

### Multi-partition source

```python
@asset(
    group_name="impact_radius_click_daily_ingestion",
    partitions_def=MultiPartitionsDefinition({
        "date": DailyPartitionsDefinition(start_date="2026-01-01"),
        "brand": StaticPartitionsDefinition(["SCUF", "ELGATO", "CORSAIR"]),
    }),
)
def impact_radius_click(context):
    keys = context.partition_key.keys_by_dimension
    date, brand = keys["date"], keys["brand"]
    client = ImpactRadiusClient(brand=brand)
    return Output(value=client.fetch_clicks(date=date), metadata={...})
```

### Loader-then-load split (when staging matters)

When the asset writes raw to object storage *then* loads to warehouse, model it as two assets with an explicit edge:

```python
@asset(group_name="zendesk_daily_ingestion", ...)
def zendesk_raw(context): ...   # writes to S3/MinIO

@asset(group_name="zendesk_daily_ingestion", ...)
def zendesk_loaded(context, zendesk_raw):
    sf = context.resources.connect_snowflake.snowpark_session
    sf.write_pandas(zendesk_raw, "ZENDESK_RAW", ...)
```

Two assets in the same group are fine — selection by group still picks both, and the edge gives Dagster lineage.

## Anti-patterns

- API auth code inside `@asset` — belongs in the Resource client
- `requests.get()` calls inlined in the asset body — same as above
- One asset per API endpoint when the data is essentially the same shape — collapse via partitions or a parameterized asset factory
- Hardcoded date strings in the asset — use `context.asset_partition_key_for_output()` and the date helpers in `utils/`
- Saving to disk paths that aren't under the asset's own folder — use the project's `utils.save_data` with `output_dir="orchestration/assets/<source>/..."` so cleanup is local
- Mixing two unrelated sources in one package (`assets/paypal/` containing both Paypal and a Stripe asset) — each source gets its own package, even if they share a client
