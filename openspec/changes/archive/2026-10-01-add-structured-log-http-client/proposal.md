## Why

`structured_log_dio` закрыл логирование HTTP-вызовов для приложений на `dio`, но многие Dart- и Flutter-приложения (и пакеты, на которых они построены) ходят в сеть через `package:http` — официальный клиент команды Dart, под который есть и нативные реализации (`cupertino_http`, `cronet_http`). У `package:http` нет перехватчиков, поэтому подключить к нему логирование «одной строкой» сейчас нечем.

## What Changes

- Новый пакет `emb/structured_log_http_client/` со `StructuredLogHttpClient extends http.BaseClient` — обёрткой над любым `http.Client` с теми же записями (`http_request`, `http_response`/`http_error`, `http_request_id`), уровнями по статусу и маскированием, что у `structured_log_dio`.
- Тело ответа логируется без буферизации: поток пропускается к читателю, для лога сохраняется начало.
- Прерывание через `abortTrigger` (`RequestAbortedException`) — отдельный уровень `cancel`.
- Регистрация в `melos.yaml`, CI-джоба `http-client`, порог покрытия.
- Документация: README пакета (EN/RU), корневые README, `AGENTS.md`, руководство по внедрению (раздел 5 становится общим разделом про HTTP-вызовы с подразделами для `dio` и `package:http`), сайт.
- Вне рамок: публикация на pub.dev; общий пакет с правилами маскирования для `dio` и `http`.

## Capabilities

### New Capabilities
- `http-client-logging`: обёртка `http.Client`, превращающая каждый HTTP-вызов в пару записей `structured_log` с маскированием секретов.

### Modified Capabilities
(нет)

## Impact

- Новый пакет `emb/structured_log_http_client/` (версия `0.1.0-dev.0`); зависимости — `http: ^1.5.0` (`RequestAbortedException` появился в 1.5.0), `structured_log: ^0.2.1`; `sdk: ^3.4.0` — нижняя граница самого `http`.
- Имя `structured_log_http` уже занято отправщиком логов на сервер (`HttpLogOutput`); новый пакет назван `structured_log_http_client`, различие подчёркнуто в README обоих направлений.
- `melos.yaml`, `.github/workflows/ci.yml`, `tool/coverage_floors.json`.
