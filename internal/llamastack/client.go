package llamastack

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/openai/openai-go/v2"
	"github.com/TomerG2/models-as-a-service-lls-poc/internal/logger"
)

// Client handles communication with LlamaStack
type Client struct {
	endpoint   string
	apiKey     string
	httpClient *http.Client
	logger     *logger.Logger
}

// LlamaStackModel represents a model from LlamaStack
type LlamaStackModel struct {
	ID          string `json:"id"`
	Name        string `json:"name,omitempty"`
	Description string `json:"description,omitempty"`
	Provider    string `json:"provider,omitempty"`
	Type        string `json:"type,omitempty"`
}

// LlamaStackResponse represents the response from LlamaStack models endpoint
type LlamaStackResponse struct {
	Models []LlamaStackModel `json:"models"`
}

const (
	defaultTimeout = 30 * time.Second
	maxRetries     = 3
)

func NewClient(endpoint, apiKey string, logger *logger.Logger) *Client {
	return &Client{
		endpoint: endpoint,
		apiKey:   apiKey,
		httpClient: &http.Client{
			Timeout: defaultTimeout,
		},
		logger: logger,
	}
}

// ListModels retrieves available models from LlamaStack and converts them to OpenAI format
func (c *Client) ListModels(ctx context.Context) ([]openai.Model, error) {
	c.logger.Debugf("Fetching models from LlamaStack endpoint: %s", c.endpoint)

	// Build request URL - assuming LlamaStack has a models endpoint
	url := c.endpoint + "/v1/models"
	if c.endpoint[len(c.endpoint)-1:] == "/" {
		url = c.endpoint + "v1/models"
	}

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// Add authentication if API key is provided
	if c.apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.apiKey)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to make request to LlamaStack: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("LlamaStack returned status %d: %s", resp.StatusCode, string(body))
	}

	var llamaResponse LlamaStackResponse
	if err := json.NewDecoder(resp.Body).Decode(&llamaResponse); err != nil {
		return nil, fmt.Errorf("failed to decode LlamaStack response: %w", err)
	}

	// Convert LlamaStack models to OpenAI format
	openaiModels := make([]openai.Model, 0, len(llamaResponse.Models))
	for _, model := range llamaResponse.Models {
		openaiModel := openai.Model{
			ID:      model.ID,
			Object:  "model",
			Created: time.Now().Unix(),
			OwnedBy: "llamastack",
		}
		openaiModels = append(openaiModels, openaiModel)
	}

	c.logger.Debugf("Successfully converted %d LlamaStack models to OpenAI format", len(openaiModels))
	return openaiModels, nil
}

// Health checks if LlamaStack is accessible
func (c *Client) Health(ctx context.Context) error {
	url := c.endpoint + "/health"
	if c.endpoint[len(c.endpoint)-1:] == "/" {
		url = c.endpoint + "health"
	}

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return fmt.Errorf("failed to create health check request: %w", err)
	}

	if c.apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.apiKey)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("health check failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}

	return fmt.Errorf("health check returned status %d", resp.StatusCode)
}