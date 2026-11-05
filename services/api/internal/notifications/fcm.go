package notifications

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/jwt"
)

type Sender struct {
	client   *http.Client
	endpoint string
}

func FromEnv(ctx context.Context) (*Sender, error) {
	if os.Getenv("FCM_ENABLED") != "true" {
		return nil, nil
	}
	raw, err := os.ReadFile(os.Getenv("GOOGLE_APPLICATION_CREDENTIALS"))
	if err != nil {
		return nil, errors.New("FCM service-account file unavailable")
	}
	var credentials struct {
		Project string `json:"project_id"`
		Email   string `json:"client_email"`
		Key     string `json:"private_key"`
	}
	if json.Unmarshal(raw, &credentials) != nil || credentials.Project == "" || credentials.Email == "" || credentials.Key == "" {
		return nil, errors.New("invalid FCM service-account configuration")
	}
	config := jwt.Config{Email: credentials.Email, PrivateKey: []byte(credentials.Key), Scopes: []string{"https://www.googleapis.com/auth/firebase.messaging"}, TokenURL: "https://oauth2.googleapis.com/token"}
	authContext := context.WithValue(ctx, oauth2.HTTPClient, &http.Client{Timeout: 10 * time.Second})
	client := oauth2.NewClient(authContext, config.TokenSource(authContext))
	client.Timeout = 10 * time.Second
	return &Sender{client: client, endpoint: "https://fcm.googleapis.com/v1/projects/" + url.PathEscape(credentials.Project) + "/messages:send"}, nil
}
func (s *Sender) send(ctx context.Context, token, language string) (bool, error) {
	title, body := "SavdoYordam", "Kam qolgan mahsulotlarni tekshiring."
	if language == "ru" {
		body = "Проверьте товары с низким остатком."
	}
	raw, _ := json.Marshal(map[string]any{"message": map[string]any{"token": token, "data": map[string]string{"title": title, "body": body, "kind": "low_stock"}, "android": map[string]string{"priority": "normal", "collapse_key": "stock"}}})
	req, err := http.NewRequestWithContext(ctx, "POST", s.endpoint, bytes.NewReader(raw))
	if err != nil {
		return false, err
	}
	req.Header.Set("Content-Type", "application/json")
	response, err := s.client.Do(req)
	if err != nil {
		return false, errors.New("FCM transport failure")
	}
	defer response.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(response.Body, 65536))
	if response.StatusCode >= 200 && response.StatusCode < 300 {
		return false, nil
	}
	var payload struct {
		Error struct {
			Details []struct {
				Code string `json:"errorCode"`
			} `json:"details"`
		} `json:"error"`
	}
	_ = json.Unmarshal(data, &payload)
	for _, detail := range payload.Error.Details {
		if detail.Code == "UNREGISTERED" {
			return true, nil
		}
	}
	return false, fmt.Errorf("FCM rejected request with status %d", response.StatusCode)
}
func Run(ctx context.Context, pool *pgxpool.Pool, sender *Sender, log *slog.Logger) {
	if sender == nil {
		log.Info("cloud notifications disabled")
		return
	}
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			batch, cancel := context.WithTimeout(ctx, 55*time.Second)
			err := runBatch(batch, pool, sender)
			cancel()
			if err != nil {
				log.Error("cloud notification batch failed", "error", err.Error())
			}
		}
	}
}
func runBatch(ctx context.Context, pool *pgxpool.Pool, sender *Sender) error {
	conn, err := pool.Acquire(ctx)
	if err != nil {
		return err
	}
	defer conn.Release()
	var locked bool
	if err = conn.QueryRow(ctx, "SELECT pg_try_advisory_lock(83921104)").Scan(&locked); err != nil {
		return err
	}
	if !locked {
		return nil
	}
	defer func() {
		unlock, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		if _, err := conn.Exec(unlock, "SELECT pg_advisory_unlock(83921104)"); err != nil {
			_ = conn.Conn().Close(unlock)
		}
	}()
	_, err = conn.Exec(ctx, "DELETE FROM push_devices WHERE updated_at<now()-interval '30 days'")
	if err != nil {
		return err
	}
	rows, err := conn.Query(ctx, `SELECT d.store_id::text,d.actor_id::text,d.device_id::text,d.token,d.language FROM push_devices d JOIN store_members m ON m.store_id=d.store_id AND m.user_id=d.actor_id JOIN stores s ON s.id=d.store_id WHERE NOT s.archived AND (d.last_sent_at IS NULL OR d.last_sent_at<now()-interval '6 hours') AND EXISTS(SELECT 1 FROM products p WHERE p.store_id=d.store_id AND NOT p.archived AND p.stock<=p.minimum_stock) ORDER BY d.last_sent_at NULLS FIRST LIMIT 50`)
	if err != nil {
		return err
	}
	type device struct{ store, actor, id, token, language string }
	devices := []device{}
	for rows.Next() {
		var d device
		if err = rows.Scan(&d.store, &d.actor, &d.id, &d.token, &d.language); err != nil {
			rows.Close()
			return err
		}
		devices = append(devices, d)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, d := range devices {
		invalid, err := sender.send(ctx, d.token, d.language)
		if err != nil {
			return err
		}
		if invalid {
			_, err = conn.Exec(ctx, "DELETE FROM push_devices WHERE store_id=$1 AND actor_id=$2 AND device_id=$3", d.store, d.actor, d.id)
		} else {
			_, err = conn.Exec(ctx, "UPDATE push_devices SET last_sent_at=now() WHERE store_id=$1 AND actor_id=$2 AND device_id=$3", d.store, d.actor, d.id)
		}
		if err != nil {
			return err
		}
	}
	return nil
}
