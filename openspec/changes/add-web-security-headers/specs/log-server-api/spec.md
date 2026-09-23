## MODIFIED Requirements

### Requirement: API не рассчитан на обращение с другого origin
По умолчанию сервер SHALL не отдавать CORS-заголовков (`Access-Control-Allow-Origin` и прочие) ни на одном эндпоинте и SHALL не выделять preflight-запрос `OPTIONS` в особый случай. Браузерный клиент (`structured_log_admin_client`) SHALL обслуживаться с того же origin, что и API — за общим обратным прокси, — а не с отдельного адреса; это остаётся образцовым способом продакшен-развёртывания.

Оператор SHALL иметь возможность явно включить CORS для конкретных origin, перечислив их через запятую в настройке (`log-server-config`). Список пуст по умолчанию — поведение без настройки не отличается от отсутствия CORS. Для origin, отсутствующего в списке, поведение SHALL быть таким же, как если бы настройка не была задана вовсе: ни заголовков, ни ответа на preflight. Для origin из списка сервер SHALL отвечать на preflight `OPTIONS` с `Access-Control-Allow-Origin`, равным запрошенному origin (не `*`), `Access-Control-Allow-Methods` и `Access-Control-Allow-Headers`, и SHALL добавлять `Access-Control-Allow-Origin` к ответу любого эндпоинта на обычный запрос с этим origin, включая ответы с кодом ошибки. Сервер SHALL не поддерживать `Access-Control-Allow-Credentials` — аутентификация идёт через `Authorization`, не через cookie.

Включение CORS на сервере SHALL быть недостаточным само по себе: политика `Content-Security-Policy`, которую отдаёт образ браузерного клиента, ограничивает `connect-src` собственным origin, и обращение к API на другом origin SHALL отклоняться браузером до того, как CORS будет учтён, пока этот origin не назван и в политике клиента.

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

### Requirement: Развёртывание отдаёт браузеру security-заголовки
Развёртывание из `deploy/` SHALL отдавать браузерному клиенту `Content-Security-Policy`, `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy` и `Permissions-Policy` на каждом ответе, включая ответы с кодом ошибки. Ответы API SHALL нести по меньшей мере `X-Content-Type-Options` и `Referrer-Policy`.

Политика клиента SHALL ограничивать источники собственным origin. Послабления SHALL быть только теми, без которых движок не работает, и SHALL сопровождаться причиной в самом конфиге. `'unsafe-eval'` и `'unsafe-inline'` в `script-src` клиента SHALL не использоваться.

Web-бандл клиента SHALL собираться без обращения к внешним CDN, чтобы политика уровня `'self'` была достижима, а панель работала на хосте без доступа в интернет.

`Strict-Transport-Security` SHALL не отдаваться контейнерами, не терминирующими TLS.

#### Scenario: Панель не обращается к внешним origin
- **WHEN** релизный бандл загружается в браузере под политикой, ограничивающей источники собственным origin
- **THEN** страница отрисовывается, консоль не содержит ошибок, и ни одного запроса к стороннему origin не выполняется

#### Scenario: Ответ API несёт свои заголовки
- **WHEN** браузер получает ответ эндпоинта `/v1/`
- **THEN** ответ содержит `X-Content-Type-Options` и `Referrer-Policy`

#### Scenario: Заголовок не дублируется
- **WHEN** ответ клиента проходит через общий обратный прокси
- **THEN** каждый security-заголовок присутствует ровно один раз
