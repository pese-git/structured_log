# Руководство по внедрению

*Read in [English](embedding-guide.md).*

Для тех, кто хочет добавить структурированное логирование — и, по
желанию, живой просмотрщик логов внутри приложения — в собственное
Dart- или Flutter-приложение. Здесь ничего не говорит с
`structured_log_server`: каждый пакет ниже работает самостоятельно, в
проекте, который никогда не запускает сервер. Если вам нужно доставлять
логи на self-hosted экземпляр `structured_log_server` (или запрашивать
их обратно) — см. [Руководство разработчика](developer-guide.ru.md), на
котором заканчивается необязательный последний раздел этого руководства.

Четыре пакета, и нужно ровно столько из них, сколько требует ваш проект:

1. **Просто логирование** —
   [`structured_log`](#1-структурированное-логирование-structured_log)
   само по себе. Чистый Dart, без сторонних runtime-зависимостей кроме
   `meta`, работает везде, где работает Dart.
2. **Живой просмотр логов внутри приложения, во Flutter** —
   [`structured_log_flutter`](#2-headless-ядро-просмотрщика-structured_log_flutter)
   (headless-ядро списка/фильтрации) плюс один готовый скин:
   [`structured_log_material`](#3-готовый-скин),
   [`structured_log_fluent`](#3-готовый-скин) или
   [`structured_log_cupertino`](#3-готовый-скин) — выберите тот, что
   соответствует дизайн-системе вашего приложения.
3. **Ещё и доставлять эти логи на сервер** —
   [`structured_log_http`](#4-опционально-доставлять-логи-и-на-сервер),
   тонкий add-on `LogSink`-вывод; здесь — кратко, полностью — в
   Руководстве разработчика.

Все три viewer-скина используют одно и то же ядро
`structured_log_flutter`, так что переход с одного на другой позже — это
вопрос того, какой виджет-просмотрщик вы импортируете, а не изменение
слоя данных.

## 1. Структурированное логирование: `structured_log`

Базовая библиотека
([`emb/structured_log`](../../emb/structured_log/),
[опубликована на pub.dev](https://pub.dev/packages/structured_log)):

```yaml
dependencies:
  structured_log: ^0.2.0
```

```dart
import 'package:structured_log/structured_log.dart';

void main() {
  final log = getLogger();
  log.info('user_login', context: {'user_id': 42, 'ip': '127.0.0.1'});
}
```

`bind()` привязывает контекст к логгеру неизменяемо (возвращает новый
экземпляр); `withCorrelation()` привязывает фиксированный, типизированный
набор полей корреляции (`session_id`, `request_id`,
`connection_generation`, `tool_call_id`, `message_id`, `operation_id`),
которые нативно понимают и фильтры запроса `structured_log_server`, и
виджеты-просмотрщики ниже — предпочитайте их произвольным ключам
контекста с тем же смыслом, чтобы запрос можно было проследить целиком
по одному из этих id, а не по совпавшему по соглашению имени поля:

```dart
final log = getLogger().withCorrelation(requestId: 'req-42');
log.info('request_started');
log.error('request_failed', context: {'status': 500});
```

Шесть уровней, от менее к более серьёзному: `trace` < `debug` < `info`
< `warning` < `error` < `critical`. Несколько выводов, каждый со своей
фильтрацией по уровню или категории, — обычная настройка: например,
цветной консольный sink рядом с sink просмотрщика из следующего раздела:

```dart
StructlogConfiguration.configure(sinks: [
  LogSink(name: 'console', output: coloredConsoleOutput),
  LogSink(name: 'viewer', output: buffer.capture, minLevel: LogLevel.debug),
]);
```

Полный API — процессоры, мульти-sink роутинг, файловый и ротируемый
вывод — в
[`emb/structured_log/README.md`](../../emb/structured_log/README.md).

## 2. Headless-ядро просмотрщика: `structured_log_flutter`

Если вы хотите построить собственный UI просмотра логов, а не
пользоваться одним из готовых скинов из следующего раздела,
[`structured_log_flutter`](../../emb/structured_log_flutter/) — то, на
чём стоит строить: ограниченный `LogBuffer` (`OutputFunction`,
подключаемый к `LogSink`, хранит в памяти последние записи) и
`LogViewerController` (фильтрация по уровню/категории/тексту поиска,
пауза, очистка). Сам он ничего не рисует и не привязан ни к какой
дизайн-системе:

```yaml
dependencies:
  structured_log_flutter: ^0.1.0
```

```dart
final buffer = LogBuffer();
final controller = LogViewerController(buffer);

StructlogConfiguration.configure(sinks: [
  LogSink(name: 'viewer', output: buffer.capture),
]);
```

`logLevelColor()` — единственный элемент визуального мнения, который
держит этот пакет (соответствие `LogLevel` → `Color`, общее для всех
трёх скинов ниже), — тоже экспортируется, если нужна визуальная
согласованность с ними без использования готового скина напрямую.
Полный API:
[`emb/structured_log_flutter/README.md`](../../emb/structured_log_flutter/README.md).

## 3. Готовый скин

Три виджета стоят поверх `structured_log_flutter`, по одному на
дизайн-систему — выбирайте тот, что соответствует вашему приложению, а
не платформе (любой из трёх работает на любой цели Flutter):

| Пакет | Дизайн-система | Поведение на узком экране |
|---|---|---|
| [`structured_log_material`](../../emb/structured_log_material/) | Material 3 | список, тап открывает модальный bottom sheet |
| [`structured_log_fluent`](../../emb/structured_log_fluent/) | Fluent UI (в стиле WinUI) | список, тап открывает панель деталей с кнопкой «назад» |
| [`structured_log_cupertino`](../../emb/structured_log_cupertino/) | Cupertino (в стиле iOS) | список, тап пушит экран деталей (`CupertinoPageRoute`) |

Все три показывают master-detail split выше своего собственного узкого
брейкпоинта (список и панель деталей рядом) и сворачиваются в паттерн
выше него ниже брейкпоинта — измеряется по собственной ширине виджета
через `LayoutBuilder`, а не по ширине окна, так что встроенная панель
ведёт себя правильно независимо от того, насколько широко окружающее
приложение.

```yaml
dependencies:
  structured_log_flutter: ^0.1.0
  structured_log_material: ^0.1.0   # или _fluent / _cupertino
```

```dart
import 'package:structured_log_material/structured_log_material.dart';   // или _fluent / _cupertino

// Полный экран:
Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => MaterialLogViewerPage(controller: controller),
));

// Или встроенный в существующую хрому (боковая панель, вкладка, ...):
MaterialLogViewer(controller: controller)
```

`controller` — тот же `LogViewerController` из предыдущего раздела:
скин чисто презентационный. У каждого пакета есть рабочий web-пример в
собственной директории `example/`, а его README покрывает полный API
виджетов:
[`structured_log_material`](../../emb/structured_log_material/README.md),
[`structured_log_fluent`](../../emb/structured_log_fluent/README.md),
[`structured_log_cupertino`](../../emb/structured_log_cupertino/README.md).

## 4. Опционально: доставлять логи и на сервер

Всё выше — полностью локально: без сети, без сервера. Если нужно ещё и
собирать эти логи централизованно (искать их между перезапусками,
делиться ими внутри команды, хранить по расписанию),
[`structured_log_http`](../../emb/structured_log_http/) — это
`LogSink`-вывод, доставляющий записи на экземпляр `structured_log_server`
по HTTP, с батчингом, повтором и ограниченным буфером:

```yaml
dependencies:
  structured_log: ^0.2.0
  structured_log_http:
    path: ../structured_log_http   # пока не на pub.dev (0.1.0-dev.0) — path- или git-зависимость
```

```dart
final output = HttpLogOutput(
  serverUrl: 'https://logs.example.com',
  projectSecretKey: 'slk_...',
);

StructlogConfiguration.configure(sinks: [
  LogSink(name: 'server', output: output),
]);
```

Это тот же пакет, что полностью описан в разделе Руководства
разработчика
[«Отправка логов на сервер»](developer-guide.ru.md#отправка-логов-на-сервер)
— как получить секретный ключ проекта, что вы получаете бесплатно
(батчинг/повтор/вытеснение) и как держать локальный sink (консоль или
просмотрщик выше) работающим рядом с ним. Развёртывание самого сервера
— в [Руководстве администратора / DevOps](admin-guide.ru.md).

## Куда дальше

- README каждого пакета — полный справочник API, дословно:
  [`structured_log`](../../emb/structured_log/README.ru.md),
  [`structured_log_flutter`](../../emb/structured_log_flutter/README.ru.md),
  [`structured_log_material`](../../emb/structured_log_material/README.ru.md),
  [`structured_log_fluent`](../../emb/structured_log_fluent/README.ru.md),
  [`structured_log_cupertino`](../../emb/structured_log_cupertino/README.ru.md),
  [`structured_log_http`](../../emb/structured_log_http/README.ru.md).
- [Руководство разработчика](developer-guide.ru.md) — когда в дело
  вступает сервер: эндпоинт приёма по HTTP напрямую, запрос логов
  обратно, живая лента программно и аутентификация как человек.
- [Руководство контрибьютора](contributor-guide.ru.md) — если вы
  хотите изменить один из этих пакетов, а не просто им пользоваться.
