package api

import (
	"fmt"
	"regexp"
	"strings"
)

var weightBarcodePrefixRe = regexp.MustCompile(`^\d{1,8}$`)

func normalizeWeightBarcodePrefix(raw string, unitType string) (string, error) {
	raw = strings.TrimSpace(raw)
	if unitType != "weight" {
		return "", nil
	}
	if raw == "" {
		return "", nil
	}
	if !weightBarcodePrefixRe.MatchString(raw) {
		return "", fmt.Errorf("weight_barcode_prefix must be 1-8 digits")
	}
	return raw, nil
}

// resolveWeightBarcodePrefix returns explicit prefix, or last 8 digits of productBarcode (digits only).
func resolveWeightBarcodePrefix(prefix, productBarcode string) string {
	prefix = strings.TrimSpace(prefix)
	if prefix != "" && weightBarcodePrefixRe.MatchString(prefix) {
		return prefix
	}
	var digits strings.Builder
	for _, r := range productBarcode {
		if r >= '0' && r <= '9' {
			digits.WriteRune(r)
		}
	}
	d := digits.String()
	if d == "" {
		return ""
	}
	if len(d) <= 8 {
		return d
	}
	return d[len(d)-8:]
}
