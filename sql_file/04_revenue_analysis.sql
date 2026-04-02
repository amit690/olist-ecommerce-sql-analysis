/* ============================================================
   REVENUE & SALES TREND ANALYSIS
   Author: Amit Sanyal
   Objective: Analyze Olist's monthly revenue performance,
   category contribution, and payment behaviour to identify
   growth trends, seasonal patterns and business insights.

   KEY FINDINGS:
   - Peak revenue month    : November 2017 (Black Friday effect)
   - Top revenue category  : (to be updated after running)
   - Dominant payment type : Credit Card (74%)
   - Average Order Value   : (to be updated after running)
   ============================================================ */


/* ============================================================
   SECTION 1: MONTHLY GMV & ORDER VOLUME TREND
   
   Calculates Gross Merchandise Value (GMV) and total order
   count for each month across the dataset period.
   
   Filters applied:
   - order_status = 'delivered' — only completed orders
   - payment_type != 'not_defined' — excludes 3 invalid rows
   - Ghost orders excluded naturally via INNER JOIN with order_payments
   
   Business Value: Reveals month-over-month revenue growth,
   seasonal spikes (Black Friday Nov 2017) and overall platform
   health over time.
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
   
   Calculates total revenue, order count and average item price
   per product category using English category names.
   
   Filters applied:
   - order_status = 'delivered'
   - COALESCE handles 610 products with NULL category names
     by grouping them under 'Uncategorized'
   
   Business Value: Identifies top performing categories and
   revenue concentration — critical for inventory and marketing
   budget allocation decisions.
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
   
   Breaks down revenue and order volume by payment method
   and analyzes installment payment behaviour.
   
   Business Value: Understanding payment preferences helps
   Olist optimize checkout experience. High installment usage
   indicates customers stretching budgets — a key Brazilian
   consumer behaviour pattern.
   ============================================================ */

-- Part A: Revenue by payment type
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

-- Part B: Installment behaviour analysis
SELECT 
    payment_installments,
    COUNT(DISTINCT op.order_id) AS total_orders,
    ROUND(SUM(op.payment_value), 2) AS total_revenue,
    ROUND(AVG(op.payment_value), 2) AS avg_order_value
FROM order_payments op
INNER JOIN orders o ON op.order_id = o.order_id
WHERE o.order_status = 'delivered'
AND op.payment_type = 'credit_card'
AND op.payment_type != 'not_defined'
GROUP BY payment_installments
ORDER BY payment_installments;


/* ============================================================
   SECTION 4: REVENUE BY CUSTOMER STATE
   
   Maps GMV to Brazilian states to identify geographic
   revenue concentration and underserved markets.
   
   Business Value: Reveals which states drive the most revenue
   and which are untapped opportunities. Visually powerful
   on a Power BI Brazil map visual.
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
   SECTION 5: DAILY REVENUE HEATMAP DATA
   
   Calculates revenue by day of week and hour of day to
   identify peak shopping windows on the platform.
   
   Business Value: Identifies optimal timing for flash sales,
   email campaigns and promotional pushes. A heatmap of this
   data in Power BI is visually striking in a portfolio.
   ============================================================ */

-- Part A: Revenue by day of week
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

-- Part B: Revenue by hour of day
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
   
   Calculates the percentage change in GMV from one month
   to the next using LAG window function.
   
   Business Value: Highlights acceleration and deceleration
   in revenue growth — more meaningful than raw GMV numbers
   for understanding business momentum.
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