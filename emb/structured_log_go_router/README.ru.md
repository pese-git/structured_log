# structured_log_go_router

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

Пишет в лог, куда переходит приложение на
[`go_router`](https://pub.dev/packages/go_router), — каждую навигацию,
перенаправление и ошибку маршрутизации — записями
[`structured_log`](https://pub.dev/packages/structured_log).

`StructuredLogGoRouter` слушает `GoRouter` и пишет запись каждый раз, когда
тот переходит на новое расположение, в уже настроенные выводы — консоль,
файл, встроенный просмотрщик логов (`structured_log_flutter`) или
`structured_log_server` через `structured_log_remote_sync`. Рядом с записями `bloc`
от `structured_log_bloc` и `http` от `structured_log_dio` /
`structured_log_http_client` он отвечает на первый вопрос большинства
баг-репортов: *на каком экране был пользователь?*

## Возможности

- **Подключается к любому роутеру** — `routeLog.attach(router)`; считаются
  `go`, `push`, `pop`, deep link и кнопка «назад» браузера
- **Шаблон рядом с расположением** — `/users/42` пишется вместе с маршрутом
  `/users/:id` и именем маршрута, так что экраны группируются без разбора URL
- **Откуда пришёл пользователь** — `previous_location` в каждой записи
- **Перенаправления и ошибки маршрутизации** — оберните `redirect` и
  `onException`, чтобы писать и их; страница «не найдено» пишется без
  обёрток
- **Токены не попадают в лог** — query-параметры, похожие на токены,
  маскируются и в query, и во фрагменте в стиле OAuth (`#access_token=...`);
  `extra` не пишется никогда
- **Своя категория** — каждая запись несёт `category: 'navigation'`
- **Никогда не ломает навигацию** — если фильтр бросит исключение, пропадёт
  только запись; ответ и исключения обёрнутого redirect доходят до роутера
  без изменений

## Установка

Опубликован на pub.dev как пре-релиз (`0.1.0-dev.1`):

```yaml
dependencies:
  go_router: ">=17.0.0 <19.0.0"
  structured_log: ^0.2.1
  structured_log_go_router: ^0.1.0-dev.1
```

## Быстрый старт

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_go_router/structured_log_go_router.dart';

void main() {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );

  final routeLog = StructuredLogGoRouter();
  final router = GoRouter(
    routes: [/* ... */],
    redirect: routeLog.redirect(authRedirect), // по желанию
  );
  routeLog.attach(router);

  runApp(MaterialApp.router(routerConfig: router));
}
```

```text
INFO:  route_changed    {"category":"navigation","location":"/","route":"/","route_name":"home"}
DEBUG: route_redirected {"category":"navigation","from":"/settings","to":"/login"}
INFO:  route_changed    {"category":"navigation","location":"/login","route":"/login","previous_location":"/","previous_route":"/"}
```

[example/main.dart](example/main.dart) — небольшое приложение с тремя
экранами, перенаправлением и страницей «не найдено». Платформенных папок у
пакета нет, поэтому запускайте его как `lib/main.dart` любого
Flutter-приложения, зависящего от этого пакета.

## Что пишется в лог

| Запись             | Когда | Уровень по умолчанию | Поля |
|--------------------|-------|----------------------|------|
| `route_changed`    | роутер перешёл на новое расположение — `go`, `push`, `pop`, deep link, кнопка «назад» браузера | `info` | `location`, `route` (шаблон), `route_name`, если у маршрута есть имя, `previous_location`, `previous_route` |
| `route_redirected` | redirect, обёрнутый `routeLog.redirect(...)`, отправил навигацию в другое место | `debug` | `from`, `to` |
| `route_error`      | расположение не совпало ни с одним маршрутом, или маршрутизация сломалась иначе | `warning` | `location`, `error` |

`route_error` попадает в лог в обоих режимах ошибок `go_router`: с
`errorBuilder`/`errorPageBuilder` (или без них) `attach` видит, как роутер
переходит на страницу ошибки; с `onException` роутер остаётся на месте,
поэтому оберните обработчик — `onException: routeLog.onException(handler)`.

Видны только страницы самого роутера. Диалог или bottom sheet, открытые
через `showDialog`/`showModalBottomSheet`, — не расположение и в лог не
попадают.

## Как не пустить секреты в лог

Расположения пишутся как есть — включая path-параметры, потому что именно
они определяют экран, — с двумя исключениями:

- значения из `defaultRedactedQueryParameters` — `access_token`,
  `refresh_token`, `id_token`, `token`, `api_key`, `apikey`, `password`,
  `client_secret` и `code` (код авторизации OAuth, который несёт callback
  входа) — заменяются на `REDACTED` и в query, и во фрагменте того же вида
  (`#access_token=...`). Набор меняется параметром `redactedQueryParameters`
  (имена в нижнем регистре; сравнение без учёта регистра);
- `extra` и другие объекты состояния маршрута не пишутся никогда.

Если чувствителен сам path-параметр (email в `/invite/:email`), исключите
такой маршрут через `filter`.

## Настройка

```dart
StructuredLogGoRouter(
  // Какие записи писать и с каким уровнем; null выключает.
  levels: const RouteLogLevels(navigation: LogLevel.debug),
  // Экран — мимо лога; только его навигации, redirect и ошибки остаются.
  filter: (state) => state.fullPath != '/invite/:email',
  category: 'ui',
);
```

Повторный `attach` переносит слушателя на другой роутер; `detach` —
перед `dispose` роутера, к которому он подключён.

## Справочник API

| Символ | Описание |
|---|---|
| `StructuredLogGoRouter({logger, loggerName, category, levels, redactedQueryParameters, filter})` | Логгер навигации. Без `logger` вызывает `getLogger(loggerName)` (`router`) на каждой записи, поэтому до него доходит и более поздний `StructlogConfiguration.configure`. `category: null` не привязывает категорию. |
| `attach(router)` / `detach()` | Начать писать навигации роутера — включая расположение, на котором он уже стоит, — или перестать. |
| `redirect(inner)` | Оборачивает `GoRouterRedirect` верхнего уровня или маршрута, записывая каждое перенаправление; синхронный redirect остаётся синхронным. |
| `onException(inner)` | Оборачивает `GoExceptionHandler`, записывая каждую ошибку маршрутизации перед передачей дальше. |
| `RouteLogLevels({navigation, redirect, error})` | `LogLevel?` на каждую запись; `null` выключает. |
| `defaultRedactedQueryParameters`, `redactedValue` | Набор маскирования по умолчанию и значение (`REDACTED`), которым заменяется найденное. |

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
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — наблюдатель DI-контейнера `cherrypick`

## Лицензия

См. [LICENSE](LICENSE).
