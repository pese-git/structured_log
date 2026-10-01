## Why

`structured_log_server` и `structured_log_admin_client` собраны на DI-контейнере [`cherrypick`](https://pub.dev/packages/cherrypick), и оба пишут его работу в `structured_log` своим `StructuredLogCherryPickObserver` — двумя дословными копиями одного класса. То же нужно любому приложению на `cherrypick`: проводка, которая молча не состоялась (скоуп не открылся, модуль не установился), видна только по журналу контейнера. Встраиваемый пакет делает этого наблюдателя доступным приложениям вне репозитория и становится тем, на что можно перевести обе копии.

## What Changes

- Новый пакет `emb/structured_log_cherrypick/` со `StructuredLogCherryPickObserver implements CherryPickObserver`: те же имена событий (`di.scope_opened`, `di.modules_installed`, `di.cycle_detected`, `di.error`, …) и поля, что у существующих копий, плюс `category: 'di'`, уровень на каждый хук (`DiLogLevels`, `null` выключает), необязательные записи на каждое разрешение, свой логгер.
- Экземпляр не пишется никогда; ошибка — по типу; `details` отбрасываются.
- Поддержка `cherrypick` 3.x и 4.x; CI гоняет тесты на обеих.
- Регистрация в `melos.yaml`, CI-джоба `cherrypick-observer`, порог покрытия.
- Документация: README пакета (EN/RU), корневые README, `AGENTS.md`, руководство по внедрению (новый раздел 7, раздел про сервер стал 8-м), сайт.
- Вне рамок: перевод сервера и admin-клиента на пакет (отдельный шаг: затрагивает их зависимости и Docker-сборку сервера); публикация на pub.dev; `configureContainer` (включение детекции циклов — политика приложения, а не логирования).

## Capabilities

### New Capabilities
- `cherrypick-log-observer`: наблюдатель DI-контейнера `cherrypick`, пишущий его работу в `structured_log`.

### Modified Capabilities
(нет)

## Impact

- Новый пакет `emb/structured_log_cherrypick/` (версия `0.1.0-dev.0`); зависимости — `cherrypick: ">=3.0.0 <5.0.0"`, `structured_log: ^0.2.1`; `sdk: ^3.2.0` — нижняя граница самого `cherrypick` 3.x.
- `melos.yaml`, `.github/workflows/ci.yml`, `tool/coverage_floors.json`.
- Сервер и admin-клиент не меняются: их копии наблюдателя остаются на месте.
