package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/TomerG2/models-as-a-service-lls-poc/internal/llamastack"
	"github.com/TomerG2/models-as-a-service-lls-poc/internal/logger"
)

type HealthHandler struct {
	llamaClient *llamastack.Client
	logger      *logger.Logger
}

type HealthResponse struct {
	Status        string            `json:"status"`
	Timestamp     time.Time         `json:"timestamp"`
	Services      map[string]string `json:"services"`
	Version       string            `json:"version,omitempty"`
	Uptime        string            `json:"uptime,omitempty"`
}

var startTime = time.Now()

func NewHealthHandler(llamaClient *llamastack.Client, logger *logger.Logger) *HealthHandler {
	return &HealthHandler{
		llamaClient: llamaClient,
		logger:      logger,
	}
}

// HandleHealth handles GET /health endpoint
func (h *HealthHandler) HandleHealth(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	response := HealthResponse{
		Timestamp: time.Now(),
		Services:  make(map[string]string),
		Uptime:    time.Since(startTime).String(),
		Version:   "1.0.0",
	}

	// Check LlamaStack connectivity
	if err := h.llamaClient.Health(ctx); err != nil {
		h.logger.Warnf("LlamaStack health check failed: %v", err)
		response.Status = "unhealthy"
		response.Services["llamastack"] = "down"
		c.JSON(http.StatusServiceUnavailable, response)
		return
	}

	response.Status = "healthy"
	response.Services["llamastack"] = "up"

	c.JSON(http.StatusOK, response)
}

// HandleReadiness handles GET /ready endpoint (for Kubernetes readiness probes)
func (h *HealthHandler) HandleReadiness(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// Quick health check for readiness
	if err := h.llamaClient.Health(ctx); err != nil {
		h.logger.Debugf("Readiness check failed: %v", err)
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"ready": false,
			"reason": "llamastack_unavailable",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"ready": true,
	})
}

// HandleLiveness handles GET /live endpoint (for Kubernetes liveness probes)
func (h *HealthHandler) HandleLiveness(c *gin.Context) {
	// Basic liveness check - service is alive if it can respond
	c.JSON(http.StatusOK, gin.H{
		"alive": true,
		"timestamp": time.Now(),
	})
}