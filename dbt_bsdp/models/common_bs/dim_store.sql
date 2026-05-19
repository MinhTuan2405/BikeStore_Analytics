{{ config(
    materialized='external',
    location='s3://' ~ env_var('LAKEHOUSE_BUCKET', 'lakehouse') ~ '/common_bs/' ~ this.name,
    format='parquet'
) }}

with stg_stores as (
    select * from {{ ref('stg_supabase__stores') }}
),

missing_member as (
    select
        --Surrogate Key
        {{ dbt_utils.generate_surrogate_key(['-1']) }}  as dim_store_sk,
        --Natural Key
        cast(-1 as integer)                             as store_id,
        --Attributes
        'Unknown Store'                                 as store_name,
        cast(null as varchar)                           as phone,
        cast(null as varchar)                           as email,
        cast(null as varchar)                           as street,
        cast(null as varchar)                           as city,
        cast(null as varchar)                           as state,
        cast(null as varchar)                           as zip_code
),

final as (
    select
        --Surrogate Key
        {{ dbt_utils.generate_surrogate_key(['store_id']) }}        as dim_store_sk,
        --Natural Key
        store_id,
        --Attributes
        store_name,
        phone,
        email,
        street,
        city,
        state,
        zip_code
    from stg_stores
)

select * from missing_member
union all
select * from final
