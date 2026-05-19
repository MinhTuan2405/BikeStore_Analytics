{{ config(
    materialized='external',
    location='s3://' ~ env_var('LAKEHOUSE_BUCKET', 'lakehouse') ~ '/staging/' ~ this.name,
    format='parquet'
) }}

with source as (
    {{ latest_full_load('supabase_sales', 'staffs') }}
),

cleaned as (
    select
        staff_id,
        trim(first_name)                                as first_name,
        trim(last_name)                                 as last_name,
        trim(first_name) || ' ' || trim(last_name)     as full_name,
        lower(trim(email))                              as email,
        nullif(trim(phone), '')                         as phone,
        active = 1                                      as is_active,
        store_id,
        manager_id
    from source
)

select * from cleaned
