package notifications

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestFCMPayloadAndRevokedToken(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if r.Header.Get("Content-Type") != "application/json" {
			t.Error("missing content type")
		}
		var p map[string]map[string]any
		if err := json.NewDecoder(r.Body).Decode(&p); err != nil {
			t.Error(err)
		}
		if p["message"]["token"] != "device-token" {
			t.Error("wrong device")
		}
		if calls == 1 {
			w.WriteHeader(200)
			_, _ = w.Write([]byte(`{"name":"projects/test/messages/test"}`))
		} else {
			w.WriteHeader(404)
			_, _ = w.Write([]byte(`{"error":{"details":[{"errorCode":"UNREGISTERED"}]}}`))
		}
	}))
	defer server.Close()
	sender := &Sender{client: server.Client(), endpoint: server.URL}
	if invalid, err := sender.send(context.Background(), "device-token", "ru"); invalid || err != nil {
		t.Fatal(invalid, err)
	}
	if invalid, err := sender.send(context.Background(), "device-token", "uz"); !invalid || err != nil {
		t.Fatal(invalid, err)
	}
}
