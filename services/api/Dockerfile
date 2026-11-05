FROM golang:1.27.3-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -buildvcs=false -trimpath -ldflags='-s -w' -o /api ./cmd/api
FROM alpine:3.23
RUN apk add --no-cache ca-certificates tzdata && adduser -D -u 10001 app
WORKDIR /app
COPY --from=build /api ./api
COPY migrations ./migrations
USER app
EXPOSE 8080
CMD ["./api"]
