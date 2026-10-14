## Why

Riverpod — один из двух основных state-менеджеров Flutter наравне с `bloc`, и у `bloc` в семействе уже есть `structured_log_bloc`, а у Riverpod нет ничего. Состояние провайдеров (создание, обновление, ошибка, удаление) видно только тому, кто сам написал `ProviderObserver`, и обычно это `print` в отладке. Поэтому оно не доходит ни до встроенного просмотрщика, ни до `structured_log_server`. Ошибка провайдера — частая причина «пустого экрана», и её стоит видеть в той же ленте, что и HTTP-вызовы и навигацию.

## What Changes

- Новый пакет `emb/structured_log_riverpod/` с `StructuredLogRiverpodObserver`, наследником `ProviderObserver` из `package:riverpod`. Он пишет записи `structured_log` с `category: 'riverpod'`:
  - `provider_added` — провайдер создан, с начальным значением;
  - `provider_updated` — значение сменилось, с прежним и новым;
  - `provider_failed` — провайдер упал, с ошибкой и стеком;
  - `provider_disposed` — провайдер удалён.
- Провайдер называется своим `name`, а без него — типом. Аргумент семейства (`family`) пишется отдельным полем. Значения пишутся через `toString()` с обрезкой, как в `structured_log_bloc`, и функцию описания можно заменить, например чтобы скрыть секреты.
- Настройка повторяет `structured_log_bloc`: уровень на хук (`null` выключает хук), `filter` по провайдеру, функция описания значений, имя логгера, категория, готовый `BoundLogger`.
- Наблюдатель никогда не бросает: исключение наблюдателя Riverpod отправляет в обработчик ошибок зоны, а во Flutter это отчёт об ошибке.
- Регистрация в `melos.yaml`, CI-джоба `riverpod-observer` со вторым прогоном тестов на нижней границе констрейнта `riverpod` и порог покрытия в `tool/coverage_floors.json`.
- Документация: README пакета (EN и RU), раздел «Related packages»/«Связанные пакеты» в README остальных живых пакетов `emb/`, корневые README, `AGENTS.md`, `docs/guides/embedding-guide.md`/`.ru.md`, главная страница и оглавление пакетов сайта.
- Вне рамок:
  - хуки мутаций Riverpod 3 (`mutation*`): API помечен экспериментальным;
  - отдельный пакет для `flutter_riverpod` или `hooks_riverpod`: оба выставляют тот же `ProviderObserver`;
  - публикация на pub.dev (делается отдельно через `melos version`/`melos publish`).

## Capabilities

### New Capabilities
- `riverpod-log-observer`: `ProviderObserver`, превращающий жизненный цикл провайдеров Riverpod в записи `structured_log` с настраиваемыми уровнями, фильтром и описанием значений, без исключений в коде провайдеров.

### Modified Capabilities
(нет)

## Impact

- Новый пакет `emb/structured_log_riverpod/` (`publish_to` не задан, версия `0.1.0-dev.0`). Зависимости: `riverpod` (не `flutter_riverpod`) и `structured_log: ^0.3.0`. Пакет чистый Dart: тестируется `dart test` и работает во Flutter-приложении через `ProviderScope(observers: [...])`.
- Меняются `melos.yaml`, `.github/workflows/ci.yml` (новая джоба) и `tool/coverage_floors.json`.
- В README остальных живых пакетов `emb/` появляется строка о новом пакете в разделе «Related packages». Код остальных пакетов не меняется.
