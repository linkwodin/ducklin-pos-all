package utils

import (
	"fmt"
	"strings"

	"github.com/google/uuid"
)

// NewInstallationID returns a new random installation identifier (32 hex chars).
func NewInstallationID() string {
	return strings.ToUpper(strings.ReplaceAll(uuid.NewString(), "-", ""))
}

// NormalizeInstallationID strips spaces/dashes and uppercases.
func NormalizeInstallationID(raw string) string {
	raw = strings.ToUpper(strings.TrimSpace(raw))
	raw = strings.ReplaceAll(raw, "-", "")
	raw = strings.ReplaceAll(raw, " ", "")
	return raw
}

// FormatInstallationID formats a 32-char id as XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX.
func FormatInstallationID(id string) string {
	id = NormalizeInstallationID(id)
	if len(id) != 32 {
		return id
	}
	return fmt.Sprintf("%s-%s-%s-%s", id[0:8], id[8:16], id[16:24], id[24:32])
}

// EnsureInstallationID returns a persisted installation id, migrating legacy
// system_fingerprint when present, or generating a new id on first init.
func EnsureInstallationID(persisted, legacyFingerprint string) (id string, generated bool) {
	if id = NormalizeInstallationID(persisted); id != "" {
		return id, false
	}
	if id = NormalizeInstallationID(legacyFingerprint); id != "" {
		return id, false
	}
	return NewInstallationID(), true
}
