package main

import (
	"encoding/json"
	"log"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = (pongWait * 9) / 10
	maxMessageSize = 512 * 1024 // 512 KB
)

type Client struct {
	hub          *Hub
	conn         *websocket.Conn
	send         chan []byte
	memberID     string
	sessionToken string
	name         string
	roomCode     string
	isHost       bool
	isApproved   bool
	colorIndex   int
	joinedAtSec  int64

	mu     sync.Mutex
	closed bool
}

func NewClient(hub *Hub, conn *websocket.Conn, memberID, sessionToken string) *Client {
	return &Client{
		hub:          hub,
		conn:         conn,
		send:         make(chan []byte, 256),
		memberID:     memberID,
		sessionToken: sessionToken,
		colorIndex:   int(time.Now().UnixNano() % 6),
		joinedAtSec:  time.Now().Unix(),
	}
}

func (c *Client) SendJSON(msgType MessageType, payload any) {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return
	}
	c.mu.Unlock()

	out := OutboundMessage{
		Type:    msgType,
		Payload: payload,
	}
	data, err := json.Marshal(out)
	if err != nil {
		log.Printf("[VibeClient] Marshal error: %v", err)
		return
	}

	select {
	case c.send <- data:
	default:
		log.Printf("[VibeClient] Send buffer full for member: %s, dropping", c.memberID)
	}
}

func (c *Client) Close() {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.closed {
		c.closed = true
		close(c.send)
		_ = c.conn.Close()
	}
}

// CloseGracefully allows buffered messages in c.send to flush to client before closing socket
func (c *Client) CloseGracefully(delay time.Duration) {
	go func() {
		time.Sleep(delay)
		c.Close()
	}()
}

func (c *Client) ReadPump() {
	defer func() {
		c.hub.Unregister(c)
		c.Close()
	}()

	c.conn.SetReadLimit(maxMessageSize)
	_ = c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		_ = c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("[VibeClient] Read error: %v", err)
			}
			break
		}

		var in InboundMessage
		if err := json.Unmarshal(message, &in); err != nil {
			log.Printf("[VibeClient] JSON parse error: %v", err)
			c.SendJSON(TypeError, ErrorPayload{Code: "MALFORMED_JSON", Message: "Invalid JSON format"})
			continue
		}

		c.hub.HandleMessage(c, in)
	}
}

func (c *Client) WritePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		_ = c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				_ = c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := c.conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			_, _ = w.Write(message)

			// Drain queued messages
			n := len(c.send)
			for i := 0; i < n; i++ {
				_, _ = w.Write([]byte{'\n'})
				_, _ = w.Write(<-c.send)
			}

			if err := w.Close(); err != nil {
				return
			}

		case <-ticker.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
