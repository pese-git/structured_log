## 1. structured_log_auto_route

- [x] 1.1 Сверить API `auto_route` пробной программой до написания кода (decision 1, 9, риск 1): пробная программа прогнана на 11.2.0, 11.0.0 и 10.0.0, 9.x не собирается; результаты и диапазон `>=10.0.0 <12.0.0` — в `design.md` (Context, решение 9)
- [x] 1.2 Скаффолдинг пакета `emb/structured_log_auto_route/`: `pubspec.yaml` (`auto_route: ">=10.0.0 <12.0.0"`, `structured_log: ^0.3.0`, версия `0.1.0-dev.0`, без `publish_to`), `LICENSE`, barrel-файл `lib/structured_log_auto_route.dart`
- [x] 1.3 `StructuredLogAutoRouteObserver` и `RouteLogLevels` (`lib/src/auto_route_observer.dart`): хуки `didPush`/`didPop`/`didRemove`/`didReplace`/`didInitTabRoute`/`didChangeTabRoute`, поля записи (decision 4), маскирование (decision 5), `filter` и читатель `RouteData` под `try` (decision 6), логгер на каждом хуке (decision 8)
- [x] 1.4 Тесты на каждый сценарий `specs/auto-route-logging/spec.md` (`test/auto_route_observer_test.dart`) на настоящем `RootStackRouter` под `MaterialApp.router`. Сценарии с бросающими колбэками — с проверкой, что ошибка не дошла до зоны. `StructlogConfiguration` восстанавливается в `tearDown`
- [x] 1.5 Проверить мутацией, что тесты краснеют: без `try` вокруг `filter`, без маскирования query, с `queryParams`, сохранёнными между событиями, с `path` вместо `match` в `location`, без пропуска `didRemove`, с логгером, взятым один раз в конструкторе
- [x] 1.6 `example/main.dart`: роутер с тремя маршрутами и вкладками, наблюдатель, `jsonLineOutput`

## 2. Workspace и CI

- [x] 2.1 `melos.yaml`: пакет в `packages:` и в скоупе Flutter-тестов
- [ ] 2.2 CI: строка во Flutter-матрице (`flutter test`) по образцу `structured_log_go_router` плюс второй прогон на нижней границе `auto_route` (decision 9)
- [x] 2.3 Порог покрытия в `tool/coverage_floors.json` — чуть ниже измеренного, с записью-обоснованием
- [ ] 2.4 CI зелёный на GitHub Actions

## 3. Документация

- [x] 3.1 `README.md`/`README.ru.md` пакета: установка, быстрый старт, таблица событий и полей, маскирование, настройка, **абзац о том, что не видно** (decision 2), API, «Related packages»
- [x] 3.2 Строка о пакете в «Related packages»/«Связанные пакеты» README всех остальных живых пакетов `emb/` (группа «Integrations»/«Интеграции»), число адаптеров во фразе «один из N адаптеров» увеличить на один
- [x] 3.3 Корневые `README.md`/`README.ru.md` и `AGENTS.md`: список пакетов, «Структура», раздел «Внутри `emb/structured_log_auto_route/`», CI, числа, правило «Related packages», список адаптеров в «Соглашениях»
- [x] 3.4 `docs/guides/embedding-guide.md`/`.ru.md`: раздел 7 стал общим «логирование навигации» с подразделами `go_router` и `auto_route` (как раздел 6 для `dio`/`http_client`), нумерация и якоря последующих разделов не менялись
- [x] 3.5 Сайт: оглавление пакетов, карточка, таблица интеграций, главная (EN/RU); `npm run build` проходит, страница `/packages/structured_log_auto_route/` создаётся
