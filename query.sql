-- ============================================================================
-- query.sql : back-office report queries (supermarket database)
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Q1. Revenue by store
-- Params:   $1 = look-back window in days (e.g. 30; the seed data spans 90)
-- Tables:   item_sale, store_transaction, store, item, tax 
-- ----------------------------------------------------------------------------
-- @report revenue_by_store
WITH lines AS (
    SELECT
        t.store_id,
        t.transaction_id,
        t.payment_method,
        l.quantity_sold * l.unit_price                                    AS subtotal,
        l.quantity_sold * l.unit_price
            * CASE WHEN i.tax_exempt THEN 0 ELSE tx.tax_rate END          AS tax
    FROM item_sale l
    JOIN store_transaction t  ON t.transaction_id = l.transaction_id
    JOIN store             s  ON s.store_id       = t.store_id
    JOIN item              i  ON i.sku            = l.sku
    JOIN tax               tx ON tx.state_code    = s.state_code
    WHERE t.date_and_time >= now() - make_interval(days => $1::int)
)
SELECT
    RANK() OVER (ORDER BY SUM(ln.subtotal + ln.tax) DESC)                 AS rank,
    s.store_id,
    s.street || ', ' || s.city || ', ' || s.state_code                    AS store,
    COUNT(DISTINCT ln.transaction_id)                                     AS transactions,
    ROUND(SUM(ln.subtotal), 2)                                            AS subtotal,
    ROUND(SUM(ln.tax), 2)                                                 AS tax,
    ROUND(SUM(ln.subtotal + ln.tax), 2)                                   AS revenue,
    ROUND(SUM(ln.subtotal + ln.tax) / COUNT(DISTINCT ln.transaction_id), 2) AS avg_basket,
    ROUND(100 * COALESCE(SUM(CASE WHEN ln.payment_method = 'card'
                                  THEN ln.subtotal + ln.tax END), 0)
              / SUM(ln.subtotal + ln.tax), 1)                             AS pct_paid_by_card,
    ROUND(100 * SUM(ln.subtotal + ln.tax)
              / SUM(SUM(ln.subtotal + ln.tax)) OVER (), 1)                AS pct_of_chain
FROM lines ln
JOIN store s ON s.store_id = ln.store_id
GROUP BY s.store_id, s.street, s.city, s.state_code
ORDER BY rank, s.store_id;
-- @end

-- ----------------------------------------------------------------------------
-- Q2. Best-selling items inside each department (top 3 by revenue)
-- Tables:   item_sale, item, department
-- ----------------------------------------------------------------------------
-- @report top_items
WITH item_revenue AS (
    SELECT
        d.department_id,
        d.name                                   AS department,
        i.sku,
        i.name                                   AS item,
        SUM(l.quantity_sold)                     AS units_sold,   -- lb for weighed items
        SUM(l.quantity_sold * l.unit_price)      AS revenue
    FROM item_sale l
    JOIN item       i ON i.sku           = l.sku
    JOIN department d ON d.department_id = i.department_id
    GROUP BY d.department_id, d.name, i.sku, i.name
),
ranked AS (
    SELECT
        r.*,
        RANK() OVER (PARTITION BY department_id ORDER BY revenue DESC)  AS rank_in_dept,
        SUM(revenue) OVER (PARTITION BY department_id)                  AS dept_revenue
    FROM item_revenue r
)
SELECT
    department,
    rank_in_dept,
    item,
    ROUND(units_sold, 2)                         AS units_sold,
    ROUND(revenue, 2)                            AS revenue,
    ROUND(100 * revenue / dept_revenue, 1)       AS pct_of_department
FROM ranked
WHERE rank_in_dept <= 3
ORDER BY department, rank_in_dept;
-- @end

-- ----------------------------------------------------------------------------
-- Q3. Restock list: items about to run out, based on recent sales speed
-- Question: which shelf items will sell out soonest, and where (aisle) does a
--           stock clerk need to go?
-- Params:   $1 = look-back window in days
--           $2 = flag items with fewer than this many days of stock 
-- Tables:   inventory, item, store, department, and sales from
--           item_sale and store_transaction 
-- ----------------------------------------------------------------------------
-- @report restock
WITH recent_sales AS (
    SELECT
        t.store_id,
        l.sku,
        SUM(l.quantity_sold) AS qty_sold
    FROM item_sale l
    JOIN store_transaction t ON t.transaction_id = l.transaction_id
    WHERE t.date_and_time >= now() - make_interval(days => $1::int)
    GROUP BY t.store_id, l.sku
)
SELECT
    st.store_id,
    st.city || ', ' || st.state_code                       AS store,
    d.name                                                 AS department,
    i.name                                                 AS item,
    inv.aisle_no,
    inv.quantity_in_stock,
    COALESCE(rs.qty_sold, 0)                               AS sold_in_window,
    ROUND(inv.quantity_in_stock
          / (rs.qty_sold / $1::int), 1)                    AS days_of_stock
FROM inventory inv
JOIN item        i  ON i.sku           = inv.sku
JOIN department  d  ON d.department_id = i.department_id
JOIN store       st ON st.store_id     = inv.store_id
LEFT JOIN recent_sales rs ON rs.store_id = inv.store_id AND rs.sku = inv.sku
WHERE rs.qty_sold > 0
  AND inv.quantity_in_stock / (rs.qty_sold / $1::int) < $2::int
ORDER BY days_of_stock ASC, st.store_id
LIMIT 50;
-- @end

