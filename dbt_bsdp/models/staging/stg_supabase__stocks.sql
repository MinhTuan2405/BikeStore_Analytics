{{ config(
    materialized='external',
    location='s3://' ~ env_var('LAKEHOUSE_BUCKET', 'lakehouse') ~ '/staging/' ~ this.name,
    format='parquet'
) }}

with source as (
    {{ latest_full_load('supabase_production', 'stocks') }}
),

cleaned as (
    select
        store_id,
        product_id,
        coalesce(quantity, 0)   as quantity,
        ingestion_date          as snapshot_date
    from source
)

select * from cleaned
