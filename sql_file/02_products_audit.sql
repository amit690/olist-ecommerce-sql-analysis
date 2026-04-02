/* ============================================================
   DATA QUALITY AUDIT: PRODUCTS & CATEGORY_TRANSLATION TABLES
   Author: Amit Sanyal
   Objective: Validate product master data integrity and ensure
   complete category coverage for department-level revenue analysis.
   
   FINDINGS SUMMARY:
   - Null product IDs                      : 0
   - Null category names                   : 610 products
   - Null name/description/photo fields    : 0
   - Null physical dimensions              : 0
   - Empty string categories               : 0
   - Duplicate product IDs                 : 0
   - Categories missing English translation: 2 (fixed via INSERT)
   - Invalid dimensions (zero or negative) : 6 weight, 2 each length/height/width
   - Unsold products                       : 0
   - Suspicious extreme dimension values   : 0
   ============================================================ */


/* ============================================================
   SECTION 1: NULL VALUE AUDIT — PRODUCTS TABLE
   
   Checks identity and descriptive columns for missing values.
   
   Expectation:
   - product_id must NEVER be NULL — it is the primary key and
     foreign key referenced by order_items.
   - product_category_name NULLs are a real data gap — 610 products
     have no category assigned. These will be handled at the query
     level using COALESCE(product_category_name, 'Uncategorized')
     to prevent silent exclusion from category revenue reports.
   - name_length, description_length, photos_qty are metadata
     fields — NULLs here are acceptable but worth tracking.
   
   Result: 610 NULL categories found. All other fields complete.
   ============================================================ */
SELECT 
    SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END) AS null_product_id,
    SUM(CASE WHEN product_category_name IS NULL THEN 1 ELSE 0 END) AS null_category,
    SUM(CASE WHEN product_name_length IS NULL THEN 1 ELSE 0 END) AS null_name_length,
    SUM(CASE WHEN product_description_length IS NULL THEN 1 ELSE 0 END) AS null_description_length,
    SUM(CASE WHEN product_photos_qty IS NULL THEN 1 ELSE 0 END) AS null_photos
FROM products;


/* ============================================================
   SECTION 2: NULL PHYSICAL DIMENSIONS AUDIT
   
   Weight and dimensions are required for shipping cost analysis.
   Olist's freight pricing is heavily influenced by package size
   and weight — NULL values here would break any logistics KPI
   that attempts to correlate product size with freight charges.
   
   Result: 0 NULLs. All physical attributes fully populated.
   ============================================================ */
SELECT 
    SUM(CASE WHEN product_weight_g IS NULL THEN 1 ELSE 0 END) AS null_weight,
    SUM(CASE WHEN product_length_cm IS NULL THEN 1 ELSE 0 END) AS null_length,
    SUM(CASE WHEN product_height_cm IS NULL THEN 1 ELSE 0 END) AS null_height,
    SUM(CASE WHEN product_width_cm IS NULL THEN 1 ELSE 0 END) AS null_width
FROM products;


/* ============================================================
   SECTION 3: EMPTY STRING CATEGORY CHECK
   
   Checks for categories that appear populated but contain only
   whitespace or empty strings — a common data entry issue that
   would pass a NULL check but still produce blank labels in
   dashboards and reports.
   
   Result: 0 empty strings. The 610 missing categories are proper
   NULLs, not hidden empty strings. No additional handling needed.
   ============================================================ */
SELECT COUNT(*) AS empty_category_strings
FROM products
WHERE product_category_name = '' OR product_category_name = ' ';


/* ============================================================
   SECTION 4: DUPLICATE PRODUCT ID CHECK
   
   product_id is the primary key of the products table and must
   be unique. Duplicate product IDs would cause fan-out issues
   when joining with order_items, inflating item counts and revenue.
   
   Result: 0 duplicates. Primary key integrity confirmed.
   ============================================================ */
SELECT product_id, COUNT(*) AS cnt
FROM products
GROUP BY product_id
HAVING cnt > 1;


/* ============================================================
   SECTION 5: CATEGORY TRANSLATION COVERAGE CHECK
   
   The category_translation table maps Portuguese category names
   to English equivalents used in Power BI dashboards.
   
   This check identifies Portuguese category names in the products
   table that have NO matching row in category_translation. These
   categories would appear as NULL in any English-language report
   or dashboard visual that joins to category_translation.
   
   NULL categories are excluded from this check (handled separately
   via COALESCE in analytical queries).
   
   Result: 2 untranslated categories found:
   - 'pc_gamer'
   - 'portateis_cozinha_e_preparadores_de_alimentos'
   Action: Missing translations inserted manually in Section 6.
   ============================================================ */
SELECT DISTINCT p.product_category_name
FROM products p
LEFT JOIN category_translation ct 
    ON p.product_category_name = ct.product_category_name
WHERE ct.product_category_name IS NULL
AND p.product_category_name IS NOT NULL;


/* ============================================================
   SECTION 6: DATA CORRECTION — INSERT MISSING TRANSLATIONS
   
   Two category names exist in the products table but were absent
   from the category_translation master table. Rather than losing
   these products in category-level analyses, the correct English
   translations are inserted directly into the reference table.
   
   Translations verified manually:
   - 'pc_gamer' → 'PC Gamer' (self-explanatory)
   - 'portateis_cozinha_e_preparadores_de_alimentos'
     → 'Portable Kitchen & Food Processors'
     (Portuguese: portáteis = portable, cozinha = kitchen,
      preparadores de alimentos = food processors)
   
   This is a permanent fix to the reference data — no query-level
   workaround needed for these two categories going forward.
   ============================================================ */
INSERT INTO category_translation (product_category_name, product_category_name_english)
VALUES 
    ('pc_gamer', 'PC Gamer'),
    ('portateis_cozinha_e_preparadores_de_alimentos', 'Portable Kitchen & Food Processors');


/* ============================================================
   SECTION 7: VERIFY TRANSLATION INSERT
   
   Confirms the two missing translations were successfully added
   to the category_translation table.
   
   Expected Result: 2 rows returned with correct English names.
   ============================================================ */
SELECT * FROM category_translation 
WHERE product_category_name IN 
    ('pc_gamer', 'portateis_cozinha_e_preparadores_de_alimentos');


/* ============================================================
   SECTION 8: INVALID PHYSICAL DIMENSION VALUES
   
   Although no NULLs were found in dimension columns (Section 2),
   zero or negative values are equally invalid — a product cannot
   have zero weight or negative length. These represent data entry
   errors likely caused by incomplete seller product registration.
   
   Result:
   - Invalid weight (<=0) : 6 products
   - Invalid length (<=0) : 2 products
   - Invalid height (<=0) : 2 products
   - Invalid width  (<=0) : 2 products
   
   Action: These 6 products are excluded from any freight cost
   or logistics analysis using: WHERE product_weight_g > 0
   The count is negligible (<0.02% of 32,951 products) and does
   not impact category or revenue analyses.
   ============================================================ */
SELECT 
    SUM(CASE WHEN product_weight_g <= 0 THEN 1 ELSE 0 END) AS invalid_weight,
    SUM(CASE WHEN product_length_cm <= 0 THEN 1 ELSE 0 END) AS invalid_length,
    SUM(CASE WHEN product_height_cm <= 0 THEN 1 ELSE 0 END) AS invalid_height,
    SUM(CASE WHEN product_width_cm <= 0 THEN 1 ELSE 0 END) AS invalid_width
FROM products;


/* ============================================================
   SECTION 9: UNSOLD PRODUCTS CHECK
   
   Identifies products registered in the master table that have
   never appeared in a single order. Unsold products indicate
   either inactive listings or products added after the dataset
   capture period ended.
   
   Result: 0 unsold products. Every registered product has been
   sold at least once — confirming the product master table is
   an accurate reflection of active inventory during this period.
   ============================================================ */
SELECT COUNT(*) AS unsold_products
FROM products p
LEFT JOIN order_items oi ON p.product_id = oi.product_id
WHERE oi.product_id IS NULL;


/* ============================================================
   SECTION 10: EXTREME DIMENSION VALUE CHECK
   
   Checks for unrealistically large physical measurements that
   could indicate unit errors (e.g. grams entered as kilograms)
   or system default placeholder values. Thresholds used:
   - Weight > 100,000g (100kg) — unusually heavy for e-commerce
   - Any dimension > 200cm — unusually large for a shipped package
   
   Result: 0 products with extreme values. All dimension data
   falls within realistic ranges for e-commerce products.
   ============================================================ */
SELECT COUNT(*) AS suspicious_dimensions
FROM products
WHERE product_weight_g > 100000
OR product_length_cm > 200
OR product_height_cm > 200
OR product_width_cm > 200;

/* ============================================================
   SECTION 11: CATEGORY_TRANSLATION TABLE INTEGRITY CHECK
   
   The category_translation table serves as the master reference
   for all English category labels used in Power BI dashboards.
   Unlike the products table where NULLs represent unregistered
   categories, this table must have zero missing or empty values
   on both sides of the mapping.
   
   Two checks are performed:
   (a) English translation column — empty strings or NULLs would
       produce blank category labels in every dashboard visual
       that displays English category names.
   (b) Portuguese category column — empty strings or NULLs would
       break the JOIN between products and category_translation,
       causing categories to silently disappear from reports.
   
   Result: 0 empty or NULL values on both sides.
   The translation reference table is fully intact and reliable.
   ============================================================ */

-- Part A: English translation column integrity
SELECT COUNT(*) AS empty_english_translations
FROM category_translation
WHERE product_category_name_english = '' 
OR product_category_name_english = ' '
OR product_category_name_english IS NULL;

-- Part B: Portuguese category column integrity
SELECT COUNT(*) AS empty_portuguese_categories
FROM category_translation
WHERE product_category_name = '' 
OR product_category_name = ' '
OR product_category_name IS NULL;