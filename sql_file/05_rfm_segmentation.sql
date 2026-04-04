/* ============================================================
   CUSTOMER SEGMENTATION — RFM ANALYSIS
   Author: Amit Sanyal
   Dataset: Olist Brazilian E-Commerce (2016-2018)
   Tool: MySQL 9.0

   WHAT IS RFM:
   RFM is a proven customer segmentation framework used by
   e-commerce and retail businesses worldwide. Each customer
   is scored across three behavioural dimensions:
   - Recency   (R): Days since their last purchase
   - Frequency (F): Total number of orders placed
   - Monetary  (M): Total amount spent in BRL

   Each dimension is scored 1-5 using NTILE(5) window function
   where 5 = best (most recent, most frequent, highest spend)
   and 1 = worst. Scores are combined into named segments.

   SQL TECHNIQUES USED:
   - 3 chained CTEs for clean step-by-step calculation
   - NTILE(5) window function for percentile-based scoring
   - CASE statements for business-readable segment labelling
   - Aggregate window functions for segment-level summarization

   DATASET SCOPE:
   - Total unique customers analysed : 93,357
   - Only delivered orders included
   - Reference date for recency      : MAX order date in dataset
                                       (avoids distortion from
                                       gap between 2018 & today)

   KEY FINDINGS:
   - Dominant segment   : Needs Attention (21.31% of customers)
                          514 avg recency days — largely inactive
   - At Risk segment    : 18.69% — previously active, going cold
   - New Customers      : 19.33% — recent buyers, low frequency
   - Champions          : only 0.90% (842 customers) but highest
                          AOV at 406 BRL and 2.2 avg orders
   - Loyal + Champion   : combined only 3.4% of base — retention
                          is a critical gap for Olist
   - Frequency insight  : almost all segments show avg frequency
                          of 1.0 — most customers buy only once,
                          confirming low repeat purchase rate
   - Revenue per segment: top 4 segments contribute ~86% of GMV
                          despite being the least engaged groups
                          (volume-driven, not loyalty-driven)

   BUSINESS RECOMMENDATIONS:
   - Champions (842)      : reward with exclusive offers, early
                            access to sales — protect this base
   - At Risk (17,453)     : launch win-back campaign immediately,
                            personalized discount within 30 days
   - New Customers(18,049): onboarding email sequence to convert
                            first-time buyers into repeat buyers
   - Needs Attention      : largest segment at 21% — re-engagement
                            campaign critical to revenue recovery
   ============================================================ */


/* ============================================================
   CTE 1: RFM BASE METRICS
   
   Calculates raw Recency, Frequency and Monetary values
   for every unique customer with at least one delivered order.

   customer_unique_id is used instead of customer_id because
   the Olist schema assigns a new customer_id per order —
   customer_unique_id is the true persistent customer identifier
   needed for accurate repeat purchase analysis.

   Recency reference point: MAX(order_purchase_timestamp) across
   the entire dataset ensures scores reflect behaviour relative
   to platform activity, not the current date in 2024+.

   Filters:
   - order_status = 'delivered'     : completed orders only
   - payment_type != 'not_defined'  : excludes 3 invalid rows
   - INNER JOIN order_payments      : naturally excludes 775
                                      ghost orders with no items
   ============================================================ */
WITH rfm_base AS (
    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp) AS last_order_date,
        DATEDIFF(
            (SELECT MAX(order_purchase_timestamp) FROM orders),
            MAX(o.order_purchase_timestamp)
        ) AS recency_days,
        COUNT(DISTINCT o.order_id) AS frequency,
        ROUND(SUM(op.payment_value), 2) AS monetary
    FROM customers c
    INNER JOIN orders o ON c.customer_id = o.customer_id
    INNER JOIN order_payments op ON o.order_id = op.order_id
    WHERE o.order_status = 'delivered'
    AND op.payment_type != 'not_defined'
    GROUP BY c.customer_unique_id
),

/* ============================================================
   CTE 2: RFM SCORING WITH NTILE(5)

   Assigns a percentile-based score of 1-5 to each customer
   for each RFM dimension using NTILE(5) window function.
   NTILE splits all customers into 5 equal-sized buckets.

   Scoring direction is critical:
   - Recency   : ORDER BY DESC — fewer days since last purchase
                 = higher score (5 = most recent buyer)
   - Frequency : ORDER BY ASC  — more orders = higher score
                 (5 = most frequent buyer)
   - Monetary  : ORDER BY ASC  — higher spend = higher score
                 (5 = highest value customer)
   ============================================================ */
rfm_scores AS (
    SELECT
        customer_unique_id,
        recency_days,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC)     AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC)      AS m_score
    FROM rfm_base
),

/* ============================================================
   CTE 3: SEGMENT ASSIGNMENT

   Combines individual R, F, M scores into a composite
   rfm_score string (e.g. '555', '312') and maps each
   customer to a human-readable business segment using
   a prioritized CASE statement.

   Segment definitions:
   - Champion        : Perfect or near-perfect on all 3 scores
   - Loyal Customer  : High recency and frequency
   - Potential Loyalist: Recent with moderate engagement
   - New Customer    : Very recent, low frequency (just joined)
   - Promising       : Moderate recency, low frequency
   - At Risk         : Low recency, previously frequent buyers
   - Needs Attention : Low recency, moderate frequency
   - Lost            : Worst score on all dimensions
   - Others          : All remaining score combinations
   ============================================================ */
rfm_segments AS (
    SELECT
        customer_unique_id,
        recency_days,
        frequency,
        monetary,
        r_score,
        f_score,
        m_score,
        CONCAT(r_score, f_score, m_score) AS rfm_score,
        CASE
            WHEN r_score = 5 AND f_score = 5 AND m_score = 5 THEN 'Champion'
            WHEN r_score = 5 AND f_score = 5 AND m_score = 4 THEN 'Champion'
            WHEN r_score = 4 AND f_score = 5 AND m_score = 5 THEN 'Champion'
            WHEN r_score >= 4 AND f_score >= 4              THEN 'Loyal Customer'
            WHEN r_score >= 4 AND f_score >= 3              THEN 'Potential Loyalist'
            WHEN r_score = 5 AND f_score <= 2               THEN 'New Customer'
            WHEN r_score >= 3 AND f_score <= 2              THEN 'Promising'
            WHEN r_score <= 2 AND f_score >= 4              THEN 'At Risk'
            WHEN r_score <= 2 AND f_score >= 2              THEN 'Needs Attention'
            WHEN r_score = 1 AND f_score = 1                THEN 'Lost'
            ELSE 'Others'
        END AS segment
    FROM rfm_scores
)

/* ============================================================
   FINAL OUTPUT: SEGMENT SUMMARY TABLE

   Aggregates all customers by segment showing size, behaviour
   averages and revenue contribution per segment.

   Columns:
   - total_customers   : number of unique customers in segment
   - pct_of_customers  : segment share of total customer base
   - avg_recency_days  : how long ago they last purchased
   - avg_frequency     : average number of orders placed
   - avg_monetary_brl  : average total spend per customer
   - total_revenue_brl : total GMV contributed by segment

   RESULTS:
   Segment            Customers  Pct    Avg Recency  Avg Freq  Avg Spend   Total GMV
   Needs Attention    19,891    21.31%  514 days     1.00      158 BRL     3,154,905
   At Risk            17,453    18.69%  362 days     1.06      173 BRL     3,019,138
   New Customer       18,049    19.33%   94 days     1.00      163 BRL     2,947,357
   Others             18,671    20.00%  268 days     1.04      156 BRL     2,920,676
   Promising          13,240    14.18%  173 days     1.00      167 BRL     2,210,529
   Potential Loyalist  2,878     3.08%  210 days     1.00      161 BRL       462,019
   Loyal Customer      2,333     2.50%  211 days     1.16      157 BRL       365,213
   Champion              842     0.90%  129 days     2.20      407 BRL       342,625

   This table is the primary export to Power BI for the
   customer segmentation treemap and segment KPI visuals.
   ============================================================ */
SELECT
    segment,
    COUNT(customer_unique_id)                                                    AS total_customers,
    ROUND(COUNT(customer_unique_id) * 100.0 / SUM(COUNT(customer_unique_id)) OVER(), 2) AS pct_of_customers,
    ROUND(AVG(recency_days), 0)                                                  AS avg_recency_days,
    ROUND(AVG(frequency), 2)                                                     AS avg_frequency,
    ROUND(AVG(monetary), 2)                                                      AS avg_monetary_brl,
    ROUND(SUM(monetary), 2)                                                      AS total_revenue_brl
FROM rfm_segments
GROUP BY segment
ORDER BY total_revenue_brl DESC;