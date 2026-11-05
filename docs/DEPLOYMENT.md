# Локальная работа и подготовка пилота

Инструкции запуска — в README. Compose поднимает PostgreSQL, отдельный one-shot migrator и API. API опубликован только на loopback. Нет автоматической публикации, платных сервисов или настройки DNS.

Для физического Android по USB: `adb reverse tcp:8080 tcp:8080`, затем debug APK с `--dart-define=API_URL=http://127.0.0.1:8080`. Для Emulator default API_URL — `http://10.0.2.2:8080`. Release использует HTTPS, подпись оператора и реальный endpoint.

Оба debug-варианта 0.1.0+1 собраны и проверены локально: [APK и инструкции установки](../artifacts/README.md). Подпись, целостность и выравнивание проверены; физический Android и emulator runtime ещё не проверялись. API_URL фиксирован внутри каждой сборки.

До пилота: согласовать регион хостинга и обработку данных; установить сертификат (пример Caddyfile); разделить migration/runtime DB credentials; поставить случайные пароли; закрыть порт БД; настроить журналирование/ротацию, мониторинг readiness и 5xx; проверить объём диска, время сервера и timezone отчётов; определить ответственного за recovery.

Резервирование: `infra/backup.sh output.dump.age` требует DATABASE_URL, age и публичный BACKUP_RECIPIENT. Использует pg_dump custom format и шифрует поток. `infra/restore.sh` требует пустую отдельную RESTORE_DATABASE_URL и AGE_IDENTITY. Сначала восстановить в изолированную БД, проверить счётчики и финансовые инварианты, затем планировать переключение. Не восстанавливать поверх работающей production БД. Требуется расписание, удалённое хранилище, политика retention и регулярный restore drill; они не настроены автоматически.

Логи JSON: request_id, метод, status и duration_ms. Liveness `/health/live`; readiness `/health/ready` проверяет PostgreSQL. Внешний Sentry/сборщик метрик пока не подключён, алерты не настроены. Не публиковать внутреннюю observability-инфраструктуру без контроля доступа.

Release signing: хранить keystore и пароли вне репозитория/CI-log, подключать через secret storage. Сейчас release signing отсутствует намеренно; проверочный debug APK не является подписанным коммерческим релизом. GitHub Actions готовит debug artifact; сам workflow ещё не запускался на GitHub.
