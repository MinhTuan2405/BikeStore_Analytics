# Sales Overview Dashboard — Metric Definitions

Primary fact table: `fct_sales` (grain: one row per order line item)

---

## KPI Cards

| KPI | Formula | Source columns |
|---|---|---|
| **Total Revenue** | `SUM(line_total)` | `fct_sales.line_total` |
| **Total Orders** | `COUNT(DISTINCT order_id)` | `fct_sales.order_id` |
| **Avg Order Value** | `SUM(line_total) / COUNT(DISTINCT order_id)` | derived |
| **Units Sold** | `SUM(quantity)` | `fct_sales.quantity` |
| **Fulfillment Rate** | `COUNT(DISTINCT order_id WHERE is_shipped) / COUNT(DISTINCT order_id)` | `fct_sales.is_shipped` |

**`line_total` computation** (from staging layer):
```
ROUND(quantity * list_price * (1 - discount), 2)
```

**`is_shipped`** (degenerate dimension in `fct_sales`):
```
is_shipped = TRUE  when shipped_date IS NOT NULL
is_shipped = FALSE when shipped_date IS NULL
```

---

## Charts

### Revenue Trend — Monthly Line Chart

Tracks net revenue over a calendar year, month by month.

```sql
SELECT
    d.year_number,
    d.month_number,
    d.month_name,
    SUM(s.line_total) AS monthly_revenue
FROM fct_sales s
JOIN dim_date d ON s.dim_date_sk = d.dim_date_sk
-- apply date range, store, category, brand, status filters
GROUP BY d.year_number, d.month_number, d.month_name
ORDER BY d.year_number, d.month_number
```

- **X-axis:** `month_name` (ordered by `month_number`)
- **Y-axis:** `monthly_revenue`
- **Key join:** `fct_sales.dim_date_sk → dim_date.dim_date_sk` (keyed on `order_date`)

---

### Order Status Distribution — Donut Chart

Breaks down order volume by fulfillment status.

```sql
SELECT
    order_status_label,
    COUNT(DISTINCT order_id) AS order_count,
    COUNT(DISTINCT order_id) * 100.0 / SUM(COUNT(DISTINCT order_id)) OVER () AS pct
FROM fct_sales
GROUP BY order_status, order_status_label
ORDER BY order_status
```

- **Values in source:** `order_status` integer (1–4) + `order_status_label` text
  - 1 = Pending
  - 2 = Processing
  - 3 = Rejected
  - 4 = Completed
- Both are **degenerate dimensions** stored directly on `fct_sales` — no join needed.

---

### Revenue by Store — Horizontal Bar Chart

Compares each physical store's contribution to total revenue.

```sql
SELECT
    st.store_name,
    SUM(s.line_total) AS store_revenue
FROM fct_sales s
JOIN dim_store st ON s.dim_store_sk = st.dim_store_sk
GROUP BY st.store_name
ORDER BY store_revenue DESC
```

- **Key join:** `fct_sales.dim_store_sk → dim_store.dim_store_sk`
- Bars sorted descending by revenue.

---

### Revenue by Product Category — Horizontal Bar Chart

Identifies which bicycle categories drive the most revenue.

```sql
SELECT
    p.category_name,
    SUM(s.line_total) AS category_revenue
FROM fct_sales s
JOIN dim_product p ON s.dim_product_sk = p.dim_product_sk
GROUP BY p.category_name
ORDER BY category_revenue DESC
```

- **Key join:** `fct_sales.dim_product_sk → dim_product.dim_product_sk`
- `category_name` is denormalized into `dim_product` (originally from `production.categories`).

---

### Top 10 Products by Revenue — Table

Identifies the highest-revenue individual products.

```sql
SELECT
    p.product_name,
    p.brand_name,
    p.category_name,
    SUM(s.quantity)    AS units_sold,
    SUM(s.line_total)  AS revenue,
    SUM(s.line_total) / NULLIF(SUM(s.quantity), 0) AS avg_selling_price
FROM fct_sales s
JOIN dim_product p ON s.dim_product_sk = p.dim_product_sk
GROUP BY p.product_name, p.brand_name, p.category_name
ORDER BY revenue DESC
LIMIT 10
```

> **Note:** `avg_selling_price` reflects the actual price-at-order-time (`fct_sales.list_price`),
> which may differ from the current `dim_product.list_price` if pricing changed after the order.

---

### Monthly Summary — Table

Full-year month-by-month breakdown with revenue, orders, and average discount.

```sql
SELECT
    d.month_name,
    d.month_number,
    SUM(s.line_total)            AS revenue,
    COUNT(DISTINCT s.order_id)   AS orders,
    AVG(s.discount)              AS avg_discount
FROM fct_sales s
JOIN dim_date d ON s.dim_date_sk = d.dim_date_sk
GROUP BY d.year_number, d.month_number, d.month_name
ORDER BY d.month_number
```

- `avg_discount` is a fraction (0.0–1.0); multiply by 100 to display as percentage.

---

## Filters

| Filter | Applied to | Column |
|---|---|---|
| Date range | `fct_sales` | `order_date` (via `dim_date.year_number`, `month_number`) |
| Store | `dim_store` | `store_name` |
| Category | `dim_product` | `category_name` |
| Brand | `dim_product` | `brand_name` |
| Order Status | `fct_sales` | `order_status_label` (degenerate dim, no join needed) |

---

## Dimensional Joins Summary

```
fct_sales
  ├── dim_date     ON dim_date_sk     (order_date basis)
  ├── dim_store    ON dim_store_sk
  ├── dim_product  ON dim_product_sk  (includes brand + category)
  ├── dim_customer ON dim_customer_sk (nullable → missing-member row for guest orders)
  └── dim_staff    ON dim_staff_sk
```
