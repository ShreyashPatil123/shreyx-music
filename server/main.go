package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024 * 32,
	WriteBufferSize: 1024 * 32,
	CheckOrigin: func(r *http.Request) bool {
		// ShreyX Music is an autonomous mobile app; allow all origins for native and web preview
		return true
	},
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	hub := NewHub()

	// WebSocket Endpoint
	http.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Printf("[VibeServer] Upgrade error: %v", err)
			return
		}

		memberID := GenerateID("mem")
		sessionToken := GenerateID("sess")

		client := NewClient(hub, conn, memberID, sessionToken)
		hub.Register(client)

		go client.WritePump()
		go client.ReadPump()
	})

	// Monitoring / Health Endpoint (Render monitoring)
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"status":    "ok",
			"service":   "shreyx-vibe-server",
			"stats":     hub.GetStats(),
			"timestamp": time.Now().Unix(),
		})
	})

	server := &http.Server{
		Addr:         ":" + port,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
	}

	go func() {
		log.Printf("--------------------------------------------------")
		log.Printf("  ShreyX Vibe Server listening on port :%s", port)
		log.Printf("  WebSocket: ws://localhost:%s/ws", port)
		log.Printf("  Monitoring: http://localhost:%s/health", port)
		log.Printf("--------------------------------------------------")
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[VibeServer] Fatal error: %v", err)
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("[VibeServer] Shutting down server gracefully...")
}
