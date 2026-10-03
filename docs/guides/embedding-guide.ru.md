# Руководство по внедрению

*Read in [English](embedding-guide.md).*

Для тех, кто хочет добавить структурированное логирование — и, по
желанию, просмотр логов в реальном времени внутри приложения — в собственное
Dart- или Flutter-приложение. Ничто из описанного здесь не обращается к
`structured_log_server`: каждый пакет ниже работает самостоятельно, в
проекте, который вообще не запускает сервер. Если вам нужно доставлять
логи на self-hosted экземпляр `structured_log_server` (или запрашивать
их обратно) — см. [Руководство разработчика](developer-guide.ru.md): оно
начинается ровно там, где заканчивается необязательный последний раздел
этого руководства.

Пакетов несколько, а подключать нужно ровно столько, сколько требует ваш проект:

1. **Просто логирование** —
   [`structured_log`](#1-структурированное-логирование-structured_log)
   само по себе. Чистый Dart, без сторонних runtime-зависимостей кроме
   `meta`, работает везде, где работает Dart.
2. **Просмотр логов в реальном времени внутри Flutter-приложения** —
   [`structured_log_flutter`](#2-headless-ядро-просмотрщика-structured_log_flutter)
   (headless-ядро списка/фильтрации) плюс один готовый скин:
   [`structured_log_material`](#3-готовый-скин),
   [`structured_log_fluent`](#3-готовый-скин) или
   [`structured_log_cupertino`](#3-готовый-скин) — выберите тот, что
   соответствует дизайн-системе вашего приложения.
3. **Писать в лог, что делают блоки** —
   [`structured_log_bloc`](#4-опционально-логировать-блоки-structured_log_bloc),
   `BlocObserver` для приложений на `bloc`/`flutter_bloc`.
4. **Писать в лог HTTP-вызовы** —
   [`structured_log_dio` или `structured_log_http_client`](#5-опционально-логировать-http-вызовы),
   для приложений, которые ходят на свой бэкенд через `dio` или `package:http`.
5. **Писать в лог навигацию** —
   [`structured_log_go_router`](#6-опционально-логировать-навигацию-structured_log_go_router),
   для Flutter-приложений с маршрутизацией на `go_router`.
6. **Писать в лог работу DI-контейнера** —
   [`structured_log_cherrypick`](#7-опционально-логировать-di-контейнер-structured_log_cherrypick),
   для приложений, собранных на `cherrypick`.
7. **Ещё и доставлять эти логи на сервер** —
   [`structured_log_remote_sync`](#8-опционально-доставлять-логи-и-на-сервер),
   тонкая надстройка над `LogSink`; кратко описан здесь, подробно — в
   Руководстве разработчика.

Все три скина просмотрщика используют одно и то же ядро
`structured_log_flutter`, поэтому, чтобы позже сменить скин, достаточно
импортировать другой виджет — слой данных переделывать не придётся.

## 1. Структурированное логирование: `structured_log`

Базовая библиотека
([`emb/structured_log`](../../emb/structured_log/),
[опубликована на pub.dev](https://pub.dev/packages/structured_log)):

```yaml
dependencies:
  structured_log: ^0.3.0
```

```dart
import 'package:structured_log/structured_log.dart';

void main() {
  final log = getLogger();
  log.info('user_login', context: {'user_id': 42, 'ip': '127.0.0.1'});
}
```

`bind()` привязывает контекст к логгеру, не меняя исходный (возвращает
новый экземпляр). `withCorrelation()` привязывает фиксированный
типизированный набор полей корреляции (`session_id`, `request_id`,
`connection_generation`, `tool_call_id`, `message_id`, `operation_id`).
Эти поля без дополнительной настройки понимают и фильтры запроса
`structured_log_server`, и виджеты-просмотрщики ниже. Используйте их
вместо произвольных ключей контекста с тем же смыслом: тогда запрос можно
проследить целиком по одному из этих id, а не по имени поля, которое
совпадает лишь по договорённости:

```dart
final log = getLogger().withCorrelation(requestId: 'req-42');
log.info('request_started');
log.error('request_failed', context: {'status': 500});
```

Логгер из `getLogger()` читает текущую конфигурацию на каждой записи,
поэтому логгер в `static final`, созданный ещё до `configure()`, всё
равно пишет туда, куда велел `configure()`. Вызов лога никогда не
выбрасывает исключений, а исключение из вашего кода передаётся через
параметры `error:`/`stackTrace:` и попадает в запись полями `error`,
`error_type` и `stack_trace`:

```dart
try {
  await charge(order);
} catch (e, st) {
  log.error('payment_failed', error: e, stackTrace: st);
}
```

`timestamp` пишется в UTC (`2026-03-05T14:30:00.100Z`); с
`timestampMode: TimestampMode.localWithOffset` в `configure()` — в
местном времени со смещением (`+03:00`).

Шесть уровней, от менее к более серьёзному: `trace` < `debug` < `info`
< `warning` < `error` < `critical`. Обычная настройка — несколько выводов,
у каждого свой фильтр по уровню или категории: например, цветной
консольный sink рядом с sink'ом просмотрщика из следующего раздела:

```dart
StructlogConfiguration.configure(sinks: [
  LogSink(name: 'console', output: coloredConsoleOutput),
  LogSink(name: 'viewer', output: buffer.capture, minLevel: LogLevel.debug),
]);
```

Если в записи могут попадать учётные данные — карта заголовков, тело
запроса, дамп конфигурации, — подключите маскирующий процессор сразу при
настройке: если секрет дошёл до sink'а, он уже утёк.

```dart
StructlogConfiguration.configure(
  processors: [redactKeys(), dropNullValues],  // sink'и видят то, что вернут они
);
```

`redactKeys()` заменяет `password`, `token`, `authorization` и остальные
имена из `defaultSensitiveKeys` на любой глубине, а если их не хватает,
можно передать собственные имена или предикаты. Если процессор выбросил
исключение, sink'и получают не запись, а заглушку — только `event`, `level`,
`timestamp`, `logger`, `category` и `processor_failed`: сбой мог произойти
как раз в том процессоре, который должен был запись замаскировать.

Файловым выводам нужен `dart:io`, поэтому они вынесены в отдельную
библиотеку, а главная собирается и под web:

```dart
import 'package:structured_log/io.dart';
import 'package:structured_log/structured_log.dart';

StructlogConfiguration.configure(sinks: [
  LogSink(name: 'file', output: rotatingFileOutput('logs/app.log')),
]);
```

Полный API — процессоры, маршрутизация по нескольким sink'ам, файловый и ротируемый
вывод, вывод JSON-строками и в logfmt — в
[`emb/structured_log/README.md`](../../emb/structured_log/README.md).

## 2. Headless-ядро просмотрщика: `structured_log_flutter`

Если вы хотите построить собственный UI просмотра логов, а не
пользоваться одним из готовых скинов из следующего раздела, возьмите за
основу [`structured_log_flutter`](../../emb/structured_log_flutter/). В нём
есть `LogBuffer` ограниченного размера (`OutputFunction`, который
подключается к `LogSink` и хранит в памяти последние записи) и
`LogViewerController` (фильтрация по уровню/категории/тексту поиска,
пауза, очистка). Сам пакет ничего не рисует и не привязан ни к какой
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

`LogBuffer` уведомляет слушателей один раз на пачку — сотня записей,
сделанных за один синхронный участок, перестраивают список один раз, — а
`entries.value` при этом всегда актуален. Экспортируется и
`logLevelColor()` — единственное визуальное решение, которое пакет
всё-таки принимает за вас (соответствие `LogLevel` → `Color`, общее для
всех трёх скинов ниже): с ним можно выдержать единый стиль со скинами, не
подключая ни одного из них. Есть и
`debugPrintOutput`: одна строка на запись через `debugPrint`, без
ANSI-кодов, — в logcat и консоли Xcode это читается лучше многострочного
JSON по умолчанию.
Полный API:
[`emb/structured_log_flutter/README.md`](../../emb/structured_log_flutter/README.md).

## 3. Готовый скин

Поверх `structured_log_flutter` построены три виджета, по одному на
дизайн-систему. Выбирайте тот, что соответствует вашему приложению, а
не платформе: любой из трёх работает на любой целевой платформе Flutter.

| Пакет | Дизайн-система | Поведение на узком экране |
|---|---|---|
| [`structured_log_material`](../../emb/structured_log_material/) | Material 3 | список, тап открывает модальный bottom sheet |
| [`structured_log_fluent`](../../emb/structured_log_fluent/) | Fluent UI (в стиле WinUI) | список, тап открывает панель деталей с кнопкой «назад» |
| [`structured_log_cupertino`](../../emb/structured_log_cupertino/) | Cupertino (в стиле iOS) | список, тап пушит экран деталей (`CupertinoPageRoute`) |

Когда ширина больше брейкпоинта узкого экрана, все три показывают
master-detail split (список и панель деталей рядом), а когда меньше —
переходят к раскладке из таблицы выше. Ширина измеряется по самому
виджету через `LayoutBuilder`, а не по окну, поэтому встроенная панель
ведёт себя правильно, какой бы ширины ни было приложение вокруг неё.

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

// Или встроенный в интерфейс существующего приложения (боковая панель, вкладка, ...):
MaterialLogViewer(controller: controller)
```

`controller` — тот же `LogViewerController` из предыдущего раздела:
скин отвечает только за отображение. У каждого пакета есть рабочий web-пример в
собственной директории `example/`, а в его README описан полный API
виджетов:
[`structured_log_material`](../../emb/structured_log_material/README.md),
[`structured_log_fluent`](../../emb/structured_log_fluent/README.md),
[`structured_log_cupertino`](../../emb/structured_log_cupertino/README.md).

## 4. Опционально: логировать блоки: `structured_log_bloc`

Если логика приложения построена на блоках и кубитах
([`bloc`](https://pub.dev/packages/bloc) /
[`flutter_bloc`](https://pub.dev/packages/flutter_bloc)),
[`structured_log_bloc`](../../emb/structured_log_bloc/) пишет всё, что
делает каждый из них — создание, события, смену состояния, ошибки,
закрытие, — в настроенные выше выводы, включая встроенный просмотрщик:

```yaml
dependencies:
  structured_log: ^0.3.0
  structured_log_bloc: ^0.1.0-dev.1
```

```dart
StructlogConfiguration.configure(sinks: [
  LogSink(name: 'console', output: coloredConsoleOutput),
]);
Bloc.observer = StructuredLogBlocObserver();
```

У каждой записи стоит `category: 'bloc'`, поэтому фильтр категорий в
просмотрщике отделяет записи блоков от остальных, а `LogSink` с
`categories: {'bloc'}` может отправлять их в отдельный вывод. Пакет зависит
только от `package:bloc` — `flutter_bloc` реэкспортирует тот же
`Bloc.observer`, — поэтому ничего Flutter-специфичного ему не нужно.

**По умолчанию состояния и события пишутся через `toString()`.** Если в
них бывают пароли, токены или персональные данные, передайте
`describe`, который их скрывает, — см.
[README](../../emb/structured_log_bloc/README.ru.md#как-не-пустить-секреты-в-лог)
пакета; там же перечислены все записи и настройка уровня на каждый хук.

## 5. Опционально: логировать HTTP-вызовы

Пакетов два, по одному на HTTP-клиент. Записи у них одинаковые
(`http_request`, затем `http_response` или `http_error`, связанные
`http_request_id`), как и уровни по статусу и маскирование. Выбирайте
тот, что подходит к HTTP-клиенту вашего приложения.

### `dio`: `structured_log_dio`

Если приложение ходит на свой бэкенд через [`dio`](https://pub.dev/packages/dio),
[`structured_log_dio`](../../emb/structured_log_dio/) пишет каждый запрос и
то, чем он закончился, — ответ, ошибку, таймаут, отмену — с длительностью
и уровнем по статусу ответа:

```yaml
dependencies:
  structured_log: ^0.3.0
  structured_log_dio: ^0.1.0-dev.1
```

```dart
final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
  ..interceptors.add(StructuredLogDioInterceptor()); // добавлять последним
```

У записей стоит `category: 'http'`, а у записей блоков — `bloc`, так что
просмотрщик может показать любую из категорий отдельно. Заголовки и тела
пишутся, только если их явно включить, а `Authorization`, cookie и query-параметры
с токенами маскируются. Включённое тело тоже маскируется: поля с именами
из `redactedBodyFields` (по умолчанию — `defaultSensitiveKeys` ядра)
заменяются на `REDACTED` на любой глубине — и в карте или списке, и в
строке JSON или формы, которая для этого сначала разбирается. Строковое
тело любого другого типа пишется только длиной (`<N chars>`), пока не
включён `logUnrecognizedBodies`; см.
[README](../../emb/structured_log_dio/README.ru.md#как-не-пустить-секреты-в-лог)
пакета.

### `package:http`: `structured_log_http_client`

Перехватчиков у `package:http` нет, поэтому
[`structured_log_http_client`](../../emb/structured_log_http_client/) — это
клиент-обёртка над тем, которым вы уже пользуетесь (`IOClient`,
`BrowserClient`, `cupertino_http`, `RetryClient`), и он пишет каждый
проходящий через него вызов:

```yaml
dependencies:
  structured_log: ^0.3.0
  structured_log_http_client: ^0.1.0-dev.1
```

```dart
final client = StructuredLogHttpClient(http.Client());
await client.get(Uri.parse('https://api.example.com/items'));
```

`package:http` не выбрасывает исключений из-за статуса ответа, поэтому 404 — это
`http_response` на уровне `warning`. При включённом `logResponseBody` тело
не буферизуется — оно доходит до вашего кода по мере поступления и без
изменений, — а запись об ответе пишется, когда тело прочитано; см.
[README](../../emb/structured_log_http_client/README.ru.md#что-пишется-в-лог)
пакета. Тела маскируются так же, как у `dio`, с двумя отличиями:
текстовое тело неизвестного типа пишется размером, `<N bytes>`, а тело
JSON или формы читается целиком до 64 КиБ, чтобы его можно было разобрать
(более длинное пишется как `<unparseable body>`).

## 6. Опционально: логировать навигацию: `structured_log_go_router`

Если маршрутизация приложения построена на
[`go_router`](https://pub.dev/packages/go_router),
[`structured_log_go_router`](../../emb/structured_log_go_router/) пишет
каждую навигацию — расположение, шаблон маршрута (`/users/:id`) и
предыдущее расположение, — и по логу видно, на каком экране был
пользователь, когда что-то пошло не так:

```yaml
dependencies:
  structured_log: ^0.3.0
  structured_log_go_router: ^0.1.0-dev.1
```

```dart
final routeLog = StructuredLogGoRouter();
final router = GoRouter(
  routes: [/* ... */],
  redirect: routeLog.redirect(authRedirect), // по желанию: пишет и перенаправления
);
routeLog.attach(router);
```

У записей стоит `category: 'navigation'` — в дополнение к `bloc` и `http`.
Query-параметры с токенами — включая `code` из callback OAuth и фрагмент
`#access_token=...` — маскируются; path-параметры — нет, поэтому если
в пути маршрута есть что-то чувствительное, см.
[README](../../emb/structured_log_go_router/README.ru.md#как-не-пустить-секреты-в-лог)
пакета.

## 7. Опционально: логировать DI-контейнер: `structured_log_cherrypick`

Если приложение собрано на [`cherrypick`](https://pub.dev/packages/cherrypick),
[`structured_log_cherrypick`](../../emb/structured_log_cherrypick/) пишет,
что делает контейнер, — открытие и закрытие скоупов, установку модулей,
циклы зависимостей, ошибки разрешения, — и по этим записям видно, где
связывание зависимостей молча не сработало:

```yaml
dependencies:
  structured_log: ^0.3.0
  structured_log_cherrypick: ^0.1.0-dev.1
```

```dart
// До первого скоупа: скоуп берёт глобального наблюдателя при создании.
CherryPick.setGlobalObserver(StructuredLogCherryPickObserver());
```

У записей стоит `category: 'di'`. Сам экземпляр не пишется никогда — только
имя и тип, под которыми он зарегистрирован, — поэтому наблюдать за
контейнером, в котором лежат клиенты и хранилища токенов, безопасно.
Записи о каждом разрешении зависимости по умолчанию
выключены; как их включить и что сам контейнер сообщает, а что нет, — в
[README](../../emb/structured_log_cherrypick/README.ru.md#что-пишется-в-лог)
пакета.

## 8. Опционально: доставлять логи и на сервер

Всё описанное выше работает полностью локально: без сети и без сервера.
Если нужно ещё и собирать эти логи в одном месте (искать по ним после
перезапусков, делиться ими с командой, хранить заданный срок), используйте
[`structured_log_remote_sync`](../../emb/structured_log_remote_sync/) — это
`LogSink`-вывод, который доставляет записи на экземпляр `structured_log_server`
по HTTP, с батчингом, повтором и ограниченным буфером (раньше —
`structured_log_http` с `HttpLogOutput`; поведение то же, изменились имена):

```yaml
dependencies:
  structured_log: ^0.3.0
  structured_log_remote_sync: ^0.2.0
```

```dart
final output = RemoteSyncLogOutput(
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
— как получить секретный ключ проекта, что пакет делает сам
(батчинг/повтор/вытеснение) и как оставить рядом с ним работающий
локальный sink (консоль или просмотрщик выше). Развёртывание самого сервера
— в [Руководстве администратора / DevOps](admin-guide.ru.md).

## Куда дальше

- README каждого пакета — полный справочник API без сокращений:
  [`structured_log`](../../emb/structured_log/README.ru.md),
  [`structured_log_flutter`](../../emb/structured_log_flutter/README.ru.md),
  [`structured_log_material`](../../emb/structured_log_material/README.ru.md),
  [`structured_log_fluent`](../../emb/structured_log_fluent/README.ru.md),
  [`structured_log_cupertino`](../../emb/structured_log_cupertino/README.ru.md),
  [`structured_log_bloc`](../../emb/structured_log_bloc/README.ru.md),
  [`structured_log_dio`](../../emb/structured_log_dio/README.ru.md),
  [`structured_log_http_client`](../../emb/structured_log_http_client/README.ru.md),
  [`structured_log_go_router`](../../emb/structured_log_go_router/README.ru.md),
  [`structured_log_cherrypick`](../../emb/structured_log_cherrypick/README.ru.md),
  [`structured_log_remote_sync`](../../emb/structured_log_remote_sync/README.ru.md).
- [Руководство разработчика](developer-guide.ru.md) — когда к делу
  подключается сервер: прямые вызовы эндпоинта приёма по HTTP, чтение
  логов с сервера, программная подписка на живую ленту и аутентификация
  от имени человека, а не по секретному ключу проекта.
- [Руководство контрибьютора](contributor-guide.ru.md) — если вы
  хотите изменить один из этих пакетов, а не просто им пользоваться.
