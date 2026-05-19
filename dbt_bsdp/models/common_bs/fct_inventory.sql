{{ config(
    materialized='external',
    location='s3://' ~ env_var('LAKEHOUSE_BUCKET', 'lakehouse') ~ '/common_bs/' ~ this.name,
    format='parquet'
) }}

with stg_stocks as (
    select * from {{ ref('stg_supabase__stocks') }}
),

stg_products as (
    select product_id, list_price
    from {{ ref('stg_supabase__products') }}
),

final as (
    select
        --Primary Key
        {{ dbt_utils.generate_surrogate_key(['s.store_id', 's.product_id']) }}          as inventory_pk,

        --Foreign Keys
        {{ dbt_utils.generate_surrogate_key(['s.snapshot_date']) }}                     as dim_date_sk,
        {{ dbt_utils.generate_surrogate_key(['s.store_id']) }}                          as dim_store_sk,
        {{ dbt_utils.generate_surrogate_key(['s.product_id']) }}                        as dim_product_sk,

        --Degenerate Dimensions
        s.store_id,
        s.product_id,

        --Dates
        s.snapshot_date,

        --Measures
        s.quantity,
        round(s.quantity * p.list_price, 2)                                             as inventory_value

    from stg_stocks   s
    left join stg_products p  on s.product_id = p.product_id
)

select * from final
