# structured_log_bloc

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

Пишет в лог всё, что делают блоки и кубиты — создание, события, смену
состояния, ошибки, закрытие — записями
[`structured_log`](https://pub.dev/packages/structured_log).

`StructuredLogBlocObserver` — обычный `BlocObserver`: достаточно поставить его
в `Bloc.observer`, и каждый блок приложения пишет в уже настроенные выводы —
консоль, файл, встроенный просмотрщик логов (`structured_log_flutter`) или
`structured_log_server` через `structured_log_remote_sync`.

## Возможности

- **Подключение одной строкой** — `Bloc.observer = StructuredLogBlocObserver()`
- **Работает с `flutter_bloc` как есть** — зависит только от `package:bloc`,
  на котором `flutter_bloc` построен, поэтому работает и в чистом Dart
- **Своя категория** — каждая запись несёт `category: 'bloc'`, так что
  `LogSink` может направить трафик блоков отдельно, а просмотрщик логов
  предлагает её как фильтр
- **Каждая смена состояния — один раз** — у блока она пишется как переход
  (вместе с событием), у кубита — как изменение; никогда не обе сразу
- **Свой уровень на каждый хук** — или `null`, чтобы хук выключить
- **Значения под вашим контролем** — состояния и события проходят через
  заменяемую функцию описания, чтобы секреты не попадали в лог
- **Никогда не ломает блок** — бросивший `toString()` или функция описания
  стоят записи её значений, а не блоку его `emit`

## Установка

Опубликован на pub.dev как пре-релиз (`0.1.0-dev.1`):

```yaml
dependencies:
  flutter_bloc: ^9.0.0 # или bloc: ^9.0.0
  structured_log: ^0.2.1
  structured_log_bloc: ^0.1.0-dev.1
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
DEBUG: bloc_created     {"category":"bloc","bloc":"CounterBloc","bloc_instance":621700500,"state":"0","state_type":"int"}
DEBUG: bloc_event_added {"category":"bloc","bloc":"CounterBloc","bloc_instance":621700500,"bloc_event":"Incremented()","bloc_event_type":"Incremented"}
DEBUG: bloc_transition  {"category":"bloc","bloc":"CounterBloc","bloc_instance":621700500,"bloc_event":"Incremented()","bloc_event_type":"Incremented","current_state":"0","next_state":"1","state_type":"int"}
```

Запускаемая версия — [example/main.dart](example/main.dart)
(`dart run example/main.dart`).

## Что пишется в лог

Каждая запись несёт `category` (по умолчанию `bloc`), `logger` (по умолчанию
`bloc`), `bloc` — тип блока — и `bloc_instance`, его идентичность, по которой
различаются два экземпляра одного типа.

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

`bloc_event_done` идёт на уровне `trace`, который `minLevel` вывода по
умолчанию (`debug`) отсекает: он повторяет событие каждого обработчика, а
такой объём редко нужен. Чтобы увидеть его, опустите `minLevel` у вывода.

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

Несколько наблюдателей сразу — этот и, скажем, отправщик крэшей —
объединяются собственным `MultiBlocObserver` из `bloc`.

## Справочник API

| Символ | Описание |
|---|---|
| `StructuredLogBlocObserver({logger, loggerName, category, levels, describe, filter})` | Наблюдатель. Без `logger` вызывает `getLogger(loggerName)` на каждом хуке, поэтому до него доходит и более поздний `StructlogConfiguration.configure`. `category: null` не привязывает категорию. |
| `BlocLogLevels({create, event, change, transition, error, done, close})` | `LogLevel?` на каждый хук; `null` выключает хук. |
| `BlocValueDescriber` | `Object? Function(Object? value)` — превращает состояние, событие или ошибку в значение записи; `null` убирает поле. |
| `describeBlocValue(value)` | Описание по умолчанию: `toString()` с обрезкой до `defaultBlocValueMaxLength` (1000) символов; бросивший `toString()` превращается в заглушку. |

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

## Лицензия

См. [LICENSE](LICENSE).
