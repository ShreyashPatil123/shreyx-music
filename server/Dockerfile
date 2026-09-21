# Multi-stage Docker build for minimal ShreyX Vibe server
FROM golang:1.22-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o vibe-server .

# Final minimal image (~15MB)
FROM alpine:3.19
RUN apk --no-cache add ca-certificates tzdata

WORKDIR /app
COPY --from=builder /app/vibe-server /app/vibe-server

EXPOSE 8080
ENV PORT=8080

CMD ["/app/vibe-server"]
