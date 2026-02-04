# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the application with build date
# Build date is set at build time (will use current time during Docker build)
RUN BUILD_DATE_VAL=$(date -u +%Y-%m-%dT%H:%M:%SZ) && \
    echo "Building with build date: $BUILD_DATE_VAL" && \
    CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo \
    -ldflags "-X 'pos-system/backend/internal/api.BuildDate=$BUILD_DATE_VAL'" \
    -o main ./main.go && \
    echo "Build completed. BuildDate should be: $BUILD_DATE_VAL"

# Final stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates tzdata

WORKDIR /root/

# Copy the binary from builder
COPY --from=builder /app/main .
COPY --from=builder /app/fonts ./fonts

# Create uploads directory (for local storage fallback)
RUN mkdir -p uploads

# Expose port (Cloud Run uses PORT environment variable)
EXPOSE 8080

# Run the binary
CMD ["./main"]

