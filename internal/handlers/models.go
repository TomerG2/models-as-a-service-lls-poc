package handlers

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/TomerG2/models-as-a-service-lls-poc/internal/llamastack"
	"github.com/TomerG2/models-as-a-service-lls-poc/internal/logger"
	"github.com/TomerG2/models-as-a-service-lls-poc/internal/models"
)

type ModelsHandler struct {
	llamaClient *llamastack.Client
	logger      *logger.Logger
	enableAuth  bool
}

func NewModelsHandler(llamaClient *llamastack.Client, logger *logger.Logger, enableAuth bool) *ModelsHandler {
	return &ModelsHandler{
		llamaClient: llamaClient,
		logger:      logger,
		enableAuth:  enableAuth,
	}
}

// HandleListModels handles GET /v1/models - OpenAI-compatible endpoint
func (h *ModelsHandler) HandleListModels(c *gin.Context) {
	startTime := time.Now()
	h.logger.Infof("Received models list request from %s", c.ClientIP())

	// Validate authentication if enabled
	if h.enableAuth {
		if err := h.validateAuth(c); err != nil {
			h.logger.Warnf("Authentication failed: %v", err)
			c.JSON(http.StatusUnauthorized, models.NewErrorResponse(
				"Authentication required",
				"authentication_error",
			))
			return
		}
	}

	// Create context with timeout for LlamaStack call
	ctx, cancel := context.WithTimeout(c.Request.Context(), 30*time.Second)
	defer cancel()

	// Fetch models from LlamaStack
	llamaModels, err := h.llamaClient.ListModels(ctx)
	if err != nil {
		h.logger.Errorf("Failed to fetch models from LlamaStack: %v", err)
		c.JSON(http.StatusInternalServerError, models.NewErrorResponse(
			"Failed to retrieve models from external service",
			"internal_error",
		))
		return
	}

	// Create OpenAI-compatible response
	response := models.NewModelsResponse(llamaModels)

	duration := time.Since(startTime)
	h.logger.Infof("Successfully returned %d models in %v", len(llamaModels), duration)

	c.JSON(http.StatusOK, response)
}

// validateAuth validates the Bearer token from the Authorization header
func (h *ModelsHandler) validateAuth(c *gin.Context) error {
	authHeader := c.GetHeader("Authorization")
	if authHeader == "" {
		return &AuthError{Message: "Missing Authorization header"}
	}

	if !strings.HasPrefix(authHeader, "Bearer ") {
		return &AuthError{Message: "Invalid Authorization header format"}
	}

	token := strings.TrimPrefix(authHeader, "Bearer ")
	if token == "" {
		return &AuthError{Message: "Empty token"}
	}

	// For now, we'll just validate that a token is present
	// In a production system, you would validate the token against
	// Kubernetes ServiceAccount tokens or your auth system
	h.logger.Debugf("Validated token: %s...", token[:min(len(token), 10)])

	return nil
}

type AuthError struct {
	Message string
}

func (e *AuthError) Error() string {
	return e.Message
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}