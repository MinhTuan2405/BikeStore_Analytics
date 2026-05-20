# Inventory Status Dashboard — Metric Definitions

Primary fact table: `fct_inventory` (grain: one row per store × product combination per snapshot)

---

## KPI Cards

| KPI | Formula | Source columns |
|---|---|---|
| **Total Units on Hand** | `SUM(quantity)` | `fct_inventory.quantity` |
| **Total Inventory Value** | `SUM(inventory_value)` | `fct_inventory.inventory_value` |
| **Low Stock Alerts** | `COUNT(*) WHERE quantity <= threshold` | `fct_inventory.quantity` |
| **Stores Covered** | `COUNT(DISTINCT store_id)` | `fct_inventory.store_id` |

**`inventory_value` computation** (from `fct_inventory` model):
```
ROUND(quantity * dim_product.list_price, 2)
```

> Uses the **current** `list_price` from `dim_product` at the time the dbt model runs,
> not a historical price. If a product's price changes between ingestion runs, earlier
> snapshots will show different values after a full refresh.

**`quantity` handling:** NULL quantities in the source (`production.stocks`) are coalesced to 0
in the staging layer before reaching `fct_inventory`.

---

## Charts

### Inventory Value by Store — Vertical Bar Chart

Compares the estimated retail value of stock held at each location.

```sql
SELECT
    st.store_name,
    SUM(i.inventory_value) AS store_inventory_value
FROM fct_inventory i
JOIN dim_store st ON i.dim_store_sk = st.dim_store_sk
-- optionally filter by snapshot_date
GROUP BY st.store_name
ORDER BY store_inventory_value DESC
```

- **Key join:** `fct_inventory.dim_store_sk → dim_store.dim_store_sk`

---

### Inventory Trend — Line Chart

Tracks total stock levels over successive ingestion snapshots. Useful for detecting seasonal
depletion, restock events, or data pipeline gaps.

```sql
SELECT
    d.date_day        AS snapshot_date,
    SUM(i.quantity)   AS total_units
FROM fct_inventory i
JOIN dim_date d ON i.dim_date_sk = d.dim_date_sk
GROUP BY d.date_day
ORDER BY d.date_day
```

- **Key join:** `fct_inventory.dim_date_sk → dim_date.dim_date_sk`
- `dim_date_sk` in `fct_inventory` is keyed on **`snapshot_date`** — the date of the
  full-load ingestion run, not an order date.
- Each point on the line = one ingestion run. Points only appear for dates where
  a snapshot was loaded.

---

### Units on Hand by Category — Horizontal Bar Chart

Shows which bicycle categories have the most stock across all stores.

```sql
SELECT
    p.category_name,
    SUM(i.quantity) AS units_on_hand
FROM fct_inventory i
JOIN dim_product p ON i.dim_product_sk = p.dim_product_sk
GROUP BY p.category_name
ORDER BY units_on_hand DESC
```

- **Key join:** `fct_inventory.dim_product_sk → dim_product.dim_product_sk`
- Filter by `store_name` (via `dim_store`) to scope to a single location.

---

### Inventory Value by Brand — Donut Chart

Breaks down the estimated retail value of stock by bicycle brand.

```sql
SELECT
    p.brand_name,
    SUM(i.inventory_value) AS brand_inventory_value,
    SUM(i.inventory_value) * 100.0 / SUM(SUM(i.inventory_value)) OVER () AS pct
FROM fct_inventory i
JOIN dim_product p ON i.dim_product_sk = p.dim_product_sk
GROUP BY p.brand_name
ORDER BY brand_inventory_value DESC
```

---

### Low Stock Alerts — Table

Lists every store × product pair where stock is at or below a configurable threshold.
Default threshold: **quantity ≤ 5**.

```sql
SELECT
    st.store_name,
    p.product_name,
    p.brand_name,
    p.category_name,
    i.quantity,
    i.inventory_value,
    i.snapshot_date,
    CASE
        WHEN i.quantity <= 2 THEN 'Critical'
        WHEN i.quantity <= 5 THEN 'Warning'
    END AS alert_level
FROM fct_inventory i
JOIN dim_store   st ON i.dim_store_sk   = st.dim_store_sk
JOIN dim_product p  ON i.dim_product_sk = p.dim_product_sk
WHERE i.quantity <= 5   -- configurable threshold
ORDER BY i.quantity ASC, i.inventory_value DESC
```

Alert levels:
- **Critical** — quantity ≤ 2 (urgent restock needed)
- **Warning**  — quantity 3–5 (monitor closely)

---

## Snapshot Filtering

`fct_inventory` holds one row per `(store_id, product_id)` **per ingestion run**. The
`inventory_pk` is keyed on `(store_id, product_id)` without the date, so only the most
recent snapshot is uniquely identified by the primary key.

To query a specific snapshot:
```sql
WHERE i.snapshot_date = '2018-12-31'
-- or via dim_date:
JOIN dim_date d ON i.dim_date_sk = d.dim_date_sk
WHERE d.date_day = '2018-12-31'
```

To query all snapshots for trend analysis, remove the date filter and group by `snapshot_date`.

---

## Filters

| Filter | Applied to | Column |
|---|---|---|
| Snapshot date | `fct_inventory` | `snapshot_date` (or via `dim_date.date_day`) |
| Store | `dim_store` | `store_name` |
| Category | `dim_product` | `category_name` |
| Brand | `dim_product` | `brand_name` |
| Stock threshold | `fct_inventory` | `quantity` |

---

## Dimensional Joins Summary

```
fct_inventory
  ├── dim_date     ON dim_date_sk     (snapshot_date basis — ingestion run date)
  ├── dim_store    ON dim_store_sk
  └── dim_product  ON dim_product_sk  (includes brand + category + current list_price)
```
