# Журнал реализации — 2026-11-05

## Исходное состояние

Рабочая папка не содержала исходников. Существующие `.git`, `.agents`, `.codex`, `.aws` представлены read-only mount; рабочий Git repository недоступен, commits не создавались. Оригинальное задание сохранено в ORIGINAL_BRIEF.md.

## Этап 1 — исследование и границы

Добавлены PRODUCT_VISION, PRODUCT_RESEARCH, COMPETITOR_ANALYSIS, UX_FLOWS, DESIGN_SYSTEM. Проверены официальные страницы FinAssist/Adstat/pDaftar, документация Flutter/пакетов/Go-библиотек и LexUZ. Интервью и пользовательских исследований не проводилось. Выбраны email/password, целочисленная модель UZS, серверное подтверждение операций, один магазин в мобильном UI.

## Этап 2 — сервер и модель данных

`services/api`: Chi, pgx, Goose, sqlc, миграция 15 таблиц, JSON logging, health checks. Реализованы сессии, membership, товары/остатки, клиенты, продажи/платежи/долги, полный возврат, расходы, отчёты, аудит и дедупликация. Финансовые журналы защищены от UPDATE/DELETE. OpenAPI — docs/openapi.json.

Запущены unit и PostgreSQL integration tests с `-race`; исходный commerce suite прошёл. Расширенный suite после добавления редактирования товара, проверки логина/истечения сессии и конкурентного replay тоже прошёл: `go test -race ./...`, httpapi 265.192 s в этой среде. Это длительность тестового прогона под нагрузкой сборки, не показатель скорости продукта.

## Этап 3 — Flutter

`apps/mobile`: Flutter 3.47.9, Dart 3.13.7, Riverpod, go_router, Dio, Drift, secure storage, intl, ARB uz/ru, локальный Noto Sans/OFL. Созданы экран входа/регистрации, onboarding, пять вкладок, POS, карточка клиента/продажи/товара, возврат, погашение, расходы и настройки. Durable outbox и корзина переживают перезапуск SQLite; команды привязаны к пользователю и магазину.

Первый прогон: 7 Flutter unit/widget/storage tests прошли. Отдельный реальный тест Repository → Go → PostgreSQL прошёл. В навигационном тесте обнаружен и исправлен ListTile/Material ink issue. Результаты полного заключительного прогона приведены ниже.

## Этап 4 — инфраструктура и восстановление

Добавлены docker-compose.yml, Dockerfile, Makefile, GitHub Actions, пример Caddy, шифрованные backup/restore scripts и restore verification script. В этой среде нет Docker, поэтому контейнеры не запускались. Workflow на GitHub не запускался.

**Выполнен успешный encrypted restore drill:** age-keygen → pg_dump → age → checksum → новая PostgreSQL база → pg_restore. Счётчики sales/payments/debt_entries/inventory_movements/audit_logs совпали. SQL-проверки согласованности stock и отсутствия отрицательных долгов прошли. Тестовые ключи созданы вне репозитория, production secrets не использовались.

## Android и среда

Flutter SDK получен из официального GitHub tag 3.47.9 (download archive вернул 404). Android SDK 36 (дополнительно API 35 для JNI)/build-tools 36/platform-tools/NDK r28c/CMake 3.22.1 получены по официальному repository XML с проверкой SHA-1 архивов. Менеджер SDK не завершил загрузку manifests, использованы проверенные официальные архивы. JDK 25 локальный. Из-за квоты `/tmp` удалены только скачанные task-архивы; Android SDK перенесён в игнорируемую `.tools/android`. Восстановлены символические ссылки NDK, которые при ZIP-распаковке стали текстовыми файлами. Исправлено слияние debug/main-манифестов через tools:replace для usesCleartextTraffic. Требуемые SDK-пакеты явно добавлены в CI workflow; сам workflow не запускался.

## Финальные проверки

Полный Flutter-прогон: **10 тестов прошли**, включая реальный API, навигацию пяти вкладок/POS/настроек в uz/ru, SQLite restart/replay и локализацию. После исправления иконки повторно прошли 2 навигационных теста. Визуальные результаты сохранены в docs/previews (явные test fixtures). **Заключительный Flutter analyze прошёл без замечаний (0 issues)** после исправления двух стилистических замечаний. Backend `go vet ./...` и сборка `go build -buildvcs=false -trimpath` также прошли. Флаг buildvcs=false необходим из-за read-only synthetic .git в этой среде.

**Android APK успешно собраны:** `artifacts/savdoyordam-0.1.0-emulator-debug.apk` и `artifacts/savdoyordam-0.1.0-usb-debug.apk`. MinSdk 24, targetSdk 36, ABI arm64-v8a/armeabi-v7a/x86_64. Для обоих прошли apksigner verify (v2), zipalign с 16 KiB alignment, CRC архивов и проверка соответствующего API_URL. SHA-256 записаны в artifacts/SHA256SUMS. Проверены упакованные JNI/SQLite/Flutter-библиотеки, шрифт и локализации. ADB не обнаружил подключённых устройств: установка и runtime на Android не выполнялись. Инструкции — artifacts/README.md.

Следующий обязательный шаг после локальных проверок: физический Android, UX/accessibility/performance, настройка pilot HTTPS и release signing. Полные ограничения — KNOWN_LIMITATIONS.md.
