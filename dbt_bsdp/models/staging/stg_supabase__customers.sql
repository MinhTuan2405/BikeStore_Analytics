{{ config(
    materialized='external',
    location='s3://' ~ env_var('LAKEHOUSE_BUCKET', 'lakehouse') ~ '/staging/' ~ this.name,
    format='parquet'
) }}

with source as (
    {{ latest_full_load('supabase_sales', 'customers') }}
),

cleaned as (
    select
        customer_id,
        trim(first_name)                                as first_name,
        trim(last_name)                                 as last_name,
        trim(first_name) || ' ' || trim(last_name)     as full_name,
        lower(trim(email))                              as email,
        nullif(trim(phone), '')                         as phone,
        nullif(trim(street), '')                        as street,
        nullif(trim(city), '')                          as city,
        upper(trim(state))                              as state,
        nullif(trim(zip_code), '')                      as zip_code
    from source
)

select * from cleaned
