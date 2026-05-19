{% macro latest_full_load(source_name, table_name) %}
(
    with _all as (
        select *
        from {{ source(source_name, table_name) }}
    ),
    _max_date as (
        select max(ingestion_date) as cutoff
        from _all
    )
    select _all.*
    from _all
    inner join _max_date
        on _all.ingestion_date = _max_date.cutoff
)
{% endmacro %}
