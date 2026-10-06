# structured_log_drift

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

**Каждый запрос к базе drift — его SQL, длительность, результат и причина
падения — попадает в лог структурированной записью. Хватает одной строки
настройки, а значения аргументов в лог не утекают.**

Документация: [structured-log.openidealab.com](https://structured-log.openidealab.com/ru/).

## Зачем

Экран, который подвис или пришёл пустым, часто означает медленный или
упавший запрос, а в логе об этом ничего нет. Встроенный в drift
`logStatements: true` печатает каждый запрос через `print` *вместе со
значениями аргументов*: хэши паролей, токены и личные данные уходят в
консоль, причём без уровня, длительности и ошибки. Поэтому в продакшене его
выключают, и запросы остаются невидимыми.

`StructuredLogDriftInterceptor` — это `QueryInterceptor` для drift. Его один
раз передают в `interceptWith`, и он пишет каждый запрос, пакет, сбой и
завершение транзакции записями `structured_log`: вид запроса, SQL,
длительность, сколько строк вернулось или изменилось. Медленные запросы
выделяются. Значения аргументов не пишутся, пока вы сами их не включите.

## Возможности

### Охват

- **Подключение одной строкой** — `NativeDatabase(file).interceptWith(StructuredLogDriftInterceptor())`.
- **Все запросы** — `select`, `insert`, `update`, `delete` и произвольные
  операторы, с полями `rows`, `affected_rows` или `insert_id`.
- **Осмысленная длительность** — `duration_ms` хранит точность до
  микросекунд: запрос к локальной базе обычно короче миллисекунды.
- **Медленные запросы выделены** — от порога (по умолчанию 500 мс) запрос
  пишется уровнем `warning` с `slow: true`.
- **Пакет — одной записью** — `batch` даёт один `db_batch`, а не запись на
  каждый оператор.
- **Сбои со стеком** — а исключение доходит до вашего кода ровно таким, каким
  его выбросил drift.
- **Транзакции** — коммиты и откаты, вложенные замеряются отдельно.
- **Любой исполнитель** — native, web, изолят: это штатный шов самого drift.

### Управление

- **Своя категория** — у каждой записи `category: 'db'`, так что `LogSink`
  может направлять записи базы отдельно, а встроенный просмотрщик логов
  предлагает её как фильтр.
- **Свой уровень на каждый вид записи** — или `null`, чтобы его выключить.
- **Фильтр** — по виду и тексту запроса, чтобы убрать `PRAGMA` или таблицу.

### Надёжность

- **По умолчанию без значений аргументов** — ни в записи, ни в тексте ошибки
  (см. ниже).
- **Никогда не меняет запрос** — сбой логирования стоит записи, но не
  результата и не исключения запроса.
- **Выключенное почти ничего не стоит** — запись, которую не примет ни один
  sink, не собирается.

## Место в проекте

Перехватчику не нужно ничего, кроме
[`structured_log`](https://pub.dev/packages/structured_log), — ни сервера,
ни Flutter. Его записи уходят в те выводы, которые вы настроили: в консоль,
в файл, во встроенный просмотрщик логов
([`structured_log_material`](https://pub.dev/packages/structured_log_material),
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) или
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino)),
где категория `db` становится фильтром, или на self-hosted
`structured_log_server` через
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync).
Это один из шести адаптеров, которые пишут в лог то, что библиотеки
приложения и так делают; проект целиком — на
[structured-log.openidealab.com](https://structured-log.openidealab.com/ru/).

## Установка

Пакет ещё не опубликован на pub.dev (`0.1.0-dev.0`), поэтому пока
подключайте его из git. Нужен drift 2.14.0 или новее — в нём появился
`QueryInterceptor`:

```yaml
dependencies:
  drift: ^2.14.0
  structured_log: ^0.3.0
  structured_log_drift:
    git:
      url: https://github.com/pese-git/structured_log.git
      path: emb/structured_log_drift
```

## Быстрый старт

```dart
import 'package:drift/native.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_drift/structured_log_drift.dart';

void main() {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );

  final db = AppDatabase(
    NativeDatabase(file).interceptWith(StructuredLogDriftInterceptor()),
  );
  // ...
}
```

Тот же `interceptWith` работает с любым `QueryExecutor` или
`DatabaseConnection` — с `WasmDatabase` на web или с соединением
`DriftIsolate`.

Вставка с токеном в аргументе, пакет из двух вставок, выборка и упавшая
транзакция дают такие записи (время убрано, ошибка и стек сокращены):

```text
{"logger":"drift","category":"db","kind":"insert","statement":"INSERT INTO users (name, token) VALUES (?, ?)","duration_ms":1.796,"insert_id":1,"event":"db_query","level":"debug"}
{"logger":"drift","category":"db","statement_count":1,"execution_count":2,"duration_ms":0.491,"event":"db_batch","level":"debug"}
{"logger":"drift","category":"db","kind":"select","statement":"SELECT * FROM users","duration_ms":1.525,"rows":3,"event":"db_query","level":"debug"}
{"logger":"drift","category":"db","kind":"custom","statement":"INSERT INTO missing VALUES (1)","duration_ms":2.476,"error":"SqliteException(1): while executing, no such table: missing, …","error_type":"SqliteException","stack_trace":"…","event":"db_query_failed","level":"error"}
{"logger":"drift","category":"db","duration_ms":4.853,"event":"db_transaction_rolled_back","level":"warning"}
```

Рабочая версия — в [example/main.dart](example/main.dart)
(`dart run example/main.dart`).

## Что пишется в лог

У каждой записи есть `category` (по умолчанию `db`) и `logger` (по умолчанию
`drift`).

| `event` | Когда | Уровень по умолчанию | Поля |
|---|---|---|---|
| `db_query` | выполнен запрос | `debug`; `warning`, если медленный | `kind`, `statement`, `duration_ms`; `rows` (select), `affected_rows` (update, delete), `insert_id` (insert); `slow: true`, если медленный; `arguments`, если включены |
| `db_batch` | выполнен пакет | `debug`; `warning`, если медленный | `statement_count` (различных операторов), `execution_count`, `duration_ms`; `slow: true`, если медленный |
| `db_query_failed` | запрос или пакет выбросил исключение | `error` | `kind` (`batch` для пакета), `statement`, `duration_ms`, `error`, `error_type`, `stack_trace` |
| `db_transaction_committed` | транзакция зафиксирована | `trace` | `duration_ms` с начала транзакции |
| `db_transaction_rolled_back` | транзакция откачена | `warning` | `duration_ms` с начала транзакции |

`kind` — одно из `select`, `insert`, `update`, `delete`, `custom`.
`statement` обрезается до 2000 символов.

Каждый `batch` drift выполняет в своей транзакции, поэтому за пакетом идёт
`db_transaction_committed`. Коммиты пишутся уровнем `trace`, который sink с
`minLevel` по умолчанию (`debug`) отсекает, — так пакет не попадает в лог
дважды. Чтобы видеть коммиты, понизьте `minLevel` у sink'а.

Что **не** пишется: миграции. drift выполняет их на исполнителе под
перехватчиком, до открытия базы. Упавшая миграция видна как исключение при
открытии.

## Как не пустить секреты в лог

Запросы, которые строит drift, содержат плейсхолдеры (`?`, `$1`), а не
значения, и **значения аргументов по умолчанию не пишутся**. Именно в них
хэши паролей, токены и личные данные.

Аргументы утекли бы и через ошибку: `sqlite3` заканчивает текст исключения
всеми параметрами упавшего оператора, а нарушение уникальности в PostgreSQL
цитирует повторившееся значение. Поэтому, пока аргументы выключены,
перехватчик пишет `error` сам и очищает его текст:

- дописанное `sqlite3` `parameters: …` становится `parameters: <hidden>`;
- каждый строковый аргумент от 4 символов заменяется на `<argument>`, где бы
  он ни встретился. Строки короче, числа, даты и двоичные данные не
  трогаются: замена каждой `1` испортила бы сообщение.

Чтобы всё же писать аргументы, передайте `logArguments: true`: строки
обрезаются до 1000 символов, двоичные данные пишутся как `<N bytes>`.
Аргументы пакета не пишутся никогда — наборов могут быть тысячи.

Внутрь SQL, написанного вручную со значениями прямо в тексте, перехватчик не
заглядывает: например, `customStatement("UPDATE users SET token = 'abc'")`.
Используйте переменные или отсекайте такие запросы через `filter`.

## Настройка

```dart
StructuredLogDriftInterceptor(
  // Какие записи пишутся и каким уровнем; null выключает.
  levels: const DriftLogLevels(
    query: LogLevel.trace,
    committed: null,
  ),
  // С какой длительности запрос медленный; null — никогда.
  slowQueryThreshold: const Duration(milliseconds: 200),
  // Убрать служебные запросы drift и чувствительную таблицу.
  filter: (kind, statement) =>
      !statement.startsWith('PRAGMA') && !statement.contains('sessions'),
  // По умолчанию выключено; см. выше.
  logArguments: false,
  category: 'storage',
);
```

Поток из `watch()` перезапускает свой запрос при каждом изменении таблиц, и
каждый перезапуск — это `db_query`. Если записей слишком много, понизьте
`query` до `trace` или отфильтруйте запрос: медленные запросы и сбои
останутся видны.

С `DriftIsolate` перехватчик работает там, где вызван `interceptWith`, —
обычно на стороне, которая отправляет запросы. Тогда `duration_ms` включает
дорогу до изолята, то есть то, сколько ждал ваш код.

## Справочник API

| Символ | Описание |
|---|---|
| `StructuredLogDriftInterceptor({logger, loggerName, category, levels, slowQueryThreshold, logArguments, filter})` | Перехватчик; передаётся в `interceptWith`. Без `logger` на каждой записи вызывает `getLogger(loggerName)`. `category: null` — без категории. |
| `DriftLogLevels({query, batch, slow, failed, committed, rolledBack})` | `LogLevel?` на каждый вид записи; `null` выключает его. |
| `defaultStatementMaxLength` | 2000 — самый длинный записываемый `statement`. |
| `defaultArgumentMaxLength` | 1000 — самый длинный записываемый строковый аргумент при включённом `logArguments`. |

## Связанные пакеты

Остальные пакеты семейства `structured_log`:

**Ядро**

- [`structured_log`](https://pub.dev/packages/structured_log) — структурированное JSON-логирование с привязкой контекста, процессорами и маршрутизацией по синкам

**Просмотрщик логов в приложении**

- [`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter) — headless-ядро просмотрщика: `LogBuffer` и `LogViewerController`
- [`structured_log_material`](https://pub.dev/packages/structured_log_material) — просмотрщик на Material 3
- [`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) — просмотрщик на Fluent UI (в стиле WinUI)
- [`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino) — просмотрщик на Cupertino (в стиле iOS)

**Доставка логов на сервер**

- [`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync) — синк с батчингом и повторами для self-hosted `structured_log_server`

**Интеграции**

- [`structured_log_bloc`](https://pub.dev/packages/structured_log_bloc) — `BlocObserver` для `bloc`/`flutter_bloc`
- [`structured_log_dio`](https://pub.dev/packages/structured_log_dio) — перехватчик `dio`, логирующий HTTP-вызовы
- [`structured_log_http_client`](https://pub.dev/packages/structured_log_http_client) — обёртка клиента `package:http`, логирующая HTTP-вызовы
- [`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router) — логирует навигацию `go_router`
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — наблюдатель DI-контейнера `cherrypick`

## Лицензия

MIT — см. [LICENSE](LICENSE).
