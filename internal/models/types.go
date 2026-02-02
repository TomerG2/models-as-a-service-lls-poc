package models

import (
	"github.com/openai/openai-go/v2"
)

// ModelsResponse represents the OpenAI-compatible response for /v1/models endpoint
type ModelsResponse struct {
	Object string        `json:"object"`
	Data   []openai.Model `json:"data"`
}

// ErrorResponse represents an error response
type ErrorResponse struct {
	Error Error `json:"error"`
}

type Error struct {
	Message string `json:"message"`
	Type    string `json:"type"`
	Code    string `json:"code,omitempty"`
}

// NewModelsResponse creates a new OpenAI-compatible models response
func NewModelsResponse(models []openai.Model) *ModelsResponse {
	return &ModelsResponse{
		Object: "list",
		Data:   models,
	}
}

// NewErrorResponse creates a new error response
func NewErrorResponse(message, errorType string) *ErrorResponse {
	return &ErrorResponse{
		Error: Error{
			Message: message,
			Type:    errorType,
		},
	}
}