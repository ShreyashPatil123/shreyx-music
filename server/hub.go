package main

import (
	"encoding/json"
	"log"
	"strings"
	"sync"
	"time"
)

type SessionInfo struct {
	MemberID    string
	Name        string
	RoomCode    string
	IsHost      bool
	ColorIndex  int
	ExpiresAt   time.Time
}

type Hub struct {
	mu           sync.RWMutex
	rooms        map[string]*Room        // roomCode -> Room
	sessions     map[string]*SessionInfo // sessionToken -> SessionInfo
	clients      map[*Client]bool
	clientCounts map[string]int // rate limiting simple tracker
}

func NewHub() *Hub {
	h := &Hub{
		rooms:        make(map[string]*Room),
		sessions:     make(map[string]*SessionInfo),
		clients:      make(map[*Client]bool),
		clientCounts: make(map[string]int),
	}
	go h.startCleanupTicker()
	return h
}

func (h *Hub) Register(c *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.clients[c] = true
}

func (h *Hub) Unregister(c *Client) {
	h.mu.Lock()
	delete(h.clients, c)
	roomCode := c.roomCode
	memberID := c.memberID
	h.mu.Unlock()

	if roomCode == "" || memberID == "" {
		return
	}

	log.Printf("[VibeHub] Client %s socket closed for room %s; starting 60s disconnect grace period", memberID, roomCode)

	// Grace period: allow mobile devices to minimize, lock screen, or switch networks without losing room/host state
	go func(rCode string, mID string, originalClient *Client) {
		time.Sleep(60 * time.Second)

		h.mu.Lock()
		room, ok := h.rooms[rCode]
		if !ok {
			h.mu.Unlock()
			return
		}

		room.mu.RLock()
		currentClient, exists := room.Members[mID]
		room.mu.RUnlock()

		// If member has reconnected with a new active connection or is no longer the original disconnected client, keep them!
		if !exists || (currentClient != nil && currentClient != originalClient) {
			h.mu.Unlock()
			return
		}

		wasHost, newHost := room.RemoveMember(mID)
		h.mu.Unlock()

		log.Printf("[VibeHub] Member %s grace period expired in room %s (wasHost=%v)", mID, rCode, wasHost)

		var newHostID string
		if newHost != nil {
			newHostID = newHost.memberID
		}

		room.BroadcastApproved(TypeMemberLeft, map[string]string{
			"member_id":   mID,
			"new_host_id": newHostID,
		})

		if newHost != nil {
			newHost.SendJSON(TypeHostTransferred, map[string]string{
				"new_host_id": newHost.memberID,
			})
		}
	}(roomCode, memberID, c)
}

func (h *Hub) startCleanupTicker() {
	ticker := time.NewTicker(3 * time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		h.mu.Lock()
		now := time.Now()

		// 1. Cleanup expired sessions
		for token, sess := range h.sessions {
			if now.After(sess.ExpiresAt) {
				delete(h.sessions, token)
			}
		}

		// 2. Cleanup expired or abandoned rooms (> 15 mins inactive with 0 members)
		for code, room := range h.rooms {
			if room.IsExpired(15 * time.Minute) {
				log.Printf("[VibeHub] Pruning inactive empty room: %s", code)
				delete(h.rooms, code)
			}
		}
		h.mu.Unlock()
	}
}

func (h *Hub) HandleMessage(c *Client, in InboundMessage) {
	switch in.Type {
	case TypePing:
		var p PingPayload
		_ = json.Unmarshal(in.Payload, &p)
		c.SendJSON(TypePong, PongPayload{
			ClientTime: p.ClientTime,
			ServerTime: nowMillis(),
		})

	case TypeCreateRoom:
		var p CreateRoomPayload
		if err := json.Unmarshal(in.Payload, &p); err != nil {
			c.SendJSON(TypeError, ErrorPayload{Code: "BAD_PAYLOAD", Message: "Invalid create room payload"})
			return
		}
		h.handleCreateRoom(c, p)

	case TypeJoinRoom:
		var p JoinRoomPayload
		if err := json.Unmarshal(in.Payload, &p); err != nil {
			c.SendJSON(TypeError, ErrorPayload{Code: "BAD_PAYLOAD", Message: "Invalid join room payload"})
			return
		}
		h.handleJoinRoom(c, p)

	case TypeApproveJoin:
		var p ApproveJoinPayload
		if err := json.Unmarshal(in.Payload, &p); err != nil {
			return
		}
		h.handleApproveJoin(c, p)

	case TypeRejectJoin:
		var p RejectJoinPayload
		if err := json.Unmarshal(in.Payload, &p); err != nil {
			return
		}
		h.handleRejectJoin(c, p)

	case TypePlaybackAction:
		var p PlaybackActionPayload
		if err := json.Unmarshal(in.Payload, &p); err != nil {
			return
		}
		h.handlePlaybackAction(c, p)

	case TypeSuggestSong:
		var p SuggestSongPayload
		if err := json.Unmarshal(in.Payload, &p); err != nil {
			return
		}
		h.handleSuggestSong(c, p)

	case TypeApproveSuggestion:
		var p ApproveSuggestionPayload
		if err := json.Unmarshal(in.Payload, &p); err != nil {
			return
		}
		h.handleApproveSuggestion(c, p)

	case TypeRejectSuggestion:
		var p RejectSuggestionPayload
		if err := json.Unmarshal(in.Payload, &p); err != nil {
			return
		}
		h.handleRejectSuggestion(c, p)

	case TypeRequestSync:
		h.handleRequestSync(c)

	case TypeLeaveRoom:
		h.handleLeaveRoom(c)

	case TypeKickMember:
		var p KickMemberPayload
		if err := json.Unmarshal(in.Payload, &p); err != nil {
			return
		}
		h.handleKickMember(c, p)

	case TypeTransferHost:
		var p TransferHostPayload
		if err := json.Unmarshal(in.Payload, &p); err != nil {
			return
		}
		h.handleTransferHost(c, p)
	}
}

func (h *Hub) handleCreateRoom(c *Client, p CreateRoomPayload) {
	h.mu.Lock()
	defer h.mu.Unlock()

	// Generate unique 6-character room code
	var code string
	for {
		code = GenerateRoomCode()
		if _, exists := h.rooms[code]; !exists {
			break
		}
	}

	c.name = strings.TrimSpace(p.HostName)
	if c.name == "" {
		c.name = "Host"
	}
	roomName := strings.TrimSpace(p.RoomName)
	if roomName == "" {
		roomName = c.name + "'s Room"
	}

	room := NewRoom(code, roomName, c)
	h.rooms[code] = room

	// Save session
	h.sessions[c.sessionToken] = &SessionInfo{
		MemberID:   c.memberID,
		Name:       c.name,
		RoomCode:   code,
		IsHost:     true,
		ColorIndex: c.colorIndex,
		ExpiresAt:  time.Now().Add(24 * time.Hour),
	}

	log.Printf("[VibeHub] Room created: %s (%s) by %s", code, roomName, c.name)

	c.SendJSON(TypeRoomCreated, RoomCreatedPayload{
		RoomCode:     code,
		RoomName:     roomName,
		MemberID:     c.memberID,
		SessionToken: c.sessionToken,
		Snapshot:     room.GetSnapshot(),
	})
}

func (h *Hub) handleJoinRoom(c *Client, p JoinRoomPayload) {
	code := strings.ToUpper(strings.TrimSpace(p.RoomCode))

	h.mu.Lock()
	room, ok := h.rooms[code]
	if !ok {
		h.mu.Unlock()
		c.SendJSON(TypeError, ErrorPayload{Code: "ROOM_NOT_FOUND", Message: "Room not found. Check code and try again."})
		return
	}

	// Check if reconnecting via known session token
	if p.SessionToken != "" {
		if sess, exists := h.sessions[p.SessionToken]; exists && sess.RoomCode == code {
			// Restore session seamlessly
			c.memberID = sess.MemberID
			c.name = sess.Name
			c.isHost = sess.IsHost
			c.colorIndex = sess.ColorIndex
			c.roomCode = code
			c.isApproved = true

			room.mu.Lock()
			room.Members[c.memberID] = c
			if c.isHost {
				room.HostID = c.memberID
			}
			room.Touch()
			room.mu.Unlock()

			h.mu.Unlock()

			log.Printf("[VibeHub] Reconnected session for member %s in room %s", c.memberID, code)
			c.SendJSON(TypeRoomJoined, RoomJoinedPayload{
				RoomCode:     code,
				RoomName:     room.Name,
				MemberID:     c.memberID,
				IsHost:       c.isHost,
				SessionToken: c.sessionToken,
				Snapshot:     room.GetSnapshot(),
			})

			room.BroadcastApproved(TypeMemberJoined, VibeMember{
				ID:          c.memberID,
				Name:        c.name,
				IsHost:      c.isHost,
				ColorIndex:  c.colorIndex,
				JoinedAtSec: c.joinedAtSec,
			}, c.memberID)
			return
		}
	}

	h.mu.Unlock()

	c.name = strings.TrimSpace(p.UserName)
	if c.name == "" {
		c.name = "Guest"
	}

	// Add to pending joins and notify host
	room.AddPendingMember(c)
	log.Printf("[VibeHub] Member %s pending join in room %s", c.name, code)

	c.SendJSON(TypeJoinPending, JoinPendingPayload{
		Message: "Waiting for host approval to enter room...",
	})
}

func (h *Hub) handleApproveJoin(c *Client, p ApproveJoinPayload) {
	if !c.isHost {
		c.SendJSON(TypeError, ErrorPayload{Code: "UNAUTHORIZED", Message: "Only the host can approve members"})
		return
	}

	h.mu.RLock()
	room, ok := h.rooms[c.roomCode]
	h.mu.RUnlock()

	if !ok {
		return
	}

	approvedClient := room.ApproveMember(p.MemberID)
	if approvedClient == nil {
		return
	}

	// Save session for re-connect
	h.mu.Lock()
	h.sessions[approvedClient.sessionToken] = &SessionInfo{
		MemberID:   approvedClient.memberID,
		Name:       approvedClient.name,
		RoomCode:   room.Code,
		IsHost:     false,
		ColorIndex: approvedClient.colorIndex,
		ExpiresAt:  time.Now().Add(24 * time.Hour),
	}
	h.mu.Unlock()

	log.Printf("[VibeHub] Host approved member %s in room %s", approvedClient.name, room.Code)

	// Send full snapshot to newly approved member
	approvedClient.SendJSON(TypeRoomJoined, RoomJoinedPayload{
		RoomCode:     room.Code,
		RoomName:     room.Name,
		MemberID:     approvedClient.memberID,
		IsHost:       false,
		SessionToken: approvedClient.sessionToken,
		Snapshot:     room.GetSnapshot(),
	})

	// Broadcast member joined to other approved members
	room.BroadcastApproved(TypeMemberJoined, VibeMember{
		ID:          approvedClient.memberID,
		Name:        approvedClient.name,
		IsHost:      false,
		ColorIndex:  approvedClient.colorIndex,
		JoinedAtSec: approvedClient.joinedAtSec,
	}, approvedClient.memberID)
}

func (h *Hub) handleRejectJoin(c *Client, p RejectJoinPayload) {
	if !c.isHost {
		return
	}

	h.mu.RLock()
	room, ok := h.rooms[c.roomCode]
	h.mu.RUnlock()

	if !ok {
		return
	}

	rejectedClient := room.RejectMember(p.MemberID, p.Reason)
	if rejectedClient != nil {
		reason := p.Reason
		if reason == "" {
			reason = "Host declined your join request."
		}
		rejectedClient.SendJSON(TypeJoinRejected, JoinRejectedPayload{Reason: reason})
		rejectedClient.Close()
	}
}

func (h *Hub) handlePlaybackAction(c *Client, p PlaybackActionPayload) {
	if !c.isHost {
		// Non-hosts cannot authoritatively mutate playback
		return
	}

	h.mu.RLock()
	room, ok := h.rooms[c.roomCode]
	h.mu.RUnlock()

	if !ok {
		return
	}

	syncState := room.ApplyPlaybackAction(p.Action, p.Stem, p.PositionMs, p.Index)

	// Broadcast authoritative state to all approved room members except sender (host already knows)
	room.BroadcastApproved(TypeSyncState, syncState, c.memberID)
}

func (h *Hub) handleSuggestSong(c *Client, p SuggestSongPayload) {
	if !c.isApproved {
		return
	}

	h.mu.RLock()
	room, ok := h.rooms[c.roomCode]
	h.mu.RUnlock()

	if !ok {
		return
	}

	sugg := room.AddSuggestion(p.Stem, c)
	log.Printf("[VibeHub] New song suggestion in room %s by %s: %s", room.Code, c.name, p.Stem.Title)

	// Send suggestion only to host
	room.SendToHost(TypeNewSuggestion, sugg)
}

func (h *Hub) handleApproveSuggestion(c *Client, p ApproveSuggestionPayload) {
	if !c.isHost {
		return
	}

	h.mu.RLock()
	room, ok := h.rooms[c.roomCode]
	h.mu.RUnlock()

	if !ok {
		return
	}

	stem, okSugg := room.ResolveSuggestion(p.SuggestionID, p.Action)
	if !okSugg {
		return
	}

	// Notify room that suggestion was approved
	room.BroadcastApproved(TypeSuggestionResolved, map[string]string{
		"suggestion_id": p.SuggestionID,
		"status":        "approved",
		"action":        p.Action,
	})

	// Broadcast new sync state
	syncState := room.GetSyncState()
	room.BroadcastApproved(TypeSyncState, syncState)
	log.Printf("[VibeHub] Host approved suggestion %s (action=%s, title=%s)", p.SuggestionID, p.Action, stem.Title)
}

func (h *Hub) handleRejectSuggestion(c *Client, p RejectSuggestionPayload) {
	if !c.isHost {
		return
	}

	h.mu.RLock()
	room, ok := h.rooms[c.roomCode]
	h.mu.RUnlock()

	if !ok {
		return
	}

	room.ResolveSuggestion(p.SuggestionID, "reject")
	room.SendToHost(TypeSuggestionResolved, map[string]string{
		"suggestion_id": p.SuggestionID,
		"status":        "rejected",
	})
}

func (h *Hub) handleRequestSync(c *Client) {
	h.mu.RLock()
	room, ok := h.rooms[c.roomCode]
	h.mu.RUnlock()

	if !ok || !c.isApproved {
		return
	}

	c.SendJSON(TypeSyncState, room.GetSyncState())
}

func (h *Hub) handleLeaveRoom(c *Client) {
	h.mu.Lock()
	delete(h.clients, c)
	delete(h.sessions, c.sessionToken)
	roomCode := c.roomCode
	memberID := c.memberID
	room, ok := h.rooms[roomCode]
	h.mu.Unlock()

	if ok && memberID != "" {
		wasHost, newHost := room.RemoveMember(memberID)
		log.Printf("[VibeHub] Member %s explicitly left room %s (wasHost=%v)", memberID, roomCode, wasHost)

		var newHostID string
		if newHost != nil {
			newHostID = newHost.memberID
		}

		room.BroadcastApproved(TypeMemberLeft, map[string]string{
			"member_id":   memberID,
			"new_host_id": newHostID,
		})

		if newHost != nil {
			newHost.SendJSON(TypeHostTransferred, map[string]string{
				"new_host_id": newHost.memberID,
			})
		}
	}

	c.roomCode = ""
	c.isApproved = false
	c.isHost = false
}

func (h *Hub) handleKickMember(c *Client, p KickMemberPayload) {
	if !c.isHost || p.MemberID == c.memberID {
		return
	}

	h.mu.RLock()
	room, ok := h.rooms[c.roomCode]
	h.mu.RUnlock()

	if !ok {
		return
	}

	room.mu.RLock()
	target, exists := room.Members[p.MemberID]
	room.mu.RUnlock()

	if exists {
		target.SendJSON(TypeKicked, map[string]string{
			"reason": "You were removed from the room by the host.",
		})
		target.Close()
	}
}

func (h *Hub) handleTransferHost(c *Client, p TransferHostPayload) {
	if !c.isHost || p.NewHostID == c.memberID {
		return
	}

	h.mu.RLock()
	room, ok := h.rooms[c.roomCode]
	h.mu.RUnlock()

	if !ok {
		return
	}

	if room.TransferHost(p.NewHostID) {
		room.BroadcastApproved(TypeHostTransferred, map[string]string{
			"new_host_id": p.NewHostID,
		})
	}
}

func (h *Hub) GetStats() map[string]any {
	h.mu.RLock()
	defer h.mu.RUnlock()

	return map[string]any{
		"active_rooms":   len(h.rooms),
		"active_clients": len(h.clients),
		"uptime_sec":     time.Now().Unix(),
	}
}
