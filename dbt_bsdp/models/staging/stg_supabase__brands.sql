{{ config(
    materialized='external',
    location='s3://' ~ env_var('LAKEHOUSE_BUCKET', 'lakehouse') ~ '/staging/' ~ this.name,
    format='parquet'
) }}

with source as (
    {{ latest_full_load('supabase_production', 'brands') }}
),

cleaned as (
    select
        brand_id,
        trim(brand_name) as brand_name
    from source
)

select * from cleaned
