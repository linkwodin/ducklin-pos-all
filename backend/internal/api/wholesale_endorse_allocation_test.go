package api

import "testing"

func TestComputeEndorseAllocationPreviewSingleDefaultStore(t *testing.T) {
	preview := computeEndorseAllocationPreview(endorseAllocationInput{
		Items: []endorseItemInput{
			{ItemID: 1, ProductID: 10, Pending: 5},
			{ItemID: 2, ProductID: 20, Pending: 3},
		},
		DefaultStoreByProd: map[uint]uint{10: 1, 20: 1},
		StockByStoreProd: map[uint]map[uint]float64{
			1: {10: 10, 20: 10},
		},
		StoreNames: map[uint]string{1: "Main"},
	})

	if preview.Outcome != endorseOutcomeSingleStore {
		t.Fatalf("outcome = %q, want %q", preview.Outcome, endorseOutcomeSingleStore)
	}
	if preview.PrimaryStoreID == nil || *preview.PrimaryStoreID != 1 {
		t.Fatalf("primary store = %v, want 1", preview.PrimaryStoreID)
	}
	if len(preview.Assignments) != 2 {
		t.Fatalf("assignments = %d, want 2", len(preview.Assignments))
	}
	for _, a := range preview.Assignments {
		wantAfter := a.StockAvailable - a.Quantity
		if a.StockAfter < wantAfter-0.0001 || a.StockAfter > wantAfter+0.0001 {
			t.Fatalf("assignment item %d: stock_after = %v, want %v", a.WholesaleOrderItemID, a.StockAfter, wantAfter)
		}
	}
}

func TestComputeEndorseAllocationPreviewSplitAfterDefaults(t *testing.T) {
	preview := computeEndorseAllocationPreview(endorseAllocationInput{
		Items: []endorseItemInput{
			{ItemID: 1, ProductID: 10, Pending: 5},
			{ItemID: 2, ProductID: 20, Pending: 4},
		},
		DefaultStoreByProd: map[uint]uint{10: 1, 20: 2},
		StockByStoreProd: map[uint]map[uint]float64{
			1: {10: 5, 20: 0},
			2: {10: 0, 20: 4},
			3: {10: 5, 20: 4},
		},
		StoreNames: map[uint]string{1: "A", 2: "B", 3: "C"},
	})

	if preview.Outcome != endorseOutcomeSplitRequired {
		t.Fatalf("outcome = %q, want %q", preview.Outcome, endorseOutcomeSplitRequired)
	}
	if len(preview.StoreIDs) < 2 {
		t.Fatalf("store ids = %v, want split across stores", preview.StoreIDs)
	}
}

func TestComputeEndorseAllocationPreviewOneStoreForRemainder(t *testing.T) {
	preview := computeEndorseAllocationPreview(endorseAllocationInput{
		Items: []endorseItemInput{
			{ItemID: 1, ProductID: 10, Pending: 5},
			{ItemID: 2, ProductID: 20, Pending: 4},
			{ItemID: 3, ProductID: 30, Pending: 2},
		},
		DefaultStoreByProd: map[uint]uint{10: 1},
		StockByStoreProd: map[uint]map[uint]float64{
			1: {10: 5, 20: 0, 30: 0},
			2: {10: 0, 20: 4, 30: 2},
		},
		StoreNames: map[uint]string{1: "Default", 2: "Other"},
	})

	if preview.Outcome != endorseOutcomeSplitRequired {
		t.Fatalf("outcome = %q, want %q", preview.Outcome, endorseOutcomeSplitRequired)
	}
	for _, line := range preview.Lines {
		if line.Shortfall > 0.0001 {
			t.Fatalf("unexpected shortfall on line %d: %v", line.WholesaleOrderItemID, line.Shortfall)
		}
	}
	foundStore2ForRemainder := false
	for _, a := range preview.Assignments {
		if a.StoreID == 2 && (a.WholesaleOrderItemID == 2 || a.WholesaleOrderItemID == 3) {
			foundStore2ForRemainder = true
		}
	}
	if !foundStore2ForRemainder {
		t.Fatalf("expected remainder assigned to store 2, got %+v", preview.Assignments)
	}
}

func TestComputeEndorseAllocationPreviewInsufficientStock(t *testing.T) {
	preview := computeEndorseAllocationPreview(endorseAllocationInput{
		Items: []endorseItemInput{
			{ItemID: 1, ProductID: 10, Pending: 10},
		},
		DefaultStoreByProd: map[uint]uint{10: 1},
		StockByStoreProd: map[uint]map[uint]float64{
			1: {10: 4},
			2: {10: 3},
		},
		StoreNames: map[uint]string{1: "A", 2: "B"},
	})

	if preview.Outcome != endorseOutcomeInsufficientStock {
		t.Fatalf("outcome = %q, want %q", preview.Outcome, endorseOutcomeInsufficientStock)
	}
	if preview.Lines[0].Shortfall < 2.999 || preview.Lines[0].Shortfall > 3.001 {
		t.Fatalf("shortfall = %v, want 3", preview.Lines[0].Shortfall)
	}
}
