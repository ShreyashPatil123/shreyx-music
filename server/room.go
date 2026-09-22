package main

import (
	"crypto/rand"
	"fmt"
	"math/big"
	"sync"
	"time"
)

const charset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // omits I, O, 0, 1 for readability

func GenerateRoomCode() string {
	b := make([]byte, 6)
	for i := range b {
		num, err := rand.Int(rand.Reader, big.NewInt(int64(len(charset))))
		if err != nil {
			return fmt.Sprintf("VX%04d", time.Now().UnixNano()%10000)
		}
		b[i] = charset[num.Int64()]
	}
	return string(b)
}

func GenerateID(prefix string) string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return fmt.Sprintf("%s_%x", prefix, b)
}

type Room struct {
	mu           sync.RWMutex
	Code         string
	Name         string
	HostID       string
	Members      map[string]*Client // approved members: memberID -> Client
	PendingJoins map[string]*Client // waiting for approval: memberID -> Client
	Queue        []StemData
	CurrentTrack *StemData
	IsPlaying    bool
	PositionMs   int64
	ServerTimeMs int64
	Seq          int64
	Suggestions  map[string]*VibeSongSuggestion
	CreatedAt    time.Time
	LastActivity time.Time
}

func NewRoom(code, name string, host *Client) *Room {
	now := time.Now()
	r := &Room{
		Code:         code,
		Name:         name,
		HostID:       host.memberID,
		Members:      make(map[string]*Client),
		PendingJoins: make(map[string]*Client),
		Queue:        make([]StemData, 0),
		Suggestions:  make(map[string]*VibeSongSuggestion),
		CreatedAt:    now,
		LastActivity: now,
		ServerTimeMs: nowMillis(),
		Seq:          1,
	}

	host.isHost = true
	host.isApproved = true
	host.roomCode = code
	r.Members[host.memberID] = host

	return r
}

func (r *Room) Touch() {
	r.LastActivity = time.Now()
}

func (r *Room) BroadcastApproved(msgType MessageType, payload any, excludeID ...string) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	var exclude string
	if len(excludeID) > 0 {
		exclude = excludeID[0]
	}

	for id, member := range r.Members {
		if id == exclude {
			continue
		}
		member.SendJSON(msgType, payload)
	}
}

func (r *Room) SendToHost(msgType MessageType, payload any) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if host, ok := r.Members[r.HostID]; ok {
		host.SendJSON(msgType, payload)
	}
}

func (r *Room) GetSnapshot() *RoomSnapshot {
	r.mu.RLock()
	defer r.mu.RUnlock()

	membersList := make([]VibeMember, 0, len(r.Members))
	for _, m := range r.Members {
		membersList = append(membersList, VibeMember{
			ID:          m.memberID,
			Name:        m.name,
			IsHost:      m.isHost,
			ColorIndex:  m.colorIndex,
			JoinedAtSec: m.joinedAtSec,
		})
	}

	queueCopy := make([]StemData, len(r.Queue))
	copy(queueCopy, r.Queue)

	suggsList := make([]VibeSongSuggestion, 0, len(r.Suggestions))
	for _, s := range r.Suggestions {
		suggsList = append(suggsList, *s)
	}

	var trackCopy *StemData
	if r.CurrentTrack != nil {
		tc := *r.CurrentTrack
		trackCopy = &tc
	}

	return &RoomSnapshot{
		RoomCode:     r.Code,
		RoomName:     r.Name,
		HostID:       r.HostID,
		Members:      membersList,
		Queue:        queueCopy,
		CurrentTrack: trackCopy,
		IsPlaying:    r.IsPlaying,
		PositionMs:   r.PositionMs,
		ServerTimeMs: r.ServerTimeMs,
		Seq:          r.Seq,
		Suggestions:  suggsList,
	}
}

func (r *Room) GetSyncState() SyncStatePayload {
	r.mu.RLock()
	defer r.mu.RUnlock()

	queueCopy := make([]StemData, len(r.Queue))
	copy(queueCopy, r.Queue)

	var trackCopy *StemData
	if r.CurrentTrack != nil {
		tc := *r.CurrentTrack
		trackCopy = &tc
	}

	return SyncStatePayload{
		CurrentTrack: trackCopy,
		IsPlaying:    r.IsPlaying,
		PositionMs:   r.PositionMs,
		ServerTimeMs: r.ServerTimeMs,
		Queue:        queueCopy,
		HostID:       r.HostID,
		Seq:          r.Seq,
	}
}

func (r *Room) AddPendingMember(c *Client) {
	r.mu.Lock()
	defer r.mu.Unlock()

	c.roomCode = r.Code
	c.isApproved = false
	c.isHost = false
	r.PendingJoins[c.memberID] = c
	r.Touch()

	// Notify host
	if host, ok := r.Members[r.HostID]; ok {
		host.SendJSON(TypeJoinRequest, JoinRequestPayload{
			MemberID:  c.memberID,
			UserName:  c.name,
			Timestamp: time.Now().Unix(),
		})
	}
}

func (r *Room) ApproveMember(memberID string) *Client {
	r.mu.Lock()
	defer r.mu.Unlock()

	client, ok := r.PendingJoins[memberID]
	if !ok {
		return nil
	}

	delete(r.PendingJoins, memberID)
	client.isApproved = true
	r.Members[memberID] = client
	r.Touch()

	return client
}

func (r *Room) RejectMember(memberID string, reason string) *Client {
	r.mu.Lock()
	defer r.mu.Unlock()

	client, ok := r.PendingJoins[memberID]
	if !ok {
		return nil
	}

	delete(r.PendingJoins, memberID)
	r.Touch()
	return client
}

func (r *Room) RemoveMember(memberID string) (wasHost bool, newHost *Client) {
	r.mu.Lock()
	defer r.mu.Unlock()

	delete(r.PendingJoins, memberID)
	client, ok := r.Members[memberID]
	if !ok {
		return false, nil
	}

	delete(r.Members, memberID)
	r.Touch()

	if client.isHost {
		wasHost = true
		// Auto-transfer to the earliest joined member
		var candidate *Client
		for _, m := range r.Members {
			if candidate == nil || m.joinedAtSec < candidate.joinedAtSec {
				candidate = m
			}
		}

		if candidate != nil {
			candidate.isHost = true
			r.HostID = candidate.memberID
			newHost = candidate
		} else {
			r.HostID = ""
		}
	}

	return wasHost, newHost
}

func (r *Room) TransferHost(newHostID string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()

	newHost, ok := r.Members[newHostID]
	if !ok {
		return false
	}

	if oldHost, okOld := r.Members[r.HostID]; okOld {
		oldHost.isHost = false
	}

	newHost.isHost = true
	r.HostID = newHostID
	r.Touch()
	return true
}

func (r *Room) ApplyPlaybackAction(action string, stem *StemData, positionMs int64, idx *int) SyncStatePayload {
	r.mu.Lock()
	defer r.mu.Unlock()

	r.Seq++
	r.ServerTimeMs = nowMillis()
	r.Touch()

	switch action {
	case "play":
		r.IsPlaying = true
		r.PositionMs = positionMs
		if stem != nil {
			r.CurrentTrack = stem
		}
	case "pause":
		r.IsPlaying = false
		r.PositionMs = positionMs
		if stem != nil && r.CurrentTrack == nil {
			r.CurrentTrack = stem
		}
	case "seek":
		r.PositionMs = positionMs
		if stem != nil && r.CurrentTrack == nil {
			r.CurrentTrack = stem
		}
	case "change_track":
		if stem != nil {
			r.CurrentTrack = stem
			r.PositionMs = positionMs
			r.IsPlaying = true
		}
	case "skip_next":
		if len(r.Queue) > 0 {
			next := r.Queue[0]
			r.Queue = r.Queue[1:]
			r.CurrentTrack = &next
			r.PositionMs = 0
			r.IsPlaying = true
		}
	case "skip_prev":
		// Reset to start of current track
		r.PositionMs = 0
	case "queue_add":
		if stem != nil {
			r.Queue = append(r.Queue, *stem)
		}
	case "queue_play_next":
		if stem != nil {
			r.Queue = append([]StemData{*stem}, r.Queue...)
		}
	case "queue_remove":
		if idx != nil && *idx >= 0 && *idx < len(r.Queue) {
			i := *idx
			r.Queue = append(r.Queue[:i], r.Queue[i+1:]...)
		}
	case "queue_clear":
		r.Queue = make([]StemData, 0)
	}

	queueCopy := make([]StemData, len(r.Queue))
	copy(queueCopy, r.Queue)

	var trackCopy *StemData
	if r.CurrentTrack != nil {
		tc := *r.CurrentTrack
		trackCopy = &tc
	}

	return SyncStatePayload{
		CurrentTrack: trackCopy,
		IsPlaying:    r.IsPlaying,
		PositionMs:   r.PositionMs,
		ServerTimeMs: r.ServerTimeMs,
		Queue:        queueCopy,
		HostID:       r.HostID,
		Seq:          r.Seq,
	}
}

func (r *Room) AddSuggestion(stem StemData, suggestedBy *Client) *VibeSongSuggestion {
	r.mu.Lock()
	defer r.mu.Unlock()

	id := GenerateID("sug")
	sugg := &VibeSongSuggestion{
		ID:            id,
		Stem:          stem,
		SuggestedBy:   suggestedBy.memberID,
		SuggesterName: suggestedBy.name,
		CreatedAtSec:  time.Now().Unix(),
	}

	r.Suggestions[id] = sugg
	r.Touch()
	return sugg
}

func (r *Room) ResolveSuggestion(suggestionID, action string) (*StemData, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()

	sugg, ok := r.Suggestions[suggestionID]
	if !ok {
		return nil, false
	}

	delete(r.Suggestions, suggestionID)
	r.Touch()

	stem := sugg.Stem
	if action == "play_now" {
		r.Seq++
		r.ServerTimeMs = nowMillis()
		r.CurrentTrack = &stem
		r.PositionMs = 0
		r.IsPlaying = true
	} else if action == "add_to_queue" {
		r.Queue = append(r.Queue, stem)
		r.Seq++
		r.ServerTimeMs = nowMillis()
	}

	return &stem, true
}

func (r *Room) IsEmpty() bool {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return len(r.Members) == 0 && len(r.PendingJoins) == 0
}

func (r *Room) IsExpired(timeout time.Duration) bool {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return len(r.Members) == 0 && time.Since(r.LastActivity) > timeout
}
