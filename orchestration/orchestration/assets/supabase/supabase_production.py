import io
import os
import time
from datetime import date

import boto3
import dagster as dg

from orchestration.resources.supabase_resource import SupabaseResource

SOURCE_NAME = "supabase"
SCHEMA_NAME = "production"
STRATEGY = "full_load"

PRODUCTION_TABLES = ["brands", "categories", "products", "stocks"]

production_partition = dg.StaticPartitionsDefinition(PRODUCTION_TABLES)


@dg.asset(
    name=SCHEMA_NAME,
    key_prefix=["raw", SOURCE_NAME],
    group_name=f"{SOURCE_NAME}_ingestion",
    partitions_def=production_partition,
    kinds={"postgres", "parquet"},
    description=(
        "Full-load ingestion of all tables in the Supabase production schema into MinIO as Parquet. "
        "Each partition corresponds to one table: brands, categories, products, stocks."
    ),
    tags={
        "domain": "product",
        "source_type": "postgres",
        "source_name": SOURCE_NAME,
        "schema_name": SCHEMA_NAME,
        "table_name": "partition",
        "ingestion_strategy": STRATEGY,
        "owner": "data-team",
    },
)
def supabase_production(
    context: dg.AssetExecutionContext,
    supabase: SupabaseResource,
) -> dg.MaterializeResult:
    start_time = time.time()
    table_name: str = context.partition_key
    bucket_name = os.environ["LAKEHOUSE_BUCKET"]

    context.log.info(f"Starting ingestion: {table_name}, strategy={STRATEGY}")

    df = supabase.fetch_all(SCHEMA_NAME, table_name)
    row_count = len(df)

    context.log.info(f"Fetched {row_count} rows from source")

    s3_key = (
        f"raw/{SOURCE_NAME}/{SCHEMA_NAME}/{table_name}/"
        f"ingestion_date={date.today().isoformat()}/"
        f"run_id={context.run_id}/data.parquet"
    )

    s3_client = boto3.client(
        "s3",
        endpoint_url=os.environ["AWS_ENDPOINT_URL"],
        aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
        region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
    )

    parquet_buffer = io.BytesIO()
    df.to_parquet(parquet_buffer, index=False, engine="pyarrow")
    s3_client.put_object(Bucket=bucket_name, Key=s3_key, Body=parquet_buffer.getvalue())

    context.log.info(f"Written to MinIO: s3://{bucket_name}/{s3_key}")

    elapsed = time.time() - start_time
    context.log.info(f"Ingestion complete. Duration: {elapsed:.1f}s")

    return dg.MaterializeResult(
        metadata={
            "row_count": dg.MetadataValue.int(row_count),
            "s3_path": dg.MetadataValue.text(f"s3://{bucket_name}/{s3_key}"),
            "ingestion_strategy": dg.MetadataValue.text(STRATEGY),
            "duration_seconds": dg.MetadataValue.float(round(elapsed, 2)),
            "run_id": dg.MetadataValue.text(context.run_id),
            "source": dg.MetadataValue.text(SOURCE_NAME),
            "schema": dg.MetadataValue.text(SCHEMA_NAME),
            "table": dg.MetadataValue.text(table_name),
        }
    )
