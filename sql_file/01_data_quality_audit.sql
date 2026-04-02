/* ============================================================
   DATA QUALITY AUDIT: ORDERS & ORDER_ITEMS TABLES
   Author: Amit Sanyal
   Objective: Identify logical inconsistencies in the Olist 
   dataset to ensure reliability of Revenue and Logistical KPIs.
   
   FINDINGS SUMMARY:
   - Null values in orders table          : 0 critical nulls
   - Duplicate order IDs                  : 0 duplicates
   - Inconsistent delivery timestamps     : 3,154 rows
   - Ghost orders (no items)              : 775 rows
   - Approval before purchase             : 160 rows
   - Estimated delivery before purchase   : 0 rows
   - Delivered orders missing date        : 0 rows
   - Unavailable orders with delivery date: 609 rows
   - Null values in order_items           : 0 nulls
   - Invalid prices (zero or negative)    : 0 rows
   - Zero freight value                   : Valid (free shipping)
   - Orphaned items (no parent order)     : 0 rows
   - Orphaned products (not in master)    : 0 rows
   - Orphaned sellers (not in master)     : 0 rows
   - Duplicate composite keys             : 0 rows
   - Free shipping items                  : 383 (0.34%)
   ============================================================ */


/* ============================================================
   SECTION 1: NULL VALUE AUDIT — ORDERS TABLE
   
   Checks every key column for missing values.
   
   Expectation:
   - order_id, customer_id, order_status, order_purchase_timestamp
     must NEVER be NULL — these are the backbone of every analysis.
   - Delivery date columns (carrier, customer, estimated) MAY be NULL
     for orders that are not yet delivered (shipped, cancelled etc.)
     These NULLs are meaningful and must NOT be treated as errors.
   
   Result: No critical nulls found. Dataset is safe to analyse.
   ============================================================ */
SELECT 
    SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) AS null_order_id,
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS null_customer_id,
    SUM(CASE WHEN order_status IS NULL THEN 1 ELSE 0 END) AS null_status,
    SUM(CASE WHEN order_purchase_timestamp IS NULL THEN 1 ELSE 0 END) AS null_purchase_date,
    SUM(CASE WHEN order_approved_at IS NULL THEN 1 ELSE 0 END) AS null_approved,
    SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END) AS null_carrier,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS null_delivered,
    SUM(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END) AS null_estimated 
FROM orders;


/* ============================================================
   SECTION 2: DUPLICATE ORDER ID CHECK
   
   order_id is the primary key of the orders table and must be
   unique. A single order appearing twice would cause revenue,
   customer count, and order volume KPIs to be double-counted.
   
   Result: No duplicates found. Primary key integrity confirmed.
   ============================================================ */
SELECT order_id, COUNT(*) AS cnt 
FROM orders 
GROUP BY order_id 
HAVING cnt > 1;


/* ============================================================
   SECTION 3: INCONSISTENT DELIVERY TIMESTAMPS
   
   Validates the logical sequence of the order fulfillment pipeline:
   Purchase → Carrier Handoff → Customer Delivery
   
   Two violations are checked:
   (a) Carrier handoff date is BEFORE the purchase date
   (b) Customer delivery date is BEFORE the carrier handoff date
   
   Note: Only rows where ALL THREE dates are non-NULL are evaluated.
   This avoids false positives from undelivered/cancelled orders
   where NULL delivery dates would otherwise trigger the condition.
   
   Result: 3,154 rows flagged (~3.2% of dataset).
   Action: Excluded from all delivery lead time calculations
           by filtering WHERE order_status = 'delivered' and 
           validating timestamp sequence in analytical queries.
   ============================================================ */
SELECT COUNT(*) AS total_invalid_dates
FROM orders
WHERE (order_delivered_carrier_date < order_purchase_timestamp 
       OR order_delivered_customer_date < order_delivered_carrier_date)
  AND order_delivered_carrier_date IS NOT NULL
  AND order_delivered_customer_date IS NOT NULL
  AND order_purchase_timestamp IS NOT NULL;


/* ============================================================
   SECTION 4: GHOST ORDERS (Orphaned Order Records)
   
   Identifies orders in the orders table that have no matching
   rows in order_items. These are orders with no products —
   likely caused by failed payments, immediate cancellations,
   or data pipeline gaps on Olist's platform.
   
   Business Impact: Ghost orders inflate order count metrics
   without contributing any revenue. They are naturally excluded
   from revenue analysis via INNER JOINs with order_items.
   
   Result: 775 ghost orders found (~0.78% of orders).
   Action: No deletion. Excluded via JOIN logic in analyses.
   ============================================================ */
SELECT COUNT(*) AS ghost_orders
FROM orders o
LEFT JOIN order_items oi ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL;


/* ============================================================
   SECTION 5: IMPOSSIBLE APPROVAL TIMESTAMPS
   
   An order cannot be approved before it is placed.
   Flags rows where order_approved_at < order_purchase_timestamp,
   which indicates a system clock synchronization error or a
   data entry mistake on Olist's order management platform.
   
   NULL approvals are excluded as they represent orders that
   were never approved (e.g. cancelled before approval).
   
   Result: 160 rows flagged (~0.16% of orders).
   Action: Excluded from approval lead time analyses.
   ============================================================ */
SELECT 
    COUNT(*) AS err_approval_before_purchase
FROM orders
WHERE order_approved_at < order_purchase_timestamp
  AND order_approved_at IS NOT NULL;


/* ============================================================
   SECTION 6: ESTIMATED DELIVERY DATE VALIDATION
   
   The estimated delivery date shown to a customer at checkout
   must always be a future date relative to the purchase date.
   An estimated delivery in the past would indicate a broken
   delivery promise engine on Olist's platform.
   
   Result: 0 rows. All estimated delivery dates are valid.
   ============================================================ */
SELECT 
    COUNT(*) AS err_past_estimated_delivery
FROM orders
WHERE order_estimated_delivery_date < order_purchase_timestamp
  AND order_estimated_delivery_date IS NOT NULL;


/* ============================================================
   SECTION 7: ORDER STATUS DISTRIBUTION
   
   Provides a full breakdown of order lifecycle statuses.
   Used to understand the proportion of completed vs incomplete
   orders and to provide context for the consistency checks
   in Section 8 below.
   
   Result:
   delivered(96,478) | shipped(1,107) | cancelled(625)
   unavailable(609)  | invoiced(314)  | processing(301)
   created(5)        | approved(2)
   
   Key Insight: 96.8% of orders reached delivered status,
   indicating a healthy order fulfillment rate on the platform.
   ============================================================ */
SELECT 
    order_status, 
    COUNT(*) AS cnt
FROM orders
GROUP BY order_status
ORDER BY cnt DESC;


/* ============================================================
   SECTION 8: ORDER STATUS VS. DELIVERY DATE CONSISTENCY
   
   Cross-validates order_status against delivery timestamps
   to catch mismatches that would corrupt KPI calculations.
   
   Part A — Delivered orders missing a delivery timestamp:
   Every order marked 'delivered' must have a recorded
   delivery date. Missing dates would make it impossible
   to calculate actual lead times or on-time delivery rates.
   Result: 0 rows. All delivered orders have a delivery date.
   
   Part B — Cancelled/unavailable orders with a delivery date:
   Orders that did not complete should not have a delivery date.
   A delivery date on a cancelled order suggests a status
   update failure in Olist's order management system.
   Result: 609 rows found.
   
   Part C — Breakdown of Part B by status:
   Confirms all 609 flagged rows belong exclusively to
   'unavailable' orders. This is a known Olist platform quirk
   where delivery was physically completed but the order status
   was never updated correctly in the system.
   Action: Always filter WHERE order_status = 'delivered'
           in delivery-related analyses to avoid these rows.
   ============================================================ */

-- Part A
SELECT COUNT(*) AS delivered_but_no_date
FROM orders
WHERE order_status = 'delivered'
AND order_delivered_customer_date IS NULL;

-- Part B
SELECT COUNT(*) AS cancelled_but_delivered
FROM orders
WHERE order_status IN ('cancelled', 'unavailable')
AND order_delivered_customer_date IS NOT NULL;

-- Part C
SELECT order_status, COUNT(*) AS cnt
FROM orders
WHERE order_delivered_customer_date IS NOT NULL
AND order_status IN ('cancelled', 'unavailable')
GROUP BY order_status;


/* ============================================================
   SECTION 9: NULL VALUE AUDIT — ORDER_ITEMS TABLE
   
   Every column in order_items is operationally critical.
   Unlike the orders table, there is no valid business reason
   for any NULL in this table — every item must have an order,
   product, seller, price and freight value to be meaningful.
   
   Result: No nulls found. order_items is fully populated.
   ============================================================ */
SELECT
    SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) AS null_order_id,
    SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END) AS null_product_id,
    SUM(CASE WHEN seller_id IS NULL THEN 1 ELSE 0 END) AS null_seller_id,
    SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END) AS null_price,
    SUM(CASE WHEN freight_value IS NULL THEN 1 ELSE 0 END) AS null_freight
FROM order_items;


/* ============================================================
   SECTION 10: INVALID PRICE CHECK — ORDER_ITEMS TABLE
   
   Every sold item must have a positive price. Zero or negative
   prices are logically invalid for a paid marketplace and would
   directly corrupt Revenue, AOV and GMV calculations.
   
   Note: Zero freight_value is intentionally excluded from this
   check — it is a valid business scenario representing free
   shipping promotions offered by sellers. Only 383 items (0.34%)
   have zero freight, confirming it is rare and legitimate.
   
   Result: 0 invalid prices found. All item prices are positive.
   ============================================================ */
SELECT COUNT(*) AS total_invalid_prices
FROM order_items
WHERE price <= 0;


/* ============================================================
   SECTION 11: REFERENTIAL INTEGRITY AUDIT — ORDER_ITEMS
   
   Validates that every foreign key in order_items resolves
   to a valid parent record in its respective master table.
   Three relationships are checked:
   
   (a) order_id → orders table
       Orphaned items with no parent order have no customer
       context and cannot be attributed to any transaction.
   
   (b) product_id → products table  
       Items referencing unknown products cannot be categorized,
       breaking all category-level revenue and ranking analyses.
   
   (c) seller_id → sellers table
       Items from unknown sellers cannot be attributed to any
       region or seller performance metric.
   
   Result: 0 orphaned records across all three checks.
   Referential integrity is fully intact across the schema.
   ============================================================ */

-- Part A: Orphaned items with no parent order
SELECT COUNT(*) AS orphaned_items_no_order
FROM order_items oi
LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;

-- Part B: Items referencing non-existent products
SELECT COUNT(*) AS orphaned_products
FROM order_items oi
LEFT JOIN products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;

-- Part C: Items referencing non-existent sellers
SELECT COUNT(*) AS orphaned_sellers
FROM order_items oi
LEFT JOIN sellers s ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;


/* ============================================================
   SECTION 12: DUPLICATE & LOGISTICS AUDIT — ORDER_ITEMS
   
   Part A — Composite Key Validation:
   Each row in order_items is uniquely identified by the
   combination of order_id + order_item_id. For example,
   order #ABC with item #1 and item #2 are two valid rows,
   but two rows both showing order #ABC item #1 would be
   a duplicate causing revenue over-reporting.
   
   Result: 0 duplicate composite keys found.
   
   Part B — Free Shipping Distribution:
   Measures the proportion of items where freight_value = 0,
   indicating seller-sponsored free shipping promotions.
   This contextualizes profit margin analysis — free shipping
   absorbs seller costs and reduces effective margins.
   
   Key Insight: Only 383 of 112,650 items (0.34%) have free
   shipping, confirming that freight charges are the norm on
   Olist. This reflects Brazil's challenging logistics landscape
   where shipping costs are a significant portion of order value.
   ============================================================ */

-- Part A: Duplicate composite key check
SELECT order_id, order_item_id, COUNT(*) AS cnt
FROM order_items
GROUP BY order_id, order_item_id
HAVING cnt > 1;

-- Part B: Free shipping distribution
SELECT 
    SUM(CASE WHEN freight_value = 0 THEN 1 ELSE 0 END) AS free_shipping_count,
    COUNT(*) AS total_items,
    ROUND((SUM(CASE WHEN freight_value = 0 THEN 1 ELSE 0 END) / COUNT(*)) * 100, 2) AS free_shipping_pct
FROM order_items;