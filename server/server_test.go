package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

func TestVibeServer_RoomFlow(t *testing.T) {
	hub := NewHub()

	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		c := NewClient(hub, conn, GenerateID("mem"), GenerateID("sess"))
		hub.Register(c)
		go c.WritePump()
		go c.ReadPump()
	}))
	defer s.Close()

	wsURL := "ws" + strings.TrimPrefix(s.URL, "http")

	// 1. Host connects
	hostWs, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("Failed to dial host WS: %v", err)
	}
	defer hostWs.Close()

	// 2. Host creates room
	createPayload, _ := json.Marshal(InboundMessage{
		Type: TypeCreateRoom,
		Payload: func() json.RawMessage {
			b, _ := json.Marshal(CreateRoomPayload{
				HostName: "HostUser",
				RoomName: "PartyRoom",
			})
			return b
		}(),
	})
	if err := hostWs.WriteMessage(websocket.TextMessage, createPayload); err != nil {
		t.Fatalf("Host failed to write: %v", err)
	}

	// Read room_created
	var resp OutboundMessage
	_ = hostWs.SetReadDeadline(time.Now().Add(2 * time.Second))
	_, msg, err := hostWs.ReadMessage()
	if err != nil {
		t.Fatalf("Failed to read room_created: %v", err)
	}
	_ = json.Unmarshal(msg, &resp)
	if resp.Type != TypeRoomCreated {
		t.Fatalf("Expected type %s, got %s", TypeRoomCreated, resp.Type)
	}

	rawPayload, _ := json.Marshal(resp.Payload)
	var roomCreated RoomCreatedPayload
	_ = json.Unmarshal(rawPayload, &roomCreated)
	roomCode := roomCreated.RoomCode
	if len(roomCode) != 6 {
		t.Fatalf("Expected 6-char room code, got %s", roomCode)
	}

	// 3. Member connects
	memberWs, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("Failed to dial member WS: %v", err)
	}
	defer memberWs.Close()

	// 4. Member requests to join room
	joinPayload, _ := json.Marshal(InboundMessage{
		Type: TypeJoinRoom,
		Payload: func() json.RawMessage {
			b, _ := json.Marshal(JoinRoomPayload{
				RoomCode: roomCode,
				UserName: "GuestUser",
			})
			return b
		}(),
	})
	if err := memberWs.WriteMessage(websocket.TextMessage, joinPayload); err != nil {
		t.Fatalf("Member failed to join: %v", err)
	}

	// Member should get join_pending
	_ = memberWs.SetReadDeadline(time.Now().Add(2 * time.Second))
	_, mMsg, err := memberWs.ReadMessage()
	if err != nil {
		t.Fatalf("Failed to read join_pending: %v", err)
	}
	var mResp OutboundMessage
	_ = json.Unmarshal(mMsg, &mResp)
	if mResp.Type != TypeJoinPending {
		t.Fatalf("Expected %s, got %s", TypeJoinPending, mResp.Type)
	}

	// Host should receive join_request
	_ = hostWs.SetReadDeadline(time.Now().Add(2 * time.Second))
	_, hMsg, err := hostWs.ReadMessage()
	if err != nil {
		t.Fatalf("Host failed to read join_request: %v", err)
	}
	var hResp OutboundMessage
	_ = json.Unmarshal(hMsg, &hResp)
	if hResp.Type != TypeJoinRequest {
		t.Fatalf("Expected %s, got %s", TypeJoinRequest, hResp.Type)
	}

	hPayloadRaw, _ := json.Marshal(hResp.Payload)
	var joinReq JoinRequestPayload
	_ = json.Unmarshal(hPayloadRaw, &joinReq)

	// 5. Host approves join
	approvePayload, _ := json.Marshal(InboundMessage{
		Type: TypeApproveJoin,
		Payload: func() json.RawMessage {
			b, _ := json.Marshal(ApproveJoinPayload{MemberID: joinReq.MemberID})
			return b
		}(),
	})
	_ = hostWs.WriteMessage(websocket.TextMessage, approvePayload)

	// Member should receive room_joined
	_ = memberWs.SetReadDeadline(time.Now().Add(2 * time.Second))
	_, approvedMsg, err := memberWs.ReadMessage()
	if err != nil {
		t.Fatalf("Member failed to read room_joined: %v", err)
	}
	var approvedResp OutboundMessage
	_ = json.Unmarshal(approvedMsg, &approvedResp)
	if approvedResp.Type != TypeRoomJoined {
		t.Fatalf("Expected %s, got %s", TypeRoomJoined, approvedResp.Type)
	}

	// 6. Host sends playback action (play)
	playPayload, _ := json.Marshal(InboundMessage{
		Type: TypePlaybackAction,
		Payload: func() json.RawMessage {
			b, _ := json.Marshal(PlaybackActionPayload{
				Action:     "change_track",
				PositionMs: 0,
				Stem: &StemData{
					ID:         "test_track_1",
					Title:      "Test Song",
					ArtistName: "Test Artist",
					DurationSec: 180,
				},
			})
			return b
		}(),
	})
	_ = hostWs.WriteMessage(websocket.TextMessage, playPayload)

	// Member receives sync_state
	_ = memberWs.SetReadDeadline(time.Now().Add(2 * time.Second))
	_, syncMsg, err := memberWs.ReadMessage()
	if err != nil {
		t.Fatalf("Member failed to read sync_state: %v", err)
	}
	var syncResp OutboundMessage
	_ = json.Unmarshal(syncMsg, &syncResp)
	if syncResp.Type != TypeSyncState {
		t.Fatalf("Expected %s, got %s", TypeSyncState, syncResp.Type)
	}
}

func TestVibeServer_SongSuggestionFlow(t *testing.T) {
	hub := NewHub()
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		c := NewClient(hub, conn, GenerateID("mem"), GenerateID("sess"))
		hub.Register(c)
		go c.WritePump()
		go c.ReadPump()
	}))
	defer s.Close()

	wsURL := "ws" + strings.TrimPrefix(s.URL, "http")

	hostWs, _, _ := websocket.DefaultDialer.Dial(wsURL, nil)
	defer hostWs.Close()

	// Create room
	createPayload, _ := json.Marshal(InboundMessage{
		Type: TypeCreateRoom,
		Payload: func() json.RawMessage {
			b, _ := json.Marshal(CreateRoomPayload{HostName: "Host", RoomName: "Jam"})
			return b
		}(),
	})
	_ = hostWs.WriteMessage(websocket.TextMessage, createPayload)

	var hResp OutboundMessage
	_ = hostWs.SetReadDeadline(time.Now().Add(2 * time.Second))
	_, msg, _ := hostWs.ReadMessage()
	_ = json.Unmarshal(msg, &hResp)
	raw, _ := json.Marshal(hResp.Payload)
	var roomCreated RoomCreatedPayload
	_ = json.Unmarshal(raw, &roomCreated)

	// Member joins directly with session restoration or approval
	memberWs, _, _ := websocket.DefaultDialer.Dial(wsURL, nil)
	defer memberWs.Close()

	joinPayload, _ := json.Marshal(InboundMessage{
		Type: TypeJoinRoom,
		Payload: func() json.RawMessage {
			b, _ := json.Marshal(JoinRoomPayload{RoomCode: roomCreated.RoomCode, UserName: "Member"})
			return b
		}(),
	})
	_ = memberWs.WriteMessage(websocket.TextMessage, joinPayload)

	// Discard join_pending on member
	_ = memberWs.SetReadDeadline(time.Now().Add(2 * time.Second))
	_, _, _ = memberWs.ReadMessage()

	// Read join_request on host
	_ = hostWs.SetReadDeadline(time.Now().Add(2 * time.Second))
	_, jMsg, _ := hostWs.ReadMessage()
	var jResp OutboundMessage
	_ = json.Unmarshal(jMsg, &jResp)
	jRaw, _ := json.Marshal(jResp.Payload)
	var jReq JoinRequestPayload
	_ = json.Unmarshal(jRaw, &jReq)

	// Host approves
	appPayload, _ := json.Marshal(InboundMessage{
		Type: TypeApproveJoin,
		Payload: func() json.RawMessage {
			b, _ := json.Marshal(ApproveJoinPayload{MemberID: jReq.MemberID})
			return b
		}(),
	})
	_ = hostWs.WriteMessage(websocket.TextMessage, appPayload)

	// Read room_joined on member
	_ = memberWs.SetReadDeadline(time.Now().Add(2 * time.Second))
	_, _, _ = memberWs.ReadMessage()

	// Member suggests song
	suggPayload, _ := json.Marshal(InboundMessage{
		Type: TypeSuggestSong,
		Payload: func() json.RawMessage {
			b, _ := json.Marshal(SuggestSongPayload{
				Stem: StemData{
					ID:         "suggested_track_1",
					Title:      "Requested Track",
					ArtistName: "Cool Artist",
					DurationSec: 210,
				},
			})
			return b
		}(),
	})
	_ = memberWs.WriteMessage(websocket.TextMessage, suggPayload)

	// Host consumes messages until new_suggestion is received
	_ = hostWs.SetReadDeadline(time.Now().Add(2 * time.Second))
	var suggResp OutboundMessage
	for {
		_, msg, err := hostWs.ReadMessage()
		if err != nil {
			t.Fatalf("Host failed to receive suggestion: %v", err)
		}
		var tmp OutboundMessage
		_ = json.Unmarshal(msg, &tmp)
		if tmp.Type == TypeNewSuggestion {
			suggResp = tmp
			break
		}
	}
	if suggResp.Type != TypeNewSuggestion {
		t.Fatalf("Expected %s, got %s", TypeNewSuggestion, suggResp.Type)
	}
}
