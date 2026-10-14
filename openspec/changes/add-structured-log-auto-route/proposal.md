## Why

`auto_route` — один из двух самых распространённых роутеров Flutter наравне с `go_router`, и у `go_router` в семействе уже есть `structured_log_go_router`, а у `auto_route` нет ничего. Навигация (экран открыт, закрыт, вкладка переключена) видна только тому, кто сам написал `AutoRouterObserver`, и обычно это `print` в отладке. Поэтому она не доходит ни до встроенного просмотрщика, ни до `structured_log_server`. «Как пользователь сюда попал?» — первый вопрос к любой ошибке на экране, и ответ стоит видеть в той же ленте, что и HTTP-вызовы и состояние провайдеров.

## What Changes

- Новый пакет `emb/structured_log_auto_route/` с `StructuredLogAutoRouteObserver`, наследником `AutoRouterObserver` из `package:auto_route`. Он пишет записи `structured_log` с `category: 'navigation'`:
  - `route_pushed` — экран открыт;
  - `route_popped` — экран закрыт;
  - `route_removed` — экран убран из стека мимо `pop` (в том числе при `replace`);
  - `route_tab_changed` — вкладка `TabsRouter` активирована или переключена.
- Маршрут называется своим именем (`RouteData.name`), шаблон пути (`/user/:id`) лежит в `route_path`, а конкретное расположение (`/user/7`) — в `location`. Значения параметров пути, query и фрагмента проходят маскирование по именам.
- Настройка повторяет остальные адаптеры: уровень на событие (`null` выключает), `filter`, имя логгера, категория, готовый `BoundLogger`.
- Наблюдатель никогда не бросает: он выполняется внутри `Navigator`, и исключение там — это сбой навигации.
- Регистрация в `melos.yaml`, CI-джоба `auto-route-observer` с прогоном на нижней границе констрейнта и порог покрытия.
- Документация: README пакета (EN и RU), раздел «Related packages»/«Связанные пакеты» в README остальных живых пакетов `emb/`, корневые README, `AGENTS.md`, `docs/guides/embedding-guide.md`/`.ru.md`, главная страница и оглавление пакетов сайта.
- Вне рамок:
  - обновление параметров **того же** маршрута на месте (`navigatePath('/user/9')` при открытом `/user/7`): наблюдатель Navigator о нём не узнаёт (см. design, решение 2), открыто для обсуждения;
  - переход на несуществующий путь: `auto_route` сообщает о нём только через `onFailure` конкретного вызова;
  - защитники маршрутов (`AutoRouteGuard`) и логирование их решений;
  - публикация на pub.dev (делается отдельно через `melos version`/`melos publish`).

## Capabilities

### New Capabilities
- `auto-route-logging`: `AutoRouterObserver`, превращающий навигацию `auto_route` в записи `structured_log` с настраиваемыми уровнями и фильтром, с маскированием параметров расположения и без исключений в навигаторе.

### Modified Capabilities
(нет)

## Impact

- Новый пакет `emb/structured_log_auto_route/` (`publish_to` не задан, версия `0.1.0-dev.0`). Зависимости: `auto_route` и `structured_log: ^0.3.0`. **Flutter-пакет**: `auto_route` тянет Flutter, поэтому `flutter test` и строка во Flutter-матрице CI, как у `structured_log_go_router`.
- Меняются `melos.yaml`, `.github/workflows/ci.yml` (новая джоба, строка матрицы) и `tool/coverage_floors.json`.
- В README остальных живых пакетов `emb/` появляется строка о новом пакете в разделе «Related packages». Код остальных пакетов не меняется.
