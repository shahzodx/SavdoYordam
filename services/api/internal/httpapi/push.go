package httpapi

import (
	"github.com/go-chi/chi/v5"
	"net/http"
)

func (s *Server) registerPush(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Device   string `json:"device_id"`
		Token    string `json:"token"`
		Language string `json:"language"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	if !validID(p.Device) || len(p.Token) < 20 || len(p.Token) > 4096 || (p.Language != "uz" && p.Language != "ru") {
		return fail(400, "invalid_request")
	}
	_, err := s.DB.Exec(r.Context(), "INSERT INTO push_devices(store_id,actor_id,device_id,token,language) VALUES($1,$2,$3,$4,$5) ON CONFLICT(store_id,actor_id,device_id) DO UPDATE SET token=EXCLUDED.token,language=EXCLUDED.language,updated_at=now()", chi.URLParam(r, "store"), user(r), p.Device, p.Token, p.Language)
	if err != nil {
		return err
	}
	write(w, 200, map[string]bool{"ok": true})
	return nil
}
func (s *Server) unregisterPush(w http.ResponseWriter, r *http.Request) error {
	var p struct {
		Device string `json:"device_id"`
	}
	if err := decode(w, r, &p); err != nil {
		return err
	}
	if !validID(p.Device) {
		return fail(400, "invalid_request")
	}
	_, err := s.DB.Exec(r.Context(), "DELETE FROM push_devices WHERE store_id=$1 AND actor_id=$2 AND device_id=$3", chi.URLParam(r, "store"), user(r), p.Device)
	if err != nil {
		return err
	}
	write(w, 200, map[string]bool{"ok": true})
	return nil
}
