## Why

Во Flutter-приложениях на `flutter_bloc` основная логика живёт в блоках и кубитах, и именно их события и смены состояния нужны при разборе инцидента. `bloc` даёт для этого один глобальный шов — `Bloc.observer`, — но писать в него приходится каждому приложению самостоятельно, обычно через `print`/`debugPrint`, и эти строки не попадают ни во встроенный просмотрщик логов (`structured_log_flutter` и скины), ни на `structured_log_server` через `structured_log_http`. Готовый наблюдатель, пишущий в `structured_log`, подключает весь трафик блоков к уже настроенным выводам одной строкой.

## What Changes

- Новый пакет `emb/structured_log_bloc/` с `StructuredLogBlocObserver extends BlocObserver`: одна запись `structured_log` на каждый хук (`onCreate`/`onEvent`/`onChange`/`onTransition`/`onError`/`onDone`/`onClose`), с `category: 'bloc'`, типом блока и идентичностью экземпляра в каждой записи.
- Уровень на каждый хук (`BlocLogLevels`, `null` выключает), фильтр блоков, своя категория/логгер, заменяемая функция описания значений (`describe`) для сокрытия секретов.
- Регистрация в `melos.yaml` (`packages:` и scope `test:dart`), отдельная CI-джоба `bloc-observer`, порог покрытия в `tool/coverage_floors.json`.
- Документация: `README.md`/`README.ru.md` пакета, корневые README, `AGENTS.md`, оглавление пакетов и главная страница сайта.
- Вне рамок: публикация на pub.dev (делается `melos version`/`melos publish` отдельно), Flutter-виджеты, обёртки вокруг отдельных блоков (миксины/базовые классы).

## Capabilities

### New Capabilities
- `bloc-log-observer`: `BlocObserver`, превращающий жизненный цикл, события, смены состояния и ошибки блоков и кубитов в записи `structured_log`.

### Modified Capabilities
(нет)

## Impact

- Новый пакет `emb/structured_log_bloc/` (`publish_to` не задан — готов к публикации, версия `0.1.0-dev.0`); зависимости — `bloc: ^9.0.0` и `structured_log: ^0.2.1`.
- `melos.yaml`, `.github/workflows/ci.yml` (новая джоба), `tool/coverage_floors.json`.
- `structured_log` и остальные пакеты не меняются.
