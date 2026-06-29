-- Backfill payment_confirmed_at for historical wholesale orders that finished
-- before the payment-confirmation workflow existed.
--
-- NOTE: This runs automatically on backend startup (see
-- backend/internal/database/wholesale_backfill.go). This file is kept for
-- reference / manual re-run if needed.
-- Targets orders where:
--   - not rejected/deleted
--   - payment_confirmed_at is still NULL
--   - all shipments are completed
--   - at least one completion signal exists (legacy proof, invoice sent, or confirm audit)
--
-- payment_confirmed_at is set from (first match):
--   1) wholesale_order_confirm_payment audit timestamp
--   2) latest completed shipment delivery_date / updated_at
--   3) invoice_sent_at
--   4) order updated_at
--
-- SAFE to re-run (only updates rows where payment_confirmed_at IS NULL).
--
-- Usage:
--   mysql -u root -p YOUR_DB_NAME < scripts/sql/backfill_wholesale_payment_confirmed_at.sql

START TRANSACTION;

-- Preview rows that will be patched
SELECT
  wo.id,
  wo.ref_no,
  wo.order_number,
  wo.status,
  wo.payment_confirmed_at,
  wo.invoice_sent_at,
  wo.payment_proof_url,
  agg.shipment_complete_at,
  audit.confirm_at
FROM wholesale_orders wo
JOIN (
  SELECT
    wo2.id AS order_id,
    COUNT(DISTINCT sh.id) AS total_shipments,
    SUM(CASE WHEN sh.status <> 'completed' THEN 1 ELSE 0 END) AS not_completed_shipments,
    MAX(
      COALESCE(
        sh.delivery_date,
        DATE(sh.updated_at),
        DATE(sh.created_at)
      )
    ) AS shipment_complete_at
  FROM wholesale_orders wo2
  LEFT JOIN shipments sh ON sh.wholesale_order_id = wo2.id
  GROUP BY wo2.id
) agg ON agg.order_id = wo.id
LEFT JOIN (
  SELECT
    al.entity_id AS order_id,
    MAX(al.created_at) AS confirm_at
  FROM audit_logs al
  WHERE al.entity_type = 'wholesale_order'
    AND al.action = 'wholesale_order_confirm_payment'
    AND al.entity_id IS NOT NULL
  GROUP BY al.entity_id
) audit ON audit.order_id = wo.id
WHERE wo.status NOT IN ('rejected', 'deleted')
  AND wo.payment_confirmed_at IS NULL
  AND agg.total_shipments > 0
  AND agg.not_completed_shipments = 0
  AND (
    NULLIF(TRIM(wo.payment_proof_url), '') IS NOT NULL
    OR wo.invoice_sent_at IS NOT NULL
    OR audit.confirm_at IS NOT NULL
    OR EXISTS (
      SELECT 1
      FROM wholesale_order_documents d
      WHERE d.wholesale_order_id = wo.id
        AND d.type = 'payment_proof'
    )
  )
ORDER BY wo.id;

-- Apply patch
UPDATE wholesale_orders wo
JOIN (
  SELECT
    wo2.id AS order_id,
    COUNT(DISTINCT sh.id) AS total_shipments,
    SUM(CASE WHEN sh.status <> 'completed' THEN 1 ELSE 0 END) AS not_completed_shipments,
    MAX(
      COALESCE(
        sh.delivery_date,
        DATE(sh.updated_at),
        DATE(sh.created_at)
      )
    ) AS shipment_complete_at
  FROM wholesale_orders wo2
  LEFT JOIN shipments sh ON sh.wholesale_order_id = wo2.id
  GROUP BY wo2.id
) agg ON agg.order_id = wo.id
LEFT JOIN (
  SELECT
    al.entity_id AS order_id,
    MAX(al.created_at) AS confirm_at
  FROM audit_logs al
  WHERE al.entity_type = 'wholesale_order'
    AND al.action = 'wholesale_order_confirm_payment'
    AND al.entity_id IS NOT NULL
  GROUP BY al.entity_id
) audit ON audit.order_id = wo.id
SET wo.payment_confirmed_at = COALESCE(
  audit.confirm_at,
  TIMESTAMP(agg.shipment_complete_at),
  TIMESTAMP(wo.invoice_sent_at),
  wo.updated_at,
  wo.created_at
)
WHERE wo.status NOT IN ('rejected', 'deleted')
  AND wo.payment_confirmed_at IS NULL
  AND agg.total_shipments > 0
  AND agg.not_completed_shipments = 0
  AND (
    NULLIF(TRIM(wo.payment_proof_url), '') IS NOT NULL
    OR wo.invoice_sent_at IS NOT NULL
    OR audit.confirm_at IS NOT NULL
    OR EXISTS (
      SELECT 1
      FROM wholesale_order_documents d
      WHERE d.wholesale_order_id = wo.id
        AND d.type = 'payment_proof'
    )
  );

SELECT ROW_COUNT() AS patched_rows;

COMMIT;
