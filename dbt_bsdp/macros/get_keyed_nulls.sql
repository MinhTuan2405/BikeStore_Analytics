{% macro get_keyed_nulls(column_expr) %}
    case
        when ({{ column_expr }}) is null
            then {{ dbt_utils.generate_surrogate_key(['-1']) }}
        else {{ dbt_utils.generate_surrogate_key([column_expr]) }}
    end
{% endmacro %}
