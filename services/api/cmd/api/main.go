package main

import (
	"context"
	"database/sql"
	"errors"
	"github.com/getsentry/sentry-go"
	"github.com/jackc/pgx/v5/pgxpool"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"savdoyordam/api/internal/httpapi"
	"savdoyordam/api/internal/notifications"
	"syscall"
	"time"
	_ "time/tzdata"
)

func main() {
	if err := run(); err != nil {
		slog.Error("startup failed", "error", err)
		os.Exit(1)
	}
}
func run() error {
	if os.Getenv("SENTRY_DSN") != "" {
		if err := sentry.Init(sentry.ClientOptions{Dsn: os.Getenv("SENTRY_DSN"), Release: "savdoyordam-api@0.2.0", Environment: os.Getenv("APP_ENV"), ServerName: "savdoyordam-api", SendDefaultPII: false, BeforeSend: func(event *sentry.Event, hint *sentry.EventHint) *sentry.Event {
			event.Request = nil
			event.User = sentry.User{}
			event.Contexts = nil
			event.Breadcrumbs = nil
			event.Exception = nil
			return event
		}}); err != nil {
			return errors.New("invalid Sentry configuration")
		}
		defer sentry.Flush(2 * time.Second)
	}
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(log)
	url := os.Getenv("DATABASE_URL")
	if url == "" {
		return errors.New("DATABASE_URL required")
	}
	if len(os.Args) > 1 && os.Args[1] == "migrate" {
		db, err := sql.Open("pgx", url)
		if err != nil {
			return err
		}
		defer db.Close()
		dir := os.Getenv("MIGRATIONS_DIR")
		if dir == "" {
			dir = "migrations"
		}
		if err = goose.SetDialect("postgres"); err != nil {
			return err
		}
		return goose.Up(db, dir)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		return err
	}
	defer pool.Close()
	if err = pool.Ping(ctx); err != nil {
		return err
	}
	sender, err := notifications.FromEnv(ctx)
	if err != nil {
		return err
	}
	go notifications.Run(ctx, pool, sender, log)
	addr := os.Getenv("LISTEN_ADDR")
	if addr == "" {
		addr = "127.0.0.1:8080"
	}
	srv := &http.Server{Addr: addr, Handler: httpapi.New(pool, log), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16384}
	result := make(chan error, 1)
	go func() { log.Info("listening", "address", addr); result <- srv.ListenAndServe() }()
	select {
	case err = <-result:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
	case <-ctx.Done():
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return srv.Shutdown(shutdown)
	}
	return nil
}
