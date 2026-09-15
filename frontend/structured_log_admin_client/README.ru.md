# structured_log_admin_client

Самостоятельный admin-клиент для
[`structured_log_server`](../../backend/structured_log_server): вход, проекты и
их секретные ключи, просмотрщик логов.

Не публикуется — это приложение, а не библиотека.

## Состояние

Слой данных готов, экранов ещё нет. Разделы 12–14 и 22 change'а
`add-structured-log-server` строят поверх него вход, управление ресурсами и
просмотрщик логов. Запуск сейчас показывает заглушку.

## Архитектура

Послойно внутри каждой фичи — `domain` / `application` / `infrastructure` /
`presentation`, плюс `lib/shared/` для сквозного. Директории появляются вместе
с первым файлом, а не заводятся пустыми.

| Задача | Выбор | Где |
|---|---|---|
| UI-кит | `fluent_ui`, компонуется из `structured_log_admin_ui` | `lib/app/`, `presentation/` фич |
| HTTP | `dio` + `retrofit`; SSE вручную на том же инстансе | `lib/shared/api/` |
| Ожидаемые ошибки | `fpdart` `Either`, но не для программных ошибок | `lib/shared/api/api_failure.dart` |
| Модели | `freezed` + `json_serializable` | `lib/shared/api/dto/` |
| DI | `cherrypick` | `lib/shared/di/` |
| Состояние | `flutter_bloc` | `presentation/` фич |
| Токены | `flutter_secure_storage`, никогда не shared preferences | `lib/shared/auth/` |
| Диагностика | `structured_log` | `lib/shared/logging/` |

### Три инстанса Dio, а не один

Это стоит знать до того, как трогать `ApiClient`:

- основной несёт перехватчик аутентификации — подставляет access-токен и один
  раз обновляет его при 401;
- клиент обновления идёт без перехватчика: refresh, которому ответили 401 на
  основном инстансе, вошёл бы обратно в тот самый перехватчик, который его и
  запустил;
- клиент повтора переигрывает исходный запрос уже с новым токеном.

Токен-эндпоинт исключён не только по флагу, но и по пути: 401 от него означает
неверный пароль или израсходованный refresh-токен, и обновление в ответ на
любое из двух превращает неудачный вход в попытку продлить сессию.

Параллельные 401 делят одно обновление. Без этого каждый запрос тратил бы
refresh-токен, и на сервере, который их ротирует, все кроме первого предъявили
бы только что отозванный.

## Запуск

```bash
flutter run -d chrome --dart-define=STRUCTURED_LOG_BASE_URL=https://logs.example.com
```

Base URL — compile-time define, по умолчанию `http://localhost:8080`.

## Кодогенерация

`*.g.dart` и `*.freezed.dart` не коммитятся:

```bash
dart run build_runner build --delete-conflicting-outputs
```

или `dart run melos run generate` из корня репозитория. В CI шаг идёт до
`analyze`/`test`.

---

English version: [README.md](README.md)
