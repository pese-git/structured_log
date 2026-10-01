# Руководство по внедрению

*Read in [English](embedding-guide.md).*

Для тех, кто хочет добавить структурированное логирование — и, по
желанию, живой просмотрщик логов внутри приложения — в собственное
Dart- или Flutter-приложение. Здесь ничто не обращается к
`structured_log_server`: каждый пакет ниже работает самостоятельно, в
проекте, который вообще не запускает сервер. Если вам нужно доставлять
логи на self-hosted экземпляр `structured_log_server` (или запрашивать
их обратно) — см. [Руководство разработчика](developer-guide.ru.md): оно
начинается ровно там, где заканчивается необязательный последний раздел
этого руководства.

Несколько пакетов, и нужно ровно столько из них, сколько требует ваш проект:

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
   тонкий add-on поверх `LogSink`; кратко описан здесь, подробно — в
   Руководстве разработчика.

Все три viewer-скина используют одно и то же ядро
`structured_log_flutter`, так что сменить скин позже — вопрос выбора
импортируемого виджета, а не переделки слоя данных.

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

Если в записи могут попадать учётные данные — карта заголовков, тело
запроса, дамп конфигурации, — поставьте процессор затирания сразу при
настройке: секрет, дошедший до sink'а, уже утёк.

```dart
StructlogConfiguration.configure(
  processors: [redactKeys(), dropNullValues],  // до любого рендерера
);
```

`redactKeys()` заменяет `password`, `token`, `authorization` и остальные
имена из `defaultSensitiveKeys` на любой глубине, а где их не хватает —
принимает ваши собственные имена или предикаты.

Полный API — процессоры, мульти-sink роутинг, файловый и ротируемый
вывод — в
[`emb/structured_log/README.md`](../../emb/structured_log/README.md).

## 2. Headless-ядро просмотрщика: `structured_log_flutter`

Если вы хотите построить собственный UI просмотра логов, а не
пользоваться одним из готовых скинов из следующего раздела, стройте на
[`structured_log_flutter`](../../emb/structured_log_flutter/) —
ограниченном `LogBuffer` (`OutputFunction`, подключаемом к `LogSink`,
хранит в памяти последние записи) и `LogViewerController` (фильтрация
по уровню/категории/тексту поиска, пауза, очистка). Сам он ничего не
рисует и не привязан ни к какой дизайн-системе:

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

`logLevelColor()` — единственное визуальное решение, которое пакет
всё-таки навязывает (соответствие `LogLevel` → `Color`, общее для всех
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
брейкпоинта (список и панель деталей рядом), а ниже него сворачиваются в
паттерн из таблицы выше — измеряется по собственной ширине виджета
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

// Или встроенный в интерфейс существующего приложения (боковая панель, вкладка, ...):
MaterialLogViewer(controller: controller)
```

`controller` — тот же `LogViewerController` из предыдущего раздела:
скин чисто презентационный. У каждого пакета есть рабочий web-пример в
собственной директории `example/`, а его README покрывает полный API
виджетов:
[`structured_log_material`](../../emb/structured_log_material/README.md),
[`structured_log_fluent`](../../emb/structured_log_fluent/README.md),
[`structured_log_cupertino`](../../emb/structured_log_cupertino/README.md).

## 4. Опционально: логировать блоки: `structured_log_bloc`

Если логика приложения живёт в блоках и кубитах
([`bloc`](https://pub.dev/packages/bloc) /
[`flutter_bloc`](https://pub.dev/packages/flutter_bloc)),
[`structured_log_bloc`](../../emb/structured_log_bloc/) пишет всё, что
делает каждый из них — создание, события, смену состояния, ошибки,
закрытие, — в настроенные выше выводы, включая встроенный просмотрщик:

```yaml
dependencies:
  structured_log: ^0.2.1
  structured_log_bloc:
    path: ../structured_log_bloc   # пока не на pub.dev (0.1.0-dev.0) — path- или git-зависимость
```

```dart
StructlogConfiguration.configure(sinks: [
  LogSink(name: 'console', output: coloredConsoleOutput),
]);
Bloc.observer = StructuredLogBlocObserver();
```

Каждая запись несёт `category: 'bloc'`, так что фильтр категорий в
просмотрщике отделяет трафик блоков от остального, а `LogSink` с
`categories: {'bloc'}` может направить его отдельно. Пакет зависит
только от `package:bloc` — `flutter_bloc` реэкспортирует тот же
`Bloc.observer`, — поэтому ничего Flutter-специфичного ему не нужно.

**По умолчанию состояния и события пишутся через `toString()`.** Если в
них бывают пароли, токены или персональные данные, передайте
`describe`, который их скрывает, — см.
[README](../../emb/structured_log_bloc/README.ru.md#как-не-пустить-секреты-в-лог)
пакета; там же перечислены все записи и настройка уровня на каждый хук.

## 5. Опционально: логировать HTTP-вызовы

Два пакета, по одному на HTTP-клиент, с одинаковыми записями
(`http_request`, затем `http_response` или `http_error`, связанные
`http_request_id`), одинаковыми уровнями по статусу и одинаковым
маскированием. Выбирайте тот, что подходит к клиенту приложения.

### `dio`: `structured_log_dio`

Если приложение ходит на свой бэкенд через [`dio`](https://pub.dev/packages/dio),
[`structured_log_dio`](../../emb/structured_log_dio/) пишет каждый запрос и
то, чем он закончился, — ответ, ошибку, таймаут, отмену — с длительностью
и уровнем по статусу ответа:

```yaml
dependencies:
  structured_log: ^0.2.1
  structured_log_dio:
    path: ../structured_log_dio   # пока не на pub.dev (0.1.0-dev.0) — path- или git-зависимость
```

```dart
final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
  ..interceptors.add(StructuredLogDioInterceptor()); // добавлять последним
```

Записи несут `category: 'http'` — рядом с `bloc` от блоков, так что
просмотрщик может показать любую из них отдельно. Заголовки и тела не
пишутся, пока их не включить, а `Authorization`, cookie и query-параметры
с токенами маскируются. Но включённое тело пишется как есть — прежде чем
включать тела для вызовов входа или выдачи токенов, см.
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
  structured_log: ^0.2.1
  structured_log_http_client:
    path: ../structured_log_http_client   # пока не на pub.dev (0.1.0-dev.0) — path- или git-зависимость
```

```dart
final client = StructuredLogHttpClient(http.Client());
await client.get(Uri.parse('https://api.example.com/items'));
```

`package:http` не бросает исключений из-за статуса, поэтому 404 — это
`http_response` на уровне `warning`. При включённом `logResponseBody` тело
не буферизуется — оно доходит до вашего кода по мере поступления, — а
запись об ответе пишется, когда тело прочитано; см.
[README](../../emb/structured_log_http_client/README.ru.md#что-пишется-в-лог)
пакета.

## 6. Опционально: логировать навигацию: `structured_log_go_router`

Если маршрутизация приложения построена на
[`go_router`](https://pub.dev/packages/go_router),
[`structured_log_go_router`](../../emb/structured_log_go_router/) пишет
каждую навигацию — расположение, шаблон маршрута (`/users/:id`) и
предыдущее расположение, — так что лог говорит, на каком экране был
пользователь, когда что-то пошло не так:

```yaml
dependencies:
  structured_log: ^0.2.1
  structured_log_go_router:
    path: ../structured_log_go_router   # пока не на pub.dev (0.1.0-dev.0) — path- или git-зависимость
```

```dart
final routeLog = StructuredLogGoRouter();
final router = GoRouter(
  routes: [/* ... */],
  redirect: routeLog.redirect(authRedirect), // по желанию: пишет и перенаправления
);
routeLog.attach(router);
```

Записи несут `category: 'navigation'` — рядом с `bloc` и `http`.
Query-параметры с токенами — включая `code` из callback OAuth и фрагмент
`#access_token=...` — маскируются; path-параметры — нет, поэтому если
маршрут несёт в пути что-то чувствительное, см.
[README](../../emb/structured_log_go_router/README.ru.md#как-не-пустить-секреты-в-лог)
пакета.

## 7. Опционально: логировать DI-контейнер: `structured_log_cherrypick`

Если приложение собрано на [`cherrypick`](https://pub.dev/packages/cherrypick),
[`structured_log_cherrypick`](../../emb/structured_log_cherrypick/) пишет,
что делает контейнер, — открытие и закрытие скоупов, установку модулей,
циклы зависимостей, ошибки разрешения, — и так становится видна проводка,
которая молча не состоялась:

```yaml
dependencies:
  structured_log: ^0.2.1
  structured_log_cherrypick:
    path: ../structured_log_cherrypick   # пока не на pub.dev (0.1.0-dev.0) — path- или git-зависимость
```

```dart
// До первого скоупа: скоуп берёт глобального наблюдателя при создании.
CherryPick.setGlobalObserver(StructuredLogCherryPickObserver());
```

Записи несут `category: 'di'`. Экземпляр не пишется никогда — только имя и
тип, под которыми он связан, — так что наблюдать контейнер с клиентами и
хранилищами токенов безопасно. Отчёты на каждое разрешение по умолчанию
выключены; как их включить и что сам контейнер сообщает, а что нет, — в
[README](../../emb/structured_log_cherrypick/README.ru.md#что-пишется-в-лог)
пакета.

## 8. Опционально: доставлять логи и на сервер

Всё выше — полностью локально: без сети, без сервера. Если нужно ещё и
собирать эти логи централизованно (искать их между перезапусками,
делиться ими внутри команды, хранить по расписанию),
[`structured_log_remote_sync`](../../emb/structured_log_remote_sync/) — это
`LogSink`-вывод, доставляющий записи на экземпляр `structured_log_server`
по HTTP, с батчингом, повтором и ограниченным буфером (раньше —
`structured_log_http` с `HttpLogOutput`; поведение то же, изменились имена):

```yaml
dependencies:
  structured_log: ^0.2.1
  structured_log_remote_sync: ^0.1.0
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
  [`structured_log_bloc`](../../emb/structured_log_bloc/README.ru.md),
  [`structured_log_dio`](../../emb/structured_log_dio/README.ru.md),
  [`structured_log_http_client`](../../emb/structured_log_http_client/README.ru.md),
  [`structured_log_go_router`](../../emb/structured_log_go_router/README.ru.md),
  [`structured_log_cherrypick`](../../emb/structured_log_cherrypick/README.ru.md),
  [`structured_log_remote_sync`](../../emb/structured_log_remote_sync/README.ru.md).
- [Руководство разработчика](developer-guide.ru.md) — когда в дело
  вступает сервер: эндпоинт приёма по HTTP напрямую, запрос логов
  обратно, живая лента программно и аутентификация от лица человека, а
  не по секретному ключу проекта.
- [Руководство контрибьютора](contributor-guide.ru.md) — если вы
  хотите изменить один из этих пакетов, а не просто им пользоваться.
