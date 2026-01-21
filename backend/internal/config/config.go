package config

import (
	"os"

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
}

func Load() *Config {
	// Load .env file if it exists (for local development)
	_ = godotenv.Load()

	return &Config{
		DatabaseURL:     getEnv("DATABASE_URL", "mysql://user:password@localhost:3306/pos_system"),
		JWTSecret:       getEnv("JWT_SECRET", "change-this-secret-key-in-production"),
		JWTExpiration:   24,                                  // 24 hours
		StorageProvider: getEnv("STORAGE_PROVIDER", "local"), // "local", "gcp", or "aws"
		GCPBucketName:   getEnv("GCP_BUCKET_NAME", ""),
		AWSS3Bucket:     getEnv("AWS_S3_BUCKET", ""),
		AWSAccessKey:    getEnv("AWS_ACCESS_KEY", ""),
		AWSSecretKey:    getEnv("AWS_SECRET_KEY", ""),
		AWSRegion:       getEnv("AWS_REGION", "us-east-1"),
		Environment:     getEnv("ENVIRONMENT", "development"),
		UploadDir:       getEnv("UPLOAD_DIR", "./uploads"),
		BaseURL:         getEnv("BASE_URL", "http://localhost:8868"),
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
