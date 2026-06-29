package api

import (
	"math"

	"pos-system/backend/internal/models"
)

func auditChangesAmount(changes map[string]interface{}) (float64, bool) {
	raw, ok := changes["amount"]
	if !ok || raw == nil {
		return 0, false
	}
	switch v := raw.(type) {
	case float64:
		return v, true
	case int:
		return float64(v), true
	case int64:
		return float64(v), true
	default:
		return 0, false
	}
}

func paymentProofTotalFromAudits(logs []models.AuditLog) float64 {
	var total float64
	for _, log := range logs {
		if log.Action != "wholesale_order_upload_payment_proof" {
			continue
		}
		changes := parseWholesaleAuditChangesJSON(log.Changes)
		if amt, ok := auditChangesAmount(changes); ok {
			total += amt
		}
	}
	return total
}

func latestInvoiceEmailDoneFromAudits(logs []models.AuditLog) bool {
	var latest *models.AuditLog
	for i := range logs {
		log := &logs[i]
		if log.Action != "wholesale_order_email" {
			continue
		}
		changes := parseWholesaleAuditChangesJSON(log.Changes)
		emailType, _ := changes["email_type"].(string)
		if emailType != "invoice" {
			continue
		}
		if latest == nil || log.CreatedAt.After(latest.CreatedAt) {
			latest = log
		}
	}
	if latest == nil {
		return false
	}
	changes := parseWholesaleAuditChangesJSON(latest.Changes)
	return wholesaleOrderEmailAuditSkipped(changes) || wholesaleOrderEmailAuditSent(changes)
}

func orderHasPaymentProofDocument(wo *models.WholesaleOrder) bool {
	if wo.PaymentProofURL != "" {
		return true
	}
	for _, d := range wo.Documents {
		if d.Type == paymentProofDocType {
			return true
		}
	}
	return false
}

func (h *WholesaleOrderHandler) enrichWholesaleOrdersWorkflow(orders []models.WholesaleOrder) {
	if len(orders) == 0 {
		return
	}
	ids := make([]uint, len(orders))
	for i := range orders {
		ids[i] = orders[i].ID
	}
	var logs []models.AuditLog
	_ = h.db.Where("entity_type = ? AND entity_id IN ?", "wholesale_order", ids).
		Where("action IN ?", []string{"wholesale_order_email", "wholesale_order_upload_payment_proof"}).
		Order("created_at ASC").
		Find(&logs).Error

	logsByOrder := make(map[uint][]models.AuditLog, len(orders))
	for _, log := range logs {
		if log.EntityID == nil {
			continue
		}
		logsByOrder[*log.EntityID] = append(logsByOrder[*log.EntityID], log)
	}

	for i := range orders {
		wo := &orders[i]
		orderLogs := logsByOrder[wo.ID]

		if wo.PaymentConfirmedAt != nil && !wo.PaymentConfirmedAt.IsZero() {
			wo.WorkflowInvoiceEmailDone = true
		} else if wo.InvoiceSentAt != nil && !wo.InvoiceSentAt.IsZero() {
			wo.WorkflowInvoiceEmailDone = true
		} else {
			wo.WorkflowInvoiceEmailDone = latestInvoiceEmailDoneFromAudits(orderLogs)
		}

		if orderHasPaymentProofDocument(wo) {
			total := paymentProofTotalFromAudits(orderLogs)
			wo.WorkflowPaymentProofTotal = &total
		}
	}
}

func wholesaleOrderGrandTotal(wo *models.WholesaleOrder) float64 {
	return wo.TotalNet + wo.ShippingFee
}

func isWholesaleOrderPaymentFullyReceived(wo *models.WholesaleOrder) bool {
	if wo.PaymentConfirmedAt != nil && !wo.PaymentConfirmedAt.IsZero() {
		return true
	}
	orderTotal := wholesaleOrderGrandTotal(wo)
	if wo.WorkflowPaymentProofTotal != nil {
		pending := math.Max(0, orderTotal-*wo.WorkflowPaymentProofTotal)
		return pending < 0.01
	}
	if orderHasPaymentProofDocument(wo) {
		return false
	}
	return false
}
