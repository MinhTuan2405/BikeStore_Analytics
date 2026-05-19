{{ config(
    materialized='external',
    location='s3://' ~ env_var('LAKEHOUSE_BUCKET', 'lakehouse') ~ '/common_bs/' ~ this.name,
    format='parquet'
) }}

with stg_orders as (
    select * from {{ ref('stg_supabase__orders') }}
),

stg_order_items as (
    select * from {{ ref('stg_supabase__order_items') }}
),

final as (
    select
        --Primary Key
        {{ dbt_utils.generate_surrogate_key(['oi.order_id', 'oi.item_id']) }}           as sales_pk,

        --Foreign Keys
        {{ dbt_utils.generate_surrogate_key(['o.order_date']) }}                         as dim_date_sk,
        {{ get_keyed_nulls('o.customer_id') }}                                           as dim_customer_sk,
        {{ dbt_utils.generate_surrogate_key(['oi.product_id']) }}                        as dim_product_sk,
        {{ dbt_utils.generate_surrogate_key(['o.store_id']) }}                           as dim_store_sk,
        {{ dbt_utils.generate_surrogate_key(['o.staff_id']) }}                           as dim_staff_sk,

        --Degenerate Dimensions
        oi.order_id,
        oi.item_id,
        o.order_status,
        o.order_status_label,
        o.is_shipped,

        --Dates
        o.order_date,
        o.required_date,
        o.shipped_date,

        --Measures
        oi.quantity,
        oi.list_price,
        oi.discount,
        oi.line_total

    from stg_order_items   oi
    inner join stg_orders  o  on oi.order_id = o.order_id
)

select * from final
