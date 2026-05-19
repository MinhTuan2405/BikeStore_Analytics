# Decision Matrix — Side-by-Side

Coarse comparison. Treat each cell as an order-of-magnitude indicator, not a precise measurement.

## Cost & complexity

| Archetype | Setup cost | Operating cost | Operational complexity | Vendor lock-in |
|---|---|---|---|---|
| `portable-duckdb` | Minutes | $0 (laptop) | Trivial | None |
| `local-lake` | 1–3 days | $0 (laptop) | Medium-high (catalog, engine) | Low (open formats) |
| `snowflake-dwh` | Hours | $$$ — credits scale with usage | Low (managed) | High (Snowflake) |
| `postgres-warehouse` | Hours | $ (VM cost) | Medium (indexes, vacuum, backups) | Low (Postgres anywhere) |
| `hybrid-snowflake-local` | Days | $$ (split) | High (two stacks) | Medium |
| `streaming-first` | Weeks | $$$ + ops time | Very high | Varies |
| `transformation-only` | Hours | Borne by upstream | Low | Inherits upstream's |

## Scale & performance

| Archetype | Practical data ceiling | Concurrent users | Query latency | Freshness |
|---|---|---|---|---|
| `portable-duckdb` | ~100 GB | 1 | Fast on local data | Manual |
| `local-lake` | ~1 TB on laptop | A few | Engine-dependent (Trino fast, DuckDB faster) | Hourly typical |
| `snowflake-dwh` | PB+ | Hundreds | Fast at higher warehouse size | Minutes possible |
| `postgres-warehouse` | ~1 TB before pain | Tens | Index-dependent | Minutes |
| `hybrid-snowflake-local` | PB+ (prod), GB (local) | As Snowflake | As Snowflake | As Snowflake |
| `streaming-first` | Limited by infra | Many | Sub-second | Sub-minute |
| `transformation-only` | As upstream | As upstream | As upstream | As upstream |

## Team fit

| Archetype | Solo OK | Team of 2–5 | Team 5+ | Need on-call experience |
|---|---|---|---|---|
| `portable-duckdb` | ✓ | Painful (sharing) | No | No |
| `local-lake` | ✓ | OK with shared infra | OK | Some |
| `snowflake-dwh` | ✓ (cost-watch) | ✓ | ✓ | Minimal |
| `postgres-warehouse` | ✓ | ✓ | Stretches | Moderate |
| `hybrid-snowflake-local` | Overkill | ✓ | ✓ | Moderate |
| `streaming-first` | No | Stretches | ✓ | Yes |
| `transformation-only` | ✓ | ✓ | ✓ | No |

## Suitability for common goals

| Goal | Top picks |
|---|---|
| Learn data engineering hands-on | `portable-duckdb` then `local-lake` |
| Ship to prod in a week | `snowflake-dwh` or `transformation-only` |
| No vendor lock-in | `local-lake`, `cloud-lake` (similar archetype on managed cloud storage), `postgres-warehouse` |
| Lowest cost in prod | `postgres-warehouse` |
| Future-proof for scale | `snowflake-dwh` or `local-lake` (→ `cloud-lake`) |
| Real-time | `streaming-first` only |
