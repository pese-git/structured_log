# structured_log_riverpod

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

**Создание, обновление, сбой и удаление каждого провайдера Riverpod попадают
в лог структурированными записями — хватает одной строки настройки.**

Документация: [structured-log.openidealab.com](https://structured-log.openidealab.com/ru/).

## Зачем

«Почему этот экран пустой?» — вопрос, который в приложении на Riverpod
возникает постоянно, и ответ обычно один: провайдер упал или так и не получил
ожидаемое значение. Без записей остаётся воспроизводить ошибку под отладчиком
или писать `ProviderObserver` с `print`, а на устройстве пользователя нельзя
ни то, ни другое.

`StructuredLogRiverpodObserver` ведёт эти записи за вас. Его передают
контейнеру один раз, и он пишет создание, обновления, сбои и удаление каждого
провайдера записями `structured_log`. Имя провайдера, аргумент семейства и
задействованные значения лежат в отдельных полях, так что историю одного
провайдера легко выделить среди остальных записей.

## Возможности

### Охват

- **Подключение одной строкой** —
  `ProviderScope(observers: [StructuredLogRiverpodObserver()])`.
- **Вся жизнь провайдера** — создание, обновления, сбои со стеком, удаление.
- **Провайдеры различимы** — по `name`, а без имени по типу; аргумент семейства
  лежит в отдельном поле.
- **Каждый сбой — один раз** — Riverpod сообщает об упавшем future дважды: как
  обновление до `AsyncError` и как сбой. Наблюдатель пишет сбой и пропускает
  обновление.
- **Работает с `flutter_riverpod` и `hooks_riverpod` как есть** — зависит
  только от `package:riverpod`, на котором построены оба, поэтому работает и в
  чистом Dart.

### Управление

- **Своя категория** — у каждой записи `category: 'riverpod'`, так что
  `LogSink` может направлять записи провайдеров отдельно, а встроенный
  просмотрщик логов предлагает её как фильтр.
- **Свой уровень на каждый хук** — или `null`, чтобы хук выключить; чаще всего
  это обновления.
- **Фильтр** — шумные провайдеры можно вовсе не пускать в лог.
- **Значения под вашим контролем** — значения и аргументы семейства проходят
  через заменяемую функцию описания: так секреты не попадут в лог, а
  `redactKeys` получит карту вместо строки.

### Надёжность

- **Никогда не ломает провайдер** — если `toString()` или функция описания
  выбросят исключение, запись лишится значений; если исключение выбросит
  фильтр, записи не будет вовсе. Код, который менял состояние, не узнает ни о
  том, ни о другом.
- **Выключенное не тратит ресурсов** — для выключенного хука, отфильтрованного
  провайдера или уровня, который не принимает ни один вывод, значение не
  описывается вовсе.

## Место в проекте

Наблюдателю не нужно ничего, кроме
[`structured_log`](https://pub.dev/packages/structured_log), — ни сервера,
ни Flutter. Его записи уходят в те выводы, которые вы настроили: в консоль,
в файл, во встроенный просмотрщик логов
([`structured_log_material`](https://pub.dev/packages/structured_log_material),
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) или
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino)),
где категория `riverpod` становится фильтром, или на self-hosted
`structured_log_server` через
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync).
Это один из восьми адаптеров, которые пишут в лог то, что библиотеки
приложения и так делают; проект целиком — на
[structured-log.openidealab.com](https://structured-log.openidealab.com/ru/).

## Установка

**Только Riverpod 3.** У хуков наблюдателя в Riverpod 2.x другие сигнатуры, и
один класс не может переопределить оба варианта; с 2.x этот пакет не
работает.

Пока не опубликован на pub.dev (`0.1.0-dev.0`), поэтому подключайте его из
git:

```yaml
dependencies:
  flutter_riverpod: ^3.0.0 # или riverpod: ^3.0.0
  structured_log: ^0.3.0
  structured_log_riverpod:
    git:
      url: https://github.com/pese-git/structured_log.git
      path: emb/structured_log_riverpod
```

## Быстрый старт

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_riverpod/structured_log_riverpod.dart';

void main() {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );

  runApp(
    ProviderScope(
      observers: [StructuredLogRiverpodObserver()],
      child: const MyApp(),
    ),
  );
}
```

В чистом Dart тот же наблюдатель передают контейнеру:
`ProviderContainer(observers: [StructuredLogRiverpodObserver()])`.

Именованный провайдер `counter`, который прочитали и затем установили в `1`,
пишет:

```text
[2026-10-13T22:27:13.862226Z] DEBUG: provider_added {"logger":"riverpod","category":"riverpod","provider":"counter","value":"0","value_type":"int"}
[2026-10-13T22:27:13.875054Z] DEBUG: provider_updated {"logger":"riverpod","category":"riverpod","provider":"counter","previous_value":"0","value":"1","value_type":"int"}
```

Упавший `FutureProvider` с именем `profile` пишет один раз, как ошибку:

```text
[2026-10-13T22:27:13.884681Z] ERROR: provider_failed {"logger":"riverpod","category":"riverpod","provider":"profile","error":"Bad state: offline","error_type":"StateError","stack_trace":"#0 ..."}
```

Запускаемая версия — [example/main.dart](example/main.dart)
(`dart run example/main.dart`).

## Что пишется в лог

У каждой записи есть `category` (по умолчанию `riverpod`), `logger` (по
умолчанию `riverpod`) и `provider` — `name` провайдера, а если имени нет, его
тип. У семейства аргумент лежит в `provider_argument`.

| Хук                  | `event`             | Уровень по умолчанию | Поля |
|----------------------|---------------------|----------------------|------|
| `didAddProvider`     | `provider_added`    | `debug`              | `value`, `value_type` |
| `didUpdateProvider`  | `provider_updated`  | `debug`              | `previous_value`, `value`, `value_type` |
| `providerDidFail`    | `provider_failed`   | `error`              | `error`, `error_type`, `stack_trace` |
| `didUnmountProvider` | `provider_disposed` | `debug`              | — |

Провайдер, который бросил при построении, пишется как `provider_added` без
`value` и с `value_type: Null`, затем как `provider_failed`.

`provider_disposed` пишется, когда провайдер **удалён из памяти**, например
когда `autoDispose`-провайдер потерял последнего слушателя. Провайдер, который
просто перестроился (изменилась зависимость, `refresh`, `invalidate`), не
удалён, и записи с таким именем он не пишет. Хук, на котором это держится,
`didUnmountProvider`, есть в `riverpod` начиная с **3.3.2**: на 3.0.0–3.2.1
эта запись не пишется вовсе, и ничто об этом не предупредит. Остальные три
записи одинаковы на любой 3.x. Если `provider_disposed` вам нужен,
подключайте `riverpod: ^3.3.2`.

Мутации (`mutationStart` и другие, новое в Riverpod 3) не пишутся: их API
помечен экспериментальным.

## Как не пустить секреты в лог

**Значения и аргументы семейства по умолчанию пишутся через `toString()`**
(обрезанному до 1000 символов). Если в них могут оказаться пароли, токены или
персональные данные — и особенно если лог уходит с устройства через
`structured_log_remote_sync`, — передайте `describe`, который их скроет.
Возврат `null` убирает значение, но оставляет его тип:

```dart
StructuredLogRiverpodObserver(
  describe: (value) => switch (value) {
    Session() || Credentials() => null,
    _ => describeRiverpodValue(value),
  },
)
```

Та же `describe` видит и аргумент семейства — часто это id пользователя или
токен, — так что одна функция закрывает оба случая. Чтобы везде писать только
типы: `describe: (_) => null`.

`describe` может вернуть и **карту** вместо строки. Карта остаётся в записи
структурой, поэтому процессор `redactKeys` доберётся до её полей так же, как
до любых других. Строка из `toString()` для него непрозрачна:

```dart
StructlogConfiguration.configure(processors: [redactKeys(), dropNullValues]);

StructuredLogRiverpodObserver(
  describe: (value) => switch (value) {
    Session(:final user, :final token) => {'user': user, 'token': token},
    _ => describeRiverpodValue(value),
  },
)
// value: {"user": "u", "token": "***"}
```

Ошибка в `provider_failed` через `describe` не проходит: её пишет сам
`structured_log` — как `error`, `error_type` и `stack_trace`.

## Настройка

```dart
StructuredLogRiverpodObserver(
  // Какие хуки писать и с каким уровнем; null выключает.
  levels: const RiverpodLogLevels(
    added: LogLevel.trace,
    updated: null, // провайдер, привязанный к полю ввода, обновляется постоянно
  ),
  // Шумные провайдеры — мимо лога.
  filter: (provider) => provider.name != 'ticker',
  category: 'state',
)
```

## Справочник API

| Символ | Описание |
|---|---|
| `StructuredLogRiverpodObserver({logger, loggerName, category, levels, describe, filter})` | Наблюдатель, `final class` — наследник `ProviderObserver`. Без `logger` вызывает `getLogger(loggerName)` на каждом хуке, поэтому до него доходит и более поздний `StructlogConfiguration.configure`. `category: null` не привязывает категорию. |
| `RiverpodLogLevels({added, updated, failed, disposed})` | `LogLevel?` на каждый хук; `null` выключает хук. |
| `RiverpodValueDescriber` | `Object? Function(Object? value)` — превращает значение или аргумент семейства в значение записи; `null` опускает поле. |
| `describeRiverpodValue(value)` | Описание по умолчанию: `toString()`, обрезанный до `defaultRiverpodValueMaxLength` (1000) символов; бросивший `toString()` превращается в заглушку. |

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
- [`structured_log_drift`](https://pub.dev/packages/structured_log_drift) — `QueryInterceptor` для drift, логирующий запросы, сбои и транзакции
- [`structured_log_logging`](https://pub.dev/packages/structured_log_logging) — мост, передающий записи `package:logging` в `structured_log`

## Лицензия

MIT — см. [LICENSE](LICENSE).
