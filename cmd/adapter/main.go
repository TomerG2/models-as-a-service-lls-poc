package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/TomerG2/models-as-a-service-lls-poc/internal/config"
	"github.com/TomerG2/models-as-a-service-lls-poc/internal/handlers"
	"github.com/TomerG2/models-as-a-service-lls-poc/internal/llamastack"
	"github.com/TomerG2/models-as-a-service-lls-poc/internal/logger"
)

func main() {
	// Load configuration
	cfg, err := config.LoadConfig()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to load configuration: %v\n", err)
		os.Exit(1)
	}

	// Initialize logger
	log, err := logger.NewLogger(cfg.LogLevel, cfg.LogJSON)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to initialize logger: %v\n", err)
		os.Exit(1)
	}
	defer log.Close()

	log.Infof("Starting LlamaStack adapter service")
	log.Infof("Configuration: endpoint=%s, auth=%v", cfg.LlamaStackEndpoint, cfg.EnableAuth)

	// Initialize LlamaStack client
	llamaClient := llamastack.NewClient(cfg.LlamaStackEndpoint, cfg.LlamaStackAPIKey, log)

	// Test LlamaStack connectivity on startup
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := llamaClient.Health(ctx); err != nil {
		log.Warnf("Warning: LlamaStack health check failed on startup: %v", err)
		log.Infof("Service will continue but may not function properly")
	} else {
		log.Infof("Successfully connected to LlamaStack")
	}

	// Initialize handlers
	modelsHandler := handlers.NewModelsHandler(llamaClient, log, cfg.EnableAuth)
	healthHandler := handlers.NewHealthHandler(llamaClient, log)

	// Setup Gin router
	if cfg.LogLevel != "debug" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()

	// Add middleware
	router.Use(gin.Recovery())
	router.Use(corsMiddleware())
	router.Use(loggingMiddleware(log))

	// Health endpoints
	router.GET("/health", healthHandler.HandleHealth)
	router.GET("/ready", healthHandler.HandleReadiness)
	router.GET("/live", healthHandler.HandleLiveness)

	// OpenAI-compatible API endpoints
	v1 := router.Group("/v1")
	{
		v1.GET("/models", modelsHandler.HandleListModels)
	}

	// Root endpoint
	router.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"service": "llamastack-adapter",
			"version": "1.0.0",
			"endpoints": []string{
				"GET /health - Service health check",
				"GET /ready - Kubernetes readiness probe",
				"GET /live - Kubernetes liveness probe",
				"GET /v1/models - List available models (OpenAI compatible)",
			},
		})
	})

	// Setup server
	server := &http.Server{
		Addr:         fmt.Sprintf("%s:%s", cfg.Address, cfg.Port),
		Handler:      router,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	// Start server in goroutine
	go func() {
		log.Infof("Starting server on %s", server.Addr)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Errorf("Failed to start server: %v", err)
			os.Exit(1)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Infof("Shutting down server...")

	// Graceful shutdown with timeout
	ctx, cancel = context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Errorf("Server forced to shutdown: %v", err)
		os.Exit(1)
	}

	log.Infof("Server exited")
}

// corsMiddleware adds basic CORS headers
func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Authorization")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusOK)
			return
		}

		c.Next()
	}
}

// loggingMiddleware logs HTTP requests
func loggingMiddleware(log *logger.Logger) gin.HandlerFunc {
	return gin.LoggerWithFormatter(func(param gin.LogFormatterParams) string {
		log.Infof("%s - [%s] \"%s %s %s %d %s \"%s\" %s\"",
			param.ClientIP,
			param.TimeStamp.Format(time.RFC3339),
			param.Method,
			param.Path,
			param.Request.Proto,
			param.StatusCode,
			param.Latency,
			param.Request.UserAgent(),
			param.ErrorMessage,
		)
		return ""
	})
}