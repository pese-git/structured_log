## Why

Refresh-токен admin-клиента лежит в `localStorage` браузера, и «защищённое хранилище» из decision 20 на web им и является.

`structured_log_admin_client` собирается только под web — из платформенных директорий у пакета есть одна, `web/`. Значит за интерфейсом `flutter_secure_storage` работает `flutter_secure_storage_web`, разрешённый в `pubspec.lock` версией `1.2.1`. Что он делает, видно в его исходниках: значение кладётся в `window.localStorage` под ключом `"FlutterSecureStorage.<имя>"`, а ключ AES-GCM экспортируется **raw** и кладётся в тот же `localStorage` под `"FlutterSecureStorage"`. Расшифровка — три строки для любого скрипта на этом origin. Шифрование здесь защищает от человека, читающего DevTools глазами, а не от кода.

Decision 20 (`add-structured-log-server/design.md`) обосновывала выбор пакета перечислением Keychain (iOS/macOS) / Keystore (Android) / Credential Manager (Windows) и прямо называла `localStorage` тем, что `shared_preferences` делает неправильно. На единственной платформе, куда этот клиент собирается, обёртка и то, от чего она защищает, — одно и то же плюс обфускация.

Под ударом не 15-минутный access-токен, а refresh: `TokenService` выдаёт его на 30 дней, и он напрямую переоформляет сессию.

Остроту снижает строгий CSP (`frontend/structured_log_admin_client/nginx.conf`, change `add-web-security-headers`): `script-src 'self' 'wasm-unsafe-eval'` без `unsafe-inline`, `object-src 'none'`, `connect-src 'self'`. Дотянуться до `localStorage` можно только скриптом с того же origin, а Flutter рисует в canvas и DOM-синков для инъекции не предоставляет. Поэтому это «защита стоит не там, где о ней написано», а не живая дыра — но защита, которую браузер даёт бесплатно и которой клиент не пользуется, называется `HttpOnly`.

## What Changes

- **Сервер ставит refresh-токен в cookie** — `HttpOnly; Secure; SameSite=Strict; Path=/v1/auth; Max-Age=<refresh TTL>` — на успешный `grant_type=password` и `grant_type=refresh_token`, и гасит её (`Max-Age=0`) на `DELETE /v1/auth/token`.
- **Тело ответа продолжает нести `refresh_token`.** Cookie — дополнение, а не замена: curl из `docs/guides/developer-guide.md`, скрипты операторов и `packages/e2e` на Dart VM работают ровно как сегодня, ничего не зная о cookie.
- **Форма выигрывает у cookie** на всех трёх эндпоинтах (`POST`/`DELETE /v1/auth/token`, `POST /v1/auth/change-password`). Поле формы — явное намерение вызывающего, cookie — окружение, которое браузер подставляет сам; вызывающий, сознательно назвавший другой токен, должен получить именно его.
- **Новое поле ответа `refresh_token_cookie_set`** (boolean) — единственный источник правды о режиме для клиента. `true` означает «сервер также поставил cookie; если ваша платформа их хранит, пользуйтесь ей и не сохраняйте копию из тела». Клиент не конфигурируется вовсе, и рассогласование настроек невозможно by construction.
- **Новая настройка `--refresh-token-cookie` / `STRUCTURED_LOG_REFRESH_TOKEN_COOKIE`** со значениями `auto` (по умолчанию) / `on` / `off`. `auto` не ставит cookie, когда `Origin` запроса перечислен в `--cors-allowed-origins` — оператор, вписавший origin в этот список, тем самым объявил его чужим.
- **`Access-Control-Allow-Credentials: true`** в `cors_middleware.dart` — без него cookie не поедет ни в одной CORS-топологии. Change `add-server-cors` явно записала обратное («клиент передаёт токен в `Authorization`, не через cookie»); это требование снимается.
- **Клиент в режиме cookie не хранит refresh-токен вовсе**, а access-токен переезжает из `localStorage` в `sessionStorage` — он пер-вкладочный, переживает перезагрузку страницы и умирает вместе с вкладкой.
- **Старт приложения перестаёт быть локальным вопросом.** `RestoreSession` сегодня только спрашивает хранилище и на сервер не ходит; при пустом `sessionStorage` в режиме cookie он SHALL пробовать `grant_type=refresh_token` — наличие сессии клиенту иначе неизвестно.
- **Гонка обновления между вкладками закрывается в клиенте** (`navigator.locks`), а не ослаблением защиты от повторного использования на сервере — обоснование в `design.md`, decision 7.
- **`AuthInterceptor._renameSpentRefreshToken` остаётся, но перестаёт работать в режиме cookie.** Первая редакция этого предложения обещала его удалить: он существует потому, что сервер не мог опознать сессию вызывающего иначе, чем по предъявленному значению токена, а cookie даёт ровно такой способ. Но режим без cookie никуда не девается — это вся топология с раздельными хостами, — и там клиент по-прежнему называет свой токен в теле, а перехватчик по-прежнему ротирует его между построением запроса и повтором. Удаление вернуло бы дефект #54 ровно тем развёртываниям, которые не могут пользоваться cookie. Поэтому вызов обусловлен наличием токена у клиента: в режиме cookie тело не называет ничего, и чинить нечего.

Вне объёма:

- **Разные регистрируемые домены остаются без cookie.** `SameSite` рассуждает о site (eTLD+1), а не об origin, поэтому разделение по поддоменам одного домена (`admin.example.com` + `api.example.com`) работает и включается через `--refresh-token-cookie=on`; клиент и API на разных доменах — нет, и для них `auto` оставляет сегодняшнее поведение.
- **`structured_log_http` не затрагивается** — он авторизуется секретным ключом проекта (`Authorization: Bearer <slk_…>`) и refresh-токенов не видит.
- **`deploy/docker-compose.yml` не меняется** по составу сервисов; меняется только документация о том, что TLS перестаёт быть опциональным для не-`localhost` развёртываний.
- Отзыв cookie при смене пароля и удалении аккаунта — существующее поведение (`revokeRefreshTokensExcept`, `revokeAllRefreshTokens`) и так гасит токен; отдельного `Set-Cookie` для этого не требуется, потому что мёртвый токен в cookie безвреден и будет заменён на следующем обновлении.

## Capabilities

### New Capabilities

<!-- нет -->

### Modified Capabilities

- `log-server-auth`: `POST /v1/auth/token` дополнительно ставит `Set-Cookie` и принимает refresh-токен из cookie, когда поля формы нет; `DELETE /v1/auth/token` — то же плюс гашение cookie; ответ несёт `refresh_token_cookie_set`.
- `log-server-config`: новая настройка `refresh-token-cookie` (`auto`/`on`/`off`).
- `log-server-api`: требование «сервер SHALL не поддерживать `Access-Control-Allow-Credentials`» снимается — заголовок отдаётся для origin из списка.
- `log-server-forced-password-change`: требование «сервер SHALL не иметь иного способа опознать сессию вызывающего, кроме предъявленного значения токена» перестаёт быть безусловным — cookie и есть такой способ; `current_refresh_token` остаётся необязательным полем и выигрывает у cookie.
- `admin-client-auth`: refresh-токен в режиме cookie не хранится клиентом; access-токен хранится пер-вкладочно; старт приложения восстанавливает сессию обращением к серверу; выход и обновление токена не предъявляют refresh-токен явно.

## Impact

- `backend/structured_log_server/lib/src/http/routes/auth_route.dart` — `Set-Cookie`, чтение cookie, новое поле ответа.
- `backend/structured_log_server/lib/src/http/routes/change_password_route.dart` — cookie как запасной путь для `current_refresh_token`.
- `backend/structured_log_server/lib/src/http/` — новый модуль разбора/сборки cookie (`refresh_cookie.dart`), правка `cors_middleware.dart`.
- `backend/structured_log_server/lib/src/config/server_config.dart` — параметр `refresh-token-cookie` с закрытым набором значений (по образцу `logFormat`).
- `backend/structured_log_server/test/http/` — новые тесты на cookie, приоритет формы, режимы `auto`/`on`/`off`; `test/config/` — разбор настройки.
- `frontend/structured_log_admin_client/lib/shared/auth/token_storage.dart` — расщепление хранилища; `restore_session.dart`, `auth_interceptor.dart`, `auth_repository_impl.dart`, `sign_out.dart`, `change_password.dart`.
- `frontend/structured_log_admin_client/lib/testing/mock_server.dart` — эмуляция `Set-Cookie`/`Cookie`: под `HttpClientAdapter` браузерного движка нет, а без эмуляции `test/integration/` перестанет проверять то, ради чего написан.
- `packages/e2e` — прогон обоих режимов; на Dart VM cookie не хранится сама.
- `frontend/structured_log_admin_client/integration_test/user_flow_test.dart` — единственный слой, где cookie ведёт себя по-настоящему.
- Документация: `AGENTS.md` (корень), `backend/structured_log_server/README.md`/`.ru.md`, `docs/operations/configuration.md`/`.ru.md`, `docs/guides/developer-guide.md`/`.ru.md`, `docs/guides/admin-guide.md`/`.ru.md` (TLS перестаёт быть опциональным).
- Капабилити `log-server-auth`, `log-server-config`, `log-server-api`, `log-server-forced-password-change`, `admin-client-auth` описаны в ещё не заархивированных changes (`openspec/specs/` в репозитории нет). Порядок архивации: `add-structured-log-server` → `unify-server-auth` → `add-server-cors` → `add-web-security-headers` → эта. Для `log-server-forced-password-change` дельта читается поверх архивной `2026-09-24-add-session-revocation-on-password-change`.
