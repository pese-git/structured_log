## MODIFIED Requirements

### Requirement: API не рассчитан на обращение с другого origin
По умолчанию сервер SHALL не отдавать CORS-заголовков (`Access-Control-Allow-Origin` и прочие) ни на одном эндпоинте и SHALL не выделять preflight-запрос `OPTIONS` в особый случай. Браузерный клиент (`structured_log_admin_client`) SHALL обслуживаться с того же origin, что и API — за общим обратным прокси, — а не с отдельного адреса; это остаётся образцовым способом продакшен-развёртывания.

Оператор SHALL иметь возможность явно включить CORS для конкретных origin, перечислив их через запятую в настройке (`log-server-config`). Список пуст по умолчанию — поведение без настройки не отличается от отсутствия CORS. Для origin, отсутствующего в списке, поведение SHALL быть таким же, как если бы настройка не была задана вовсе: ни заголовков, ни ответа на preflight. Для origin из списка сервер SHALL отвечать на preflight `OPTIONS` с `Access-Control-Allow-Origin`, равным запрошенному origin (не `*`), `Access-Control-Allow-Methods` и `Access-Control-Allow-Headers`, и SHALL добавлять `Access-Control-Allow-Origin` к ответу любого эндпоинта на обычный запрос с этим origin, включая ответы с кодом ошибки. Сервер SHALL не поддерживать `Access-Control-Allow-Credentials` — аутентификация идёт через `Authorization`, не через cookie.

Требование фиксирует уже существующее поведение по умолчанию, а не вводит его заново — история сохранена в предыдущей формулировке (`add-structured-log-server`, задача 6.7): CORS отсутствовал в сервере безусловно. Явный список меняет это только для origin, названных оператором.

#### Scenario: Ответ не разрешает сторонний origin по умолчанию
- **WHEN** список разрешённых origin пуст (настройка не задана) и любой эндпоинт отвечает на запрос, пришедший с заголовком `Origin`
- **THEN** ответ не содержит `Access-Control-Allow-Origin` — браузер отклоняет его на своей стороне, и никакой настройкой клиента это не обходится

#### Scenario: Клиент и API отдаются с одного адреса
- **WHEN** `structured_log_admin_client` собирается для развёртывания
- **THEN** его базовый URL пуст, и API доступен по тому же origin, что и статика клиента — открыть API для стороннего origin значит изменить настройку сервера, а не настроить прокси

#### Scenario: Origin из явно заданного списка получает CORS-заголовки
- **WHEN** список разрешённых origin содержит `http://dev.example.test`, и запрос с заголовком `Origin: http://dev.example.test` приходит на любой эндпоинт
- **THEN** ответ содержит `Access-Control-Allow-Origin: http://dev.example.test`, независимо от кода ответа (включая 401/403/500)

#### Scenario: Preflight для origin из списка отвечает без обращения к маршруту
- **WHEN** список разрешённых origin содержит `http://dev.example.test`, и приходит `OPTIONS`-запрос с `Origin: http://dev.example.test` и `Access-Control-Request-Method`
- **THEN** сервер отвечает `204` с `Access-Control-Allow-Origin`, `Access-Control-Allow-Methods` и `Access-Control-Allow-Headers`, не обращаясь к аутентификации, ограничению частоты или маршрутизатору

#### Scenario: Origin вне списка не получает ничего, даже когда CORS включён для других
- **WHEN** список разрешённых origin непуст, но не содержит origin запроса
- **THEN** ответ не содержит `Access-Control-Allow-Origin`, а `OPTIONS` на реальный маршрут по-прежнему отвечает так, будто маршрута для этого метода нет
