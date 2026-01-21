package utils

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"fmt"
	"strconv"
	"strings"

	"golang.org/x/crypto/argon2"
)

const (
	// Argon2 parameters
	argon2Time    = 3         // Number of iterations
	argon2Memory  = 64 * 1024 // 64 MB memory
	argon2Threads = 4         // Number of threads
	argon2KeyLen  = 32        // Length of the derived key
	saltLength    = 16        // Length of the salt
)

// HashPassword hashes a password using Argon2id
func HashPassword(password string) (string, error) {
	// Generate a random salt
	salt := make([]byte, saltLength)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}

	// Hash the password
	hash := argon2.IDKey([]byte(password), salt, argon2Time, argon2Memory, argon2Threads, argon2KeyLen)

	// Encode salt and hash to base64
	b64Salt := base64.RawStdEncoding.EncodeToString(salt)
	b64Hash := base64.RawStdEncoding.EncodeToString(hash)

	// Return Argon2id format: $argon2id$v=19$m=65536,t=3,p=2$salt$hash
	return fmt.Sprintf("$argon2id$v=19$m=%d,t=%d,p=%d$%s$%s", argon2Memory, argon2Time, argon2Threads, b64Salt, b64Hash), nil
}

// HashPIN hashes a PIN using Argon2id
func HashPIN(pin string) (string, error) {
	return HashPassword(pin)
}

// VerifyPassword verifies a password against an Argon2 hash or plain text
// Returns true if password matches, false otherwise
func VerifyPassword(password, hash string) bool {
	// If hash doesn't start with $argon2id$, treat it as plain text
	if !strings.HasPrefix(hash, "$argon2id$") {
		// Plain text comparison for easy setup
		return password == hash
	}

	// Parse Argon2 hash
	parts := strings.Split(hash, "$")
	if len(parts) != 6 || parts[1] != "argon2id" {
		return false
	}

	// Extract parameters
	params := strings.Split(parts[3], ",")
	var memory, time, threads uint32 = argon2Memory, argon2Time, argon2Threads
	for _, param := range params {
		if strings.HasPrefix(param, "m=") {
			if val, err := strconv.ParseUint(strings.TrimPrefix(param, "m="), 10, 32); err == nil {
				memory = uint32(val)
			}
		} else if strings.HasPrefix(param, "t=") {
			if val, err := strconv.ParseUint(strings.TrimPrefix(param, "t="), 10, 32); err == nil {
				time = uint32(val)
			}
		} else if strings.HasPrefix(param, "p=") {
			if val, err := strconv.ParseUint(strings.TrimPrefix(param, "p="), 10, 32); err == nil {
				threads = uint32(val)
			}
		}
	}

	// Decode salt and hash
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return false
	}

	expectedHash, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return false
	}

	// Compute hash (threads must be uint8)
	computedHash := argon2.IDKey([]byte(password), salt, time, memory, uint8(threads), uint32(len(expectedHash)))

	// Constant-time comparison
	return subtle.ConstantTimeCompare(computedHash, expectedHash) == 1
}

// IsPlainText checks if a hash is plain text (not hashed)
func IsPlainText(hash string) bool {
	return !strings.HasPrefix(hash, "$argon2id$")
}

// GenerateIconColor generates a random color for user icons
func GenerateIconColor(firstName, lastName string) string {
	// Simple hash-based color generation
	hash := 0
	name := firstName + lastName
	for i := 0; i < len(name); i++ {
		hash = int(name[i]) + ((hash << 5) - hash)
	}

	// Generate a color from the hash
	r := (hash & 0xFF0000) >> 16
	g := (hash & 0x00FF00) >> 8
	b := hash & 0x0000FF

	// Ensure minimum brightness
	if r < 100 {
		r = 100
	}
	if g < 100 {
		g = 100
	}
	if b < 100 {
		b = 100
	}

	return string(rune(r)) + string(rune(g)) + string(rune(b))
}
