# Build stage
FROM golang:1.25-alpine AS builder

# Install ca-certificates for TLS
RUN apk --no-cache add ca-certificates

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o adapter ./cmd/adapter

# Final stage
FROM alpine:latest

# Install ca-certificates for TLS
RUN apk --no-cache add ca-certificates tzdata

WORKDIR /root/

# Copy the binary from builder stage
COPY --from=builder /app/adapter .

# Create non-root user
RUN addgroup -g 1001 -S adapter && \
    adduser -u 1001 -S adapter -G adapter

# Change to non-root user
USER adapter

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/live || exit 1

# Run the binary
CMD ["./adapter"]