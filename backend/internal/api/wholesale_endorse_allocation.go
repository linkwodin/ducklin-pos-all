package api

import (
	"math"
	"net/http"
	"sort"

	"github.com/gin-gonic/gin"
	"pos-system/backend/internal/models"
)

const (
	endorseOutcomeSingleStore        = "single_store"
	endorseOutcomeSplitRequired      = "split_required"
	endorseOutcomeInsufficientStock  = "insufficient_stock"
)

type endorseItemInput struct {
	ItemID    uint
	ProductID uint
	Pending   float64
}

type endorseAllocationInput struct {
	Items              []endorseItemInput
	DefaultStoreByProd map[uint]uint
	StockByStoreProd   map[uint]map[uint]float64
	StoreNames         map[uint]string
}

type EndorseAllocationAssignmentPreview struct {
	WholesaleOrderItemID uint    `json:"wholesale_order_item_id"`
	StoreID              uint    `json:"store_id"`
	StoreName            string  `json:"store_name"`
	Quantity             float64 `json:"quantity"`
	StockAvailable       float64 `json:"stock_available"`
	StockAfter           float64 `json:"stock_after"`
}

type EndorseAllocationLinePreview struct {
	WholesaleOrderItemID uint    `json:"wholesale_order_item_id"`
	ProductID            uint    `json:"product_id"`
	Needed               float64 `json:"needed"`
	Allocated            float64 `json:"allocated"`
	Shortfall            float64 `json:"shortfall"`
	DefaultStoreID       *uint   `json:"default_store_id,omitempty"`
	DefaultStoreName     string  `json:"default_store_name,omitempty"`
}

type EndorseAllocationPreview struct {
	Outcome        string                               `json:"outcome"`
	PrimaryStoreID *uint                                `json:"primary_store_id,omitempty"`
	PrimaryStoreName string                             `json:"primary_store_name,omitempty"`
	StoreIDs       []uint                               `json:"store_ids"`
	Lines          []EndorseAllocationLinePreview       `json:"lines"`
	Assignments    []EndorseAllocationAssignmentPreview `json:"assignments"`
}

func stockAvailable(stockByStoreProd map[uint]map[uint]float64, storeID, productID uint) float64 {
	if stockByStoreProd[storeID] == nil {
		return 0
	}
	return stockByStoreProd[storeID][productID]
}

func cloneStockByStoreProd(src map[uint]map[uint]float64) map[uint]map[uint]float64 {
	out := make(map[uint]map[uint]float64, len(src))
	for storeID, byProd := range src {
		cp := make(map[uint]float64, len(byProd))
		for productID, qty := range byProd {
			cp[productID] = qty
		}
		out[storeID] = cp
	}
	return out
}

func computeEndorseAllocationPreview(in endorseAllocationInput) EndorseAllocationPreview {
	remaining := make(map[uint]float64, len(in.Items))
	neededByItem := make(map[uint]float64, len(in.Items))
	productByItem := make(map[uint]uint, len(in.Items))
	defaultStoreByItem := make(map[uint]*uint, len(in.Items))
	for _, item := range in.Items {
		if item.Pending <= 0.0001 {
			continue
		}
		remaining[item.ItemID] = item.Pending
		neededByItem[item.ItemID] = item.Pending
		productByItem[item.ItemID] = item.ProductID
		if storeID, ok := in.DefaultStoreByProd[item.ProductID]; ok && storeID > 0 {
			sid := storeID
			defaultStoreByItem[item.ItemID] = &sid
		}
	}

	available := cloneStockByStoreProd(in.StockByStoreProd)
	assignments := make([]EndorseAllocationAssignmentPreview, 0)

	// Phase 1: allocate from each product's default wholesale ship store first.
	itemIDs := make([]uint, 0, len(remaining))
	for itemID := range remaining {
		itemIDs = append(itemIDs, itemID)
	}
	sort.Slice(itemIDs, func(i, j int) bool { return itemIDs[i] < itemIDs[j] })
	for _, itemID := range itemIDs {
		pending := remaining[itemID]
		if pending <= 0.0001 {
			continue
		}
		defaultStoreID, ok := defaultStoreByItem[itemID]
		if !ok || defaultStoreID == nil {
			continue
		}
		storeID := *defaultStoreID
		productID := productByItem[itemID]
		avail := stockAvailable(available, storeID, productID)
		alloc := math.Min(pending, avail)
		if alloc <= 0.0001 {
			continue
		}
		remaining[itemID] -= alloc
		available[storeID][productID] -= alloc
		assignments = append(assignments, EndorseAllocationAssignmentPreview{
			WholesaleOrderItemID: itemID,
			StoreID:              storeID,
			StoreName:            in.StoreNames[storeID],
			Quantity:             alloc,
			StockAvailable:       avail,
			StockAfter:           available[storeID][productID],
		})
	}

	// Phase 2: assign all remaining lines to one store that can fulfill every remaining item.
	remainingItemIDs := make([]uint, 0)
	for itemID, qty := range remaining {
		if qty > 0.0001 {
			remainingItemIDs = append(remainingItemIDs, itemID)
		}
	}
	sort.Slice(remainingItemIDs, func(i, j int) bool { return remainingItemIDs[i] < remainingItemIDs[j] })

	if len(remainingItemIDs) > 0 {
		storeIDs := make([]uint, 0, len(available))
		for storeID := range available {
			storeIDs = append(storeIDs, storeID)
		}
		sort.Slice(storeIDs, func(i, j int) bool { return storeIDs[i] < storeIDs[j] })

		usedInPhase1 := make(map[uint]int)
		for _, a := range assignments {
			usedInPhase1[a.StoreID]++
		}

		var bestStore uint
		found := false
		bestScore := -1
		for _, storeID := range storeIDs {
			canFulfillAll := true
			for _, itemID := range remainingItemIDs {
				productID := productByItem[itemID]
				if stockAvailable(available, storeID, productID) < remaining[itemID]-0.0001 {
					canFulfillAll = false
					break
				}
			}
			if !canFulfillAll {
				continue
			}
			score := usedInPhase1[storeID]
			if !found || score > bestScore || (score == bestScore && storeID < bestStore) {
				found = true
				bestScore = score
				bestStore = storeID
			}
		}

		if found {
			for _, itemID := range remainingItemIDs {
				productID := productByItem[itemID]
				qty := remaining[itemID]
				avail := stockAvailable(available, bestStore, productID)
				remaining[itemID] = 0
				available[bestStore][productID] -= qty
				assignments = append(assignments, EndorseAllocationAssignmentPreview{
					WholesaleOrderItemID: itemID,
					StoreID:              bestStore,
					StoreName:            in.StoreNames[bestStore],
					Quantity:             qty,
					StockAvailable:       avail,
					StockAfter:           available[bestStore][productID],
				})
			}
		} else {
			// Phase 3: greedy split — allocate each remaining line from the store with the most stock.
			for _, itemID := range remainingItemIDs {
				pending := remaining[itemID]
				if pending <= 0.0001 {
					continue
				}
				productID := productByItem[itemID]
				var pickStore uint
				pickAvail := 0.0
				for storeID, byProd := range available {
					avail := byProd[productID]
					if avail > pickAvail+0.0001 || (avail > 0.0001 && avail == pickAvail && storeID < pickStore) {
						pickAvail = avail
						pickStore = storeID
					}
				}
				if pickAvail <= 0.0001 {
					continue
				}
				alloc := math.Min(pending, pickAvail)
				remaining[itemID] -= alloc
				available[pickStore][productID] -= alloc
				assignments = append(assignments, EndorseAllocationAssignmentPreview{
					WholesaleOrderItemID: itemID,
					StoreID:              pickStore,
					StoreName:            in.StoreNames[pickStore],
					Quantity:             alloc,
					StockAvailable:       pickAvail,
					StockAfter:           available[pickStore][productID],
				})
			}
		}
	}

	allocatedByItem := make(map[uint]float64)
	for _, a := range assignments {
		allocatedByItem[a.WholesaleOrderItemID] += a.Quantity
	}

	lines := make([]EndorseAllocationLinePreview, 0, len(neededByItem))
	itemIDsForLines := make([]uint, 0, len(neededByItem))
	for itemID := range neededByItem {
		itemIDsForLines = append(itemIDsForLines, itemID)
	}
	sort.Slice(itemIDsForLines, func(i, j int) bool { return itemIDsForLines[i] < itemIDsForLines[j] })
	for _, itemID := range itemIDsForLines {
		needed := neededByItem[itemID]
		allocated := allocatedByItem[itemID]
		shortfall := math.Max(0, needed-allocated)
		line := EndorseAllocationLinePreview{
			WholesaleOrderItemID: itemID,
			ProductID:            productByItem[itemID],
			Needed:               needed,
			Allocated:            allocated,
			Shortfall:            shortfall,
		}
		if ds := defaultStoreByItem[itemID]; ds != nil {
			line.DefaultStoreID = ds
			line.DefaultStoreName = in.StoreNames[*ds]
		}
		lines = append(lines, line)
	}

	storeSet := make(map[uint]struct{})
	for _, a := range assignments {
		storeSet[a.StoreID] = struct{}{}
	}
	storeIDsOut := make([]uint, 0, len(storeSet))
	for storeID := range storeSet {
		storeIDsOut = append(storeIDsOut, storeID)
	}
	sort.Slice(storeIDsOut, func(i, j int) bool { return storeIDsOut[i] < storeIDsOut[j] })

	totalShortfall := 0.0
	for _, line := range lines {
		totalShortfall += line.Shortfall
	}

	outcome := endorseOutcomeSplitRequired
	var primaryStoreID *uint
	primaryStoreName := ""
	if totalShortfall > 0.0001 {
		outcome = endorseOutcomeInsufficientStock
	} else if len(storeIDsOut) == 1 {
		outcome = endorseOutcomeSingleStore
		sid := storeIDsOut[0]
		primaryStoreID = &sid
		primaryStoreName = in.StoreNames[sid]
	}

	return EndorseAllocationPreview{
		Outcome:          outcome,
		PrimaryStoreID:   primaryStoreID,
		PrimaryStoreName: primaryStoreName,
		StoreIDs:         storeIDsOut,
		Lines:            lines,
		Assignments:      assignments,
	}
}

func (h *WholesaleOrderHandler) EndorseAllocationPreview(c *gin.Context) {
	if !requireManagementOrSupervisor(c) {
		return
	}

	var wo models.WholesaleOrder
	if err := h.db.Preload("Items").First(&wo, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Wholesale order not found"})
		return
	}
	if abortIfWholesaleOrderDeleted(c, wo.Status) {
		return
	}
	if wo.Status != models.WholesaleOrderStatusPending {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Order is not pending approval"})
		return
	}
	if len(wo.Items) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Order has no lines"})
		return
	}

	productIDs := make([]uint, 0, len(wo.Items))
	for _, item := range wo.Items {
		productIDs = append(productIDs, item.ProductID)
	}

	var stockRows []models.Stock
	if err := h.db.Where("product_id IN ?", productIDs).Preload("Store").Find(&stockRows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	defaultStoreByProd := make(map[uint]uint)
	stockByStoreProd := make(map[uint]map[uint]float64)
	storeNames := make(map[uint]string)
	for _, row := range stockRows {
		if stockByStoreProd[row.StoreID] == nil {
			stockByStoreProd[row.StoreID] = make(map[uint]float64)
		}
		stockByStoreProd[row.StoreID][row.ProductID] = row.Quantity
		if row.Store.Name != "" {
			storeNames[row.StoreID] = row.Store.Name
		} else if storeNames[row.StoreID] == "" {
			storeNames[row.StoreID] = ""
		}
		if row.WholesaleShipFrom {
			defaultStoreByProd[row.ProductID] = row.StoreID
		}
	}

	items := make([]endorseItemInput, 0, len(wo.Items))
	for _, item := range wo.Items {
		assigned, err := h.assignedQtyForOrderItem(item.ID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		pending := item.Quantity - assigned
		if pending <= 0.0001 {
			continue
		}
		items = append(items, endorseItemInput{
			ItemID:    item.ID,
			ProductID: item.ProductID,
			Pending:   pending,
		})
	}

	preview := computeEndorseAllocationPreview(endorseAllocationInput{
		Items:              items,
		DefaultStoreByProd: defaultStoreByProd,
		StockByStoreProd:   stockByStoreProd,
		StoreNames:         storeNames,
	})
	c.JSON(http.StatusOK, preview)
}
