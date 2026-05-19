{{ config(
    materialized='external',
    location='s3://' ~ env_var('LAKEHOUSE_BUCKET', 'lakehouse') ~ '/common_bs/' ~ this.name,
    format='parquet'
) }}

with date_spine as (
    select (date '2015-01-01' + cast(n as integer))::date as date_day
    from generate_series(0, 7304) t(n)
),

missing_member as (
    select
        --Surrogate Key
        {{ dbt_utils.generate_surrogate_key(['-1']) }}  as dim_date_sk,
        --Natural Key
        cast(null as date)                              as date_day,
        --Attributes
        cast(null as integer)                           as year_number,
        cast(null as integer)                           as quarter_number,
        cast(null as varchar)                           as quarter_label,
        cast(null as integer)                           as month_number,
        cast(null as varchar)                           as month_name,
        cast(null as integer)                           as week_of_year,
        cast(null as integer)                           as day_of_month,
        cast(null as integer)                           as day_of_week,
        cast(null as varchar)                           as day_name,
        cast(null as boolean)                           as is_weekend
),

final as (
    select
        --Surrogate Key
        {{ dbt_utils.generate_surrogate_key(['date_day']) }}                            as dim_date_sk,
        --Natural Key
        date_day,
        --Attributes
        extract(year    from date_day)::integer                                         as year_number,
        extract(quarter from date_day)::integer                                         as quarter_number,
        'Q' || cast(extract(quarter from date_day) as varchar)                         as quarter_label,
        extract(month   from date_day)::integer                                         as month_number,
        strftime(date_day, '%B')                                                        as month_name,
        extract(week    from date_day)::integer                                         as week_of_year,
        extract(day     from date_day)::integer                                         as day_of_month,
        extract(dayofweek from date_day)::integer                                       as day_of_week,
        strftime(date_day, '%A')                                                        as day_name,
        extract(dayofweek from date_day) in (0, 6)                                     as is_weekend
    from date_spine
)

select * from missing_member
union all
select * from final
