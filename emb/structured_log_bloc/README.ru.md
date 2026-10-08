# structured_log_bloc

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

**Каждое событие, смена состояния и ошибка блоков и кубитов приложения
попадают в лог структурированными записями — хватает одной строки
настройки.**

Документация: [structured-log.openidealab.com](https://structured-log.openidealab.com/ru/).

## Зачем

«Почему экран показал *это*?» — вопрос, который в приложении на bloc
возникает постоянно, и чтобы ответить, приходится восстанавливать
случившееся: какое событие пришло, к какому состоянию оно привело, какой
обработчик упал. Без записей остаётся расставлять `print`, воспроизводить
ошибку и убирать их обратно, а на устройстве пользователя нельзя и этого.

`StructuredLogBlocObserver` ведёт эти записи за вас. Его ставят один раз в
`Bloc.observer`, и он пишет создание, события, переходы, ошибки и закрытие
каждого блока и кубита записями `structured_log`. Тип блока, экземпляр и
задействованные значения лежат в отдельных полях, так что историю одного
блока легко выделить среди остальных записей.

## Возможности

### Охват

- **Подключение одной строкой** — `Bloc.observer = StructuredLogBlocObserver()`.
- **Все хуки** — создание, события, переходы, изменения кубитов, ошибки со
  стеком, завершение обработчика, закрытие.
- **Каждая смена состояния — один раз** — у блока она пишется как переход
  (вместе с событием), у кубита — как изменение; никогда не обе сразу.
- **Экземпляры различимы** — по `bloc_instance` различаются два блока одного
  типа.
- **Работает с `flutter_bloc` как есть** — зависит только от `package:bloc`,
  на котором `flutter_bloc` построен, поэтому работает и в чистом Dart.

### Управление

- **Своя категория** — у каждой записи `category: 'bloc'`, так что
  `LogSink` может направлять записи блоков отдельно, а встроенный просмотрщик
  логов предлагает её как фильтр.
- **Свой уровень на каждый хук** — или `null`, чтобы хук выключить.
- **Фильтр** — шумные блоки можно вовсе не пускать в лог.
- **Значения под вашим контролем** — состояния и события проходят через
  заменяемую функцию описания: так секреты не попадут в лог, а `redactKeys`
  получит карту вместо строки.

### Надёжность

- **Никогда не ломает блок** — если `toString()` или функция описания выбросят
  исключение, запись лишится значений; если исключение выбросит фильтр, записи
  не будет вовсе. Блок свой `emit` не потеряет ни в одном из случаев.
- **Выключенное не тратит ресурсов** — для выключенного хука или
  отфильтрованного блока состояние не описывается вовсе.

## Место в проекте

Наблюдателю не нужно ничего, кроме
[`structured_log`](https://pub.dev/packages/structured_log), — ни сервера,
ни Flutter. Его записи уходят в те выводы, которые вы настроили: в консоль,
в файл, во встроенный просмотрщик логов
([`structured_log_material`](https://pub.dev/packages/structured_log_material),
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) или
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino)),
где категория `bloc` становится фильтром, или на self-hosted
`structured_log_server` через
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync).
Это один из шести адаптеров, которые пишут в лог то, что библиотеки
приложения и так делают; проект целиком — на
[structured-log.openidealab.com](https://structured-log.openidealab.com/ru/).

## Установка

Опубликован на pub.dev как пре-релиз:

```yaml
dependencies:
  flutter_bloc: ^9.0.0 # или bloc: ^9.0.0
  structured_log: ^0.3.0
  structured_log_bloc: ^0.1.0-dev.3
```

## Быстрый старт

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_bloc/structured_log_bloc.dart';

void main() {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );
  Bloc.observer = StructuredLogBlocObserver();

  runApp(const MyApp());
}
```

`CounterBloc`, получивший одно событие `Incremented`, пишет:

```text
[2026-10-02T16:04:41.519257Z] DEBUG: bloc_created {"logger":"bloc","category":"bloc","bloc":"CounterBloc","bloc_instance":787006492,"state":"0","state_type":"int"}
[2026-10-02T16:04:41.527204Z] DEBUG: bloc_event_added {"logger":"bloc","category":"bloc","bloc":"CounterBloc","bloc_instance":787006492,"bloc_event":"Incremented()","bloc_event_type":"Incremented"}
[2026-10-02T16:04:41.531119Z] DEBUG: bloc_transition {"logger":"bloc","category":"bloc","bloc":"CounterBloc","bloc_instance":787006492,"bloc_event":"Incremented()","bloc_event_type":"Incremented","current_state":"0","next_state":"1","state_type":"int"}
```

Запускаемая версия — [example/main.dart](example/main.dart)
(`dart run example/main.dart`).

## Что пишется в лог

В каждой записи есть `category` (по умолчанию `bloc`), `logger` (по умолчанию
`bloc`), `bloc` — тип блока — и `bloc_instance`, идентификатор экземпляра,
по которому различаются два экземпляра одного типа.

| Хук            | `event`            | Уровень по умолчанию | Поля |
|----------------|--------------------|----------------------|------|
| `onCreate`     | `bloc_created`     | `debug`              | `state`, `state_type` |
| `onEvent`      | `bloc_event_added` | `debug`              | `bloc_event`, `bloc_event_type` |
| `onChange`     | `bloc_change`      | `debug`              | `current_state`, `next_state`, `state_type` — **только кубиты** |
| `onTransition` | `bloc_transition`  | `debug`              | `bloc_event`, `bloc_event_type`, `current_state`, `next_state`, `state_type` |
| `onError`      | `bloc_error`       | `error`              | `error`, `error_type`, `stack_trace` |
| `onDone`       | `bloc_event_done`  | `trace`              | `bloc_event`, `bloc_event_type`; `error`, `error_type`, если обработчик упал |
| `onClose`      | `bloc_closed`      | `debug`              | — |

Событие блока лежит в `bloc_event`, а не в `event`: в `structured_log`
`event` — это имя самой записи.

`bloc_event_done` пишется на уровне `trace`, и вывод с `minLevel` по
умолчанию (`debug`) его отсекает: эта запись дублирует событие каждого
обработчика, а такой объём нужен редко. Чтобы увидеть его, опустите `minLevel` у вывода.

## Как не пустить секреты в лог

**По умолчанию состояния и события пишутся через `toString()`** (с обрезкой
до 1000 символов). Если в них бывают пароли, токены или персональные данные —
тем более если лог уходит с устройства через `structured_log_remote_sync`, —
передайте `describe`, который их скрывает. Возврат `null` убирает значение,
но оставляет его тип:

```dart
Bloc.observer = StructuredLogBlocObserver(
  describe: (value) => switch (value) {
    AuthState() || LoginSubmitted() => null,
    _ => describeBlocValue(value),
  },
);
```

Чтобы везде писать только типы: `describe: (_) => null`.

`describe` может вернуть и **карту** вместо строки. Карта остаётся в записи
структурой, поэтому процессор `redactKeys` видит её поля, как и любые другие.
Строку из `toString()` он разобрать не может:

```dart
StructlogConfiguration.configure(processors: [redactKeys(), dropNullValues]);

Bloc.observer = StructuredLogBlocObserver(
  describe: (value) => switch (value) {
    AuthState(:final user, :final token) => {'user': user, 'token': token},
    _ => describeBlocValue(value),
  },
);
// next_state: {"user": "u", "token": "***"}
```

## Настройка

```dart
Bloc.observer = StructuredLogBlocObserver(
  // Какие хуки писать и с каким уровнем; null выключает хук.
  levels: const BlocLogLevels(
    event: LogLevel.trace,
    transition: LogLevel.info,
    done: null,
  ),
  // Шумные блоки — мимо лога.
  filter: (bloc) => bloc is! TickerCubit,
  category: 'state',
);
```

Чтобы подключить несколько наблюдателей сразу — этот и, скажем, отправщик
отчётов о сбоях, — объедините их `MultiBlocObserver` из самого `bloc`
(начиная с `bloc` 9.2.0).

## Справочник API

| Символ | Описание |
|---|---|
| `StructuredLogBlocObserver({logger, loggerName, category, levels, describe, filter})` | Наблюдатель. Без `logger` вызывает `getLogger(loggerName)` на каждом хуке, поэтому до него доходит и более поздний `StructlogConfiguration.configure`. `category: null` не привязывает категорию. |
| `BlocLogLevels({create, event, change, transition, error, done, close})` | `LogLevel?` на каждый хук; `null` выключает хук. |
| `BlocValueDescriber` | `Object? Function(Object? value)` — превращает состояние, событие или ошибку в значение записи; `null` убирает поле. |
| `describeBlocValue(value)` | Описание по умолчанию: `toString()` с обрезкой до `defaultBlocValueMaxLength` (1000) символов; если `toString()` выбросит исключение, вместо значения пишется заглушка. |

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

- [`structured_log_dio`](https://pub.dev/packages/structured_log_dio) — перехватчик `dio`, логирующий HTTP-вызовы
- [`structured_log_http_client`](https://pub.dev/packages/structured_log_http_client) — обёртка клиента `package:http`, логирующая HTTP-вызовы
- [`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router) — логирует навигацию `go_router`
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — наблюдатель DI-контейнера `cherrypick`
- [`structured_log_drift`](https://pub.dev/packages/structured_log_drift) — `QueryInterceptor` для drift, логирующий запросы, сбои и транзакции

## Лицензия

MIT — см. [LICENSE](LICENSE).
