## Why

`package:logging` — фактический стандарт логирования в экосистеме Dart: через него пишут драйверы баз данных, генераторы, HTTP-стеки и множество прикладных библиотек. Только в зависимостях `structured_log_server` его используют `postgres` и `sqlite3`. Записи `package:logging` никуда не попадают сами: их видит только тот, кто подписался на `Logger.root.onRecord`, и обычно это `print` в `main`. Поэтому они не доходят ни до встроенного просмотрщика (`structured_log_flutter` и скины), ни до `structured_log_server` через `structured_log_remote_sync`, ни до фильтрации по уровню и категории в sink'ах `structured_log`. Мост, переводящий `LogRecord` в запись `structured_log`, подключает весь этот поток к уже настроенным выводам одной строкой и без правок в чужом коде.

## What Changes

- Новый пакет `emb/structured_log_logging/` с `StructuredLogLoggingBridge`: подписка на `onRecord` логгера `package:logging` (по умолчанию `Logger.root`). Каждая `LogRecord` даёт одну запись `structured_log`: сообщение становится `event`, имя логгера становится `logger`, `category` по умолчанию `logging`, уровень сопоставляется по числовому значению `Level`. `error` и `stackTrace` передаются ядру как есть, поэтому поля `error`/`error_type`/`stack_trace` получаются те же, что у `BoundLogger.error`.
- Настройка: функция сопоставления уровней (`levelOf`), фильтр записей (`filter`), категория (`category`, `null` убирает поле), дополнительный контекст из записи (`context` — например, id запроса из `Zone`). Методы `attach()`/`detach()` идемпотентны.
- Защита от рекурсии: запись, пришедшая из `package:logging`, пока мост сам доставляет предыдущую (sink или процессор снова пишет в `package:logging`), отбрасывается, а не зацикливает вызов.
- Регистрация в `melos.yaml` (`packages:` и скоуп `test:dart`), отдельная CI-джоба `logging-bridge` и порог покрытия в `tool/coverage_floors.json`.
- Документация: `README.md`/`README.ru.md` пакета, раздел «Related packages»/«Связанные пакеты» во всех остальных живых пакетах `emb/`, корневые README, `AGENTS.md`, `docs/guides/embedding-guide.md`/`.ru.md`, оглавление пакетов и главная страница сайта.
- Вне рамок:
  - обратное направление (вывод `structured_log` в `package:logging`);
  - публикация на pub.dev (делается отдельно через `melos version`/`melos publish`);
  - перевод `structured_log_server` на мост (отдельной заявкой, после выхода пакета).

## Capabilities

### New Capabilities
- `logging-bridge`: мост, превращающий записи `package:logging` (`LogRecord`) в записи `structured_log` с сопоставлением уровней, категорией, ошибкой и стеком, без рекурсии и без исключений в вызывающем коде.

### Modified Capabilities
(нет)

## Impact

- Новый пакет `emb/structured_log_logging/` (`publish_to` не задан, версия `0.1.0-dev.0`). Зависимости: `logging: ^1.2.0` и `structured_log: ^0.3.0`. Пакет чистый Dart и собирается под web.
- Меняются `melos.yaml`, `.github/workflows/ci.yml` (новая джоба) и `tool/coverage_floors.json`.
- В README одиннадцати живых пакетов `emb/` (22 файла) появляется строка о новом пакете в разделе «Related packages». Код остальных пакетов не меняется.
