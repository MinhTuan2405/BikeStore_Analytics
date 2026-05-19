import io
import os
import time
from datetime import date

import boto3
import dagster as dg

from orchestration.resources.dummyjson_resource import DummyjsonResource

SOURCE_NAME = "dummyjson"
SCHEMA_NAME = "api"
TABLE_NAME = "products"
STRATEGY = "full_load"


@dg.asset(
    name="api_products",
    key_prefix=["raw", SOURCE_NAME],
    group_name=f"{SOURCE_NAME}_ingestion",
    kinds={"rest_api", "parquet"},
    description=(
        "Full-load ingestion of all products from the dummyjson.com REST API into MinIO as Parquet. "
        "Nested scalar fields (dimensions, meta) are flattened with underscore separator; "
        "reviews, tags, and images are stored as list columns."
    ),
    tags={
        "domain": "product",
        "source_type": "rest_api",
        "source_name": SOURCE_NAME,
        "schema_name": SCHEMA_NAME,
        "table_name": TABLE_NAME,
        "ingestion_strategy": STRATEGY,
        "owner": "data-team",
    },
)
def dummyjson_api_products(
    context: dg.AssetExecutionContext,
    dummyjson: DummyjsonResource,
) -> dg.MaterializeResult:
    start_time = time.time()
    bucket_name = os.environ["LAKEHOUSE_BUCKET"]

    context.log.info(f"Starting ingestion: {TABLE_NAME}, strategy={STRATEGY}")

    df = dummyjson.fetch_products()
    row_count = len(df)

    context.log.info(f"Fetched {row_count} rows from source")

    s3_key = (
        f"raw/{SOURCE_NAME}/{SCHEMA_NAME}/{TABLE_NAME}/"
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
            "table": dg.MetadataValue.text(TABLE_NAME),
        }
    )
