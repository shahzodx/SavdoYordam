# Проверка внешнего вида

`dashboard_uz.png` и `dashboard_ru.png` получены из настоящих Flutter widgets тестом `navigation_test.dart` на размере 390 × 844 с локальным Noto Sans. Значения — **явные UI-test fixtures**, не production-данные и не измеренные продажи.

Обновление:

```sh
cd apps/mobile
flutter test test/navigation_test.dart --dart-define=CAPTURE_PREVIEWS=true
```

Тест также проходит пять вкладок, открывает POS, возвращается назад и открывает настройки в обеих локализациях. Эти изображения не заменяют проверку на физическом Android.
