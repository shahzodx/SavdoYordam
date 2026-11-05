# Подготовленные внешние подключения

Облачные аккаунты и публичный сервер у основателя пока отсутствуют. Код подготовлен; Firebase и Sentry не включены в текущей локальной конфигурации. Создание аккаунтов, публикация и платные услуги не выполнялись.

## Firebase Cloud Messaging

Android использует Firebase BoM 35.1.0 и firebase-messaging, без Analytics. Автоматическая регистрация выключена в манифесте. Инициализация происходит только с полной конфигурацией проекта и после включения уведомлений пользователем. Android запрашивает разрешение POST_NOTIFICATIONS. Без Firebase работают локальные напоминания об остатках при открытии приложения.

1. Создать свой Firebase-проект и зарегистрировать Android-приложение `uz.savdoyordam.savdoyordam`.
2. Для сборки передать публичные значения конфигурации Firebase:

```sh
export FIREBASE_PROJECT_ID='your-project-id'
export FIREBASE_APP_ID='your-android-app-id'
export FIREBASE_API_KEY='your-public-android-api-key'
export FIREBASE_SENDER_ID='your-messaging-sender-id'
cd apps/mobile
flutter build apk --debug --dart-define=API_URL=https://your-api-domain
```

Это публичная конфигурация Android-приложения. **Приватный service-account JSON никогда не входит в APK, Git или пользовательские экспорты.** Ограничения API key/приложения и доступ к проекту настраивает оператор.

3. Для API включить Cloud Messaging API проекта и выдать серверному сервисному аккаунту минимальное право отправки FCM. Сохранить его ключ вне репозитория, с закрытыми правами, подключить в контейнер read-only secret mount.

```sh
FCM_ENABLED=true
GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/firebase-service-account.json
```

`internal/notifications` получает короткоживущий OAuth2-токен официальной библиотекой `golang.org/x/oauth2/jwt` и использует FCM HTTP v1. При отсутствии конфигурации worker отключён. Некорректная конфигурация не подменяется тестовым провайдером.

Приложение регистрирует токен через авторизованный `/notifications/register`. Worker раз в 5 минут проверяет реальные низкие остатки, текущую membership и архивность магазина. Не чаще одного напоминания на устройство/магазин за 6 часов; PostgreSQL advisory lock координирует несколько экземпляров API. UNREGISTERED-токены удаляются. Регистрации старше 30 дней очищаются. Сообщение общее: без сумм, имён клиентов и состава покупок. Отзыв доступа исключает устройство из выборки. Выход отзывает регистрации данного устройства; отключение уведомлений немедленно запрещает нативное отображение и удаляет FCM-токен.

**Что проверено:** формат HTTP v1 и обработка UNREGISTERED — unit-тест с локальным HTTP-сервером; Android SDK должен пройти сборку вместе с приложением. Реальная доставка через Firebase, фон, Doze, переустановка и обновление токена на телефоне требуют собственного проекта и отдельного прогона. Доставка зависит от Android/Google Play services и сети; это не механизм подтверждения продаж.

Официальные источники: [Android setup и BoM](https://firebase.google.com/docs/android/setup), [FCM HTTP v1 и авторизация](https://firebase.google.com/docs/cloud-messaging/send/v1-api).

## Sentry

Серверный SDK `sentry-go` 0.50.0 включается только при заданном `SENTRY_DSN`. Без DSN внешней отправки нет. События HTTP 5xx содержат общий текст, method, route pattern и request_id. BeforeSend удаляет Request, User, Contexts, Breadcrumbs и Exception. Тела запросов, cookies, bearer-токены, email, пароли и финансовые суммы не отправляются.

```sh
APP_ENV=pilot
SENTRY_DSN=https://your-public-key@your-sentry-host/your-project
```

DSN задаётся окружением сервера. Приватные ключи и project tokens не добавляются в исходники. Включение и реальную доставку события нужно проверить в собственном проекте, согласовав обработку данных. Мониторинг ошибок не заменяет readiness, метрики PostgreSQL, контроль диска и проверяемые backups.

## Публичный сервер

Подготовлены Docker Compose, Caddyfile, миграции, health checks и backup/restore scripts. Для публичного размещения нужны выбранный хост, домен, TLS, отдельные runtime/migration DB-роли и secret storage. Последовательность — [DEPLOYMENT](DEPLOYMENT.md). Внешнее развёртывание и DNS в этой сессии не выполнялись.
