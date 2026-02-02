package config

import (
	"fmt"
	"os"
)

type Config struct {
	// Server configuration
	Address string
	Port    string

	// LlamaStack configuration
	LlamaStackEndpoint string
	LlamaStackAPIKey   string

	// Authentication
	EnableAuth bool

	// Logging
	LogLevel string
	LogJSON  bool
}

func LoadConfig() (*Config, error) {
	cfg := &Config{
		Address:            getEnvOrDefault("ADAPTER_ADDRESS", "0.0.0.0"),
		Port:               getEnvOrDefault("ADAPTER_PORT", "8080"),
		LlamaStackEndpoint: getEnvOrDefault("LLAMASTACK_ENDPOINT", ""),
		LlamaStackAPIKey:   getEnvOrDefault("LLAMASTACK_API_KEY", ""),
		EnableAuth:         getEnvOrDefault("ENABLE_AUTH", "true") == "true",
		LogLevel:           getEnvOrDefault("LOG_LEVEL", "info"),
		LogJSON:            getEnvOrDefault("LOG_JSON", "false") == "true",
	}

	// Validate required configuration
	if cfg.LlamaStackEndpoint == "" {
		return nil, fmt.Errorf("LLAMASTACK_ENDPOINT is required")
	}

	return cfg, nil
}

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}