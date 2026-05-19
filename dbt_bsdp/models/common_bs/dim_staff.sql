{{ config(
    materialized='external',
    location='s3://' ~ env_var('LAKEHOUSE_BUCKET', 'lakehouse') ~ '/common_bs/' ~ this.name,
    format='parquet'
) }}

with stg_staffs as (
    select * from {{ ref('stg_supabase__staffs') }}
),

-- Self-join to flatten one level of the manager hierarchy
manager_lookup as (
    select
        staff_id                                                    as manager_staff_id,
        full_name                                                   as manager_full_name,
        {{ dbt_utils.generate_surrogate_key(['staff_id']) }}        as manager_dim_staff_sk
    from stg_staffs
),

missing_member as (
    select
        --Surrogate Key
        {{ dbt_utils.generate_surrogate_key(['-1']) }}  as dim_staff_sk,
        --Natural Key
        cast(-1 as integer)                             as staff_id,
        --Attributes
        'Unknown'                                       as first_name,
        'Unknown'                                       as last_name,
        'Unknown Staff'                                 as full_name,
        cast(null as varchar)                           as email,
        cast(null as varchar)                           as phone,
        false                                           as is_active,
        cast(-1 as integer)                             as store_id,
        cast(null as integer)                           as manager_id,
        {{ dbt_utils.generate_surrogate_key(['-1']) }}  as manager_dim_staff_sk,
        cast(null as varchar)                           as manager_full_name
),

final as (
    select
        --Surrogate Key
        {{ dbt_utils.generate_surrogate_key(['s.staff_id']) }}      as dim_staff_sk,
        --Natural Key
        s.staff_id,
        --Attributes
        s.first_name,
        s.last_name,
        s.full_name,
        s.email,
        s.phone,
        s.is_active,
        s.store_id,
        s.manager_id,
        {{ get_keyed_nulls('s.manager_id') }}                       as manager_dim_staff_sk,
        m.manager_full_name
    from stg_staffs         s
    left join manager_lookup m  on s.manager_id = m.manager_staff_id
)

select * from missing_member
union all
select * from final
