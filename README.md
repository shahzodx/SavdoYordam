# SavdoYordam

**Savdongiz nazorat ostida.** Flutter + Go + PostgreSQL для учёта небольшого магазина.

Реализован рабочий вертикальный срез: аккаунт → магазин → товар → продажа → склад → Dashboard, а также клиенты, частичная оплата, погашение долга, полный возврат и расходы. Это **разрабатываемый пилот**, не готовый коммерческий релиз и не фискальная касса. Статус проверок: [PROGRESS](docs/PROGRESS.md), границы: [KNOWN_LIMITATIONS](docs/KNOWN_LIMITATIONS.md).

**Android APK собраны:** [варианты для телефона по USB и эмулятора, установка и контрольные суммы](artifacts/README.md). Требуется Android 7.0+ и запущенный локальный API. На физическом устройстве сборки ещё не проверены.

## Быстрый запуск

Нужны Docker Compose, Flutter **3.47.9** / Dart **3.13.7**, Android SDK 36 (дополнительно API 35 для JNI), Build Tools 36.0.0, NDK 28.2.13676358, CMake 3.22.1 и совместимый JDK (сборка проверена с JDK 25). Go-зависимости и Flutter-зависимости закреплены lock-файлами.

```sh
cp .env.example .env
# Замените POSTGRES_PASSWORD случайной hex-строкой: openssl rand -hex 32
docker compose up --build -d
curl http://127.0.0.1:8080/health/ready
cd apps/mobile
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:8080
```

`10.0.2.2` — хост из Android Emulator. Для физического телефона используйте `adb reverse tcp:8080 tcp:8080` и `API_URL=http://127.0.0.1:8080` в debug-сборке. Создайте аккаунт с почтой и паролем от 12 символов. SMS-провайдера и тестовых OTP нет. Данные изначально пустые.

Запуск без Docker:

```sh
export DATABASE_URL='postgres://USER:PASSWORD@127.0.0.1:5432/savdoyordam?sslmode=disable'
cd services/api
go run ./cmd/api migrate
go run ./cmd/api
```

Сервер по умолчанию слушает только `127.0.0.1:8080`. Миграции запускаются отдельной командой, не при каждом старте API.

## Проверки

```sh
# PostgreSQL URL должен разрешать CREATE DATABASE: тесты создают и удаляют только
# собственные базы savdo_test_<uuid>. Не используйте production credentials.
export TEST_DATABASE_URL='postgres://USER:PASSWORD@localhost:5432/postgres?sslmode=disable'
cd services/api
go test -race ./...
go vet ./...

cd ../../apps/mobile
flutter analyze
flutter test
# Дополнительный сквозной тест против отдельного запущенного тестового API:
flutter test test/api_integration_test.dart --dart-define=API_TEST_URL=http://127.0.0.1:8080
flutter build apk --debug
```

Сквозной тест создаёт собственные аккаунт и магазин; его данные остаются в тестовой базе. Без `API_TEST_URL` этот тест явно пропускается. Без `TEST_DATABASE_URL` Go-интеграционные тесты явно пропускаются.

## Основные решения

- Деньги: integer **tiyin**, 100 = 1 UZS. Количество: тысячные единицы, 1000 = 1 штука/кг/литр. Округление half-up на строке продажи.
- PostgreSQL атомарно сохраняет продажу, платежи, долг и движение склада. Все изменения одного магазина сериализуются его row lock.
- Финансовые журналы append-only. Возврат — отдельная обратная операция.
- Каждая команда магазина содержит UUID `Idempotency-Key`; сервер хранит результат и проверяет совпадение содержимого и автора.
- Drift хранит кэш, черновик корзины и durable outbox. Без ответа сервера операция остаётся неподтверждённой. Полноценные автономные офлайн-продажи не заявлены.
- Секрет сессии находится в secure storage; на сервере — только SHA-256 токена. Пароли — bcrypt cost 12.

Структура: `apps/mobile`, `services/api`, `docs`, `infra`. [API](docs/API.md), [архитектура](docs/ARCHITECTURE.md), [развёртывание](docs/DEPLOYMENT.md).
