package api

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"pos-system/backend/internal/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type StocktakeHandler struct {
	db *gorm.DB
}

func NewStocktakeHandler(db *gorm.DB) *StocktakeHandler {
	return &StocktakeHandler{db: db}
}

func todayDate() string {
	return time.Now().Format("2006-01-02")
}

// RecordRequest is the body for POST /stocktake-day-start
type RecordRequest struct {
	Action     string `json:"action" binding:"required"` // first_login, done, skipped, logout
	SkipReason string `json:"skip_reason"`
	StoreID    *uint  `json:"store_id,omitempty"` // store where user is working (required for first_login/done/skipped when multi-store)
}

// stocktakeRecordQuery returns a query scoped to (userID, date, storeID) for StocktakeDayStartRecord.
func (h *StocktakeHandler) stocktakeRecordQuery(userID uint, date string, storeID *uint) *gorm.DB {
	q := h.db.Model(&models.StocktakeDayStartRecord{}).Where("user_id = ? AND date = ?", userID, date)
	if storeID == nil {
		q = q.Where("store_id IS NULL")
	} else {
		q = q.Where("store_id = ?", *storeID)
	}
	return q
}

// recordActivityEvent inserts a row into user_activity_events (best-effort, does not fail the request).
func (h *StocktakeHandler) recordActivityEvent(userID uint, storeID *uint, eventType string, at time.Time, skipReason string) {
	ev := models.UserActivityEvent{
		UserID:     userID,
		StoreID:    storeID,
		EventType:  eventType,
		OccurredAt: at,
		SkipReason: skipReason,
	}
	_ = h.db.Create(&ev).Error
}

// hasFirstLoginToday returns true if this user already has a first_login event today (any store).
func (h *StocktakeHandler) hasFirstLoginToday(userID uint, date string) bool {
	var count int64
	h.db.Model(&models.UserActivityEvent{}).
		Where("user_id = ? AND event_type = ? AND DATE(occurred_at) = ?", userID, models.EventFirstLogin, date).
		Count(&count)
	return count > 0
}

// RecordFirstLoginOrResult records first login of the day, or the result (done/skipped) for day-start stocktake, or logout.
func (h *StocktakeHandler) RecordFirstLoginOrResult(c *gin.Context) {
	userIDInterface, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	userID := userIDInterface.(uint)

	var req RecordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	date := todayDate()
	now := time.Now()
	storeID := req.StoreID

	switch req.Action {
	case "logout":
		h.recordActivityEvent(userID, storeID, models.EventLogout, now, "")
		c.JSON(http.StatusOK, gin.H{"ok": true})
		return
	case "first_login":
		var rec models.StocktakeDayStartRecord
		q := h.stocktakeRecordQuery(userID, date, storeID)
		err := q.First(&rec).Error
		if err == gorm.ErrRecordNotFound {
			rec = models.StocktakeDayStartRecord{
				UserID:       userID,
				StoreID:      storeID,
				Date:         date,
				FirstLoginAt: now,
				Status:       "pending",
			}
			if err = h.db.Create(&rec).Error; err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
		} else if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		// Only one first_login event per user per day (across all stores).
		if !h.hasFirstLoginToday(userID, date) {
			h.recordActivityEvent(userID, storeID, models.EventFirstLogin, now, "")
		}
		c.JSON(http.StatusOK, gin.H{"ok": true, "id": rec.ID})
		return
	case "done":
		res := h.stocktakeRecordQuery(userID, date, storeID).Updates(map[string]interface{}{
			"status":     "done",
			"done_at":    now,
			"updated_at": now,
		})
		if res.Error != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": res.Error.Error()})
			return
		}
		if res.RowsAffected == 0 {
			rec := models.StocktakeDayStartRecord{
				UserID:       userID,
				StoreID:      storeID,
				Date:         date,
				FirstLoginAt: now,
				Status:       "done",
				DoneAt:       &now,
			}
			if err := h.db.Create(&rec).Error; err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
		}
		h.recordActivityEvent(userID, storeID, models.EventStocktakeDayStartDone, now, "")
		c.JSON(http.StatusOK, gin.H{"ok": true})
		return
	case "skipped":
		res := h.stocktakeRecordQuery(userID, date, storeID).Updates(map[string]interface{}{
			"status":      "skipped",
			"skip_reason": req.SkipReason,
			"updated_at":  now,
		})
		if res.Error != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": res.Error.Error()})
			return
		}
		if res.RowsAffected == 0 {
			rec := models.StocktakeDayStartRecord{
				UserID:      userID,
				StoreID:     storeID,
				Date:        date,
				FirstLoginAt: now,
				Status:      "skipped",
				SkipReason:  req.SkipReason,
			}
			if err := h.db.Create(&rec).Error; err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
		}
		h.recordActivityEvent(userID, storeID, models.EventStocktakeDayStartSkipped, now, req.SkipReason)
		c.JSON(http.StatusOK, gin.H{"ok": true})
		return
	case "day_end_skipped":
		h.recordActivityEvent(userID, storeID, models.EventStocktakeDayEndSkipped, now, req.SkipReason)
		c.JSON(http.StatusOK, gin.H{"ok": true})
		return
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "action must be first_login, done, skipped, day_end_skipped, or logout"})
		return
	}
}

// ListDayStartRecords returns records for the management timetable (optional date range, user_id, store_ids).
// store_ids filters by the record's store_id (store where user did first login/stocktake).
func (h *StocktakeHandler) ListDayStartRecords(c *gin.Context) {
	from := c.Query("from")
	to := c.Query("to")
	userIDQ := c.Query("user_id")
	storeIDsQ := c.Query("store_ids") // comma-separated, e.g. "1,2,3"

	query := h.db.Model(&models.StocktakeDayStartRecord{}).Preload("User").Preload("User.Stores").Preload("Store")
	if from != "" {
		query = query.Where("date >= ?", from)
	}
	if to != "" {
		query = query.Where("date <= ?", to)
	}
	if userIDQ != "" {
		query = query.Where("user_id = ?", userIDQ)
	}
	if storeIDs := parseStoreIDs(storeIDsQ); len(storeIDs) > 0 {
		query = query.Where("store_id IN ?", storeIDs)
	}
	query = query.Order("date DESC, first_login_at DESC")

	var list []models.StocktakeDayStartRecord
	if err := query.Find(&list).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, list)
}

// ListUserActivityEvents returns events from user_activity_events for the timetable (login, logout, stocktake).
func (h *StocktakeHandler) ListUserActivityEvents(c *gin.Context) {
	from := c.Query("from")
	to := c.Query("to")
	userIDQ := c.Query("user_id")
	storeIDsQ := c.Query("store_ids")
	eventTypeQ := c.Query("event_type") // optional comma-separated filter

	query := h.db.Model(&models.UserActivityEvent{}).Preload("User").Preload("Store")
	if from != "" {
		query = query.Where("occurred_at >= ?", from+" 00:00:00")
	}
	if to != "" {
		query = query.Where("occurred_at <= ?", to+" 23:59:59")
	}
	if userIDQ != "" {
		query = query.Where("user_id = ?", userIDQ)
	}
	if storeIDs := parseStoreIDs(storeIDsQ); len(storeIDs) > 0 {
		query = query.Where("store_id IN ?", storeIDs)
	}
	if eventTypeQ != "" {
		types := strings.Split(eventTypeQ, ",")
		for i := range types {
			types[i] = strings.TrimSpace(types[i])
		}
		if len(types) > 0 {
			query = query.Where("event_type IN ?", types)
		}
	}
	query = query.Order("occurred_at ASC")

	var list []models.UserActivityEvent
	if err := query.Find(&list).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, list)
}

// parseStoreIDs parses "1,2,3" into []uint for use in IN clause. Invalid parts are skipped.
func parseStoreIDs(s string) []uint {
	var ids []uint
	for _, part := range strings.Split(s, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		n, err := strconv.ParseUint(part, 10, 64)
		if err != nil {
			continue
		}
		ids = append(ids, uint(n))
	}
	return ids
}
