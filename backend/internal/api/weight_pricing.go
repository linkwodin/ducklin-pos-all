package api

import (
	"fmt"
	"strconv"
	"strings"

	"pos-system/backend/internal/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func isWeightUnitType(unitType string) bool {
	return strings.EqualFold(strings.TrimSpace(unitType), "weight")
}

// effectivePriceWeightG returns the reference weight in grams that a retail unit price applies to.
// For weight products with no value set, defaults to 1000 g (1 kg).
func effectivePriceWeightG(unitType string, priceWeightG float64) float64 {
	if !isWeightUnitType(unitType) {
		return 1
	}
	if priceWeightG > 0 {
		return priceWeightG
	}
	return 1000
}

// orderLineFactor converts cart/order quantity into a billable factor.
// Quantity products: factor = quantity. Weight products: factor = actual grams / reference grams.
func orderLineFactor(unitType string, priceWeightG float64, quantity float64) float64 {
	if isWeightUnitType(unitType) {
		ref := effectivePriceWeightG(unitType, priceWeightG)
		if ref <= 0 {
			ref = 1000
		}
		return quantity / ref
	}
	return quantity
}

func normalizePriceWeightG(sellByWeight bool, priceWeightG float64) (float64, error) {
	if !sellByWeight {
		return 0, nil
	}
	if priceWeightG < 0 {
		return 0, fmt.Errorf("price_weight_g must be positive")
	}
	return priceWeightG, nil
}

func formBool(c *gin.Context, key string) bool {
	raw := strings.TrimSpace(c.PostForm(key))
	return raw == "true" || raw == "1" || raw == "on"
}

func fillProductRequestSaleFields(c *gin.Context, req *CreateProductRequest) {
	if ut := strings.TrimSpace(c.PostForm("unit_type")); ut != "" {
		req.UnitType = ut
	}
	req.WeightBarcode = strings.TrimSpace(c.PostForm("weight_barcode"))
	// Legacy booleans only when unit_type omitted (old clients).
	if strings.TrimSpace(req.UnitType) == "" {
		req.SellByQty = formBool(c, "sell_by_qty")
		req.SellByWeight = formBool(c, "sell_by_weight")
	}
	if pw := strings.TrimSpace(c.PostForm("prepack_weight_g")); pw != "" {
		if v, err := strconv.ParseFloat(pw, 64); err == nil {
			req.PrepackWeightG = v
		}
	}
	if pw := strings.TrimSpace(c.PostForm("price_weight_g")); pw != "" {
		if v, err := strconv.ParseFloat(pw, 64); err == nil {
			req.PriceWeightG = v
		}
	}
	if sw := strings.TrimSpace(c.PostForm("selling_weight_g")); sw != "" {
		if v, err := strconv.ParseFloat(sw, 64); err == nil {
			req.PrepackWeightG = v
			req.PriceWeightG = v
		}
	}
}

// normalizeLegacySaleFields maps deprecated flags to unit_type when unit_type is omitted.
func normalizeLegacySaleFields(req *CreateProductRequest) {
	if strings.TrimSpace(req.UnitType) != "" {
		return
	}
	if req.SellByWeight && !req.SellByQty {
		req.UnitType = "weight"
		return
	}
	if req.SellByQty && !req.SellByWeight {
		req.UnitType = "quantity"
		return
	}
	if req.CanSellByWeight || req.SellByWeight {
		req.UnitType = "weight"
		if req.WeightBarcode == "" {
			req.WeightBarcode = strings.TrimSpace(req.Barcode)
		}
		return
	}
	req.UnitType = "quantity"
}

func validateProductSaleModes(req *CreateProductRequest) error {
	normalizeLegacySaleFields(req)
	normalizeUnitTypeFromSaleFields(req)

	unitType := strings.ToLower(strings.TrimSpace(req.UnitType))
	if unitType != "quantity" && unitType != "weight" {
		return fmt.Errorf("unit_type must be quantity or weight")
	}
	req.UnitType = unitType
	req.SellByQty = unitType == "quantity"
	req.SellByWeight = unitType == "weight"
	req.CanSellByWeight = false

	if req.SellByQty && strings.TrimSpace(req.Barcode) == "" {
		return fmt.Errorf("barcode is required for quantity variants")
	}
	if req.SellByWeight {
		if strings.TrimSpace(req.WeightBarcode) == "" {
			req.WeightBarcode = strings.TrimSpace(req.Barcode)
		}
		if strings.TrimSpace(req.WeightBarcode) == "" {
			return fmt.Errorf("barcode is required for weight variants")
		}
	}
	return nil
}

// normalizeUnitTypeFromSaleFields maps legacy dual-mode requests to a single unit_type.
func normalizeUnitTypeFromSaleFields(req *CreateProductRequest) {
	if strings.TrimSpace(req.UnitType) != "" {
		return
	}
	if req.SellByWeight && !req.SellByQty {
		req.UnitType = "weight"
	} else if req.SellByQty && !req.SellByWeight {
		req.UnitType = "quantity"
	} else if req.SellByWeight {
		// Legacy dual mode: prefer quantity when both selected (split should use separate variants).
		req.UnitType = "quantity"
		req.SellByWeight = false
	} else {
		req.UnitType = "quantity"
	}
}

func applyProductSaleFields(product *models.Product, req CreateProductRequest) {
	product.UnitType = req.UnitType
	product.SellByQty = req.UnitType == "quantity"
	product.SellByWeight = req.UnitType == "weight"
	product.CanSellByWeight = false
	if req.UnitType == "weight" {
		product.WeightBarcode = strings.TrimSpace(req.WeightBarcode)
		if product.WeightBarcode == "" {
			product.WeightBarcode = strings.TrimSpace(req.Barcode)
		}
	} else {
		product.Barcode = strings.TrimSpace(req.Barcode)
	}
	if req.PrepackWeightG > 0 || req.PriceWeightG > 0 {
		sellingWeight := req.PrepackWeightG
		if sellingWeight <= 0 {
			sellingWeight = req.PriceWeightG
		}
		product.PrepackWeightG = sellingWeight
		product.PriceWeightG = sellingWeight
	} else if req.UnitType != "weight" {
		product.PrepackWeightG = 0
		product.PriceWeightG = 0
	}
}

// saveProduct persists a product, storing NULL (not '') for unused barcode columns so unique indexes stay valid.
func saveProduct(db *gorm.DB, product *models.Product) error {
	if product.ID == 0 {
		return createProductRecord(db, product)
	}
	return updateProductRecord(db, product)
}

func createProductRecord(db *gorm.DB, product *models.Product) error {
	if isWeightUnitType(product.UnitType) {
		product.Barcode = ""
		return db.Omit("Barcode").Create(product).Error
	}
	product.WeightBarcode = ""
	product.WeightBarcodePrefix = ""
	return db.Omit("WeightBarcode").Create(product).Error
}

func updateProductRecord(db *gorm.DB, product *models.Product) error {
	return db.Transaction(func(tx *gorm.DB) error {
		id := product.ID
		if isWeightUnitType(product.UnitType) {
			if err := tx.Model(&models.Product{}).Where("id = ?", id).Update("barcode", nil).Error; err != nil {
				return err
			}
			product.Barcode = ""
			return tx.Model(&models.Product{}).Where("id = ?", id).Omit("Barcode").Updates(product).Error
		}
		if err := tx.Model(&models.Product{}).Where("id = ?", id).Updates(map[string]interface{}{
			"weight_barcode":        nil,
			"weight_barcode_prefix": "",
		}).Error; err != nil {
			return err
		}
		product.WeightBarcode = ""
		product.WeightBarcodePrefix = ""
		return tx.Model(&models.Product{}).Where("id = ?", id).Omit("WeightBarcode").Updates(product).Error
	})
}

func productUsesWeightPricing(sellByWeight bool, unitType string) bool {
	return sellByWeight || isWeightUnitType(unitType)
}

func productSupportsDualInventory(p *models.Product) bool {
	return false
}

func productSellByWeight(p *models.Product) bool {
	return p != nil && isWeightUnitType(p.UnitType)
}

func productSellByQty(p *models.Product) bool {
	return p != nil && !isWeightUnitType(p.UnitType)
}

// deriveWeightBarcodePrefix auto-sets receipt prefix from the variant barcode (no separate prefix field).
func deriveWeightBarcodePrefix(req CreateProductRequest, unitType string) (string, error) {
	if !isWeightUnitType(unitType) {
		return "", nil
	}
	wtBC := strings.TrimSpace(req.WeightBarcode)
	if wtBC == "" {
		wtBC = strings.TrimSpace(req.Barcode)
	}
	return normalizeWeightBarcodePrefix(autoWeightBarcodePrefix("", wtBC), "weight")
}

// autoWeightBarcodePrefix derives receipt prefix from weight barcode when not explicitly set.
func autoWeightBarcodePrefix(prefix, weightBarcode string) string {
	p := strings.TrimSpace(prefix)
	if p != "" {
		return p
	}
	digits := strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		return -1
	}, weightBarcode)
	if len(digits) == 0 {
		return ""
	}
	if len(digits) <= 8 {
		return digits
	}
	return digits[len(digits)-8:]
}
