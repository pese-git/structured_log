## Why

`structured_log_bloc`, `structured_log_dio` и `structured_log_http_client` уже пишут, что приложение делало и с кем разговаривало. Не хватает ответа на первый вопрос большинства баг-репортов — на каком экране был пользователь и как он туда попал. Во Flutter-приложениях на [`go_router`](https://pub.dev/packages/go_router) эта информация есть в одном месте, у роутера, но готового способа направить её в `structured_log` нет.

## What Changes

- Новый Flutter-пакет `emb/structured_log_go_router/` со `StructuredLogGoRouter`: `attach(router)` слушает `GoRouter` и пишет `route_changed` (`location`, `route` — шаблон, `route_name`, `previous_location`/`previous_route`) на каждый переход; обёртка `redirect(...)` пишет `route_redirected` (`from`, `to`); ошибка маршрутизации — `route_error` (через слушатель при странице ошибки или через обёртку `onException(...)`).
- `category: 'navigation'`, уровни на каждую запись (`RouteLogLevels`), фильтр, свой логгер.
- Маскирование query-параметров с токенами — в query и во фрагменте вида `a=b`; `extra` не пишется.
- Регистрация в `melos.yaml` (`test:flutter`), строка во Flutter-матрице CI, порог покрытия.
- Документация: README пакета (EN/RU), корневые README, `AGENTS.md`, руководство по внедрению (новый раздел 6, раздел про сервер стал 7-м), сайт.
- Вне рамок: публикация на pub.dev; `NavigatorObserver` для диалогов и bottom sheet; обёртка `onEnter`.

## Capabilities

### New Capabilities
- `go-router-logging`: запись навигаций, перенаправлений и ошибок маршрутизации `go_router` в `structured_log`.

### Modified Capabilities
(нет)

## Impact

- Новый пакет `emb/structured_log_go_router/` (версия `0.1.0-dev.0`); зависимости — `flutter`, `go_router: ">=17.0.0 <19.0.0"`, `structured_log: ^0.2.1`; `sdk: ^3.10.0`, `flutter: ">=3.38.0"` — нижние границы `go_router` 17.
- `melos.yaml`, `.github/workflows/ci.yml` (Flutter-матрица), `tool/coverage_floors.json`.
