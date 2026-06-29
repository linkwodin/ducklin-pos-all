package api

import (
	"image"
	"image/color"
	"testing"

	"github.com/disintegration/imaging"
)

func TestResizeImageForLogoTypeDimensions(t *testing.T) {
	src := imaging.New(800, 600, color.White)
	src = imaging.Paste(src, imaging.New(400, 200, color.NRGBA{R: 20, G: 40, B: 200, A: 255}), image.Pt(200, 200))

	cases := []struct {
		typ   string
		wantW int
		wantH int
	}{
		{LogoTypePDF, BrandingLogoPxW, BrandingLogoPxH},
		{LogoTypeWeb, WebLogoPxW, WebLogoPxH},
		{LogoTypePOS, PosLogoPxW, PosLogoPxH},
	}
	for _, tc := range cases {
		out := ResizeImageForLogoType(src, tc.typ)
		b := out.Bounds()
		if b.Dx() != tc.wantW || b.Dy() != tc.wantH {
			t.Fatalf("%s: got %dx%d want %dx%d", tc.typ, b.Dx(), b.Dy(), tc.wantW, tc.wantH)
		}
	}
}

func TestCopyResizeUsesTargetDimensions(t *testing.T) {
	// Simulate copying a web-sized icon to POS dimensions.
	webLike := resizeImageToBox(imaging.New(300, 300, color.NRGBA{R: 200, G: 20, B: 20, A: 255}), WebLogoPxW, WebLogoPxH)
	posOut := ResizeImageForLogoType(trimNearWhiteBorder(webLike), LogoTypePOS)
	b := posOut.Bounds()
	if b.Dx() != PosLogoPxW || b.Dy() != PosLogoPxH {
		t.Fatalf("pos copy resize: got %dx%d want %dx%d", b.Dx(), b.Dy(), PosLogoPxW, PosLogoPxH)
	}
}
