# dbt Layer Mapping — Directory and Config

Reference layout for a dbt project that follows `staging` / `intermediate` / `marts`. The directory shape **is** the convention — agents and humans both navigate by path.

## Directory layout

```
models/
├── staging/
│   ├── stripe/
│   │   ├── _stripe__sources.yml         # source definitions
│   │   ├── _stripe__models.yml          # model docs + tests
│   │   ├── stg_stripe__charges.sql
│   │   ├── stg_stripe__customers.sql
│   │   └── stg_stripe__refunds.sql
│   └── postgres_app/
│       ├── _postgres_app__sources.yml
│       ├── _postgres_app__models.yml
│       └── stg_postgres_app__users.sql
├── intermediate/
│   ├── finance/
│   │   ├── _int_finance__models.yml
│   │   ├── int_orders__joined_payments.sql
│   │   └── int_refunds__deduplicated.sql
│   └── product/
│       ├── _int_product__models.yml
│       └── int_users__sessionized.sql
└── marts/
    ├── finance/
    │   ├── _finance__models.yml
    │   ├── fct_revenue.sql
    │   └── dim_customer.sql
    └── product/
        ├── _product__models.yml
        └── fct_user_activity.sql
```

## File naming rules

- One leading underscore on YAML files (`_stripe__sources.yml`) — file system sorts them to the top of the directory.
- Double underscore (`__`) separates category from entity. Single underscores within each side.
- Always snake_case for both filenames and identifiers inside.

## `dbt_project.yml` materialization defaults

Set materialization per layer. Override on individual models when needed:

```yaml
models:
  <project_name>:
    staging:
      +materialized: view
      +schema: staging
    intermediate:
      +materialized: ephemeral   # or `view` for debuggability
      +schema: intermediate
    marts:
      +materialized: table
      +schema: marts
      finance:
        +schema: marts_finance
      product:
        +schema: marts_product
```

Reasoning:
- Staging as `view`: cheap, reflects source immediately, no storage cost. Switch to `table` only when the source is gigantic and a downstream model scans it many times.
- Intermediate as `ephemeral`: no materialization, inlined into downstream. Use `view` instead when ephemeral is hard to debug (most projects switch).
- Marts as `table`: read often by BI / API, materialization cost is paid back.

## Source declarations (raw)

```yaml
# models/staging/stripe/_stripe__sources.yml
version: 2

sources:
  - name: stripe
    schema: raw_stripe         # or bronze_stripe
    description: "Stripe payment data loaded by dlt"
    freshness:
      warn_after: { count: 6, period: hour }
      error_after: { count: 24, period: hour }
    tables:
      - name: charges
        loaded_at_field: _dlt_load_id
      - name: customers
      - name: refunds
```

- `source` schema is the loader's destination. `staging` reads via `{{ source('stripe', 'charges') }}`.
- Freshness checks belong on sources, not staging. They catch ingestion lag at the right layer.

## Staging model pattern

```sql
-- models/staging/stripe/stg_stripe__charges.sql
with source as (
    select * from {{ source('stripe', 'charges') }}
),
renamed as (
    select
        id::varchar              as charge_id,
        customer_id::varchar     as customer_id,
        amount::numeric / 100    as amount_usd,         -- Stripe stores cents
        status::varchar          as status,
        created::timestamp       as created_at,
        _dlt_load_id::varchar    as loaded_at
    from source
)
select * from renamed
```

Pattern rules:
- CTEs named `source`, `renamed` (or `cleaned`, `casted`) — readable, conventional
- One source per model — no joins
- Type casts explicit in the rename CTE — no surprise types downstream
- Rename `id` to `<entity>_id` — `charge_id` not `id`

## Intermediate model pattern

```sql
-- models/intermediate/finance/int_orders__joined_payments.sql
{{ config(materialized='view') }}

with orders as (
    select * from {{ ref('stg_postgres_app__orders') }}
),
payments as (
    select * from {{ ref('stg_stripe__charges') }} where status = 'succeeded'
),
joined as (
    select
        o.order_id,
        o.customer_id,
        o.order_at,
        p.charge_id,
        p.amount_usd,
        p.created_at as paid_at
    from orders o
    left join payments p on p.charge_id = o.stripe_charge_id
)
select * from joined
```

Pattern rules:
- `ref()` for staging / intermediate inputs, never `source()` (sources only appear in staging)
- Joins are explicit; fan-out tested via uniqueness on the resulting key
- Filters that constrain the source population live here when they're business-logic (not data-cleanup)

## Mart model pattern

```sql
-- models/marts/finance/fct_revenue.sql
{{ config(materialized='table') }}

with orders_with_payments as (
    select * from {{ ref('int_orders__joined_payments') }}
),
revenue as (
    select
        date_trunc('day', paid_at)::date as revenue_date,
        customer_id,
        sum(amount_usd) as revenue_usd,
        count(*) as paid_order_count
    from orders_with_payments
    where paid_at is not null
    group by 1, 2
)
select * from revenue
```

Pattern rules:
- Reads from intermediate / staging — not from sources
- Aggregations and metric shapes live here
- Naming follows Kimball: `fct_` for facts, `dim_` for dimensions, `agg_` / `mtr_` for aggregates / metrics

## Tests by layer

| Layer | Tests |
|---|---|
| Source | Freshness, optional row count |
| Staging | Primary key uniqueness, not-null on key columns, accepted-value enums |
| Intermediate | Join fan-out, key integrity, referential where applicable |
| Marts | Business-logic reconciliation, completeness, optional `dbt-expectations` style checks |

Schema YAMLs at each layer carry the tests. Keep tests close to the models they cover.

## Avoiding cross-layer leaks

A staging model that reads from `marts` is a mistake — invert the reference and put the shared logic in intermediate. dbt's `--exclude-resource-type model` plus `dbt deps` analysis catches these in CI.

## Going further

For incremental strategies, snapshot patterns, semantic-layer integration, see the `dbt@dbt-agent-marketplace` plugin — owns those details. This reference covers the layer convention only.
