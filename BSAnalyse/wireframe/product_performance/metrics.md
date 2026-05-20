# Product & Staff Performance Dashboard — Metric Definitions

Primary fact table: `fct_sales` (grain: one row per order line item)
Key dimensions: `dim_product`, `dim_staff`, `dim_customer`

---

## KPI Cards

| KPI | Formula | Source columns |
|---|---|---|
| **Products Sold** | `COUNT(DISTINCT dim_product_sk)` | `fct_sales.dim_product_sk` |
| **Top Brand** | `brand_name` with highest `SUM(line_total)` | `dim_product.brand_name` |
| **Active Staff** | `COUNT(*) WHERE is_active = TRUE` | `dim_staff.is_active` |
| **Avg Discount** | `AVG(discount) * 100` | `fct_sales.discount` |
| **Top Performer** | `full_name` with highest `SUM(line_total)` | `dim_staff.full_name` |

`discount` is a fraction (0.0 = no discount, 1.0 = 100% off). Multiply by 100 to display
as a percentage.

---

## Charts

### Revenue by Brand — Horizontal Bar Chart

Ranks bicycle brands by total sales revenue.

```sql
SELECT
    p.brand_name,
    SUM(s.line_total)          AS brand_revenue,
    SUM(s.quantity)            AS units_sold,
    COUNT(DISTINCT s.order_id) AS order_count
FROM fct_sales s
JOIN dim_product p ON s.dim_product_sk = p.dim_product_sk
GROUP BY p.brand_name
ORDER BY brand_revenue DESC
```

- **Key join:** `fct_sales.dim_product_sk → dim_product.dim_product_sk`
- `brand_name` is denormalized into `dim_product` (originally from `production.brands`).

---

### Revenue by Model Year — Vertical Bar Chart

Compares sales performance across bicycle model years. Reveals whether newer or older models
drive more revenue.

```sql
SELECT
    p.model_year,
    SUM(s.line_total)          AS revenue,
    SUM(s.quantity)            AS units_sold,
    COUNT(DISTINCT s.order_id) AS orders
FROM fct_sales s
JOIN dim_product p ON s.dim_product_sk = p.dim_product_sk
WHERE p.model_year IS NOT NULL  -- excludes missing-member row
GROUP BY p.model_year
ORDER BY p.model_year
```

- `model_year` is a `SMALLINT` on `dim_product` (e.g., 2016, 2017, 2018).
- NULL model_year belongs to the missing-member row and should be excluded.

---

### Revenue Share by Category — Donut Chart

Shows each product category's percentage contribution to total revenue.

```sql
SELECT
    p.category_name,
    SUM(s.line_total) AS category_revenue,
    SUM(s.line_total) * 100.0 / SUM(SUM(s.line_total)) OVER () AS revenue_pct
FROM fct_sales s
JOIN dim_product p ON s.dim_product_sk = p.dim_product_sk
GROUP BY p.category_name
ORDER BY category_revenue DESC
```

---

### Avg Discount by Category — Horizontal Bar Chart

Identifies which categories receive the heaviest discounting. High discount rates on
high-value categories may erode margin.

```sql
SELECT
    p.category_name,
    AVG(s.discount)            AS avg_discount_rate,
    AVG(s.discount) * 100      AS avg_discount_pct,
    COUNT(DISTINCT s.order_id) AS orders
FROM fct_sales s
JOIN dim_product p ON s.dim_product_sk = p.dim_product_sk
GROUP BY p.category_name
ORDER BY avg_discount_rate DESC
```

- `discount` range: 0.0 (no discount) to 1.0 (fully discounted).
- Displayed as percentage: `AVG(discount) * 100`.

---

### Staff Leaderboard — Table

Ranks all sales staff by total revenue generated. Includes manager context from the
flattened hierarchy in `dim_staff`.

```sql
SELECT
    st.full_name                                   AS staff_name,
    st.manager_full_name,
    ds.store_name,
    st.is_active,
    COUNT(DISTINCT s.order_id)                     AS orders_handled,
    SUM(s.line_total)                              AS revenue,
    SUM(s.line_total) / COUNT(DISTINCT s.order_id) AS avg_order_value
FROM fct_sales s
JOIN dim_staff  st ON s.dim_staff_sk   = st.dim_staff_sk
JOIN dim_store  ds ON st.store_id      = ds.store_id
WHERE st.staff_id != -1  -- exclude missing-member row
GROUP BY st.full_name, st.manager_full_name, ds.store_name, st.is_active
ORDER BY revenue DESC
```

**`dim_staff` hierarchy notes:**
- `manager_full_name` — flattened one level from a self-join on `manager_id`; top-level
  staff (no manager) resolve to the missing-member key.
- `is_active` — `TRUE` when the source `active` flag = 1; `FALSE` otherwise.
- The join `st.store_id = ds.store_id` uses the natural key from `dim_staff.store_id`
  (the store the staff member is assigned to) rather than a surrogate key join.

---

### Top 10 Customers by Revenue — Table

Identifies the most valuable customers by lifetime revenue. Guest (anonymous) orders
are grouped under the missing-member customer row.

```sql
SELECT
    c.full_name        AS customer_name,
    c.city,
    c.state,
    COUNT(DISTINCT s.order_id) AS orders,
    SUM(s.line_total)          AS revenue
FROM fct_sales s
JOIN dim_customer c ON s.dim_customer_sk = c.dim_customer_sk
GROUP BY c.full_name, c.city, c.state
ORDER BY revenue DESC
LIMIT 10
```

> **Guest orders:** When `customer_id` is NULL in the source (anonymous/guest checkout),
> `fct_sales.dim_customer_sk` resolves to `MD5('-1')` — the missing-member row in
> `dim_customer` where `full_name = 'Unknown Customer'`. These appear as one combined
> row in any customer-level aggregation.

---

## Filters

| Filter | Applied to | Column |
|---|---|---|
| Date range | `fct_sales` | `order_date` (via `dim_date`) |
| Store | `dim_store` | `store_name` (join via `dim_staff.store_id` for staff scope) |
| Brand | `dim_product` | `brand_name` |
| Category | `dim_product` | `category_name` |
| Staff | `dim_staff` | `full_name` |

---

## Dimensional Joins Summary

```
fct_sales
  ├── dim_date     ON dim_date_sk     (order_date basis)
  ├── dim_store    ON dim_store_sk    (store that accepted the order)
  ├── dim_product  ON dim_product_sk  (brand, category, model_year)
  ├── dim_customer ON dim_customer_sk (nullable → missing-member for guest orders)
  └── dim_staff    ON dim_staff_sk    (staff who processed the order;
                                       also joins dim_staff again via manager_dim_staff_sk
                                       for manager hierarchy without recursion)
```
