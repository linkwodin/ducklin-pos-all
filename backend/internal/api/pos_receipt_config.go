package api

import (
	"fmt"
	"strings"

	"pos-system/backend/internal/models"
)

var (
	defaultPosReceiptTypes = []string{
		"audit_note",
		"no_price_with_barcode",
		"customer_counterfoil",
		"no_price_no_barcode",
	}
	defaultPosAutoPrintReceiptTypes = []string{
		"no_price_with_barcode",
		"customer_counterfoil",
		"no_price_no_barcode",
	}
	validPosReceiptTypes = map[string]bool{
		"audit_note":             true,
		"no_price_with_barcode":  true,
		"customer_counterfoil": true,
		"no_price_no_barcode":    true,
		"full":                   true,
	}
)

func effectivePosReceiptTypes(store *models.Store) []string {
	if store == nil || !store.PosReceiptSettingsConfigured || len(store.PosReceiptTypes) == 0 {
		out := make([]string, len(defaultPosReceiptTypes))
		copy(out, defaultPosReceiptTypes)
		return out
	}
	return append([]string(nil), store.PosReceiptTypes...)
}

func effectivePosAutoPrintReceiptTypes(store *models.Store) []string {
	if store == nil || !store.PosReceiptSettingsConfigured {
		out := make([]string, len(defaultPosAutoPrintReceiptTypes))
		copy(out, defaultPosAutoPrintReceiptTypes)
		return out
	}
	enabled := make(map[string]bool, len(store.PosReceiptTypes))
	for _, t := range store.PosReceiptTypes {
		enabled[t] = true
	}
	out := make([]string, 0, len(store.PosAutoPrintReceiptTypes))
	for _, t := range store.PosAutoPrintReceiptTypes {
		if enabled[t] {
			out = append(out, t)
		}
	}
	return out
}

func withStoreReceiptDefaults(store models.Store) models.Store {
	store.PosReceiptTypes = effectivePosReceiptTypes(&store)
	store.PosAutoPrintReceiptTypes = effectivePosAutoPrintReceiptTypes(&store)
	return store
}

func normalizePosReceiptTypeList(types []string) []string {
	seen := make(map[string]bool)
	out := make([]string, 0, len(types))
	for _, raw := range types {
		t := strings.ToLower(strings.TrimSpace(raw))
		if t == "" || !validPosReceiptTypes[t] || seen[t] {
			continue
		}
		seen[t] = true
		out = append(out, t)
	}
	return out
}

func validatePosReceiptConfig(enabled, autoPrint []string) error {
	enabled = normalizePosReceiptTypeList(enabled)
	autoPrint = normalizePosReceiptTypeList(autoPrint)
	if len(enabled) == 0 {
		return fmt.Errorf("at least one receipt type must be enabled")
	}
	enabledSet := make(map[string]bool, len(enabled))
	for _, t := range enabled {
		enabledSet[t] = true
	}
	for _, t := range autoPrint {
		if !enabledSet[t] {
			return fmt.Errorf("auto-print type %q must also be enabled", t)
		}
	}
	return nil
}

func markStoreReceiptSettingsConfigured(store *models.Store, enabled, autoPrint []string) {
	store.PosReceiptTypes = enabled
	store.PosAutoPrintReceiptTypes = autoPrint
	store.PosReceiptSettingsConfigured = true
}
