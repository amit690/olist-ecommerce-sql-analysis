/* ============================================================
   REVENUE & SALES TREND ANALYSIS
   Author: Amit Sanyal
   Dataset: Olist Brazilian E-Commerce (2016-2018)
   Tool: MySQL 9.0

   KEY FINDINGS:
   - Total GMV (delivered orders)  : ~15.4M BRL across 22 months
   - Peak revenue month            : November 2017 — 1.15M BRL (Black Friday)
   - Platform growth               : 21x revenue growth Oct 2016 to Aug 2018
   - Top category by revenue       : Health & Beauty (1.23M BRL)
   - Top category by avg price     : Computers (1,098 BRL avg item price)
   - Dominant payment method       : Credit Card (78.46% of revenue)
   - Most popular installment plan : 1 installment (24,711 orders)
   - Highest AOV installment       : 10 installments (410 BRL avg)
   - Top state by revenue          : São Paulo (37.41% of total GMV)
   - Top 3 states combined         : SP + RJ + MG = 62.5% of revenue
   - Peak shopping day             : Monday (15,701 orders)
   - Peak shopping hours           : 10AM to 4PM
   - Avg Order Value               : ~158 BRL across all delivered orders
   ============================================================ */


/* ============================================================
   SECTION 1: MONTHLY GMV & ORDER VOLUME TREND

   Calculates Gross Merchandise Value (GMV) and total order
   count for each month across the full dataset period.

   Filters applied:
   - order_status = 'delivered'       : only completed orders counted
   - payment_type != 'not_defined'    : excludes 3 invalid payment rows
   - INNER JOIN with order_payments   : naturally excludes 775 ghost orders

   KEY FINDINGS:
   - Oct 2016: 46K BRL (dataset starts mid-month, partial data)
   - Nov 2017: 1.15M BRL — peak month driven by Black Friday
   - Dec 2017: 843K BRL — 26.9% drop, typical post-Black Friday correction
   - 2018 plateau: ~1M BRL/month suggesting platform maturity
   - Overall trajectory: strong growth from startup to scale
   ============================================================ */
SELECT 
    YEAR(o.order_purchase_timestamp) AS order_year,
    MONTH(o.order_purchase_timestamp) AS order_month,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(op.payment_value), 2) AS monthly_gmv,
    ROUND(SUM(op.payment_value) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value
FROM orders o
INNER JOIN order_payments op ON o.order_id = op.order_id
WHERE o.order_status = 'delivered'
AND op.payment_type != 'not_defined'
GROUP BY order_year, order_month
ORDER BY order_year, order_month;


/* ============================================================
   SECTION 2: REVENUE BY PRODUCT CATEGORY

   Calculates total revenue, order count, average item price
   and revenue per order for every product category using
   English category names from category_translation table.

   Filters applied:
   - order_status = 'delivered'
   - COALESCE on category name groups 610 NULL-category products
     under 'Uncategorized' to prevent silent revenue exclusion
   - LEFT JOIN on category_translation preserves all products
     including the 2 categories we manually inserted

   KEY FINDINGS:
   - Health & Beauty    : #1 by revenue (1.23M BRL, 8,647 orders)
   - Watches & Gifts    : #2 by revenue, highest avg price (199 BRL)
   - Computers          : only 177 orders but 1,098 BRL avg — premium niche
   - Uncategorized      : 1,392 orders, 170K BRL — retained via COALESCE
   - PC Gamer           : 7 orders, 1.3K BRL — manually translated category
   - Bottom categories  : flowers, home_comfort_2, fashion_childrens_clothes
   - Revenue is highly concentrated in top 10 categories
   ============================================================ */
SELECT 
    COALESCE(ct.product_category_name_english, 'Uncategorized') AS category,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(oi.price), 2) AS total_revenue,
    ROUND(AVG(oi.price), 2) AS avg_item_price,
    ROUND(SUM(oi.price) / COUNT(DISTINCT o.order_id), 2) AS revenue_per_order
FROM orders o
INNER JOIN order_items oi ON o.order_id = oi.order_id
INNER JOIN products p ON oi.product_id = p.product_id
LEFT JOIN category_translation ct ON p.product_category_name = ct.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY category
ORDER BY total_revenue DESC;


/* ============================================================
   SECTION 3: PAYMENT METHOD ANALYSIS

   Part A analyses revenue contribution and order share by
   payment type. Part B analyses installment behaviour
   specifically for credit card payments to understand how
   Brazilian consumers spread their purchasing costs.

   KEY FINDINGS — Part A:
   - Credit card : 78.46% of revenue — overwhelmingly dominant
   - Boleto      : 17.96% — significant, reflects Brazil's large
                   unbanked population using bank slip payments
   - Voucher     : 2.22% — promotional codes minimally used
   - Debit card  : 1.35% — very low adoption on the platform

   KEY FINDINGS — Part B (Credit Card Installments):
   - 1 installment  : most common (24,711 orders, 95 BRL avg)
   - 10 installments: surprisingly popular (5,137 orders, 410 BRL avg)
   - High installment usage reflects Brazilian consumer behaviour
     of stretching budgets over monthly payments
   - 0 installment rows (2 orders) likely system anomalies
   ============================================================ */

-- Part A: Revenue and order share by payment type
SELECT 
    payment_type,
    COUNT(DISTINCT op.order_id) AS total_orders,
    ROUND(SUM(op.payment_value), 2) AS total_revenue,
    ROUND(AVG(op.payment_value), 2) AS avg_payment_value,
    ROUND(SUM(op.payment_value) * 100.0 / SUM(SUM(op.payment_value)) OVER(), 2) AS revenue_share_pct
FROM order_payments op
INNER JOIN orders o ON op.order_id = o.order_id
WHERE o.order_status = 'delivered'
AND op.payment_type != 'not_defined'
GROUP BY payment_type
ORDER BY total_revenue DESC;

-- Part B: Installment behaviour for credit card payments
SELECT 
    payment_installments,
    COUNT(DISTINCT op.order_id) AS total_orders,
    ROUND(SUM(op.payment_value), 2) AS total_revenue,
    ROUND(AVG(op.payment_value), 2) AS avg_order_value
FROM order_payments op
INNER JOIN orders o ON op.order_id = o.order_id
WHERE o.order_status = 'delivered'
AND op.payment_type = 'credit_card'
GROUP BY payment_installments
ORDER BY payment_installments;


/* ============================================================
   SECTION 4: REVENUE BY CUSTOMER STATE

   Maps total GMV, order volume and revenue share to each
   Brazilian state to identify geographic concentration
   and underserved regional markets.

   KEY FINDINGS:
   - São Paulo (SP)  : 37.41% of total GMV — single state dominance
   - Top 3 (SP+RJ+MG): 62.5% of all revenue — high concentration
   - Northern states : RR(0.06%), AP(0.10%), AC(0.13%) — virtually
                       untapped markets, opportunity for expansion
   - Higher AOV in   : PE(185), CE(198), PA(216) vs SP(136) —
                       smaller states have higher per-order spend,
                       possibly due to fewer local alternatives
   ============================================================ */
SELECT 
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(op.payment_value), 2) AS total_revenue,
    ROUND(AVG(op.payment_value), 2) AS avg_order_value,
    ROUND(SUM(op.payment_value) * 100.0 / SUM(SUM(op.payment_value)) OVER(), 2) AS revenue_share_pct
FROM orders o
INNER JOIN customers c ON o.customer_id = c.customer_id
INNER JOIN order_payments op ON o.order_id = op.order_id
WHERE o.order_status = 'delivered'
AND op.payment_type != 'not_defined'
GROUP BY c.customer_state
ORDER BY total_revenue DESC;


/* ============================================================
   SECTION 5: SHOPPING BEHAVIOUR — DAY & HOUR ANALYSIS

   Identifies peak shopping windows by day of week and hour
   of day. Useful for timing promotional campaigns, flash
   sales and email marketing pushes for maximum impact.

   KEY FINDINGS — Day of Week:
   - Monday is peak shopping day (15,701 orders, 2.53M BRL)
   - Weekend is lowest — Saturday(10,555) and Sunday(11,635)
   - Pattern suggests weekend browsing, Monday purchasing —
     opposite of typical Western e-commerce behaviour
   - Weekday revenue fairly consistent Mon-Fri

   KEY FINDINGS — Hour of Day:
   - Peak window : 10AM to 4PM (consistent ~6,000+ orders/hour)
   - Secondary peak: 8PM to 11PM (evening browsing after work)
   - Dead zone    : 1AM to 5AM as expected
   - 11AM is single busiest hour (6,385 orders)
   ============================================================ */

-- Part A: Orders and revenue by day of week
SELECT 
    DAYNAME(o.order_purchase_timestamp) AS day_of_week,
    DAYOFWEEK(o.order_purchase_timestamp) AS day_number,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(op.payment_value), 2) AS total_revenue
FROM orders o
INNER JOIN order_payments op ON o.order_id = op.order_id
WHERE o.order_status = 'delivered'
AND op.payment_type != 'not_defined'
GROUP BY day_of_week, day_number
ORDER BY day_number;

-- Part B: Orders and revenue by hour of day
SELECT 
    HOUR(o.order_purchase_timestamp) AS hour_of_day,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(op.payment_value), 2) AS total_revenue
FROM orders o
INNER JOIN order_payments op ON o.order_id = op.order_id
WHERE o.order_status = 'delivered'
AND op.payment_type != 'not_defined'
GROUP BY hour_of_day
ORDER BY hour_of_day;


/* ============================================================
   SECTION 6: MONTH OVER MONTH REVENUE GROWTH

   Uses the LAG window function to calculate percentage change
   in GMV from one month to the next, revealing acceleration
   and deceleration in platform revenue momentum.

   KEY FINDINGS:
   - Jan 2017 spike (649%): ignore — dataset starts Oct 2016
     with partial data making Dec 2016 artificially tiny
   - Nov 2017: +53.57% MoM — Black Friday effect confirmed
   - Dec 2017: -26.90% MoM — typical post-Black Friday drop
   - Jan 2018: +27.92% MoM — strong recovery after holidays
   - Mid 2018 slowdown: Jun-Aug 2018 showing negative or flat
     growth suggesting platform maturity or market saturation
   ============================================================ */
WITH monthly_revenue AS (
    SELECT 
        YEAR(o.order_purchase_timestamp) AS order_year,
        MONTH(o.order_purchase_timestamp) AS order_month,
        ROUND(SUM(op.payment_value), 2) AS monthly_gmv
    FROM orders o
    INNER JOIN order_payments op ON o.order_id = op.order_id
    WHERE o.order_status = 'delivered'
    AND op.payment_type != 'not_defined'
    GROUP BY order_year, order_month
)
SELECT 
    order_year,
    order_month,
    monthly_gmv,
    LAG(monthly_gmv) OVER (ORDER BY order_year, order_month) AS prev_month_gmv,
    ROUND(
        (monthly_gmv - LAG(monthly_gmv) OVER (ORDER BY order_year, order_month)) 
        / LAG(monthly_gmv) OVER (ORDER BY order_year, order_month) * 100, 2
    ) AS mom_growth_pct
FROM monthly_revenue
ORDER BY order_year, order_month;