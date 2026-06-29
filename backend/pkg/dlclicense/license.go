package dlclicense

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"fmt"
	"regexp"
	"strings"
)

const (
	FeatureWholesale = "wholesale"
	FeaturePOS       = "pos"
)

// Signing key is embedded in the backend and dlc-gen tool (not .env).
const signingKey = "pos-system-dlc-v1"

const codeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var legacyMacDisplayRE = regexp.MustCompile(`^MAC[-:]?([0-9A-F]{12})$`)

// NormalizeInstallationID accepts raw installation id or legacy display names.
func NormalizeInstallationID(raw string) string {
	raw = strings.ToUpper(strings.TrimSpace(raw))
	if raw == "" {
		return ""
	}
	if m := legacyMacDisplayRE.FindStringSubmatch(raw); len(m) == 2 {
		return m[1]
	}
	for _, prefix := range []string{"DOMAIN-", "HOST-", "INST-", "MAC-"} {
		if strings.HasPrefix(raw, prefix) {
			raw = strings.TrimPrefix(raw, prefix)
			break
		}
	}
	raw = strings.ReplaceAll(raw, ":", "")
	raw = strings.ReplaceAll(raw, "-", "")
	raw = strings.ReplaceAll(raw, " ", "")
	return raw
}

// NormalizeFingerprint is an alias for NormalizeInstallationID (legacy name).
func NormalizeFingerprint(raw string) string {
	return NormalizeInstallationID(raw)
}

// NormalizeCode uppercases and strips spaces/dashes from activation codes.
func NormalizeCode(raw string) string {
	raw = strings.ToUpper(strings.TrimSpace(raw))
	raw = strings.ReplaceAll(raw, " ", "")
	raw = strings.ReplaceAll(raw, "-", "")
	return raw
}

func featurePrefix(feature string) string {
	switch feature {
	case FeatureWholesale:
		return "WS"
	case FeaturePOS:
		return "PS"
	default:
		return ""
	}
}

// FormatCode formats WS-XXXX-XXXX-XXXX or PS-XXXX-XXXX-XXXX for display.
func FormatCode(feature, normalized string) string {
	prefix := featurePrefix(feature)
	normalized = NormalizeCode(normalized)
	if prefix == "" || len(normalized) != 14 || !strings.HasPrefix(normalized, prefix) {
		return normalized
	}
	body := normalized[2:]
	return fmt.Sprintf("%s-%s-%s-%s", prefix, body[0:4], body[4:8], body[8:12])
}

// FormatWholesaleCode formats WS-XXXX-XXXX-XXXX for display.
func FormatWholesaleCode(normalized string) string {
	return FormatCode(FeatureWholesale, normalized)
}

// FormatPOSCode formats PS-XXXX-XXXX-XXXX for display.
func FormatPOSCode(normalized string) string {
	return FormatCode(FeaturePOS, normalized)
}

// ActivationCode returns the deterministic activation code for a feature and installation id.
func ActivationCode(feature, installationID string) string {
	prefix := featurePrefix(feature)
	id := NormalizeInstallationID(installationID)
	if prefix == "" || id == "" {
		return ""
	}
	mac := hmac.New(sha256.New, []byte(signingKey))
	_, _ = mac.Write([]byte(feature + ":" + id))
	sum := mac.Sum(nil)
	body := make([]byte, 12)
	for i := 0; i < 12; i++ {
		body[i] = codeAlphabet[int(sum[i])%len(codeAlphabet)]
	}
	return prefix + string(body)
}

// ValidateCode checks an entered code against the expected code for this installation id.
func ValidateCode(feature, installationID, code string) bool {
	expected := ActivationCode(feature, installationID)
	if expected == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(NormalizeCode(code)), []byte(expected)) == 1
}

// WholesaleActivationCode returns the wholesale DLC code for an installation id.
func WholesaleActivationCode(installationID string) string {
	return ActivationCode(FeatureWholesale, installationID)
}

// POSActivationCode returns the POS DLC code for an installation id.
func POSActivationCode(installationID string) string {
	return ActivationCode(FeaturePOS, installationID)
}

// ValidateWholesaleCode checks a wholesale DLC code.
func ValidateWholesaleCode(installationID, code string) bool {
	return ValidateCode(FeatureWholesale, installationID, code)
}

// ValidatePOSCode checks a POS DLC code.
func ValidatePOSCode(installationID, code string) bool {
	return ValidateCode(FeaturePOS, installationID, code)
}
