{{ config(
    materialized='external',
    location='s3://' ~ env_var('LAKEHOUSE_BUCKET', 'lakehouse') ~ '/staging/' ~ this.name,
    format='parquet'
) }}

with source as (
    {{ latest_full_load('supabase_sales', 'order_items') }}
),

cleaned as (
    select
        order_id,
        item_id,
        product_id,
        quantity,
        list_price,
        discount,
        round(quantity * list_price * (1 - discount), 2)   as line_total
    from source
)

select * from cleaned
