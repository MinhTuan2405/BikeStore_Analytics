{{ config(
    materialized='external',
    location='s3://' ~ env_var('LAKEHOUSE_BUCKET', 'lakehouse') ~ '/staging/' ~ this.name,
    format='parquet'
) }}

with source as (
    {{ latest_full_load('supabase_sales', 'orders') }}
),

cleaned as (
    select
        order_id,
        customer_id,
        order_status,
        case order_status
            when 1 then 'Pending'
            when 2 then 'Processing'
            when 3 then 'Rejected'
            when 4 then 'Completed'
        end                             as order_status_label,
        order_date,
        required_date,
        shipped_date,
        shipped_date is not null        as is_shipped,
        store_id,
        staff_id
    from source
)

select * from cleaned
