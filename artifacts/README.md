# Проверочные Android-сборки — 0.1.0+1

Собраны локально 2026-11-05. Это debug APK для проверки приложения с локальным сервером. Публичный сервер не развёрнут. APK находятся в рабочей папке и исключены из Git; для переноса передавайте их отдельно.

| Файл | API_URL | Назначение |
| --- | --- | --- |
| [savdoyordam-0.1.0-usb-debug.apk](savdoyordam-0.1.0-usb-debug.apk) | `http://127.0.0.1:8080` | Телефон с USB-пробросом порта |
| [savdoyordam-0.1.0-emulator-debug.apk](savdoyordam-0.1.0-emulator-debug.apk) | `http://10.0.2.2:8080` | Android Emulator |

Android 7.0+ (minSdk 24), targetSdk 36. Архитектуры arm64-v8a, armeabi-v7a, x86_64. Package ID `uz.savdoyordam.savdoyordam`. Оба файла устанавливают одно приложение; `adb install -r` заменяет вариант, сохраняя данные при совместимой подписи. Не удаляйте приложение с неотправленными операциями: удаление стирает локальную очередь.

## Телефон по USB

1. Запустите PostgreSQL, миграции и API на компьютере по [README](../README.md); проверьте `http://127.0.0.1:8080/health/ready`.
2. Включите USB debugging на телефоне, подключите его и подтвердите доступ компьютера.
3. Из корня проекта выполните:

```sh
adb devices -l
adb install -r artifacts/savdoyordam-0.1.0-usb-debug.apk
adb reverse tcp:8080 tcp:8080
adb shell am start -n uz.savdoyordam.savdoyordam/.MainActivity
```

Для нескольких подключённых устройств добавьте `-s SERIAL` после `adb`. После переподключения USB может потребоваться повторить `adb reverse`. Этот вариант требует соединения с компьютером; адрес отдельного HTTPS-сервера задаётся при пересборке через `--dart-define=API_URL=https://...`.

Для эмулятора установите emulator APK; проброс `adb reverse` ему не нужен. Создайте свой аккаунт и магазин: готовых учётных записей в приложении нет.

## Что проверено

- Обе команды `flutter build apk --debug` завершились успешно (USB-вариант — с API_URL).
- `apksigner verify --verbose`: корректная debug-подпись APK Signature Scheme v2.
- `zipalign -c -P 16 4`: успешно для обоих APK.
- CRC всех записей ZIP, наличие Flutter/JNI/SQLite, Noto Sans, uz/ru ресурсов и соответствующего API_URL в скомпилированном Dart проверены.
- Основной манифест запрещает Android backup; HTTP разрешён только в debug-манифесте.
- Контрольные суммы: [SHA256SUMS](SHA256SUMS). Проверка из этой папки: `sha256sum -c SHA256SUMS`.

Устройства и эмуляторы к ADB не подключены: установка и запуск Android, работа Keystore и поведение при принудительном завершении на телефоне ещё не проверены. Сценарий проверки — [TEST_PLAN](../docs/TEST_PLAN.md). Эти debug APK не являются коммерческим release; ограничения — [KNOWN_LIMITATIONS](../docs/KNOWN_LIMITATIONS.md).
