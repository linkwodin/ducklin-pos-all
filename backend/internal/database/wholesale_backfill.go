package database

import (
	"log"

	"pos-system/backend/internal/models"

	"gorm.io/gorm"
)

// backfillWholesalePaymentConfirmedAt sets payment_confirmed_at on historical orders that
// finished delivery before the payment-confirmation workflow existed. Safe to re-run.
func backfillWholesalePaymentConfirmedAt(db *gorm.DB) {
	const updateSQL = `
UPDATE wholesale_orders wo
JOIN (
  SELECT
    wo2.id AS order_id,
    COUNT(DISTINCT sh.id) AS total_shipments,
    SUM(CASE WHEN sh.status <> ? THEN 1 ELSE 0 END) AS not_completed_shipments,
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
WHERE wo.status NOT IN (?, ?)
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
  )`

	result := db.Exec(
		updateSQL,
		models.ShipmentStatusCompleted,
		models.WholesaleOrderStatusRejected,
		models.WholesaleOrderStatusDeleted,
	)
	if result.Error != nil {
		log.Printf("WARNING: wholesale payment_confirmed_at backfill: %v", result.Error)
		return
	}
	if result.RowsAffected > 0 {
		log.Printf("Backfilled payment_confirmed_at on %d wholesale order(s)", result.RowsAffected)
	}
}
