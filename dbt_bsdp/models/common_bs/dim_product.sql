{{ config(
    materialized='external',
    location='s3://' ~ env_var('LAKEHOUSE_BUCKET', 'lakehouse') ~ '/common_bs/' ~ this.name,
    format='parquet'
) }}

with stg_products as (
    select * from {{ ref('stg_supabase__products') }}
),

stg_brands as (
    select * from {{ ref('stg_supabase__brands') }}
),

stg_categories as (
    select * from {{ ref('stg_supabase__categories') }}
),

enriched as (
    select
        p.product_id,
        p.product_name,
        p.model_year,
        p.list_price,
        b.brand_id,
        b.brand_name,
        c.category_id,
        c.category_name
    from stg_products p
    left join stg_brands     b  using (brand_id)
    left join stg_categories c  using (category_id)
),

missing_member as (
    select
        --Surrogate Key
        {{ dbt_utils.generate_surrogate_key(['-1']) }}  as dim_product_sk,
        --Natural Key
        cast(-1 as integer)                             as product_id,
        --Attributes
        'Unknown Product'                               as product_name,
        cast(null as smallint)                          as model_year,
        cast(null as decimal(10, 2))                    as list_price,
        cast(-1 as integer)                             as brand_id,
        'Unknown Brand'                                 as brand_name,
        cast(-1 as integer)                             as category_id,
        'Unknown Category'                              as category_name
),

final as (
    select
        --Surrogate Key
        {{ dbt_utils.generate_surrogate_key(['product_id']) }}      as dim_product_sk,
        --Natural Key
        product_id,
        --Attributes
        product_name,
        model_year,
        list_price,
        brand_id,
        brand_name,
        category_id,
        category_name
    from enriched
)

select * from missing_member
union all
select * from final
