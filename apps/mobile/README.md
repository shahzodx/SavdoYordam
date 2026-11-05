# SavdoYordam — Android

Flutter-приложение на узбекском и русском. Запуск сервера, миграции и общий статус описаны в [основном README](../../README.md).

## Разработка

Использован Flutter 3.47.9 / Dart 3.13.7, Android SDK 36, дополнительный SDK 35 для JNI, Build Tools 36.0.0, NDK 28.2.13676358, CMake 3.22.1 и JDK 25. Зависимости закреплены в pubspec.lock.

```sh
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_URL=http://10.0.2.2:8080
```

По умолчанию API_URL указывает на хост Android Emulator. Сервер должен работать на порту 8080. На физическом устройстве по USB:

```sh
adb reverse tcp:8080 tcp:8080
flutter run --dart-define=API_URL=http://127.0.0.1:8080
```

## Сборка

```sh
# Эмулятор
flutter build apk --debug
# Телефон с USB-пробросом порта
flutter build apk --debug --dart-define=API_URL=http://127.0.0.1:8080
```

Результат: `build/app/outputs/flutter-apk/app-debug.apk`. API_URL фиксируется при сборке; для другого сервера приложение нужно пересобрать. Debug допускает HTTP для локальной разработки. Release требует HTTPS и отдельной настройки подписи; коммерческий release пока не подготовлен.

## Проверки

Сквозной тест использует настоящий отдельный тестовый API и оставляет созданные им аккаунт и магазин в тестовой БД:

```sh
flutter test test/api_integration_test.dart --dart-define=API_TEST_URL=http://127.0.0.1:8080
```

Без API_TEST_URL он явно пропускается. Остальные тесты проверяют точные денежные вычисления, SQLite/outbox, локализацию и навигацию. Скриншоты из навигационных тестов используют тестовые данные, см. [previews](../../docs/previews/README.md).
