package api

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

const (
	RoleManagement = "management"
	RolePosUser    = "pos_user"
	RoleSupervisor = "supervisor"
	RoleHQStaff    = "hq_staff"
)

func currentRole(c *gin.Context) string {
	role, _ := c.Get("role")
	r, _ := role.(string)
	return strings.TrimSpace(r)
}

func isValidUserRole(role string) bool {
	switch role {
	case RoleManagement, RolePosUser, RoleSupervisor, RoleHQStaff:
		return true
	default:
		return false
	}
}

func rejectUnlessRole(c *gin.Context, allowed ...string) bool {
	r := currentRole(c)
	for _, a := range allowed {
		if r == a {
			return false
		}
	}
	c.JSON(http.StatusForbidden, gin.H{"error": "Insufficient permissions for this action"})
	c.Abort()
	return true
}

func rejectIfHQStaffProductCostEdit(c *gin.Context) bool {
	if currentRole(c) == RoleHQStaff {
		c.JSON(http.StatusForbidden, gin.H{"error": "HQ staff cannot edit product costs"})
		c.Abort()
		return true
	}
	return false
}

func rejectIfHQStaffProductDelete(c *gin.Context) bool {
	if currentRole(c) == RoleHQStaff {
		c.JSON(http.StatusForbidden, gin.H{"error": "HQ staff cannot delete products"})
		c.Abort()
		return true
	}
	return false
}

func rejectIfPosUserWrite(c *gin.Context) bool {
	if currentRole(c) == RolePosUser {
		c.JSON(http.StatusForbidden, gin.H{"error": "POS users have read-only access here"})
		c.Abort()
		return true
	}
	return false
}
