# API v1

Машиночитаемый контракт: [openapi.json](openapi.json), OpenAPI 3.1. Все тела JSON, ошибки `{ "error": "machine_code" }`. Пользовательский текст локализуется мобильным клиентом.

Регистрация `POST /v1/auth/register` принимает email/password (12–72 байта на сервере); вход — `/v1/auth/login`; выход — `/v1/auth/logout`. Заголовок `Authorization: Bearer <opaque token>`. Email не подтверждается провайдером; восстановление забытого пароля через почту пока отсутствует. Смена известного пароля реализована.

`GET /v1/stores` возвращает доступные магазины и роль. `POST /v1/stores` требует клиентский UUID `id` и `name`; повтор того же владельца и имени безопасен. Другой владелец не может присвоить этот UUID.

Все пути ниже имеют префикс `/v1/stores/{store}`:

| Метод и путь | Правило |
|---|---|
| GET/POST /products | Список / создание (owner) |
| POST /products/{product} | Название, SKU, цена, себестоимость и минимальный остаток, с version (owner) |
| POST /inventory | Изменение остатка с reason и version (owner) |
| GET /inventory/{product} | История движения |
| GET/POST /customers | Клиенты / создание |
| GET /customers/{customer}/ledger | История долга |
| GET/POST /sales | История / атомарное проведение |
| GET /sales/{sale} | Снимки строк продажи |
| POST /sales/{sale}/payments | Погашение остатка долга |
| POST /sales/{sale}/return | Частичный/полный возврат с причиной (owner) |
| GET/POST /expenses | Расходы / создание (owner) |
| GET /dashboard, /reports | Одинаковые агрегаты, from/to включительно, до 366 дней |

POST магазинам требует UUID `Idempotency-Key`. Ответы новых и повторных команд — 200; повтор содержит `Idempotency-Replayed: true`. Ключ общий для команд одного магазина, проверяются путь, каноническое типизированное тело и автор. При 5xx/таймауте всегда повторять **тот же** ключ и тело. При 409 изучить код: insufficient_stock, price_changed, overpayment, sale_returned, version_conflict, idempotency_conflict или data_conflict.

Списки принимают limit (1–200, default 100), offset. Каталог/клиенты — q; продажи — customer_id. Клиент загружает полный каталог страницами. Сервер не возвращает total count. Неизвестный/чужой магазин — 404. Неверная роль — 403. Rate limit auth: 12 запросов/минуту на сетевой IP в одном процессе; forwarded headers не считаются доверенными.

Пример продажи 1.5 кг по 12 000 UZS с оплатой 5 000 UZS:

```json
{
  "customer_id": "00000000-0000-4000-8000-000000000001",
  "paid": 500000,
  "method": "cash",
  "items": [{
    "product_id": "00000000-0000-4000-8000-000000000002",
    "quantity": 1500,
    "expected_price": 1200000
  }]
}
```

В реальном запросе UUID берутся из ответов API. Итог 1 800 000 tiyin, долг 1 300 000 tiyin. Никаких sample-данных сервер не создаёт автоматически.

## Дополнения 0.2

Точный актуальный контракт — OpenAPI 0.2.0 (41 путь, 49 операций). Создание магазина принимает retail_type. Каталог включает category/archived; `?archived=true` добавляет архивные товары. SaleLineInput поддерживает discount только владельца. Возврат принимает items с product_id/quantity; отсутствие items означает весь остаток продажи, явный пустой список запрещён. Sale возвращает returned_total, detail — returned_quantity/discount/unit.

Новые пути магазина: members, invitations/accept/revoke, purchases и detail, offline/status/enable/disable, settings, analytics, export, audit, customer payments и expense void, notifications/register/unregister. Глобальные auth/password, auth/sessions, auth/sessions/revoke и auth/delete работают под текущей сессией. Принятие приглашения — `/v1/invitations/accept`, код привязан к email и сроку 7 дней.

Для подготовленной офлайн-продажи: X-Device-ID, X-Offline-Lease, occurred_at. Для явного ручного решения после истечения — X-Offline-Resolution с основанием владельца, при тех же UUID/теле. Правила — OFFLINE_SYNC.md.

Push-регистрация — idempotent upsert по actor/device/store, без финансового outbox/Idempotency-Key. Пароли передаются напрямую под TLS, не через локальную очередь. Удаление аккаунта требует пароль и confirm=DELETE; блокируется при сотрудниках/действующем офлайн-разрешении собственных магазинов. Финансовые журналы при этом не стираются.
