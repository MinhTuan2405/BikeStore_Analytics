{{ config(
    materialized='external',
    location='s3://' ~ env_var('LAKEHOUSE_BUCKET', 'lakehouse') ~ '/staging/' ~ this.name,
    format='parquet'
) }}

with source as (
    {{ latest_full_load('supabase_production', 'products') }}
),

cleaned as (
    select
        product_id,
        trim(product_name)  as product_name,
        brand_id,
        category_id,
        model_year,
        list_price
    from source
)

select * from cleaned
