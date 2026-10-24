-- Olist e-commerce: SQL analysis (SQLite)
-- Tables: customers, orders, order_items, products, category_translation, sellers, reviews, payments
-- Scope: delivered orders purchased Jan 2017 - Aug 2018 (see views below)

-- ============================================================
-- Views
-- ============================================================

DROP VIEW IF EXISTS order_reviews_avg;
DROP VIEW IF EXISTS delivered_orders;
DROP VIEW IF EXISTS delivered_items;

CREATE VIEW order_reviews_avg AS
SELECT order_id, AVG(review_score) AS review_score
FROM reviews
GROUP BY order_id;

CREATE VIEW delivered_orders AS
SELECT o.order_id,
       o.customer_id,
       c.customer_unique_id,
       c.customer_state,
       strftime('%Y-%m', o.order_purchase_timestamp) AS month,
       CAST(julianday(o.order_delivered_customer_date)
            - julianday(o.order_estimated_delivery_date) AS INTEGER) AS delay_days,
       r.review_score
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
LEFT JOIN order_reviews_avg r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01';

CREATE VIEW delivered_items AS
SELECT oi.order_id, oi.order_item_id, oi.product_id, oi.seller_id,
       oi.price, oi.freight_value, d.month
FROM order_items oi
JOIN delivered_orders d ON d.order_id = oi.order_id;


-- ============================================================
-- Q1. Monthly revenue and month-over-month growth
-- ============================================================

WITH monthly AS (
    SELECT month, ROUND(SUM(price), 2) AS revenue
    FROM delivered_items
    GROUP BY month
)
SELECT month,
       revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
             / LAG(revenue) OVER (ORDER BY month), 1) AS mom_growth_pct
FROM monthly
ORDER BY month;


-- ============================================================
-- Q2. Which categories drive revenue?
-- ============================================================

WITH cat AS (
    SELECT COALESCE(t.product_category_name_english, 'unknown') AS category,
           ROUND(SUM(di.price), 2) AS revenue
    FROM delivered_items di
    JOIN products p ON p.product_id = di.product_id
    LEFT JOIN category_translation t
           ON t.product_category_name = p.product_category_name
    GROUP BY category
)
SELECT category,
       revenue,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 1) AS share_pct,
       ROUND(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
             / SUM(revenue) OVER (), 1) AS cumulative_share_pct
FROM cat
ORDER BY revenue DESC
LIMIT 10;


-- ============================================================
-- Q3. Top 3 sellers by revenue in the five biggest seller states
-- ============================================================

WITH seller_rev AS (
    SELECT s.seller_state,
           substr(s.seller_id, 1, 8) AS seller,
           ROUND(SUM(di.price), 2) AS revenue,
           COUNT(DISTINCT di.order_id) AS orders
    FROM delivered_items di
    JOIN sellers s ON s.seller_id = di.seller_id
    GROUP BY s.seller_state, s.seller_id
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY seller_state ORDER BY revenue DESC) AS rank_in_state
    FROM seller_rev
)
SELECT seller_state, rank_in_state, seller, revenue, orders
FROM ranked
WHERE rank_in_state <= 3
  AND seller_state IN ('SP', 'RJ', 'MG', 'PR', 'SC')
ORDER BY seller_state, rank_in_state;


-- ============================================================
-- Q4. Which states have the most late deliveries, and how do they review?
-- ============================================================

SELECT customer_state,
       COUNT(*) AS orders,
       ROUND(100.0 * AVG(CASE WHEN delay_days > 0 THEN 1 ELSE 0 END), 1) AS late_pct,
       ROUND(AVG(review_score), 2) AS avg_review
FROM delivered_orders
GROUP BY customer_state
HAVING COUNT(*) >= 500
ORDER BY late_pct DESC
LIMIT 10;


-- ============================================================
-- Q5. How much does lateness hurt reviews?
-- ============================================================

SELECT CASE
           WHEN delay_days <= 0 THEN '1. On time or early'
           WHEN delay_days <= 3 THEN '2. Late 1-3 days'
           WHEN delay_days <= 7 THEN '3. Late 4-7 days'
           ELSE '4. Late 8+ days'
       END AS delivery_bucket,
       COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_orders,
       ROUND(AVG(review_score), 2) AS avg_review
FROM delivered_orders
WHERE review_score IS NOT NULL
GROUP BY delivery_bucket
ORDER BY delivery_bucket;


-- ============================================================
-- Q6. What share of customers buy more than once?
-- ============================================================

WITH per_customer AS (
    SELECT customer_unique_id, COUNT(DISTINCT order_id) AS n_orders
    FROM delivered_orders
    GROUP BY customer_unique_id
)
SELECT COUNT(*) AS customers,
       SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END) AS repeat_customers,
       ROUND(100.0 * SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_pct,
       MAX(n_orders) AS max_orders_by_one_customer
FROM per_customer;


-- ============================================================
-- Q7. Which payment methods dominate?
-- ============================================================

SELECT payment_type,
       COUNT(DISTINCT order_id) AS orders,
       ROUND(100.0 * COUNT(DISTINCT order_id)
             / (SELECT COUNT(DISTINCT order_id) FROM payments), 1) AS pct_of_orders,
       ROUND(AVG(payment_installments), 2) AS avg_installments,
       ROUND(AVG(payment_value), 2) AS avg_payment_value
FROM payments
GROUP BY payment_type
ORDER BY orders DESC;


-- ============================================================
-- Q8. Cumulative revenue over time
-- ============================================================

WITH monthly AS (
    SELECT month, ROUND(SUM(price), 2) AS revenue
    FROM delivered_items
    GROUP BY month
)
SELECT month,
       revenue,
       ROUND(SUM(revenue) OVER (ORDER BY month
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2) AS cumulative_revenue
FROM monthly
ORDER BY month;
