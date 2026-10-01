## Why

`dio` — самый распространённый HTTP-клиент во Flutter-приложениях, и при разборе инцидента первым делом нужно знать, какие запросы ушли, чем закончились и сколько заняли. У `dio` для этого есть шов — `Interceptor`, — но штатный `LogInterceptor` печатает текст через `print`, пишет заголовки (включая `Authorization`) и тела без маскирования и не попадает ни во встроенный просмотрщик логов, ни на `structured_log_server`. После `structured_log_bloc` это второй источник логов приложения, который стоит подключать одной строкой.

## What Changes

- Новый пакет `emb/structured_log_dio/` с `StructuredLogDioInterceptor extends Interceptor`: запись `http_request` на отправку и `http_response`/`http_error` на итог, связанные `http_request_id`, с `category: 'http'`, `method`, `url`, `status_code`, `duration_ms`.
- Уровень итога — по статусу ответа (`HttpLogLevels`: успех/4xx/5xx/сбой без ответа/отмена, `null` выключает), фильтр запросов, свой логгер/категория.
- Секреты по умолчанию не пишутся: заголовки и тела выключены; при включении — маскирование заголовков авторизации и cookie; query-параметры с токенами и user info в URL маскируются всегда; заменяемая функция описания тел.
- Регистрация в `melos.yaml`, CI-джоба `dio-interceptor`, порог покрытия.
- Документация: README пакета (EN/RU), корневые README, `AGENTS.md`, руководство по внедрению, сайт.
- Вне рамок: публикация на pub.dev; подключение перехватчика в `structured_log_admin_client` (у клиента своя история с перехватчиками — отдельное решение); поддержка `http`/`HttpClient`.

## Capabilities

### New Capabilities
- `dio-log-interceptor`: перехватчик `dio`, превращающий каждый HTTP-вызов в пару записей `structured_log` с маскированием секретов.

### Modified Capabilities
(нет)

## Impact

- Новый пакет `emb/structured_log_dio/` (версия `0.1.0-dev.0`); зависимости — `dio: ^5.4.0`, `structured_log: ^0.2.1`.
- `melos.yaml`, `.github/workflows/ci.yml`, `tool/coverage_floors.json`.
- Остальные пакеты не меняются.
