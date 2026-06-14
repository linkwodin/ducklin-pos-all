-- Backfill wholesale order hard status to pending payment ("approved")
-- for historical data created before the hard-status logic was introduced.
--
-- This script is SAFE to re-run.
--
-- Conditions to patch an order:
-- 1) order is not rejected
-- 2) payment_confirmed_at is NULL (still pending payment)
-- 3) order has at least one shipment
-- 4) ALL shipments are completed
-- 5) shipment items (distinct wholesale_order_item_id) cover ALL order items
--
-- Result:
--   wholesale_orders.status => 'approved'
--
-- Usage:
--   mysql -u root -p YOUR_DB_NAME < scripts/sql/backfill_wholesale_pending_payment_status.sql

START TRANSACTION;

-- Preview rows that will be patched
SELECT
  wo.id,
  wo.order_number,
  wo.status AS old_status,
  wo.payment_confirmed_at
FROM wholesale_orders wo
JOIN (
  SELECT
    wo2.id AS order_id,
    COUNT(DISTINCT oi.id) AS total_items,
    COUNT(DISTINCT CASE WHEN sh.status = 'completed' THEN si.wholesale_order_item_id END) AS covered_items,
    COUNT(DISTINCT sh.id) AS total_shipments,
    SUM(CASE WHEN sh.status <> 'completed' THEN 1 ELSE 0 END) AS not_completed_shipments
  FROM wholesale_orders wo2
  LEFT JOIN wholesale_order_items oi
    ON oi.wholesale_order_id = wo2.id
  LEFT JOIN shipments sh
    ON sh.wholesale_order_id = wo2.id
  LEFT JOIN shipment_items si
    ON si.shipment_id = sh.id
  GROUP BY wo2.id
) agg ON agg.order_id = wo.id
WHERE wo.status <> 'rejected'
  AND wo.payment_confirmed_at IS NULL
  AND agg.total_shipments > 0
  AND agg.not_completed_shipments = 0
  AND agg.total_items > 0
  AND agg.covered_items >= agg.total_items
  AND wo.status <> 'approved'
ORDER BY wo.id;

-- Apply patch
UPDATE wholesale_orders wo
JOIN (
  SELECT
    wo2.id AS order_id,
    COUNT(DISTINCT oi.id) AS total_items,
    COUNT(DISTINCT CASE WHEN sh.status = 'completed' THEN si.wholesale_order_item_id END) AS covered_items,
    COUNT(DISTINCT sh.id) AS total_shipments,
    SUM(CASE WHEN sh.status <> 'completed' THEN 1 ELSE 0 END) AS not_completed_shipments
  FROM wholesale_orders wo2
  LEFT JOIN wholesale_order_items oi
    ON oi.wholesale_order_id = wo2.id
  LEFT JOIN shipments sh
    ON sh.wholesale_order_id = wo2.id
  LEFT JOIN shipment_items si
    ON si.shipment_id = sh.id
  GROUP BY wo2.id
) agg ON agg.order_id = wo.id
SET
  wo.status = 'approved'
WHERE wo.status <> 'rejected'
  AND wo.payment_confirmed_at IS NULL
  AND agg.total_shipments > 0
  AND agg.not_completed_shipments = 0
  AND agg.total_items > 0
  AND agg.covered_items >= agg.total_items
  AND wo.status <> 'approved';

-- Show how many rows were changed in this run
SELECT ROW_COUNT() AS patched_rows;

COMMIT;

