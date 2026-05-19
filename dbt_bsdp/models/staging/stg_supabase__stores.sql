{{ config(
    materialized='external',
    location='s3://' ~ env_var('LAKEHOUSE_BUCKET', 'lakehouse') ~ '/staging/' ~ this.name,
    format='parquet'
) }}

with source as (
    {{ latest_full_load('supabase_sales', 'stores') }}
),

cleaned as (
    select
        store_id,
        trim(store_name)            as store_name,
        nullif(trim(phone), '')     as phone,
        nullif(trim(email), '')     as email,
        nullif(trim(street), '')    as street,
        nullif(trim(city), '')      as city,
        upper(trim(state))          as state,
        nullif(trim(zip_code), '')  as zip_code
    from source
)

select * from cleaned
