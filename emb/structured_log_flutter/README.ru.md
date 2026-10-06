# structured_log_flutter

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

**Основа просмотрщика логов внутри Flutter-приложения: последние записи
[`structured_log`](https://pub.dev/packages/structured_log) хранятся в памяти,
фильтруются и готовы для любого UI. Кроме того, в пакете есть аккуратный
однострочный вывод в консоль для телефонов.**

## Зачем

Тестировщик ловит ошибку на устройстве, а логи, которые могли бы её
объяснить, ушли в консоль, к которой никто не был подключён, или утонули в
logcat среди системного шума. Выход — держать последние записи внутри
приложения и показывать их по запросу. Как бы ни выглядел такой экран, под
ним одно и то же: буфер, который не растёт бесконечно, фильтры по уровню,
категории и тексту и пауза, чтобы список не уезжал, пока вы его читаете.

`structured_log_flutter` содержит ровно эти части и ни одного виджета. Пакет
ничего не рисует и не зависит ни от одной дизайн-системы, поэтому на нём
построены все три готовых просмотрщика — Material, Fluent и Cupertino, — и
на нём же можно собрать свой. Большинству приложений он напрямую не нужен:
достаточно выбрать скин. Берите этот пакет, если нужен просмотрщик в
собственной дизайн-системе или доступ к последним записям из кода —
например, чтобы приложить их к отчёту об ошибке. А на случай, когда консоль
*всё-таки* под рукой, в нём есть `debugPrintOutput`: он пишет каждую запись
одной читаемой строкой, а не многострочным JSON.

## Возможности

### Сбор записей

- **Ещё один синк** — у `LogBuffer.capture` сигнатура `OutputFunction`,
  так что буфер подключается отдельным `LogSink` рядом с консолью, и ни
  один вызов лога менять не нужно.
- **Ограниченная память** — кольцевой буфер фиксированной ёмкости (по
  умолчанию 500): первой вытесняется самая старая запись, на диск ничего не
  пишется.
- **Одна перерисовка на пачку** — `entries` — это `ValueListenable`: его
  значение всегда актуально, а слушатели узнают о пачке записей один раз, а
  не о каждой по отдельности. Если запрос написал в лог пятьдесят строк,
  интерфейс перерисуется один раз.
- **Снимки можно хранить** — прочитанный список неизменяем и потом уже не
  меняется, поэтому ссылку на него можно хранить или сравнивать с более
  поздним чтением.

### Состояние просмотрщика

- **Фильтры** — `LogViewerController` отбирает записи по минимальному
  уровню, точному значению категории и регистронезависимому поиску по
  событию и всем значениям контекста.
- **Пауза** — замораживает видимый список, пока буфер продолжает
  принимать записи, так что ничего не уезжает посреди чтения; после
  возобновления список догоняет буфер.
- **Очистка** — одним вызовом опустошает и буфер, и снимок паузы.
- **Обычный `ChangeNotifier`** — работает с `AnimatedBuilder`,
  `ListenableBuilder` и любым state management, которым вы уже пользуетесь.

### Чтение логов в консоли

- **`debugPrintOutput`** — одна строка на запись
  (`12:30:15.250 INFO login user="u" attempt=2`): местное время, без
  ANSI-кодов, значения экранируются, так что перевод строки не разорвёт
  запись. Печать идёт через `debugPrint`, который сглаживает всплески
  вывода, чтобы Android не терял строки.

### Общее для всех скинов

- **Одна палитра уровней** — `logLevelColor()` задаёт каждому `LogLevel` цвет
  для светлой и тёмной темы, поэтому просмотрщики Material, Fluent и
  Cupertino не расходятся в цветах; `logLevelOf()` восстанавливает уровень
  по записи.
- **Без привязки к дизайн-системе** — пакет зависит только от `dart:ui`,
  `package:flutter/foundation.dart` и `structured_log`.

## Место в проекте

[`structured_log`](https://pub.dev/packages/structured_log) пишет записи и
раздаёт их по синкам; этот пакет — синк, который оставляет их внутри
приложения, плюс состояние, нужное просмотрщику, чтобы их показать.
[`structured_log_material`](https://pub.dev/packages/structured_log_material),
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) и
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino)
— готовые экраны поверх него. Всё это работает целиком внутри приложения,
без сервера; если позже вы начнёте отправлять логи на self-hosted сервер
через [`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync),
просмотрщик продолжит работать рядом с ним — синки друг от друга не
зависят. Подробнее — в документации на
[structured-log.openidealab.com](https://structured-log.openidealab.com/ru/)
и в [руководстве по встраиванию](https://structured-log.openidealab.com/ru/guides/embedding-guide/).

## Установка

```yaml
dependencies:
  structured_log: ^0.3.0
  structured_log_flutter: ^0.1.2
```

Внутри этого monorepo `melos bootstrap` подставляет вместо неё
path-зависимость:

```yaml
dependencies:
  structured_log_flutter:
    path: ../structured_log_flutter
```

## Быстрый старт

```dart
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

final buffer = LogBuffer(capacity: 500);
final controller = LogViewerController(buffer);

StructlogConfiguration.configure(sinks: [
  LogSink(name: 'console', output: coloredConsoleOutput),
  LogSink(name: 'viewer', output: buffer.capture),
]);

getLogger().info('user_login', context: {'user_id': 42});

controller.levelFilter = LogLevel.warning; // только warning и выше
controller.searchQuery = 'login';          // дополнительно сужено текстом
print(controller.visibleEntries);
```

## Справочник API

### `LogBuffer`

| Член | Описание |
|---|---|
| `LogBuffer({int capacity = 500})` | Создаёт пустой буфер; при превышении `capacity` вытесняется самая старая запись |
| `capacity` | Наибольшее число записей, которое буфер хранит одновременно |
| `capture(Map<String, dynamic> entry, LogLevel level)` | Совпадает по сигнатуре с `OutputFunction` — передавайте напрямую как `output` синка |
| `entries` | `ValueListenable<List<Map<String, dynamic>>>`, от старой к новой |
| `clear()` | Опустошает буфер и сразу уведомляет слушателей `entries` |

`entries.value` всегда актуален, но слушателей уведомляют не чаще раза за
оборот цикла событий: пачка записей, залогированных разом, — всё, что
написал один запрос, или плотный цикл, — это одно уведомление и одна
перерисовка, а не по одной на запись. Возвращаемый список неизменяемый и
после чтения уже не меняется, так что ссылку на него можно хранить; два
чтения подряд без новых записей между ними дают один и тот же список —
копия создаётся один раз на каждое прочитанное изменение, а не на каждую
запись.

`LogBuffer` держит записи только в памяти. Если логи должны сохраняться
после завершения приложения, нужны файловые выводы — они импортируются из
`package:structured_log/io.dart`.

### `LogViewerController`

`ChangeNotifier`, оборачивающий `LogBuffer`:

| Член | Описание |
|---|---|
| `levelFilter` (`LogLevel?`) | Минимальный уровень видимой записи; `null` — без ограничения |
| `categoryFilter` (`String?`) | Требуемое точное значение `category`; `null` — без ограничения |
| `searchQuery` (`String`) | Регистронезависимое совпадение подстроки с `event` и остальными значениями контекста (`level`/`timestamp` исключены) |
| `paused` (`bool`) | Пока `true`, `visibleEntries` остаются такими, какими были в момент паузы, даже если `buffer` продолжает принимать записи |
| `visibleEntries` | Записи буфера, отфильтрованные тремя свойствами выше, от старой к новой |
| `clear()` | Очищает `buffer` (и зафиксированный снимок, если есть) и уведомляет слушателей |
| `dispose()` | Отписывается от `buffer.entries` — вызывать, когда контроллер больше не нужен |

### `debugPrintOutput`

`OutputFunction`, который пишет каждую запись одной строкой через
`debugPrint`, без ANSI-цветов: местное время (из `timestamp`, с
миллисекундами), уровень, `event` и все остальные поля парами `key=value`:

```text
12:30:15.250 INFO login user="u" attempt=2
```

```dart
StructlogConfiguration.configure(sinks: [
  LogSink(name: 'console', output: debugPrintOutput),
]);
```

Он нужен там, где логи читают в logcat или в консоли Xcode. `defaultOutput`
печатает JSON с отступами на несколько строк, и эти консоли перемешивают их
со всем остальным, а escape-коды `coloredConsoleOutput` в консоли iOS
превращаются в мусор. Значения экранируются так же, как это делает
`formatLogfmt` из `structured_log`, поэтому значение с переводом строки не
разрывает строку лога. `debugPrint` притормаживает поток строк, чтобы Android
их не терял, но длинную строку не укорачивает — logcat обрезает строку
длиннее примерно 4 КБ. В терминале на десктопе `coloredConsoleOutput`
по-прежнему читается лучше.

### `logLevelOf(Map<String, dynamic> entry)`

Разбирает ключ контекста `level` записи обратно в `LogLevel` по совпадению
имени — возвращает `null`, если ключа нет или он не распознан. Вынесена в
отдельную функцию, чтобы UI-скин (например, `structured_log_material`) не дублировал
этот разбор.

### `logLevelColor(LogLevel level, Brightness brightness)`

Единственный источник цветов индикатора `LogLevel`: им пользуются строка
списка, вид деталей и бейджи каждого скина. Находится здесь (а не в
каком-то одном скине), потому что `Color`/`Brightness` не привязаны ни к
Material, ни к Cupertino, ни к Fluent — эта таблица действительно
не зависит от дизайн-системы, в отличие от виджетов, построенных поверх неё.

## Построение UI-скина

`structured_log_flutter` намеренно ничего не рисует — подключайте
`LogViewerController` к любым виджетам, слушая его как обычный `ChangeNotifier`
(`AnimatedBuilder`, `ListenableBuilder` и т.п.) и читая `visibleEntries` для
отображения. Простейший список, которому хватает одного
`package:flutter/widgets.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

class PlainLogList extends StatelessWidget {
  const PlainLogList({required this.controller, super.key});

  final LogViewerController controller;

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // visibleEntries идут от старой к новой; новые показываем сверху.
        final entries = controller.visibleEntries.reversed.toList();
        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            final level = logLevelOf(entry);
            return Text(
              '${level?.name ?? '?'}  ${entry['event']}',
              style: TextStyle(
                color: level == null ? null : logLevelColor(level, brightness),
              ),
            );
          },
        );
      },
    );
  }
}
```

Полные эталонные реализации (список, детали записи, пустые состояния) на
Material 3, Fluent UI и Cupertino смотрите в
[`structured_log_material`](https://pub.dev/packages/structured_log_material),
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) и
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino)
соответственно.

## Связанные пакеты

Остальные пакеты семейства `structured_log`:

**Ядро**

- [`structured_log`](https://pub.dev/packages/structured_log) — структурированное JSON-логирование с привязкой контекста, процессорами и маршрутизацией по синкам

**Просмотрщик логов в приложении**

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

## Лицензия

MIT
