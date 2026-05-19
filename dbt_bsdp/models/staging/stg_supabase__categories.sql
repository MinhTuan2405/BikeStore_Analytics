{{ config(
    materialized='external',
    location='s3://' ~ env_var('LAKEHOUSE_BUCKET', 'lakehouse') ~ '/staging/' ~ this.name,
    format='parquet'
) }}

with source as (
    {{ latest_full_load('supabase_production', 'categories') }}
),

cleaned as (
    select
        category_id,
        trim(category_name) as category_name
    from source
)

select * from cleaned
