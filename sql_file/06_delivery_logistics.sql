/* ============================================================
   DELIVERY & LOGISTICS ANALYSIS
   Author: Amit Sanyal
   Dataset: Olist Brazilian E-Commerce (2016-2018)
   Tool: MySQL 9.0

   BUSINESS PROBLEM:
   Brazil is the 5th largest country in the world with complex
   regional logistics. Olist operates across 27 states with
   vastly different delivery infrastructure. Poor delivery
   experience directly impacts customer satisfaction scores
   and repeat purchase rates. This analysis quantifies delivery
   performance, identifies regional gaps, and measures the
   financial impact of late deliveries on customer sentiment.

   KPIs TRACKED:
   - On-Time Delivery Rate    : % orders delivered by estimated date
   - Average Lead Time        : avg days from purchase to delivery
   - Average Delay            : avg days late for all deliveries
   - Delivery vs Review Score : satisfaction impact of late orders

   SQL TECHNIQUES USED:
   - DATEDIFF for lead time and delay calculations
   - CASE statements for on-time classification and bucketing
   - RANK() window function for regional performance ranking
   - CTEs for clean multi-step calculations
   - Aggregate window functions for percentage calculations

   KEY FINDINGS:
   - Overall on-time rate      : 91.88% across 96,304 orders
   - Avg estimated lead time   : 24.4 days (promised to customer)
   - Avg actual lead time      : 12.5 days (reality)
   - Olist over-promises       : consistently sets conservative
                                 estimates — actual delivery is
                                 nearly 2x faster than promised
   - Fastest state             : SP — 8.7 days average
   - Slowest states            : RR(29.3d), AP(27.2d), AM(26.4d)
   - On-time → avg review      : 4.29 stars, 82.77% positive
   - Late 1-7 days → avg review: 2.71 stars, 49.43% negative
   - Late 8-14 days→ avg review: 1.68 stars, 80.03% negative
   - Black Friday impact       : on-time rate dropped to 85.69%
                                 in Nov 2017 due to volume spike
   - No premium shipping tier  : higher freight does NOT result
                                 in faster delivery — major gap
   ============================================================ */


/* ============================================================
   SECTION 1: OVERALL DELIVERY PERFORMANCE

   Platform-wide delivery KPIs across all 96,304 delivered orders.

   Filters:
   - order_status = 'delivered'
   - All date columns non-NULL
   - Timestamp sequence validated (excludes 3,154 flagged rows
     identified in data quality audit)

   RESULT:
   - Total orders    : 96,304
   - Avg estimated   : 24.4 days
   - Avg actual      : 12.5 days
   - Avg delay       : -11.9 days (negative = delivered early)
   - On-time rate    : 91.88%

   Insight: Negative avg delay means Olist systematically
   under-promises and over-delivers — a smart strategy that
   keeps customer satisfaction high by managing expectations.
   ============================================================ */
SELECT
    COUNT(DISTINCT order_id) AS total_delivered_orders,
    ROUND(AVG(DATEDIFF(order_estimated_delivery_date,
                       order_purchase_timestamp)), 1) AS avg_estimated_days,
    ROUND(AVG(DATEDIFF(order_delivered_customer_date,
                       order_purchase_timestamp)), 1) AS avg_actual_days,
    ROUND(AVG(DATEDIFF(order_delivered_customer_date,
                       order_estimated_delivery_date)), 1) AS avg_delay_days,
    ROUND(SUM(CASE WHEN order_delivered_customer_date <= order_estimated_delivery_date
                   THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS on_time_delivery_pct
FROM orders
WHERE order_status = 'delivered'
AND order_delivered_customer_date IS NOT NULL
AND order_estimated_delivery_date IS NOT NULL
AND order_purchase_timestamp IS NOT NULL
AND order_delivered_customer_date >= order_purchase_timestamp
AND order_delivered_carrier_date >= order_purchase_timestamp;


/* ============================================================
   SECTION 2: DELIVERY PERFORMANCE BY STATE

   Regional breakdown of delivery speed and on-time rate
   across all 27 Brazilian states. Ranked slowest to fastest
   to highlight the most underserved regions.

   RESULT HIGHLIGHTS:
   - RR (Roraima)  : slowest at 29.3 days — remote north
   - AP (Amapá)    : 27.2 days — Amazon region
   - SP (São Paulo): fastest at 8.7 days — logistics hub
   - AC, RO        : remote but 96-97% on-time because Olist
                     sets very conservative delivery estimates
                     for these states — smart expectation mgmt

   Business Value: States with high delay AND low on-time rate
   (AL at 76%, MA at 80%) are priority targets for logistics
   partnership investment to improve customer experience.
   ============================================================ */
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(AVG(DATEDIFF(o.order_estimated_delivery_date,
                       o.order_purchase_timestamp)), 1) AS avg_estimated_days,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date,
                       o.order_purchase_timestamp)), 1) AS avg_actual_days,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date,
                       o.order_estimated_delivery_date)), 1) AS avg_delay_days,
    ROUND(SUM(CASE WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date
                   THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS on_time_pct,
    RANK() OVER (ORDER BY AVG(DATEDIFF(o.order_delivered_customer_date,
                               o.order_purchase_timestamp)) DESC) AS slowest_rank
FROM orders o
INNER JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
AND o.order_delivered_customer_date IS NOT NULL
AND o.order_estimated_delivery_date IS NOT NULL
AND o.order_purchase_timestamp IS NOT NULL
AND o.order_delivered_customer_date >= o.order_purchase_timestamp
AND o.order_delivered_carrier_date >= o.order_purchase_timestamp
GROUP BY c.customer_state
ORDER BY avg_actual_days DESC;


/* ============================================================
   SECTION 3: DELIVERY PUNCTUALITY VS CUSTOMER REVIEW SCORE

   The most powerful insight in this analysis — directly links
   delivery performance to customer satisfaction by correlating
   on-time status with average review scores.

   Delivery is bucketed into 4 categories:
   - On Time      : delivered on or before estimated date
   - Late 1-7d    : minor delay
   - Late 8-14d   : significant delay
   - Late 15+d    : severe delay

   RESULT:
   Status          Orders   Avg Score  Positive%  Negative%
   On Time         88,001   4.29       82.77%      9.24%
   Late 1-7 days    3,597   2.71       38.24%     49.43%
   Late 8-14 days   1,446   1.68       11.09%     80.03%
   Late 15+ days    2,614   2.85       42.54%     46.03%

   Critical Insight: Even a 1-7 day delay drops avg score from
   4.29 to 2.71 — a 37% collapse in satisfaction. Late 8-14
   days produces 80% negative reviews. This quantifies the exact
   cost of poor logistics on brand reputation.
   ============================================================ */
SELECT
    CASE
        WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date
            THEN 'On Time'
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date)
            BETWEEN 1 AND 7
            THEN 'Late (1-7 days)'
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date)
            BETWEEN 8 AND 14
            THEN 'Late (8-14 days)'
        ELSE 'Late (15+ days)'
    END AS delivery_status,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    ROUND(SUM(CASE WHEN r.review_score >= 4 THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2) AS pct_positive_reviews,
    ROUND(SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2) AS pct_negative_reviews
FROM orders o
INNER JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
AND o.order_delivered_customer_date IS NOT NULL
AND o.order_estimated_delivery_date IS NOT NULL
AND o.order_purchase_timestamp IS NOT NULL
AND o.order_delivered_customer_date >= o.order_purchase_timestamp
AND o.order_delivered_carrier_date >= o.order_purchase_timestamp
GROUP BY delivery_status
ORDER BY avg_review_score DESC;


/* ============================================================
   SECTION 4: MONTHLY ON-TIME DELIVERY TREND

   Tracks on-time delivery rate and average lead time month
   by month to evaluate whether logistics performance scaled
   with the 21x revenue growth between 2016 and 2018.

   RESULT HIGHLIGHTS:
   - Nov 2017 Black Friday : on-time dropped to 85.69% —
                             volume spike overwhelmed logistics
   - Feb-Mar 2018          : dipped to 78-84% — concerning
                             degradation as platform scaled
   - Jun-Aug 2018          : recovered to 89-98% showing
                             logistics infrastructure caught up
   - General trend         : delivery speed improved over time
                             (avg days dropped from 19.6 in
                             Oct 2016 to 7.7 in Aug 2018)
   ============================================================ */
SELECT
    YEAR(o.order_purchase_timestamp) AS order_year,
    MONTH(o.order_purchase_timestamp) AS order_month,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date,
                       o.order_purchase_timestamp)), 1) AS avg_actual_days,
    ROUND(SUM(CASE WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date
                   THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS on_time_pct
FROM orders o
WHERE o.order_status = 'delivered'
AND o.order_delivered_customer_date IS NOT NULL
AND o.order_estimated_delivery_date IS NOT NULL
AND o.order_purchase_timestamp IS NOT NULL
AND o.order_delivered_customer_date >= o.order_purchase_timestamp
AND o.order_delivered_carrier_date >= o.order_purchase_timestamp
GROUP BY order_year, order_month
ORDER BY order_year, order_month;


/* ============================================================
   SECTION 5: FREIGHT COST VS DELIVERY SPEED

   Tests whether higher freight charges result in faster
   deliveries — identifying if a premium express shipping
   tier effectively exists on the platform.

   Freight bucketed into ranges for clean comparison.

   RESULT:
   Bucket      Orders   Avg Freight  Avg Days  On-Time%
   Free           337      0 BRL      13.2d    96.33%
   1-20 BRL    69,503     14 BRL      11.1d    92.73%
   21-40 BRL   18,775     27 BRL      15.6d    90.39%
   41-60 BRL    3,725     49 BRL      16.8d    89.47%
   61-80 BRL    1,240     68 BRL      16.3d    90.86%
   80+ BRL      3,772     52 BRL      15.3d    90.90%

   Critical Insight: Higher freight does NOT produce faster
   delivery. The 61-80 BRL bucket takes 16.3 days vs 11.1 days
   for the cheapest tier. This confirms no premium express
   shipping tier exists — customers paying more are simply
   in remote locations with higher base freight costs.
   This represents a significant product gap Olist could
   monetize by introducing guaranteed express delivery tiers.
   ============================================================ */
SELECT
    CASE
        WHEN oi.freight_value = 0               THEN 'Free'
        WHEN oi.freight_value BETWEEN 1  AND 20 THEN '1-20 BRL'
        WHEN oi.freight_value BETWEEN 21 AND 40 THEN '21-40 BRL'
        WHEN oi.freight_value BETWEEN 41 AND 60 THEN '41-60 BRL'
        WHEN oi.freight_value BETWEEN 61 AND 80 THEN '61-80 BRL'
        ELSE '80+ BRL'
    END AS freight_bucket,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(AVG(oi.freight_value), 2) AS avg_freight_brl,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date,
                       o.order_purchase_timestamp)), 1) AS avg_delivery_days,
    ROUND(SUM(CASE WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date
                   THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS on_time_pct
FROM orders o
INNER JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
AND o.order_delivered_customer_date IS NOT NULL
AND o.order_estimated_delivery_date IS NOT NULL
AND o.order_purchase_timestamp IS NOT NULL
AND o.order_delivered_customer_date >= o.order_purchase_timestamp
AND o.order_delivered_carrier_date >= o.order_purchase_timestamp
GROUP BY freight_bucket
ORDER BY avg_freight_brl;