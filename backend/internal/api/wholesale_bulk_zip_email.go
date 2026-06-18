package api

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/mail"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	apimail "pos-system/backend/internal/mail"
	"pos-system/backend/internal/models"

	"cloud.google.com/go/storage"
	"github.com/gin-gonic/gin"
)

const bulkAttachmentEmailMaxOrders = 200

var pathSanitizeRe = regexp.MustCompile(`[/\\?*:|"<>]+`)

func safeZipSegment(s string) string {
	s = strings.TrimSpace(s)
	s = pathSanitizeRe.ReplaceAllString(s, "_")
	s = strings.TrimSpace(s)
	if s == "" {
		return "file"
	}
	runes := []rune(s)
	if len(runes) > 120 {
		s = string(runes[:120])
	}
	return s
}

func zipEntryLeaf(base string, docKind string, data []byte) string {
	base = strings.TrimSpace(base)
	if base == "" {
		base = docKind
	}
	if strings.TrimSpace(filepath.Ext(base)) != "" {
		return base
	}
	if len(data) >= 4 && string(data[0:4]) == "%PDF" {
		return base + ".pdf"
	}
	if docKind == "po_attachment" {
		return base + ".bin"
	}
	return base + ".pdf"
}

// gcsObjectPathFromURL returns the object path inside a *-pos-uploads bucket (strips bucket segment).
func gcsObjectPathFromURL(fileURL string) (string, error) {
	if !strings.Contains(fileURL, "storage.googleapis.com") {
		return "", fmt.Errorf("not a GCS URL")
	}
	u, err := url.Parse(fileURL)
	if err != nil {
		return "", err
	}
	path := strings.TrimPrefix(u.Path, "/")
	if slash := strings.Index(path, "/"); slash > 0 {
		bucket := path[:slash]
		if strings.HasSuffix(bucket, "-pos-uploads") {
			object := path[slash+1:]
			if object == "" {
				return "", fmt.Errorf("invalid GCS path")
			}
			return object, nil
		}
	}
	if path == "" {
		return "", fmt.Errorf("invalid GCS path")
	}
	return path, nil
}

func (h *WholesaleOrderHandler) readBytesFromFileURL(fileURL string) ([]byte, error) {
	if strings.Contains(fileURL, "storage.googleapis.com") && h.cfg.GCPBucketName != "" {
		path, err := gcsObjectPathFromURL(fileURL)
		if err != nil {
			return nil, err
		}
		ctx := context.Background()
		client, err := storage.NewClient(ctx)
		if err != nil {
			return nil, err
		}
		defer client.Close()
		r, err := client.Bucket(h.cfg.GCPBucketName).Object(path).NewReader(ctx)
		if err != nil {
			return nil, err
		}
		defer r.Close()
		return io.ReadAll(r)
	}
	u, err := url.Parse(fileURL)
	if err != nil {
		return nil, err
	}
	uploadDir := h.cfg.UploadDir
	if uploadDir == "" {
		uploadDir = "./uploads"
	}
	localPath := filepath.Join(uploadDir, strings.TrimPrefix(u.Path, "/uploads/"))
	return os.ReadFile(localPath)
}

func fetchRemoteBytes(rawURL string, maxBytes int64) ([]byte, error) {
	client := &http.Client{Timeout: 3 * time.Minute}
	resp, err := client.Get(rawURL)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	return io.ReadAll(io.LimitReader(resp.Body, maxBytes))
}

// buildBulkAttachmentZipBytes builds a ZIP matching the management frontend bulk export (document types + signed DN + legacy payment proof).
func (h *WholesaleOrderHandler) buildBulkAttachmentZipBytes(orders []models.WholesaleOrder, kind string) ([]byte, int, error) {
	buf := new(bytes.Buffer)
	zw := zip.NewWriter(buf)
	fileCount := 0

	const (
		oc  = "order_confirmation"
		poa = "po_attachment"
		dn  = "delivery_note"
		inv = "invoice"
		pp  = "payment_proof"
	)
	standardTypes := []string{oc, poa, dn, inv, pp}

	for _, order := range orders {
		ref := order.RefNo
		if ref == "" {
			ref = fmt.Sprintf("%d", order.ID)
		}
		folder := safeZipSegment(fmt.Sprintf("%s_%s", order.OrderNumber, ref))
		idx := 0
		writeDoc := func(prefix, baseName string, data []byte) error {
			idx++
			leaf := zipEntryLeaf(baseName, prefix, data)
			path := fmt.Sprintf("%s/%02d_%s_%s", folder, idx, prefix, safeZipSegment(leaf))
			w, err := zw.Create(path)
			if err != nil {
				return err
			}
			_, err = w.Write(data)
			return err
		}

		var typesToAdd []string
		switch kind {
		case "all":
			typesToAdd = append([]string{}, standardTypes...)
		case "signed_delivery_note":
			typesToAdd = nil
		case "":
			return nil, 0, fmt.Errorf("invalid kind")
		default:
			typesToAdd = []string{kind}
		}

		for _, docType := range typesToAdd {
			for _, doc := range order.Documents {
				if doc.Type != docType {
					continue
				}
				data, err := h.readBytesFromFileURL(doc.FileURL)
				if err != nil {
					continue // skip broken files like client would skip
				}
				base := strings.TrimSpace(doc.OriginalFilename)
				if base == "" {
					base = fmt.Sprintf("%s_%d", docType, doc.ID)
				}
				if err := writeDoc(docType, base, data); err != nil {
					_ = zw.Close()
					return nil, 0, err
				}
				fileCount++
			}
			if docType == pp {
				hasDoc := false
				for _, doc := range order.Documents {
					if doc.Type == pp {
						hasDoc = true
						break
					}
				}
				if !hasDoc && strings.TrimSpace(order.PaymentProofURL) != "" {
					data, err := h.readBytesFromFileURL(order.PaymentProofURL)
					if err == nil {
						if err := writeDoc(pp, "legacy_payment_proof", data); err != nil {
							_ = zw.Close()
							return nil, 0, err
						}
						fileCount++
					}
				}
			}
		}

		if kind == "all" || kind == "signed_delivery_note" {
			for _, sh := range order.Shipments {
				u := strings.TrimSpace(sh.SignedDeliveryNotePDFURL)
				if u == "" {
					continue
				}
				data, err := fetchRemoteBytes(u, 80<<20)
				if err != nil {
					continue
				}
				if err := writeDoc("signed_dn", fmt.Sprintf("shipment_%d_signed_dn", sh.ID), data); err != nil {
					_ = zw.Close()
					return nil, 0, err
				}
				fileCount++
			}
		}
	}

	if err := zw.Close(); err != nil {
		return nil, 0, err
	}
	return buf.Bytes(), fileCount, nil
}

var validEmailAttachmentKinds = map[string]bool{
	"po_attachment":        true,
	"payment_proof":        true,
	"invoice":              true,
	"order_confirmation":   true,
	"delivery_note":        true,
	"signed_delivery_note": true,
}

func parseEmailList(raw string) []string {
	parts := strings.FieldsFunc(raw, func(r rune) bool {
		return r == ',' || r == ';' || r == '\n' || r == '\r'
	})
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func attachmentMIMEType(name string, data []byte) string {
	switch strings.ToLower(filepath.Ext(name)) {
	case ".pdf":
		return "application/pdf"
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".png":
		return "image/png"
	case ".gif":
		return "image/gif"
	case ".webp":
		return "image/webp"
	}
	if len(data) >= 4 && string(data[0:4]) == "%PDF" {
		return "application/pdf"
	}
	return "application/octet-stream"
}

func emailAttachmentFilename(refSafe, kind, base string, data []byte) string {
	base = strings.TrimSpace(base)
	if base == "" {
		base = kind
	}
	leaf := zipEntryLeaf(base, kind, data)
	if strings.HasPrefix(leaf, refSafe+"_") {
		return leaf
	}
	return refSafe + "_" + leaf
}

func shipmentIncludedInEmailFilter(shipmentID uint, shipmentIDs []uint, signedDeliveryShipmentID *uint) bool {
	if len(shipmentIDs) > 0 {
		for _, id := range shipmentIDs {
			if id == shipmentID {
				return true
			}
		}
		return false
	}
	if signedDeliveryShipmentID != nil && *signedDeliveryShipmentID > 0 {
		return shipmentID == *signedDeliveryShipmentID
	}
	return true
}

// collectOrderEmailAttachments gathers files for the selected attachment kinds on one order.
func (h *WholesaleOrderHandler) collectOrderEmailAttachments(order *models.WholesaleOrder, kinds []string, signedDeliveryShipmentID *uint, shipmentIDs []uint) ([]apimail.Attachment, error) {
	ref := wholesaleOrderRefLabel(order)
	refSafe := strings.ReplaceAll(strings.ReplaceAll(ref, "/", "_"), "\\", "_")

	seenKind := make(map[string]struct{})
	var orderedKinds []string
	for _, k := range kinds {
		k = strings.TrimSpace(k)
		if !validEmailAttachmentKinds[k] {
			continue
		}
		if _, ok := seenKind[k]; ok {
			continue
		}
		seenKind[k] = struct{}{}
		orderedKinds = append(orderedKinds, k)
	}

	var out []apimail.Attachment
	for _, kind := range orderedKinds {
		switch kind {
		case "po_attachment", "payment_proof", "invoice", "order_confirmation":
			for _, doc := range order.Documents {
				if doc.Type != kind {
					continue
				}
				data, err := h.readBytesFromFileURL(doc.FileURL)
				if err != nil {
					continue
				}
				base := strings.TrimSpace(doc.OriginalFilename)
				if base == "" {
					base = fmt.Sprintf("%s_%d", kind, doc.ID)
				}
				fn := emailAttachmentFilename(refSafe, kind, base, data)
				out = append(out, apimail.Attachment{
					Filename:    fn,
					ContentType: attachmentMIMEType(fn, data),
					Data:        data,
				})
			}
			if kind == "payment_proof" {
				hasDoc := false
				for _, doc := range order.Documents {
					if doc.Type == "payment_proof" {
						hasDoc = true
						break
					}
				}
				if !hasDoc && strings.TrimSpace(order.PaymentProofURL) != "" {
					data, err := h.readBytesFromFileURL(order.PaymentProofURL)
					if err == nil {
						fn := emailAttachmentFilename(refSafe, kind, "legacy_payment_proof", data)
						out = append(out, apimail.Attachment{
							Filename:    fn,
							ContentType: attachmentMIMEType(fn, data),
							Data:        data,
						})
					}
				}
			}
		case "delivery_note":
			seenShipment := make(map[uint]struct{})
			seenURL := make(map[string]struct{})
			for _, sh := range order.Shipments {
				if !shipmentIncludedInEmailFilter(sh.ID, shipmentIDs, nil) {
					continue
				}
				if _, ok := seenShipment[sh.ID]; ok {
					continue
				}
				seenShipment[sh.ID] = struct{}{}
				u := strings.TrimSpace(sh.DeliveryNotePDFURL)
				if u == "" {
					continue
				}
				if _, ok := seenURL[u]; ok {
					continue
				}
				seenURL[u] = struct{}{}
				data, err := h.readBytesFromFileURL(u)
				if err != nil {
					continue
				}
				fn := fmt.Sprintf("%s_delivery_note_shipment_%d.pdf", refSafe, sh.ID)
				out = append(out, apimail.Attachment{
					Filename:    fn,
					ContentType: attachmentMIMEType(fn, data),
					Data:        data,
				})
			}
		case "signed_delivery_note":
			for _, sh := range order.Shipments {
				if !shipmentIncludedInEmailFilter(sh.ID, shipmentIDs, signedDeliveryShipmentID) {
					continue
				}
				u := strings.TrimSpace(sh.SignedDeliveryNotePDFURL)
				if u == "" {
					continue
				}
				data, err := fetchRemoteBytes(u, 80<<20)
				if err != nil {
					continue
				}
				ext := ".pdf"
				if i := strings.LastIndex(u, "."); i >= 0 {
					candidate := strings.ToLower(u[i:])
					if len(candidate) <= 6 && candidate != "." {
						ext = candidate
					}
				}
				fn := fmt.Sprintf("%s_signed_dn_shipment_%d%s", refSafe, sh.ID, ext)
				out = append(out, apimail.Attachment{
					Filename:    fn,
					ContentType: attachmentMIMEType(fn, data),
					Data:        data,
				})
			}
		}
	}
	return out, nil
}

// EmailOrder sends an email with selected attachments for a wholesale order.
func (h *WholesaleOrderHandler) EmailOrder(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	if strings.TrimSpace(h.cfg.SMTPHost) == "" || strings.TrimSpace(h.cfg.SMTPUser) == "" || h.cfg.SMTPPassword == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Email is not configured (set SMTP_HOST, SMTP_USER, SMTP_PASSWORD)"})
		return
	}

	var wo models.WholesaleOrder
	if err := h.db.Preload("WholesaleClient").Preload("Documents").Preload("Shipments").
		First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
		return
	}

	var req struct {
		Recipient                string   `json:"recipient"`
		To                       []string `json:"to"`
		CC                       string   `json:"cc"`
		Cc                       []string `json:"cc_list"`
		BCC                      string   `json:"bcc"`
		Bcc                      []string `json:"bcc_list"`
		Subject                  string   `json:"subject"`
		Message                  string   `json:"message"`
		Attachments              []string `json:"attachments" binding:"required,min=1"`
		SignedDeliveryShipmentID *uint    `json:"signed_delivery_shipment_id"`
		ShipmentIDs              []uint   `json:"shipment_ids"`
		EmailType                string   `json:"email_type"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	toList := append([]string{}, req.To...)
	if r := strings.TrimSpace(req.Recipient); r != "" {
		toList = append(toList, parseEmailList(r)...)
	}
	if len(toList) == 0 {
		if fallback := strings.TrimSpace(wo.WholesaleClient.Email); fallback != "" {
			toList = append(toList, fallback)
		}
	}
	if len(toList) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No recipient email address"})
		return
	}

	ccList := append([]string{}, req.Cc...)
	if cc := strings.TrimSpace(req.CC); cc != "" {
		ccList = append(ccList, parseEmailList(cc)...)
	}
	if len(ccList) == 0 {
		userIDVal, _ := c.Get("user_id")
		if uid, ok := userIDVal.(uint); ok && uid > 0 {
			var u models.User
			if err := h.db.Select("email").First(&u, uid).Error; err == nil {
				if email := strings.TrimSpace(u.Email); email != "" {
					ccList = append(ccList, email)
				}
			}
		}
	}
	bccList := append([]string{}, req.Bcc...)
	if bcc := strings.TrimSpace(req.BCC); bcc != "" {
		bccList = append(bccList, parseEmailList(bcc)...)
	}

	var initiatorName string
	userIDVal, _ := c.Get("user_id")
	if uid, ok := userIDVal.(uint); ok && uid > 0 {
		var u models.User
		if err := h.db.Select("id", "username", "first_name", "last_name", "email").First(&u, uid).Error; err == nil {
			initiatorName = userDisplayName(&u)
		}
	}

	mailAttachments, err := h.collectOrderEmailAttachments(&wo, req.Attachments, req.SignedDeliveryShipmentID, req.ShipmentIDs)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if len(mailAttachments) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No files found for the selected attachments"})
		return
	}

	var company models.CompanySettings
	_ = h.db.First(&company, companySettingsID).Error

	subject := strings.TrimSpace(req.Subject)
	if subject == "" {
		emailType := strings.TrimSpace(req.EmailType)
		tmpl := strings.TrimSpace(company.WholesaleOrderEmailSubjectTemplate)
		switch emailType {
		case "shipments_delivered":
			tmpl = defaultWholesaleShipmentsDeliveredEmailSubjectTemplate
		case "invoice":
			tmpl = defaultWholesaleInvoiceEmailSubjectTemplate
		case "order_confirm":
			tmpl = defaultWholesaleOrderConfirmEmailSubjectTemplate
		default:
			signedDnSelected := false
			for _, k := range req.Attachments {
				if strings.TrimSpace(k) == "signed_delivery_note" {
					signedDnSelected = true
					break
				}
			}
			if tmpl == "" {
				if signedDnSelected {
					tmpl = defaultWholesaleDeliveryProofEmailSubjectTemplate
				} else {
					tmpl = defaultWholesaleOrderEmailSubjectTemplate
				}
			}
		}
		subject = applyWholesaleOrderEmailSubjectTemplate(tmpl, &wo)
	}
	body := strings.TrimSpace(req.Message)
	if body == "" {
		contactEmail := strings.TrimSpace(company.Email)
		switch {
		case isWholesaleOrderConfirmEmail(req.Attachments, req.EmailType):
			body = wholesaleOrderEmailDefaultOrderConfirmBody(&wo, contactEmail)
		case isWholesaleShipmentsDeliveredEmail(req.Attachments, req.SignedDeliveryShipmentID, req.EmailType):
			body = wholesaleOrderEmailDefaultDeliveryCompleteBody(&wo, contactEmail)
		case isWholesaleInvoiceEmail(req.Attachments, req.EmailType):
			body = wholesaleOrderEmailDefaultInvoiceBody(&wo, contactEmail)
		default:
			body = wholesaleOrderEmailDefaultBody(&wo, "the attached documents")
		}
	}

	from := h.cfg.EffectiveSMTPFrom()
	if err := apimail.SendWithAttachments(
		h.cfg.SMTPHost, h.cfg.SMTPPort, h.cfg.SMTPUser, h.cfg.SMTPPassword, from,
		toList, ccList, bccList, subject, body, mailAttachments,
	); err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "Failed to send email: " + err.Error()})
		return
	}

	sentAt := time.Now().UTC()
	hasInvoice := false
	attachmentKinds := make([]string, 0, len(req.Attachments))
	seenKind := make(map[string]struct{})
	for _, k := range req.Attachments {
		k = strings.TrimSpace(k)
		if k == "invoice" {
			hasInvoice = true
		}
		if _, ok := seenKind[k]; ok || k == "" {
			continue
		}
		seenKind[k] = struct{}{}
		attachmentKinds = append(attachmentKinds, k)
	}
	if hasInvoice {
		today := time.Date(sentAt.Year(), sentAt.Month(), sentAt.Day(), 0, 0, 0, 0, time.UTC)
		_ = h.db.Model(&wo).Update("invoice_sent_at", &today).Error
	}

	filenames := make([]string, len(mailAttachments))
	for i, a := range mailAttachments {
		filenames[i] = a.Filename
	}
	changes := map[string]interface{}{
		"recipient":        strings.Join(toList, ", "),
		"to":               toList,
		"subject":          subject,
		"sent_at":          sentAt.Format(time.RFC3339),
		"initiated_by":     initiatorName,
		"attachment_kinds": attachmentKinds,
		"attachment_count": len(mailAttachments),
		"filenames":        filenames,
	}
	if req.SignedDeliveryShipmentID != nil && *req.SignedDeliveryShipmentID > 0 {
		changes["signed_delivery_shipment_id"] = *req.SignedDeliveryShipmentID
	}
	if len(req.ShipmentIDs) > 0 {
		changes["shipment_ids"] = req.ShipmentIDs
	}
	if len(ccList) > 0 {
		changes["cc"] = strings.Join(ccList, ", ")
		changes["cc_list"] = ccList
	}
	if len(bccList) > 0 {
		changes["bcc"] = strings.Join(bccList, ", ")
		changes["bcc_list"] = bccList
	}
	if strings.TrimSpace(req.Message) != "" {
		changes["message"] = strings.TrimSpace(req.Message)
	}
	if emailType := strings.TrimSpace(req.EmailType); emailType != "" {
		changes["email_type"] = emailType
	}

	h.audit(c, "wholesale_order_email", wo.ID, changes)

	h.db.Preload("Items.Product").Preload("WholesaleClient.Stores").Preload("WholesaleClientStore").Preload("Store").Preload("User").Preload("Sector").
		Preload("Reviewer").Preload("Documents").Preload("Shipments.Store").
		Preload("Shipments.Items.WholesaleOrderItem.Product").
		First(&wo, wo.ID)

	c.JSON(http.StatusOK, gin.H{
		"message":          "Email sent",
		"recipient":        strings.Join(toList, ", "),
		"to":               toList,
		"cc":               strings.Join(ccList, ", "),
		"cc_list":          ccList,
		"bcc":              strings.Join(bccList, ", "),
		"bcc_list":         bccList,
		"sent_at":          sentAt.Format(time.RFC3339),
		"initiated_by":     initiatorName,
		"attachment_count": len(mailAttachments),
		"order":            wo,
	})
}

// SkipWholesaleOrderEmail records that a structured wholesale order email step was skipped.
func (h *WholesaleOrderHandler) SkipWholesaleOrderEmail(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}

	var wo models.WholesaleOrder
	if err := h.db.First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
		return
	}

	var req struct {
		EmailType string `json:"email_type" binding:"required"`
		Remark    string `json:"remark" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	emailType := strings.TrimSpace(req.EmailType)
	remark := strings.TrimSpace(req.Remark)
	if remark == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "remark is required"})
		return
	}
	switch emailType {
	case "order_confirm", "shipments_delivered", "invoice":
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid email type"})
		return
	}

	if log, ok := h.findLatestWholesaleOrderStructuredEmailAudit(wo.ID, emailType); ok {
		changes := parseWholesaleAuditChangesJSON(log.Changes)
		if wholesaleOrderEmailAuditSkipped(changes) {
			c.JSON(http.StatusConflict, gin.H{"error": "Email step already skipped"})
			return
		}
		if wholesaleOrderEmailAuditSent(changes) {
			c.JSON(http.StatusConflict, gin.H{"error": "Email already sent"})
			return
		}
	}

	var initiatorName string
	userIDVal, _ := c.Get("user_id")
	if uid, ok := userIDVal.(uint); ok && uid > 0 {
		var u models.User
		if err := h.db.Select("id", "username", "first_name", "last_name", "email").First(&u, uid).Error; err == nil {
			initiatorName = userDisplayName(&u)
		}
	}

	skippedAt := time.Now().UTC()
	changes := map[string]interface{}{
		"email_type":   emailType,
		"skipped":      true,
		"skipped_at":   skippedAt.Format(time.RFC3339),
		"initiated_by": initiatorName,
		"skip_remark":  remark,
	}
	h.audit(c, "wholesale_order_email", wo.ID, changes)

	if emailType == "invoice" {
		today := time.Now()
		_ = h.db.Model(&wo).Update("invoice_sent_at", &today).Error
	}

	c.JSON(http.StatusOK, gin.H{
		"message":      "Email skipped",
		"email_type":   emailType,
		"skipped_at":   skippedAt.Format(time.RFC3339),
		"initiated_by": initiatorName,
		"skip_remark":  remark,
	})
}

func parseWholesaleAuditChangesJSON(raw string) map[string]interface{} {
	var m map[string]interface{}
	if err := json.Unmarshal([]byte(raw), &m); err != nil {
		return map[string]interface{}{}
	}
	if nested, ok := m["changes"].(map[string]interface{}); ok {
		return nested
	}
	return m
}

func wholesaleOrderEmailAuditSkipped(changes map[string]interface{}) bool {
	v, ok := changes["skipped"]
	if !ok {
		return false
	}
	switch b := v.(type) {
	case bool:
		return b
	case string:
		return strings.EqualFold(strings.TrimSpace(b), "true")
	default:
		return false
	}
}

func wholesaleOrderEmailAuditSent(changes map[string]interface{}) bool {
	if wholesaleOrderEmailAuditSkipped(changes) {
		return false
	}
	s, _ := changes["sent_at"].(string)
	return strings.TrimSpace(s) != ""
}

func classifyWholesaleOrderStructuredEmailType(changes map[string]interface{}) string {
	if t, ok := changes["email_type"].(string); ok {
		t = strings.TrimSpace(t)
		if t == "order_confirm" || t == "shipments_delivered" || t == "invoice" {
			return t
		}
	}
	kinds := auditChangesStringSlice(changes, "attachment_kinds")
	if len(kinds) == 0 {
		return ""
	}
	allPo := true
	allConfirmBundle := true
	for _, k := range kinds {
		if k != "po_attachment" {
			allPo = false
		}
		if k != "po_attachment" && k != "order_confirmation" {
			allConfirmBundle = false
		}
	}
	if allPo {
		return "order_confirm"
	}
	if allConfirmBundle {
		return "order_confirm"
	}
	allSigned := true
	for _, k := range kinds {
		if k != "signed_delivery_note" {
			allSigned = false
			break
		}
	}
	if allSigned {
		if sid, ok := auditChangesUint(changes, "signed_delivery_shipment_id"); ok && sid > 0 {
			return ""
		}
		return "shipments_delivered"
	}
	hasInvoice := false
	allInvoiceBundle := true
	for _, k := range kinds {
		if k == "invoice" {
			hasInvoice = true
		}
		if k != "invoice" && k != "delivery_note" && k != "signed_delivery_note" {
			allInvoiceBundle = false
		}
	}
	if hasInvoice && allInvoiceBundle {
		return "invoice"
	}
	return ""
}

func (h *WholesaleOrderHandler) findLatestWholesaleOrderStructuredEmailAudit(orderID uint, emailType string) (*models.AuditLog, bool) {
	var logs []models.AuditLog
	if err := h.db.Where("entity_type = ? AND entity_id = ? AND action = ?", "wholesale_order", orderID, "wholesale_order_email").
		Order("created_at DESC, id DESC").Find(&logs).Error; err != nil {
		return nil, false
	}
	for i := range logs {
		changes := parseWholesaleAuditChangesJSON(logs[i].Changes)
		if classifyWholesaleOrderStructuredEmailType(changes) == emailType {
			return &logs[i], true
		}
	}
	return nil, false
}

func randomZipFilename() string {
	b := make([]byte, 10)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b) + ".zip"
}

// SendTestEmail sends a simple test SMTP email for connectivity/auth verification.
func (h *WholesaleOrderHandler) SendTestEmail(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	if strings.TrimSpace(h.cfg.SMTPHost) == "" || strings.TrimSpace(h.cfg.SMTPUser) == "" || h.cfg.SMTPPassword == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Email is not configured (set SMTP_HOST, SMTP_USER, SMTP_PASSWORD)"})
		return
	}

	var req struct {
		RecipientEmail string `json:"recipient_email"`
		Subject        string `json:"subject"`
		Body           string `json:"body"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	recipient := strings.TrimSpace(req.RecipientEmail)
	if recipient == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "recipient_email is required"})
		return
	}
	parsedTo, err := mail.ParseAddress(recipient)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid recipient_email"})
		return
	}
	recipientAddr := parsedTo.Address

	from := "no-reply@ducklincompany.co.uk"
	subject := strings.TrimSpace(req.Subject)
	if subject == "" {
		subject = "POS SMTP test email"
	}
	body := strings.TrimSpace(req.Body)
	if body == "" {
		body = fmt.Sprintf("SMTP test succeeded.\n\nTime: %s\nFrom backend service.\n", time.Now().Format(time.RFC3339))
	}

	log.Printf("[test-email] sending to=%q from=%q smtp_host=%q smtp_port=%d smtp_user=%q", recipientAddr, from, h.cfg.SMTPHost, h.cfg.SMTPPort, h.cfg.SMTPUser)
	if err := apimail.SendPlain(h.cfg.SMTPHost, h.cfg.SMTPPort, h.cfg.SMTPUser, h.cfg.SMTPPassword, from, []string{recipientAddr}, subject, body); err != nil {
		log.Printf("[test-email] send failed to=%q err=%v", recipientAddr, err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "Failed to send test email: " + err.Error()})
		return
	}
	log.Printf("[test-email] sent to=%q", recipientAddr)
	c.JSON(http.StatusOK, gin.H{
		"message":         "Test email sent",
		"recipient_email": recipientAddr,
		"from":            from,
	})
}

// BulkAttachmentsZipEmail builds a ZIP server-side and emails a download link.
// Runs synchronously so platforms like Cloud Run keep CPU until the request finishes (background work after 202 often never runs).
func (h *WholesaleOrderHandler) BulkAttachmentsZipEmail(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}
	if strings.TrimSpace(h.cfg.SMTPHost) == "" || strings.TrimSpace(h.cfg.SMTPUser) == "" || h.cfg.SMTPPassword == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Email is not configured (set SMTP_HOST, SMTP_USER, SMTP_PASSWORD)"})
		return
	}

	var req struct {
		OrderIDs       []uint `json:"order_ids"`
		Kind           string `json:"kind"`
		RecipientEmail string `json:"recipient_email"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	recipient := strings.TrimSpace(req.RecipientEmail)
	if recipient == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "recipient_email is required"})
		return
	}
	parsedTo, err := mail.ParseAddress(recipient)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid recipient_email"})
		return
	}
	recipientAddr := parsedTo.Address
	if len(req.OrderIDs) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "order_ids is required"})
		return
	}
	if len(req.OrderIDs) > bulkAttachmentEmailMaxOrders {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Too many orders (max %d)", bulkAttachmentEmailMaxOrders)})
		return
	}
	kind := strings.TrimSpace(req.Kind)
	validKinds := map[string]bool{
		"all": true, "order_confirmation": true, "po_attachment": true, "delivery_note": true,
		"signed_delivery_note": true, "invoice": true, "payment_proof": true,
	}
	if !validKinds[kind] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid kind"})
		return
	}

	orderIDs := req.OrderIDs
	from := h.cfg.EffectiveSMTPFrom()

	log.Printf("[bulk-zip-email] started orders=%d kind=%q recipient=%q smtp_host=%q smtp_port=%d smtp_user=%q smtp_from=%q", len(orderIDs), kind, recipientAddr, h.cfg.SMTPHost, h.cfg.SMTPPort, h.cfg.SMTPUser, from)

	var orders []models.WholesaleOrder
	if err := h.db.Where("id IN ? AND status != ?", orderIDs, models.WholesaleOrderStatusDeleted).
		Preload("Documents").
		Preload("Shipments").
		Find(&orders).Error; err != nil {
		log.Printf("[bulk-zip-email] db load error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Could not load orders: " + err.Error()})
		return
	}
	if len(orders) == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "No orders found for the given IDs"})
		return
	}

	zipData, n, err := h.buildBulkAttachmentZipBytes(orders, kind)
	if err != nil {
		log.Printf("[bulk-zip-email] zip build error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Could not build ZIP: " + err.Error()})
		return
	}
	if n == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No matching attachments were found for the selected orders."})
		return
	}
	log.Printf("[bulk-zip-email] zip ok files=%d bytes=%d", n, len(zipData))

	fileName := "bulk-zips/" + randomZipFilename()
	publicURL, err := h.uploadWholesaleFile(fileName, zipData)
	if err != nil {
		log.Printf("[bulk-zip-email] upload error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ZIP was built but upload failed: " + err.Error()})
		return
	}
	log.Printf("[bulk-zip-email] uploaded %s", publicURL)

	body := fmt.Sprintf(
		"Your wholesale attachment export is ready (%d file(s), type: %s).\n\nDownload:\n%s\n\nLink points to stored file; download it whenever ready; your organisation may delete old bulk exports over time.\n",
		n, kind, publicURL,
	)
	subjOK := "Wholesale attachments ready"
	log.Printf("[bulk-zip-email] smtp sending to=%q from=%q", recipientAddr, from)
	if err := apimail.SendPlain(h.cfg.SMTPHost, h.cfg.SMTPPort, h.cfg.SMTPUser, h.cfg.SMTPPassword, from, []string{recipientAddr}, subjOK, body); err != nil {
		log.Printf("[bulk-zip-email] FAILED success email to %q: %v", recipientAddr, err)
		c.JSON(http.StatusBadGateway, gin.H{
			"error":        "The ZIP was uploaded but the email could not be sent: " + err.Error(),
			"download_url": publicURL,
		})
		return
	}
	log.Printf("[bulk-zip-email] sent download link to %q (check spam if inbox empty)", recipientAddr)
	c.JSON(http.StatusOK, gin.H{
		"message":      "An email with the download link was sent.",
		"download_url": publicURL,
	})
}
