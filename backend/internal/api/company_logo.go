package api

import (
	"context"
	"fmt"
	"image"
	"image/color"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"pos-system/backend/internal/config"
	"pos-system/backend/internal/models"

	"cloud.google.com/go/storage"
	"github.com/disintegration/imaging"
	"github.com/jung-kurt/gofpdf"
)

// Branding logo dimensions — PDF matches backend/pdf-assets/images/pdf_logo.png (500×150).
const (
	BrandingLogoPxW = 500
	BrandingLogoPxH = 150
	WebLogoPxW      = 400
	WebLogoPxH      = 120
	PosLogoPxW      = 256
	PosLogoPxH      = 256
	pdfLogoDrawWmm  = 50.0
	pdfLogoDrawHmm  = 15.0 // 50mm × (150/500)
)

const (
	LogoTypePDF = "pdf"
	LogoTypeWeb = "web"
	LogoTypePOS = "pos"
)

func parseLogoType(raw string) (string, bool) {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case LogoTypePDF, LogoTypeWeb, LogoTypePOS:
		return strings.ToLower(strings.TrimSpace(raw)), true
	default:
		return "", false
	}
}

// EffectivePdfLogoURL returns the PDF logo path, falling back to legacy logo_url.
func EffectivePdfLogoURL(s models.CompanySettings) string {
	if u := normalizeLogoURL(s.PdfLogoURL); u != "" {
		return u
	}
	return normalizeLogoURL(s.LogoURL)
}

// EffectiveWebLogoURL returns the web portal logo path, falling back to legacy logo_url.
func EffectiveWebLogoURL(s models.CompanySettings) string {
	if u := normalizeLogoURL(s.WebLogoURL); u != "" {
		return u
	}
	return normalizeLogoURL(s.LogoURL)
}

// EffectivePosLogoURL returns the POS app logo path, falling back to legacy logo_url.
func EffectivePosLogoURL(s models.CompanySettings) string {
	if u := normalizeLogoURL(s.PosLogoURL); u != "" {
		return u
	}
	return normalizeLogoURL(s.LogoURL)
}

func logoURLForType(s models.CompanySettings, logoType string) string {
	switch logoType {
	case LogoTypePDF:
		return EffectivePdfLogoURL(s)
	case LogoTypeWeb:
		return EffectiveWebLogoURL(s)
	case LogoTypePOS:
		return EffectivePosLogoURL(s)
	default:
		return ""
	}
}

func setLogoURLForType(s *models.CompanySettings, logoType, url string) {
	switch logoType {
	case LogoTypePDF:
		s.PdfLogoURL = url
	case LogoTypeWeb:
		s.WebLogoURL = url
	case LogoTypePOS:
		s.PosLogoURL = url
	}
}

func readGCPObjectBytes(bucketName, fileURL string) ([]byte, error) {
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
	r, err := client.Bucket(bucketName).Object(path).NewReader(ctx)
	if err != nil {
		return nil, err
	}
	defer r.Close()
	return io.ReadAll(r)
}

func readStoredFileBytes(fileURL string, cfg *config.Config) ([]byte, error) {
	fileURL = strings.TrimSpace(fileURL)
	if fileURL == "" {
		return nil, fmt.Errorf("empty url")
	}
	if strings.Contains(fileURL, "storage.googleapis.com") && cfg != nil && cfg.GCPBucketName != "" {
		return readGCPObjectBytes(cfg.GCPBucketName, fileURL)
	}
	if strings.HasPrefix(fileURL, "http://") || strings.HasPrefix(fileURL, "https://") {
		client := &http.Client{Timeout: 2 * time.Minute}
		resp, err := client.Get(fileURL)
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
		}
		return io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	}
	uploadDir := "./uploads"
	if cfg != nil && cfg.UploadDir != "" {
		uploadDir = cfg.UploadDir
	}
	u, err := url.Parse(fileURL)
	if err != nil {
		return nil, err
	}
	pathPart := u.Path
	if decoded, decErr := url.PathUnescape(pathPart); decErr == nil {
		pathPart = decoded
	}
	localPath := filepath.Join(uploadDir, strings.TrimPrefix(pathPart, "/uploads/"))
	return os.ReadFile(localPath)
}

// normalizeLogoURL returns a portable /uploads/... path when possible.
func normalizeLogoURL(logoURL string) string {
	logoURL = strings.TrimSpace(logoURL)
	if logoURL == "" {
		return ""
	}
	if strings.HasPrefix(logoURL, "/uploads/") {
		return logoURL
	}
	u, err := url.Parse(logoURL)
	if err != nil {
		return logoURL
	}
	pathPart := u.Path
	if decoded, decErr := url.PathUnescape(pathPart); decErr == nil {
		pathPart = decoded
	}
	if strings.HasPrefix(pathPart, "/uploads/") {
		return pathPart
	}
	return logoURL
}

// ResizeImageToBrandingLogo fits [src] inside 500×150 (same as pdf_logo.png) on a white canvas.
func ResizeImageToBrandingLogo(src image.Image) *image.NRGBA {
	return resizeImageToBox(src, BrandingLogoPxW, BrandingLogoPxH)
}

func resizeImageToBox(src image.Image, boxW, boxH int) *image.NRGBA {
	fitted := imaging.Fit(src, boxW, boxH, imaging.Lanczos)
	canvas := imaging.New(boxW, boxH, color.White)
	offX := (boxW - fitted.Bounds().Dx()) / 2
	offY := (boxH - fitted.Bounds().Dy()) / 2
	return imaging.Paste(canvas, fitted, image.Pt(offX, offY))
}

// trimNearWhiteBorder removes uniform white margins so copy-between-types refits the logo content.
func trimNearWhiteBorder(src image.Image) image.Image {
	bounds := src.Bounds()
	minX, minY := bounds.Max.X, bounds.Max.Y
	maxX, maxY := bounds.Min.X, bounds.Min.Y
	found := false
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			r, g, b, a := src.At(x, y).RGBA()
			if a < 0x0f00 {
				continue
			}
			if r >= 0xf000 && g >= 0xf000 && b >= 0xf000 {
				continue
			}
			found = true
			if x < minX {
				minX = x
			}
			if x+1 > maxX {
				maxX = x + 1
			}
			if y < minY {
				minY = y
			}
			if y+1 > maxY {
				maxY = y + 1
			}
		}
	}
	if !found || minX >= maxX || minY >= maxY {
		return src
	}
	return imaging.Crop(src, image.Rect(minX, minY, maxX, maxY))
}

// ResizeImageForLogoType resizes an image for pdf, web, or pos branding.
func ResizeImageForLogoType(src image.Image, logoType string) *image.NRGBA {
	switch logoType {
	case LogoTypeWeb:
		return resizeImageToBox(src, WebLogoPxW, WebLogoPxH)
	case LogoTypePOS:
		return resizeImageToBox(src, PosLogoPxW, PosLogoPxH)
	default:
		return ResizeImageToBrandingLogo(src)
	}
}

func localUploadFilePath(logoURL string, uploadDir string) string {
	logoURL = strings.TrimSpace(logoURL)
	if logoURL == "" {
		return ""
	}
	uploadDir = strings.TrimSuffix(uploadDir, "/")
	if uploadDir == "" {
		uploadDir = "./uploads"
	}

	pathPart := ""
	switch {
	case strings.HasPrefix(logoURL, "/uploads/"):
		pathPart = logoURL
	case strings.HasPrefix(logoURL, "http://"), strings.HasPrefix(logoURL, "https://"):
		u, err := url.Parse(logoURL)
		if err != nil {
			return ""
		}
		pathPart = u.Path
		if decoded, decErr := url.PathUnescape(pathPart); decErr == nil {
			pathPart = decoded
		}
	default:
		return ""
	}
	if !strings.HasPrefix(pathPart, "/uploads/") {
		return ""
	}
	rel := strings.TrimPrefix(pathPart, "/uploads/")
	localPath := filepath.Join(uploadDir, rel)
	if _, err := os.Stat(localPath); err != nil {
		return ""
	}
	abs, err := filepath.Abs(localPath)
	if err != nil {
		return localPath
	}
	return abs
}

func ensureLogoFileOnDisk(logoURL string, cfg *config.Config, uploadDir string) string {
	if p := localUploadFilePath(logoURL, uploadDir); p != "" {
		return p
	}
	logoURL = strings.TrimSpace(logoURL)
	if logoURL == "" {
		return ""
	}
	data, err := readStoredFileBytes(logoURL, cfg)
	if err != nil {
		return ""
	}
	uploadDir = strings.TrimSuffix(uploadDir, "/")
	if uploadDir == "" {
		uploadDir = "./uploads"
	}
	cacheDir := filepath.Join(uploadDir, ".cache")
	_ = os.MkdirAll(cacheDir, 0755)
	cachePath := filepath.Join(cacheDir, "company_logo_source.bin")
	if writeErr := os.WriteFile(cachePath, data, 0644); writeErr != nil {
		return ""
	}
	return cachePath
}

func referencePDFLogoPath(cfg *config.Config, uploadDir string) string {
	candidates := []string{}
	if cfg != nil {
		if p := strings.TrimSpace(cfg.PDFLogoPath); p != "" {
			candidates = append(candidates, p)
		}
	}
	candidates = append(candidates,
		filepath.Join("pdf-assets", "images", "pdf_logo.png"),
		filepath.Join(uploadDir, "assets", "images", "pdf_logo.png"),
	)
	for _, logoPath := range candidates {
		if !filepath.IsAbs(logoPath) {
			if abs, err := filepath.Abs(logoPath); err == nil {
				logoPath = abs
			}
		}
		if _, err := os.Stat(logoPath); err == nil {
			return logoPath
		}
	}
	return ""
}

// preparePDFLogoRaster normalizes any logo file to 500×150 PNG for PDF embedding.
func preparePDFLogoRaster(srcPath, cacheDir string) (string, error) {
	srcPath = strings.TrimSpace(srcPath)
	if srcPath == "" {
		return "", fmt.Errorf("empty source path")
	}
	if err := os.MkdirAll(cacheDir, 0755); err != nil {
		return "", err
	}
	outPath := filepath.Join(cacheDir, "company_logo_pdf.png")

	src, err := imaging.Open(srcPath)
	if err != nil {
		return "", err
	}
	normalized := ResizeImageToBrandingLogo(src)
	if err := imaging.Save(normalized, outPath); err != nil {
		return "", err
	}
	return outPath, nil
}

// drawCompanyLogoOnPDF draws the company logo at the same size as pdf_logo.png (50mm × 15mm).
func drawCompanyLogoOnPDF(pdf *gofpdf.Fpdf, company models.CompanySettings, cfg *config.Config, uploadDir string, margin, x, y, maxW, maxH float64) float64 {
	_ = maxW
	_ = maxH

	uploadDir = strings.TrimSuffix(uploadDir, "/")
	if uploadDir == "" {
		uploadDir = "./uploads"
	}
	cacheDir := filepath.Join(uploadDir, ".cache")

	logoPath := ""
	if pdfURL := EffectivePdfLogoURL(company); pdfURL != "" {
		logoPath = ensureLogoFileOnDisk(pdfURL, cfg, uploadDir)
	}
	if logoPath == "" {
		logoPath = referencePDFLogoPath(cfg, uploadDir)
	}
	if logoPath == "" {
		return 0
	}

	rasterPath, err := preparePDFLogoRaster(logoPath, cacheDir)
	if err != nil {
		if logoPath != referencePDFLogoPath(cfg, uploadDir) {
			logoPath = referencePDFLogoPath(cfg, uploadDir)
			if logoPath == "" {
				return 0
			}
			rasterPath, err = preparePDFLogoRaster(logoPath, cacheDir)
		}
		if err != nil {
			return 0
		}
	}

	if pdf.RegisterImage(rasterPath, "PNG") == nil {
		return 0
	}
	pdf.Image(rasterPath, x, y, pdfLogoDrawWmm, pdfLogoDrawHmm, false, "PNG", 0, "")
	return pdfLogoDrawHmm
}
