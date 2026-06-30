
CREATE DATABASE ecommerce;
USE ecommerce;
SET GLOBAL local_infile = ON;
CREATE TABLE geolocation( geolocation_zip_code_prefix VARCHAR(5),
    geolocation_lat DECIMAL(20,16),
    geolocation_lng DECIMAL(20,16),
    geolocation_city VARCHAR(100),
    geolocation_state CHAR(2)
);
LOAD DATA LOCAL INFILE 'C:/Users/arunt/Downloads/archive/olist_geolocation_dataset.csv'
INTO TABLE geolocation
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;



CREATE VIEW order_payment_totals AS
SELECT
    order_id,
    SUM(payment_value) AS total_payment_value,
    COUNT(*) AS payment_installments_count
FROM order_payments
GROUP BY order_id;

/*=========================================================
  Doing Sanity Check
=========================================================*/

CREATE VIEW order_item_detail AS
SELECT
    oi.order_id,
    oi.product_id,
    oi.seller_id,
    oi.price,
    oi.freight_value,
    p.product_category_name,
    ct.product_category_name_english,
    s.seller_city,
    s.seller_state
FROM order_items oi
JOIN products p
    ON oi.product_id = p.product_id
LEFT JOIN category_translation ct
    ON p.product_category_name = ct.product_category_name
JOIN sellers s
    ON oi.seller_id = s.seller_id;



SELECT 'master_transactions' AS view_name, COUNT(*) AS row_count FROM master_transactions
UNION ALL
SELECT 'order_item_detail', COUNT(*) FROM order_item_detail
UNION ALL

 
SELECT * FROM master_transactions LIMIT 10;

/*=========================================================
  Cleaning and Making Sellers Table
=========================================================*/

SELECT order_id, COUNT(*) AS cnt FROM orders GROUP BY order_id HAVING COUNT(*) > 1;
SELECT customer_id, COUNT(*) AS cnt FROM customers GROUP BY customer_id HAVING COUNT(*) > 1;

SELECT
    SUM(order_purchase_timestamp IS NULL) AS null_purchase_date,
    SUM(order_delivered_customer_date IS NULL) AS null_delivered_date,
    SUM(customer_id IS NULL) AS null_customer_id
FROM orders;

SELECT COUNT(*) AS zero_or_negative_price FROM order_items WHERE price <= 0;
SELECT COUNT(*) AS zero_or_negative_payment FROM order_payments WHERE payment_value <= 0;

SELECT * FROM order_payments WHERE payment_value <= 0;

SELECT COUNT(*) AS bad_date_orders
FROM orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_delivered_customer_date < order_purchase_timestamp;
  
  
SELECT COUNT(*) AS orphan_products
FROM order_items oi
LEFT JOIN products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;


SELECT DISTINCT customer_city
FROM customers
WHERE customer_city LIKE '%sao paulo%' OR customer_city LIKE '%são paulo%';

DROP VIEW IF EXISTS master_transactions;
DROP VIEW IF EXISTS order_item_detail;
DROP VIEW IF EXISTS geolocation_avg;

/*=========================================================
  Cleaning and Making Customers Table
=========================================================*/

CREATE VIEW customers_clean AS
SELECT
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_state,
    LOWER(
      REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
      TRIM(customer_city),
      'á','a'),'à','a'),'â','a'),'ã','a'),
      'é','e'),'ê','e'),
      'í','i'),
      'ó','o'),'ô','o'),'õ','o'),
      'ú','u'),
      'ç','c')
    ) AS customer_city_clean
FROM customers;

/*=========================================================
  Cleaning and Making Sellers Table
=========================================================*/

CREATE VIEW sellers_clean AS
SELECT
    seller_id,
    seller_zip_code_prefix,
    seller_state,
    LOWER(
      REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
      TRIM(seller_city),
      'á','a'),'à','a'),'â','a'),'ã','a'),
      'é','e'),'ê','e'),
      'í','i'),
      'ó','o'),'ô','o'),'õ','o'),
      'ú','u'),
      'ç','c')
    ) AS seller_city_clean
FROM sellers;

/*=========================================================
 Master Transactions Table
=========================================================*/

CREATE VIEW master_transactions AS
SELECT
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.customer_zip_code_prefix,
    c.customer_city_clean,
    c.customer_state,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    opt.total_payment_value,
    opt.payment_installments_count,
    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
             AND o.order_delivered_customer_date < o.order_purchase_timestamp
        THEN 1 ELSE 0
    END AS has_bad_date_flag
FROM orders o
JOIN customers_clean c
    ON o.customer_id = c.customer_id
JOIN order_payment_totals opt
    ON o.order_id = opt.order_id
WHERE o.order_status = 'delivered'
  AND opt.total_payment_value > 0;   -- drop zero/negative-value orders (data errors)
  
  /*=========================================================
  Order Item View Table
=========================================================*/
  
  CREATE VIEW order_item_detail AS
SELECT
    oi.order_id,
    oi.product_id,
    oi.seller_id,
    oi.price,
    oi.freight_value,
    COALESCE(ct.product_category_name_english, 'uncategorized') AS category_english,
    s.seller_city_clean,
    s.seller_state,
    CASE WHEN p.product_id IS NULL THEN 1 ELSE 0 END AS missing_product_flag,
    CASE WHEN s.seller_id IS NULL THEN 1 ELSE 0 END AS missing_seller_flag
FROM order_items oi
LEFT JOIN products p
    ON oi.product_id = p.product_id
LEFT JOIN category_translation ct
    ON p.product_category_name = ct.product_category_name
LEFT JOIN sellers_clean s
    ON oi.seller_id = s.seller_id
WHERE oi.price > 0;  -- drop zero/negative price line items

/*=========================================================
  making avg lat and longt for same zipcodes
=========================================================*/

CREATE VIEW geolocation_avg AS
SELECT
    geolocation_zip_code_prefix,
    AVG(geolocation_lat) AS avg_lat,
    AVG(geolocation_lng) AS avg_lng,
    MIN(
      LOWER(
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
        TRIM(geolocation_city),
        'á','a'),'à','a'),'â','a'),'ã','a'),
        'é','e'),'ê','e'),
        'í','i'),
        'ó','o'),'ô','o'),'õ','o'),
        'ú','u'),
        'ç','c')
      )
    ) AS city_clean,
    MIN(geolocation_state) AS state
FROM geolocation
GROUP BY geolocation_zip_code_prefix;

SELECT 'master_transactions' AS view_name, COUNT(*) AS row_count, SUM(has_bad_date_flag) AS bad_date_rows FROM master_transactions
UNION ALL
SELECT 'order_item_detail', COUNT(*), NULL FROM order_item_detail;
 
SELECT COUNT(*) AS remaining_orphan_products FROM order_item_detail WHERE missing_product_flag = 1;
SELECT COUNT(*) AS remaining_orphan_sellers FROM order_item_detail WHERE missing_seller_flag = 1;



/*=========================================================
  RFM ANALYSIS
=========================================================*/

DROP VIEW IF EXISTS rfm_raw;
CREATE VIEW rfm_raw AS
SELECT
    customer_unique_id,
    MAX(order_purchase_timestamp) AS last_order_date,
    DATEDIFF(
        (SELECT MAX(order_purchase_timestamp) FROM master_transactions),
        MAX(order_purchase_timestamp)
    ) AS recency,
    COUNT(DISTINCT order_id) AS frequency,
    SUM(total_payment_value) AS monetary
FROM master_transactions
GROUP BY customer_unique_id;

/*=========================================================
  Customers Scores
=========================================================*/

DROP VIEW IF EXISTS rfm_scored;
CREATE VIEW rfm_scored AS
SELECT
    customer_unique_id,
    recency,
    frequency,
    monetary,
    NTILE(5) OVER (ORDER BY recency DESC) AS r_score,
    CASE
        WHEN frequency = 1 THEN 1
        WHEN frequency = 2 THEN 3
        WHEN frequency >= 3 THEN 5
    END AS f_score,
    NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
FROM rfm_raw;

/*=========================================================
 RFM segments
=========================================================*/

DROP VIEW IF EXISTS rfm_segments;
CREATE VIEW rfm_segments AS
SELECT
    customer_unique_id,
    recency,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3                   THEN 'Loyal Customers'
        WHEN r_score >= 4 AND f_score <= 2                   THEN 'New Customers'
        WHEN r_score <= 2 AND f_score >= 3                   THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2  THEN 'Lost'
        ELSE 'Needs Attention'
    END AS segment
FROM rfm_scored;

SELECT frequency, COUNT(*) AS customer_count
FROM rfm_raw
GROUP BY frequency
ORDER BY frequency;


SELECT segment, COUNT(*) AS customer_count, ROUND(AVG(monetary),2) AS avg_monetary
FROM rfm_segments
GROUP BY segment
ORDER BY customer_count DESC;

/*=========================================================
  Customer Cohort
=========================================================*/

CREATE VIEW customer_cohort AS
SELECT
    customer_unique_id,
    DATE_FORMAT(MIN(order_purchase_timestamp), '%Y-%m-01') AS cohort_month
FROM master_transactions
GROUP BY customer_unique_id;

/*=========================================================
  COHORT ORDERS VIEW
=========================================================*/

CREATE VIEW cohort_orders AS
SELECT
    mt.customer_unique_id,
    cc.cohort_month,
    PERIOD_DIFF(
        DATE_FORMAT(mt.order_purchase_timestamp, '%Y%m'),
        DATE_FORMAT(cc.cohort_month, '%Y%m')
    ) AS month_number
FROM master_transactions mt
JOIN customer_cohort cc
    ON mt.customer_unique_id = cc.customer_unique_id;
    
    /*=========================================================
        Cohort Sizes
=========================================================*/
    
    CREATE VIEW cohort_sizes AS
SELECT cohort_month, COUNT(DISTINCT customer_unique_id) AS cohort_size
FROM customer_cohort
GROUP BY cohort_month;


SELECT
    co.cohort_month,
    co.month_number,
    COUNT(DISTINCT co.customer_unique_id) AS active_customers,
    cs.cohort_size,
    ROUND(COUNT(DISTINCT co.customer_unique_id) / cs.cohort_size * 100, 1) AS retention_pct
FROM cohort_orders co
JOIN cohort_sizes cs
    ON co.cohort_month = cs.cohort_month
GROUP BY co.cohort_month, co.month_number, cs.cohort_size
ORDER BY co.cohort_month, co.month_number;

/*=========================================================
  Cohort Retention View
=========================================================*/

DROP VIEW IF EXISTS cohort_retention;
CREATE VIEW cohort_retention AS
SELECT
    co.cohort_month,
    co.month_number,
    COUNT(DISTINCT co.customer_unique_id) AS active_customers,
    cs.cohort_size,
    ROUND(COUNT(DISTINCT co.customer_unique_id) / cs.cohort_size * 100, 1) AS retention_pct
FROM cohort_orders co
JOIN cohort_sizes cs
    ON co.cohort_month = cs.cohort_month
GROUP BY co.cohort_month, co.month_number, cs.cohort_size
ORDER BY co.cohort_month, co.month_number;
 
SELECT * FROM cohort_retention;
 
/*=========================================================
  Customer State Map
=========================================================*/

DROP VIEW IF EXISTS customer_state_map;
CREATE VIEW customer_state_map AS
SELECT
    customer_unique_id,
    MAX(customer_state) AS customer_state  -- arbitrary tie-break if a customer's orders show >1 state (rare)
FROM master_transactions
GROUP BY customer_unique_id;

SELECT
    csm.customer_state,
    rs.segment,
    COUNT(DISTINCT rs.customer_unique_id) AS customer_count,
    ROUND(AVG(rs.monetary),2) AS avg_monetary
FROM rfm_segments rs
JOIN customer_state_map csm
    ON rs.customer_unique_id = csm.customer_unique_id
GROUP BY csm.customer_state, rs.segment
ORDER BY csm.customer_state, customer_count DESC;

SELECT
    csm.customer_state,
    COUNT(DISTINCT csm.customer_unique_id) AS total_customers,
    SUM(CASE WHEN rs.segment IN ('Champions','Loyal Customers') THEN 1 ELSE 0 END) AS high_value_customers,
    ROUND(SUM(CASE WHEN rs.segment IN ('Champions','Loyal Customers') THEN 1 ELSE 0 END) 
          / COUNT(DISTINCT csm.customer_unique_id) * 100, 2) AS high_value_pct
FROM customer_state_map csm
JOIN rfm_segments rs
    ON csm.customer_unique_id = rs.customer_unique_id
GROUP BY csm.customer_state
HAVING total_customers >= 100  -- exclude tiny states with too few customers to be meaningful
ORDER BY high_value_pct DESC;

/*=========================================================
  REGIONAL CUSTOMER SEGMENT ANALYSIS
=========================================================*/

DROP VIEW IF EXISTS regional_segment_summary;
CREATE VIEW regional_segment_summary AS
SELECT
    csm.customer_state,
    rs.segment,
    COUNT(DISTINCT rs.customer_unique_id) AS customer_count,
    ROUND(AVG(rs.monetary),2) AS avg_monetary
FROM rfm_segments rs
JOIN customer_state_map csm
    ON rs.customer_unique_id = csm.customer_unique_id
GROUP BY csm.customer_state, rs.segment;
 
SELECT * FROM regional_segment_summary ORDER BY customer_state, customer_count DESC;

