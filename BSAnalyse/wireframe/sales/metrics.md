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

---

## DAX Reference

### Calculated Tables

```dax
-- Empty holder table to keep all Sales measures organised in one place
_Sales Measures = ROW("info", "Sales measure table")
```

```dax
-- Disconnected slicer for selecting the comparison period offset (1 = prior year, 2 = two years ago …)
Period Offset = GENERATESERIES(1, 3, 1)
```

---

### Calculated Columns

```dax
-- fct_sales | Human-readable discount shown as a percentage (e.g. 10.5)
-- Avoids multiplying by 100 in every measure
Discount % = fct_sales[discount] * 100
```

```dax
-- fct_sales | Revenue tier for segmentation slicers and conditional formatting
Revenue Band =
    SWITCH(
        TRUE(),
        fct_sales[line_total] >= 3000, "Premium   (≥ $3K)",
        fct_sales[line_total] >= 1000, "Mid-Range ($1K–$3K)",
        fct_sales[line_total] >= 300,  "Entry     ($300–$1K)",
        "Budget    (< $300)"
    )
```

```dax
-- dim_date | Short axis label used on the monthly trend chart (e.g. "Jan 2018")
Month-Year Label =
    FORMAT(dim_date[date_day], "MMM YYYY")
```

```dax
-- dim_date | Quarter label for quarterly grouping (e.g. "Q1 2018")
Quarter-Year Label =
    "Q" & dim_date[quarter_number] & " " & dim_date[year_number]
```

---

### Measures

#### KPI Cards

```dax
Total Revenue = SUM(fct_sales[line_total])
```

```dax
Total Orders = DISTINCTCOUNT(fct_sales[order_id])
```

```dax
Avg Order Value = DIVIDE([Total Revenue], [Total Orders], 0)
```

```dax
Units Sold = SUM(fct_sales[quantity])
```

```dax
-- Percentage of orders that have a non-null shipped_date (is_shipped = TRUE)
Fulfillment Rate % =
    DIVIDE(
        CALCULATE(
            DISTINCTCOUNT(fct_sales[order_id]),
            fct_sales[is_shipped] = TRUE()
        ),
        [Total Orders],
        0
    ) * 100
```

#### Year-over-Year Comparison

```dax
-- Revenue for the same period in the prior calendar year
PY Revenue =
    CALCULATE(
        [Total Revenue],
        SAMEPERIODLASTYEAR(dim_date[date_day])
    )
```

```dax
YoY Revenue Growth % =
    DIVIDE(
        [Total Revenue] - [PY Revenue],
        [PY Revenue],
        0
    ) * 100
```

```dax
-- Dynamic prior-period using the Period Offset slicer (N years back)
Revenue N Years Ago =
    CALCULATE(
        [Total Revenue],
        DATEADD(
            dim_date[date_day],
            -SELECTEDVALUE('Period Offset'[Value], 1),
            YEAR
        )
    )
```

#### Order Status Distribution (Donut Chart)

```dax
Completed Orders =
    CALCULATE(
        DISTINCTCOUNT(fct_sales[order_id]),
        fct_sales[order_status] = 4
    )
```

```dax
Pending Orders =
    CALCULATE(
        DISTINCTCOUNT(fct_sales[order_id]),
        fct_sales[order_status] = 1
    )
```

```dax
Rejected Orders =
    CALCULATE(
        DISTINCTCOUNT(fct_sales[order_id]),
        fct_sales[order_status] = 3
    )
```

```dax
Processing Orders =
    CALCULATE(
        DISTINCTCOUNT(fct_sales[order_id]),
        fct_sales[order_status] = 2
    )
```

#### Chart Measures

```dax
-- Average discount shown as a percentage for the Monthly Summary table
Avg Discount % = AVERAGE(fct_sales[discount]) * 100
```

```dax
-- Revenue share of the currently selected store / category / brand vs. all
Revenue Share % =
    DIVIDE(
        [Total Revenue],
        CALCULATE([Total Revenue], ALL(dim_store), ALL(dim_product)),
        0
    ) * 100
```

```dax
-- Rank of selected entity by revenue (used in Top Products table visual)
Revenue Rank =
    RANKX(
        ALLSELECTED(dim_product[product_name]),
        [Total Revenue],
        ,
        DESC,
        DENSE
    )
```
