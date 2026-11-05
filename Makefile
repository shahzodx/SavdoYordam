.PHONY: api-test api-run migrate mobile-test generate
api-test:
	cd services/api && go test -race ./...
api-run:
	cd services/api && go run ./cmd/api
migrate:
	cd services/api && go run ./cmd/api migrate
mobile-test:
	cd apps/mobile && flutter analyze && flutter test
generate:
	cd services/api && sqlc generate
