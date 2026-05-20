## Dashboard 1 — Sales Overview

**Audience:** Executives, store managers
**How often used:** Daily / weekly

### What the user needs to see

| # | Business Need | Why it matters |
|---|---|---|
| 1 | Total revenue for the selected period | Primary business health indicator |
| 2 | Number of orders placed | Understand customer demand volume |
| 3 | Average value per order | Track whether customers are spending more or less per visit |
| 4 | Total units sold | Measure physical sales volume |
| 5 | Percentage of orders shipped | Flag fulfilment bottlenecks before customers complain |
| 6 | Monthly revenue trend | Spot seasonality and growth patterns across the year |
| 7 | Revenue split by store | Identify which locations drive the business |
| 8 | Revenue split by product category | See which bicycle types are most in demand |
| 9 | Order status breakdown | Understand the mix of completed, pending, and rejected orders |
| 10 | Top-selling products | Know what to promote, reorder, and stock more of |
| 11 | Month-by-month summary table | Quick reference for any specific month's numbers |

### Filters the user expects
- **Time period** — select a specific year, quarter, or custom date range
- **Store** — focus on one store or see all stores combined
- **Product category** — zoom in on a specific bike type (e.g. Mountain Bikes only)
- **Brand** — analyse a single supplier's performance
- **Order status** — look at only completed orders, or only pending ones

### Acceptance criteria
- Revenue figures must match what appears on sales reports
- Order count must count unique orders, not individual line items
- The trend chart must clearly show which months were strongest and weakest
- A manager must be able to answer "what was last month's revenue?" in under 10 seconds

---

## Dashboard 2 — Inventory Status

**Audience:** Inventory manager, store managers
**How often used:** Daily — especially before placing supplier orders

### What the user needs to see

| # | Business Need | Why it matters |
|---|---|---|
| 1 | Total units currently in stock across all stores | Know overall stock health at a glance |
| 2 | Total estimated retail value of current stock | Understand capital tied up in inventory |
| 3 | Number of products with critically low stock | Immediate action list for restocking |
| 4 | Inventory levels per store | Balance stock across locations |
| 5 | How stock levels have changed over time | Detect depletion trends and measure restock impact |
| 6 | Units on hand by product category | Ensure all bicycle types are adequately stocked |
| 7 | Inventory value split by brand | Understand supplier exposure |
| 8 | Low-stock alert list with product details | Actionable restock list, sorted by urgency |

### Business rules for alerts
- **Critical** — fewer than 3 units remaining at a store → immediate restock action required
- **Warning** — 3 to 5 units remaining → order within the next few days
- A product that hits zero at one store but is well-stocked at another should still trigger an alert for that specific store

### Filters the user expects
- **Date / snapshot** — view stock as of a specific date (today vs. last month)
- **Store** — focus on a single location
- **Category** — check just Mountain Bikes or Electric Bikes
- **Brand** — review a specific supplier's stock position
- **Alert threshold** — adjust the low-stock cutoff (default: 5 units)

### Acceptance criteria
- Low-stock alerts must be sorted by urgency (fewest units first)
- The inventory trend must clearly show whether total stock is rising or falling
- An inventory manager must be able to produce a restock priority list in one click
- Numbers must update whenever a new stock snapshot is loaded

---

## Dashboard 3 — Product & Staff Performance

**Audience:** Store managers, sales team leads, executives
**How often used:** Weekly / monthly performance reviews

### What the user needs to see

| # | Business Need | Why it matters |
|---|---|---|
| 1 | Revenue breakdown by brand | Evaluate which supplier partnerships are most profitable |
| 2 | Revenue by bicycle model year | Understand whether newer models justify their premium |
| 3 | Revenue share by product category | Strategic view of the product mix |
| 4 | Average discount rate per category | Identify where margin is being eroded by discounting |
| 5 | Staff leaderboard — revenue and orders | Recognise top performers and support underperformers |
| 6 | Staff manager and store context | Understand team structure alongside individual results |
| 7 | Top 10 customers by revenue | Identify VIP customers for loyalty and retention programmes |

### Business rules
- Staff rankings must only include active employees
- Customer ranking should include anonymous (guest) orders as a combined entry — this
  helps management understand how much revenue comes from non-registered customers
- Discount rates should be shown as a percentage (e.g. 10%), not a decimal (e.g. 0.10)
- Staff performance should reflect orders they personally processed, not their whole store

### Filters the user expects
- **Time period** — year, quarter, or custom date range
- **Store** — compare staff within one store or across all locations
- **Brand / Category** — see how a specific product line performs
- **Staff member** — managers may want to review a single employee's numbers

### Acceptance criteria
- The staff leaderboard must show each person's manager name for organisational context
- A store manager must be able to identify their top performer in under 30 seconds
- The customer table must clearly label guest/anonymous orders rather than hiding them
- Discount analysis must be easy to read — bars sorted from highest to lowest discount rate

---

## General Requirements (All Dashboards)

| Requirement | Detail |
|---|---|
| **No database access needed** | Business users interact only with the dashboards |
| **Plain language labels** | No technical column names visible to end users |
| **Filter defaults** | Default to the current year and all stores on first load |
| **Period comparison** | Where possible, show change vs. the same period last year |
| **Consistent currency** | All monetary values displayed in USD with $ symbol |
| **Mobile-friendly** | Dashboards must be readable on a tablet screen |
| **Fast to read** | Key numbers visible without scrolling (above the fold) |
| **Colour coding** | Green = good/healthy · Red/orange = attention needed · Blue = informational |

