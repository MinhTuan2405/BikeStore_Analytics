{{ config(
    materialized='external',
    location='s3://' ~ env_var('LAKEHOUSE_BUCKET', 'lakehouse') ~ '/common_bs/' ~ this.name,
    format='parquet'
) }}

with stg_customers as (
    select * from {{ ref('stg_supabase__customers') }}
),

missing_member as (
    select
        --Surrogate Key
        {{ dbt_utils.generate_surrogate_key(['-1']) }}  as dim_customer_sk,
        --Natural Key
        cast(-1 as integer)                             as customer_id,
        --Attributes
        'Unknown'                                       as first_name,
        'Unknown'                                       as last_name,
        'Unknown Customer'                              as full_name,
        cast(null as varchar)                           as email,
        cast(null as varchar)                           as phone,
        cast(null as varchar)                           as street,
        cast(null as varchar)                           as city,
        cast(null as varchar)                           as state,
        cast(null as varchar)                           as zip_code
),

final as (
    select
        --Surrogate Key
        {{ dbt_utils.generate_surrogate_key(['customer_id']) }}     as dim_customer_sk,
        --Natural Key
        customer_id,
        --Attributes
        first_name,
        last_name,
        full_name,
        email,
        phone,
        street,
        city,
        state,
        zip_code
    from stg_customers
)

select * from missing_member
union all
select * from final
