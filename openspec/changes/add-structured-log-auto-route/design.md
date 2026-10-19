## Context

`auto_route` строится поверх `Navigator 2.0`: `RootStackRouter` держит стек страниц (`AutoRoutePage`), а `Navigator` под ним получает `NavigatorObserver` через `config(navigatorObservers: () => [...])`. `AutoRouterObserver` — наследник `NavigatorObserver` с двумя дополнительными хуками для вкладок (`didInitTabRoute`, `didChangeTabRoute`). Данные маршрута читаются из `Route.data` (расширение `RouteX`, возвращает `RouteData` страницы или `null` для не-`AutoRoutePage`).

Что известно о поведении — **проверено пробной программой** (задача 1.1, 14.10.2026, `auto_route` 11.2.0, Flutter 3.47.4), с `RootStackRouter` на четырёх маршрутах и записывающим наблюдателем:

- `push` и `pushPath` дают `didPush(route, previousRoute)`. `RouteData.name` — имя страницы, `path` — **шаблон** (`/user/:id`), `match` — **конкретное расположение** (`/user/7`), `params` — параметры пути, `queryParams` — query, `fragment` — фрагмент.
- `navigate` на ещё не открытый маршрут — тоже `didPush`.
- `maybePop` даёт `didPop(route, previousRoute)`.
- **`replace` приходит как `didPush` нового и `didRemove` старого, `didReplace` не вызывается** (стек страничный, `Navigator` сравнивает списки).
- **`navigatePath('/user/9?token=zzz#f')` при уже открытом `/user/7` не даёт ни одного события наблюдателя**: страница та же, `auto_route` обновляет её `RouteData` на месте. Слушатель самого роутера (`router.addListener`) об этом узнаёт, но в этот момент `urlState` ещё старый.
- **`RouteData.queryParams` — общее состояние роутера, а не слепок на момент события**: у предыдущего маршрута в `didPush` они уже показывают query нового, а позже у прежнего маршрута читаются пустыми. Читать их надо в момент хука и ничего не держать.
- Вкладки: при первой активации вкладки приходит `didInitTabRoute` (у второй вкладки `previousRoute` — первая), при возврате — `didChangeTabRoute(route, previousRoute)`. Вложенный `Shell`, открытый через `navigate`, даёт `didPush` оболочки и сразу `didInitTabRoute` вкладки по умолчанию.
- Переход на неизвестный путь: наблюдатель молчит, `RouteNotFoundFailure` получает только `onFailure` конкретного вызова.
- Та же проба прогнана на 11.0.0 и 10.0.0, файл `AutoRouterObserver` в 10.3.0 и 11.2.0 совпадает построчно. **Единственное расхождение — вкладки:** на 10.0.0 первое переключение на вторую вкладку приходит как `didChangeTabRoute(A → B)`, а на 11.x — как `didInitTabRoute(B, previous: A)`; первая вкладка при открытии оболочки одинаково `didInitTabRoute(A, null)`, возврат — `didChangeTabRoute`. Поэтому поле `tab_event` отражает хук, а не «первый раз».
- **9.x не поддерживается**: там нет `RouteData.params`, `PageInfo.builder`, `navigatePath`/`pushPath`; проба на нём не собирается, и покрывать вторую линию API ради версии, которая уходит, не стоит.

## Goals / Non-Goals

**Goals:**
- Подключение одной строкой: `router.config(navigatorObservers: () => [StructuredLogAutoRouteObserver()])`.
- Форма записей и настроек — как у `structured_log_go_router`: тот, кто знает один адаптер навигации, узнаёт другой.
- Секреты в расположении (токены в query, параметры пути) не попадают в лог.
- Наблюдатель не бросает в `Navigator`.

**Non-Goals:**
- Всё, что перечислено в proposal как вне рамок.
- Свой слой над `RootStackRouter`: пакет остаётся наблюдателем.

## Decisions

1. **Наблюдатель, а не обёртка роутера.** Для `go_router` выбрали `routerDelegate`, потому что `NavigatorObserver` не видел `go` и deep link. Здесь `auto_route` сам предлагает `AutoRouterObserver` с данными маршрута и вкладками, и проба показала, что `push`/`pop`/`remove`/вкладки он видит. Цена — слепые зоны решения 2.

2. **Обновление маршрута на месте не пишется.** Это единственное, что наблюдатель Navigator не видит принципиально: страница та же, событий нет. Альтернативы:
   - слушатель `RootStackRouter` (`attach(router)`, как у `structured_log_go_router`): видит обновление, но `topMatch` лежит на вложенных маршрутах неоднозначно (у вкладки `fullPath` приходит как `a`, а не `/shell/a`), срабатывает и без смены расположения, а `urlState` отстаёт. Это отдельный механизм со своими тестами;
   - ничего в первой версии, слепая зона описана в README. **Предложено.** Если на практике окажется нужным, `route_updated` добавляется отдельной заявкой, не ломая наблюдателя.

3. **События и имена.** `route_pushed` (`didPush`), `route_popped` (`didPop`), `route_removed` (`didRemove`), `route_tab_changed` (`didInitTabRoute` и `didChangeTabRoute`, поле `tab_event: 'init' | 'change'`). `didReplace` переопределяется на случай другой версии `auto_route` и пишется как `route_replaced`. Замена из пробы — `route_pushed` и `route_removed`, README говорит об этом прямо. Префикс `route_` — как у `route_changed` в `structured_log_go_router`.

4. **Поля записи.** `route` — имя (`RouteData.name`); `route_path` — шаблон; `location` — `match` с замаскированными параметрами пути, плюс `?query` и `#fragment` после маскирования; `previous_route` и `previous_location` — то же для соседа, **но `previous_location` только путём, без query и фрагмента**: проба показала, что query лежит на роутере, а не на маршруте, и у соседа читается query движущегося маршрута. Для `route_tab_changed` — `tab_index`, `previous_tab`. Маршрут без `RouteData` (диалог, bottom sheet мимо роутера) — `route` из `RouteSettings.name` или тип маршрута, `location` не пишется.

5. **Маскирование — по именам, до записи.** Набор по умолчанию — как у `structured_log_go_router` (`defaultSensitiveKeys` ядра плюс `code`), без учёта регистра. Применяется к значениям `params`, `queryParams` и к фрагменту вида `a=b`. **Это четвёртая копия правил маскирования URL**: общего пакета у `_dio`/`_http_client`/`_go_router` по-прежнему нет. Шаблон `route_path` не содержит значений и пишется как есть. `queryParams` читаются в момент хука и нигде не хранятся (проба: это общее состояние).

6. **Никогда не бросает, `filter` — fail-closed.** Хуки выполняются внутри `Navigator`: исключение там — сбой навигации. Всё обёрнуто в `try`; бросивший `filter` стоит записи, бросивший читатель `RouteData` — полей маршрута (`route_failed` с типом исключения, без текста). Как у остальных адаптеров.

7. **Уровни по умолчанию:** `pushed`, `popped`, `removed`, `tabChanged` — `info`; `null` выключает событие. `RouteLogLevels` по образцу `structured_log_go_router`.

8. **Логгер берётся на каждом хуке** (`getLogger(loggerName)`, по умолчанию `router` — как у `structured_log_go_router`, чтобы обе навигации шли одним логгером), если `BoundLogger` не передан: наблюдатель создают один раз и он переживает `StructlogConfiguration.configure`.

9. **Диапазон версий — по прогону, а не по надежде.** Проба прогнана на 10.0.0, 11.0.0 и 11.2.0, наблюдатель ведёт себя одинаково, кроме разбора вкладок (Context). Диапазон — `auto_route: ">=10.0.0 <12.0.0"`. CI-джоба гоняет тесты вторым прогоном на нижней границе, как у `go_router`/`riverpod`. `auto_route` 11.x требует `material_ui`/`cupertino_ui` — они приезжают транзитивно и в `pubspec` пакета не попадают.

## Risks / Trade-offs

- **[1] API между мажорными линиями менялся** (`PageInfo`, `RouteData`, тип `RouteType`). Наблюдателю нужны только `Route.data` и поля `RouteData`; на 10.0.0–11.2.0 они проверены пробой. Следующий мажорный релиз проверяется заново, потому верхняя граница `<12.0.0`.
- **[2] Слепая зона «обновление на месте» и «неизвестный путь»** — описаны в README и спеке как нерегистрируемые. Риск: пользователь ждёт полного журнала навигации. Смягчение — честная таблица «что видно, что нет».
- **[3] Тест без приложения**: `RootStackRouter` нужен `MaterialApp.router` и `testWidgets`, а не чистый `dart test`. Принято, пакет Flutter.

## Open Questions

- Нужен ли `route_updated` через слушатель роутера уже в первой версии (решение 2)? По умолчанию — нет.
- Стоит ли логировать неизвестный путь, если `auto_route` когда-нибудь даст глобальный хук?
