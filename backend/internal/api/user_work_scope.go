package api

import (
	"strings"

	"pos-system/backend/internal/models"

	"gorm.io/gorm"
)

func posUserStoreIDs(db *gorm.DB, userID uint) []uint {
	var ids []uint
	_ = db.Table("user_stores").Where("user_id = ?", userID).Pluck("store_id", &ids).Error
	return ids
}

func posUserWholesaleClientIDs(db *gorm.DB, userID uint) []uint {
	var ids []uint
	_ = db.Table("user_wholesale_clients").Where("user_id = ?", userID).Pluck("wholesale_client_id", &ids).Error
	return ids
}

// applyPosUserWholesaleOrderScope: POS users always see orders they created. Other orders require
// wholesale-client access; store assignments further narrow those orders when set.
func applyPosUserWholesaleOrderScope(db *gorm.DB, query *gorm.DB, userID uint) *gorm.DB {
	storeIDs := posUserStoreIDs(db, userID)
	clientIDs := posUserWholesaleClientIDs(db, userID)

	orParts := []string{"user_id = ?"}
	orArgs := []interface{}{userID}

	if len(clientIDs) > 0 {
		if len(storeIDs) > 0 {
			orParts = append(orParts,
				"(wholesale_client_id IN ? AND (store_id IN ? OR id IN (SELECT DISTINCT wholesale_order_id FROM wholesale_order_items WHERE assigned_store_id IN ?) OR id IN (SELECT DISTINCT wholesale_order_id FROM shipments WHERE store_id IN ?)))",
			)
			orArgs = append(orArgs, clientIDs, storeIDs, storeIDs, storeIDs)
		} else {
			orParts = append(orParts, "wholesale_client_id IN ?")
			orArgs = append(orArgs, clientIDs)
		}
	}

	return query.Where("("+strings.Join(orParts, " OR ")+")", orArgs...)
}

func posUserCanViewWholesaleOrder(db *gorm.DB, userID uint, wo *models.WholesaleOrder) bool {
	if wo.UserID == userID {
		return true
	}

	clientIDs := posUserWholesaleClientIDs(db, userID)
	if len(clientIDs) == 0 || !uintSliceContains(clientIDs, wo.WholesaleClientID) {
		return false
	}

	storeIDs := posUserStoreIDs(db, userID)
	if len(storeIDs) == 0 {
		return true
	}
	if uintSliceContains(storeIDs, wo.StoreID) {
		return true
	}
	var itemCount int64
	db.Model(&models.WholesaleOrderItem{}).
		Where("wholesale_order_id = ? AND assigned_store_id IN ?", wo.ID, storeIDs).
		Count(&itemCount)
	if itemCount > 0 {
		return true
	}
	var shipCount int64
	db.Model(&models.Shipment{}).
		Where("wholesale_order_id = ? AND store_id IN ?", wo.ID, storeIDs).
		Count(&shipCount)
	return shipCount > 0
}
