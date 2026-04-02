/* ============================================================
   DATA QUALITY AUDIT: ORDER_REVIEWS & ORDER_PAYMENTS TABLES
   Author: Amit Sanyal
   Objective: Validate customer feedback integrity and payment
   data reliability to ensure accurate Sentiment and Revenue KPIs.
   
   FINDINGS SUMMARY — ORDER_REVIEWS:
   - Null review scores                   : 0
   - Out of range scores (outside 1-5)    : 0
   - Duplicate review IDs                 : 814 (platform bug)
   - Reviews without comment (NULL)       : 0
   - Reviews without comment (empty string): 58,256 (58.7%)
   
   FINDINGS SUMMARY — ORDER_PAYMENTS:
   - Null values                          : 0
   - Zero value payments                  : 9 (voucher/not_defined only)
   - Invalid payment types (not_defined)  : 3 rows
   - Split payment orders                 : 2,246 orders
   ============================================================ */


/* ============================================================
   SECTION 1: REVIEW SCORE VALIDATION
   
   Review scores must be integers between 1 and 5 inclusive.
   NULL scores cannot be averaged and would corrupt CSAT/NPS
   calculations. Out of range scores (0, 6+) indicate a broken
   scoring interface or data entry error on Olist's platform.
   
   Result: 0 NULL scores, 0 out of range scores.
   All 99,223 reviews have valid scores. Sentiment analysis
   can proceed without any score-level filtering.
   ============================================================ */
SELECT 
    SUM(CASE WHEN review_score IS NULL THEN 1 ELSE 0 END) AS null_review_scores,
    COUNT(*) AS out_of_range_scores
FROM order_reviews
WHERE review_score < 1 OR review_score > 5;


/* ============================================================
   SECTION 2: DUPLICATE REVIEW ID CHECK
   
   Each review_id should uniquely identify a single customer
   review. Duplicates would inflate review counts and distort
   average rating calculations.
   
   Investigation revealed this is NOT simple data duplication —
   the same review_id is assigned to 2 or 3 DIFFERENT order_ids.
   This is a systematic ID generation bug on Olist's platform
   where the review_id counter was not properly isolated per order.
   
   Result: 814 duplicate review_ids found.
   Each duplicate review_id maps to 2-3 different orders.
   
   Action: review_id is NOT a reliable unique key in this dataset.
   All review analyses must be performed at the order_id level.
   Deduplication handled in analytical queries using:
   ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_creation_date DESC)
   ============================================================ */
SELECT 
    SUM(cnt - 1) AS total_duplicate_rows
FROM (
    SELECT COUNT(*) AS cnt
    FROM order_reviews
    GROUP BY review_id
    HAVING COUNT(*) > 1
) t;

-- Confirms duplicate review_ids map to multiple distinct orders
-- (not the same order inserted twice)
SELECT review_id, COUNT(DISTINCT order_id) AS distinct_orders
FROM order_reviews
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY distinct_orders DESC
LIMIT 10;


/* ============================================================
   SECTION 3: REVIEW COMMENT TEXT AUDIT
   
   Checks whether customers left written feedback alongside
   their star rating. Two separate checks are required:
   
   (a) NULL check — standard missing value detection
   (b) Empty string check — detects reviews where the comment
       field was submitted as blank rather than left as NULL,
       a common pattern in web form submissions
   
   Result:
   - NULL comments    : 0 (no NULLs in the column)
   - Empty strings    : 58,256 out of 99,223 reviews (58.7%)
   
   Key Insight: Only 41.3% of customers wrote a comment —
   the majority left only a star rating. This limits NLP/text
   analysis to ~41,000 reviews but does not affect score-based
   sentiment KPIs.
   
   Action: All text analysis queries must filter using:
   WHERE review_comment_message IS NOT NULL
   AND review_comment_message != ''
   ============================================================ */

-- Part A: NULL comment check
SELECT 
    SUM(CASE WHEN review_comment_message IS NULL THEN 1 ELSE 0 END) AS reviews_without_text,
    COUNT(*) AS total_reviews
FROM order_reviews;

-- Part B: Empty string comment check
SELECT COUNT(*) AS empty_comment_strings
FROM order_reviews
WHERE review_comment_message = '' 
OR review_comment_message = ' ';


/* ============================================================
   SECTION 4: NULL VALUE AUDIT — ORDER_PAYMENTS TABLE
   
   Every payment record must have an order reference, payment
   type, value and installment count. NULLs in any of these
   fields would make the payment unattributable and corrupt
   total revenue and payment method distribution reports.
   
   Result: 0 NULLs across all columns.
   Payment table is fully populated and ready for analysis.
   ============================================================ */
SELECT
    SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) AS null_order_id,
    SUM(CASE WHEN payment_type IS NULL THEN 1 ELSE 0 END) AS null_payment_type,
    SUM(CASE WHEN payment_value IS NULL THEN 1 ELSE 0 END) AS null_payment_value,
    SUM(CASE WHEN payment_installments IS NULL THEN 1 ELSE 0 END) AS null_installments
FROM order_payments;


/* ============================================================
   SECTION 5: INVALID PAYMENT VALUE CHECK
   
   Every payment must have a positive value. Zero or negative
   payment values would corrupt GMV, AOV and revenue totals.
   
   Investigation of the 9 zero-value payments revealed:
   - 6 rows: payment_type = 'voucher' with payment_value = 0
     These represent fully discounted orders where a voucher
     covered the entire order value. This is VALID business data.
   - 3 rows: payment_type = 'not_defined' with payment_value = 0
     These are system placeholder rows with no valid payment
     type or value — likely failed payment type detection.
   
   Result: 9 zero value payments found.
   Action: Voucher zeros retained. 'not_defined' rows excluded
   from all revenue calculations using:
   WHERE payment_type != 'not_defined'
   ============================================================ */

-- Identify count of zero/negative payments
SELECT COUNT(*) AS invalid_payment_values
FROM order_payments
WHERE payment_value <= 0;

-- Investigate zero payment breakdown by type
SELECT * FROM order_payments
WHERE payment_value = 0;


/* ============================================================
   SECTION 6: PAYMENT TYPE DISTRIBUTION
   
   Provides a breakdown of all payment methods used on the
   platform. Helps contextualize Brazilian consumer payment
   behaviour and validates no unexpected payment types exist.
   
   Result:
   - credit_card : 76,795 (74.0%) — dominant payment method
   - boleto      : 19,784 (19.1%) — Brazilian bank slip, common
                                     for unbanked population
   - voucher     :  5,775 ( 5.6%) — discount/promotional codes
   - debit_card  :  1,529 ( 1.5%) — direct bank debit
   - not_defined :      3 ( 0.0%) — invalid, excluded from analysis
   
   Key Insight: Brazil's high boleto usage (19%) reflects the
   large unbanked population that cannot access credit cards.
   This is a unique characteristic of Brazilian e-commerce
   not seen in Western markets.
   ============================================================ */
SELECT payment_type, COUNT(*) AS cnt
FROM order_payments
GROUP BY payment_type
ORDER BY cnt DESC;


/* ============================================================
   SECTION 7: SPLIT PAYMENT DETECTION
   
   Some customers pay for a single order using multiple payment
   methods — for example, part by voucher and part by credit card.
   These orders appear as multiple rows in order_payments with
   the same order_id but different payment_types.
   
   Failing to account for split payments would cause revenue
   double-counting if payment rows are summed without aggregation.
   
   Result: 2,246 orders used more than one payment method (2.2%).
   
   Action: Always aggregate payment values at the order level:
   SELECT order_id, SUM(payment_value) AS total_payment
   FROM order_payments
   GROUP BY order_id
   This naturally handles both single and split payment orders.
   ============================================================ */
SELECT COUNT(*) AS split_payment_orders
FROM (
    SELECT order_id, COUNT(DISTINCT payment_type) AS payment_methods
    FROM order_payments
    GROUP BY order_id
    HAVING payment_methods > 1
) t;