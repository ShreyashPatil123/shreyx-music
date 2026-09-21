package main

import (
	"encoding/json"
	"time"
)

// MessageType identifies the message payload
type MessageType string

const (
	// Client -> Server
	TypeCreateRoom        MessageType = "create_room"
	TypeJoinRoom          MessageType = "join_room"
	TypeApproveJoin       MessageType = "approve_join"
	TypeRejectJoin        MessageType = "reject_join"
	TypeLeaveRoom         MessageType = "leave_room"
	TypeKickMember        MessageType = "kick_member"
	TypeTransferHost      MessageType = "transfer_host"
	TypePlaybackAction    MessageType = "playback_action"
	TypeSuggestSong       MessageType = "suggest_song"
	TypeApproveSuggestion MessageType = "approve_suggestion"
	TypeRejectSuggestion  MessageType = "reject_suggestion"
	TypeRequestSync       MessageType = "request_sync"
	TypePing              MessageType = "ping"

	// Server -> Client
	TypeRoomCreated        MessageType = "room_created"
	TypeJoinPending        MessageType = "join_pending"
	TypeJoinRequest        MessageType = "join_request"
	TypeRoomJoined         MessageType = "room_joined"
	TypeJoinRejected       MessageType = "join_rejected"
	TypeSyncState          MessageType = "sync_state"
	TypeNewSuggestion      MessageType = "new_suggestion"
	TypeSuggestionResolved MessageType = "suggestion_resolved"
	TypeMemberJoined       MessageType = "member_joined"
	TypeMemberLeft         MessageType = "member_left"
	TypeKicked             MessageType = "kicked"
	TypeHostTransferred    MessageType = "host_transferred"
	TypePong               MessageType = "pong"
	TypeError              MessageType = "error"
)

// InboundMessage represents a generic wrapper from client
type InboundMessage struct {
	Type    MessageType     `json:"type"`
	Payload json.RawMessage `json:"payload"`
}

// OutboundMessage represents a generic wrapper to client
type OutboundMessage struct {
	Type    MessageType `json:"type"`
	Payload any         `json:"payload"`
}

// StemData mirrors ShreyX Dart Stem model for serialization
type StemData struct {
	ID          string  `json:"id"`
	Title       string  `json:"title"`
	ArtistName  string  `json:"artistName"`
	ArtworkURL  string  `json:"artworkUrl"`
	DurationSec int     `json:"durationSec"`
	SourceID    string  `json:"sourceId"`
	AlbumName   *string `json:"albumName,omitempty"`
}

// VibeMember represents an anonymous member in a room
type VibeMember struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	IsHost      bool   `json:"isHost"`
	ColorIndex  int    `json:"colorIndex"`
	JoinedAtSec int64  `json:"joinedAtSec"`
}

// VibeSongSuggestion represents a song suggestion submitted by a member
type VibeSongSuggestion struct {
	ID           string   `json:"id"`
	Stem         StemData `json:"stem"`
	SuggestedBy  string   `json:"suggestedBy"`
	SuggesterName string  `json:"suggesterName"`
	CreatedAtSec int64    `json:"createdAtSec"`
}

// RoomSnapshot contains all data sent to newly joined or reconnected members
type RoomSnapshot struct {
	RoomCode      string               `json:"roomCode"`
	RoomName      string               `json:"roomName"`
	HostID        string               `json:"hostId"`
	Members       []VibeMember         `json:"members"`
	Queue         []StemData           `json:"queue"`
	CurrentTrack  *StemData            `json:"currentTrack"`
	IsPlaying     bool                 `json:"isPlaying"`
	PositionMs    int64                `json:"positionMs"`
	ServerTimeMs  int64                `json:"serverTimeMs"`
	Seq           int64                `json:"seq"`
	Suggestions   []VibeSongSuggestion `json:"suggestions,omitempty"`
}

// --- Request Payloads ---

type CreateRoomPayload struct {
	HostName string `json:"host_name"`
	RoomName string `json:"room_name"`
}

type JoinRoomPayload struct {
	RoomCode     string `json:"room_code"`
	UserName     string `json:"user_name"`
	SessionToken string `json:"session_token,omitempty"`
}

type ApproveJoinPayload struct {
	MemberID string `json:"member_id"`
}

type RejectJoinPayload struct {
	MemberID string `json:"member_id"`
	Reason   string `json:"reason,omitempty"`
}

type KickMemberPayload struct {
	MemberID string `json:"member_id"`
}

type TransferHostPayload struct {
	NewHostID string `json:"new_host_id"`
}

type PlaybackActionPayload struct {
	Action     string    `json:"action"` // "play", "pause", "seek", "change_track", "skip_next", "skip_prev", "queue_add", "queue_remove", "queue_clear"
	Stem       *StemData `json:"stem,omitempty"`
	PositionMs int64     `json:"position_ms"`
	Timestamp  int64     `json:"timestamp"`
	Index      *int      `json:"index,omitempty"`
}

type SuggestSongPayload struct {
	Stem StemData `json:"stem"`
}

type ApproveSuggestionPayload struct {
	SuggestionID string `json:"suggestion_id"`
	Action       string `json:"action"` // "play_now" or "add_to_queue"
}

type RejectSuggestionPayload struct {
	SuggestionID string `json:"suggestion_id"`
}

type PingPayload struct {
	ClientTime int64 `json:"client_time"`
}

// --- Response Payloads ---

type RoomCreatedPayload struct {
	RoomCode     string        `json:"room_code"`
	RoomName     string        `json:"room_name"`
	MemberID     string        `json:"member_id"`
	SessionToken string        `json:"session_token"`
	Snapshot     *RoomSnapshot `json:"snapshot"`
}

type JoinPendingPayload struct {
	Message string `json:"message"`
}

type JoinRequestPayload struct {
	MemberID  string `json:"member_id"`
	UserName  string `json:"user_name"`
	Timestamp int64  `json:"timestamp"`
}

type RoomJoinedPayload struct {
	RoomCode     string        `json:"room_code"`
	RoomName     string        `json:"room_name"`
	MemberID     string        `json:"member_id"`
	IsHost       bool          `json:"is_host"`
	SessionToken string        `json:"session_token"`
	Snapshot     *RoomSnapshot `json:"snapshot"`
}

type JoinRejectedPayload struct {
	Reason string `json:"reason"`
}

type SyncStatePayload struct {
	CurrentTrack *StemData  `json:"current_track"`
	IsPlaying    bool       `json:"is_playing"`
	PositionMs   int64      `json:"position_ms"`
	ServerTimeMs int64      `json:"server_time_ms"`
	Queue        []StemData `json:"queue"`
	HostID       string     `json:"host_id"`
	Seq          int64      `json:"seq"`
}

type PongPayload struct {
	ClientTime int64 `json:"client_time"`
	ServerTime int64 `json:"server_time"`
}

type ErrorPayload struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func nowMillis() int64 {
	return time.Now().UnixNano() / int64(time.Millisecond)
}
