package config

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/joho/godotenv"
)

type Config struct {
	DatabaseURL     string
	JWTSecret       string
	JWTExpiration   int    // in hours
	StorageProvider string // "local", "gcp", or "aws"
	GCPBucketName   string
	AWSS3Bucket     string
	AWSAccessKey    string
	AWSSecretKey    string
	AWSRegion       string
	Environment     string // "development" or "production"
	UploadDir       string // Directory for local file uploads
	BaseURL         string // Base URL for serving uploaded files
	PDFFontPath     string // Optional path to TTF for PDF (UTF-8: Chinese, £). e.g. uploads/assets/fonts/NotoSansTC-Regular.ttf
	PDFLogoPath     string // Optional path to logo image for PDF header. e.g. uploads/assets/images/pdf_logo.png
	// SMTP (optional; used for async wholesale attachment ZIP email). Use Google Workspace App Password or relay.
	SMTPHost     string
	SMTPPort     int
	SMTPUser     string
	SMTPPassword string
	SMTPFrom     string // envelope From; if empty, EffectiveSMTPFrom() uses no-reply@<SMTP_USER domain>
}

func loadDotEnv() {
	// Try CWD first, then backend/.env when started from repo root.
	candidates := []string{".env", filepath.Join("backend", ".env")}
	if wd, err := os.Getwd(); err == nil {
		candidates = append(candidates, filepath.Join(wd, ".env"), filepath.Join(wd, "backend", ".env"))
	}
	seen := make(map[string]struct{})
	for _, p := range candidates {
		if p == "" {
			continue
		}
		if _, ok := seen[p]; ok {
			continue
		}
		seen[p] = struct{}{}
		if _, err := os.Stat(p); err != nil {
			continue
		}
		_ = godotenv.Load(p)
		return
	}
}

func Load() *Config {
	loadDotEnv()

	return &Config{
		DatabaseURL:     getEnv("DATABASE_URL", "mysql://user:password@localhost:3306/pos_system"),
		JWTSecret:       getEnv("JWT_SECRET", "change-this-secret-key-in-production"),
		JWTExpiration:   getEnvInt("JWT_EXPIRATION", 24), // hours
		StorageProvider: getEnv("STORAGE_PROVIDER", "local"), // "local", "gcp", or "aws"
		GCPBucketName:   getEnv("GCP_BUCKET_NAME", ""),
		AWSS3Bucket:     getEnv("AWS_S3_BUCKET", ""),
		AWSAccessKey:    getEnv("AWS_ACCESS_KEY", ""),
		AWSSecretKey:    getEnv("AWS_SECRET_KEY", ""),
		AWSRegion:       getEnv("AWS_REGION", "us-east-1"),
		Environment:     getEnv("ENVIRONMENT", "development"),
		UploadDir:       getEnv("UPLOAD_DIR", "./uploads"),
		BaseURL:         getEnv("BASE_URL", "http://localhost:8868"),
		PDFFontPath:     getEnv("PDF_FONT_PATH", ""),
		PDFLogoPath:     getEnv("PDF_LOGO_PATH", "uploads/assets/images/pdf_logo.png"),
		// TrimSpace: Secret Manager / env often includes a trailing newline, which breaks SMTP AUTH.
		SMTPHost:        strings.TrimSpace(getEnv("SMTP_HOST", "")),
		SMTPPort:        getEnvInt("SMTP_PORT", 587),
		SMTPUser:        strings.TrimSpace(getEnv("SMTP_USER", "")),
		SMTPPassword:    strings.TrimSpace(getEnv("SMTP_PASSWORD", "")),
		SMTPFrom:        strings.TrimSpace(getEnv("SMTP_FROM", "")),
	}
}

func getEnvInt(key string, defaultVal int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			return n
		}
	}
	return defaultVal
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// EffectiveSMTPFrom returns SMTP_FROM when set; otherwise no-reply@<domain> from SMTP_USER
// (same domain as the authenticated mailbox). Falls back to SMTP_USER if the address has no domain.
func (c *Config) EffectiveSMTPFrom() string {
	if s := strings.TrimSpace(c.SMTPFrom); s != "" {
		return s
	}
	u := strings.TrimSpace(c.SMTPUser)
	if i := strings.LastIndex(u, "@"); i > 0 && i < len(u)-1 {
		domain := strings.TrimSpace(u[i+1:])
		if domain != "" {
			return "no-reply@" + domain
		}
	}
	return u
}
