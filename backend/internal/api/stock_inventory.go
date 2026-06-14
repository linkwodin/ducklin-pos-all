package api

import "pos-system/backend/internal/models"

// effectivePrepackWeightG returns grams per prepacked unit for pack/unpack conversions.
func effectivePrepackWeightG(p *models.Product) float64 {
	if p == nil {
		return 0
	}
	if p.PrepackWeightG > 0 {
		return p.PrepackWeightG
	}
	if p.PriceWeightG > 0 {
		return p.PriceWeightG
	}
	return 0
}

// effectivePrepackedQuantity returns prepacked unit count (Quantity field).
func effectivePrepackedQuantity(stock *models.Stock, product *models.Product) float64 {
	if stock == nil {
		return 0
	}
	if product != nil && productSellByWeight(product) && !productSellByQty(product) {
		return 0
	}
	return stock.Quantity
}

// effectiveWeightQuantityG returns loose weight inventory in grams.
func effectiveWeightQuantityG(stock *models.Stock, product *models.Product) float64 {
	if stock == nil {
		return 0
	}
	if stock.WeightQuantityG > 0 {
		return stock.WeightQuantityG
	}
	if product != nil && productSellByWeight(product) && !productSellByQty(product) {
		return stock.Quantity
	}
	return stock.WeightQuantityG
}
