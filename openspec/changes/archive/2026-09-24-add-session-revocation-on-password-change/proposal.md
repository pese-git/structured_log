## Why

`POST /v1/auth/change-password` инкрементирует `User.token_version`, но не трогает refresh-токены (`change_password_route.dart`). Инкремент убивает только access-токены: refresh живёт 30 дней, и первый же `grant_type=refresh_token` выдаёт новый access-токен уже с новым `tv`. То есть человек, сменивший пароль **потому что подозревает компрометацию**, не выгоняет того, кто пароль узнал, — а именно это он и считает, что делает.

Асимметрия внутри самого сервера ровно обратна ожиданию. Пароль, который поставил администратор (`PATCH /v1/users/:id`), блокировка (`POST /v1/users/:id/block`) и удаление (`delete_user.dart`) — все три зовут `revokeAllRefreshTokens` рядом с `incrementTokenVersion`. Не зовёт его единственный путь, по которому действует сам пострадавший.

Обратная сторона — почему это нельзя починить одной строкой. Отзыв «всех» отзывает и токен того, кто меняет пароль, то есть выкидывает его на экран входа посреди осознанного действия. Сервер при этом не может отличить его сессию от прочих: `change-password` аутентифицируется access-токеном, а в `refresh_tokens` лежат хэши, ничего не говорящие о том, чьё это устройство.

## What Changes

- `POST /v1/auth/change-password` принимает два необязательных поля: `keep_other_sessions` (boolean) и `current_refresh_token` (string). Ответ не меняется — по-прежнему `200` с пустым объектом.
- По умолчанию (поле отсутствует или `false`) успешная смена пароля SHALL отзывать все refresh-токены учётной записи, кроме предъявленного в `current_refresh_token`. Отзыв идёт в той же транзакции, что новый хэш и инкремент `token_version`.
- Если `current_refresh_token` не предъявлен или не соответствует ни одному живому токену, отзываются **все**, включая сессию вызывающего. Это осознанный fail-safe: сервер, не сумевший опознать спрашивающего, обязан применить подметание и к нему, а не тихо пропустить кого-то.
- `keep_other_sessions: true` сохраняет сегодняшнее поведение — не отзывается ничего.
- Флаг назван как **исключение**, а не как просьба (`revoke_other_sessions`), чтобы отсутствие поля означало безопасное поведение: старый клиент, `curl` и забывчивый автор нового клиента получают отзыв, а не молчаливое сохранение чужих сессий.
- Аудит-запись `password.changed` получает `metadata.other_sessions_revoked` — число завершённых сессий. Ни пароль, ни предъявленный токен в журнал не попадают.
- `structured_log_admin_client`: на экране настроек аккаунта — снятая по умолчанию галка «Оставить другие устройства в системе»; клиент всегда предъявляет свой refresh-токен из `TokenStorage`, так что его собственная сессия переживает смену. На принудительном экране смены пароля галки нет: временный пароль заведомо прошёл через чужие руки, и отзыв там безусловен.

Вне объёма: отдельный экран «активные сессии» со списком устройств и точечным отзывом — для него в `refresh_tokens` нет ни `user_agent`, ни `last_used_at`, и это отдельное решение о том, какие данные об устройствах сервер вправе хранить. Отзыв при `grant_type=password` (вход) не вводится.

## Capabilities

### New Capabilities

<!-- нет -->

### Modified Capabilities

- `log-server-forced-password-change`: требование к `POST /v1/auth/change-password` дополняется отзывом refresh-токенов и двумя необязательными полями тела; требование к аудит-записи `password.changed` — полем `metadata.other_sessions_revoked`.

## Impact

- Капабилити `log-server-forced-password-change` описана в ещё не заархивированной change `add-structured-log-server` (в `openspec/specs/` её пока нет) — delta этой change читается поверх той, и при архивации порядок должен быть «сначала `add-structured-log-server`, потом эта» (тот же порядок уже зафиксирован в `unify-server-auth` и `add-server-cors`).
- `backend/structured_log_server/lib/src/auth/session.dart` — `revokeRefreshTokensExcept(db, userId, {exceptTokenHash})`, возвращающая число отозванных; `revokeAllRefreshTokens` становится её вызовом без исключения, её четыре существующих вызова не меняются.
- `backend/structured_log_server/lib/src/http/routes/change_password_route.dart` — разбор двух полей и вызов отзыва внутри существующей транзакции.
- `backend/structured_log_server/test/auth/session_test.dart` (новый) и `test/http/routes/change_password_route_test.dart` — существующий ассерт «метаданные аудит-записи пусты» меняется на проверку единственного ключа `other_sessions_revoked`.
- `frontend/structured_log_admin_client` — `AuthRepository.changePassword` получает параметр `keepOtherSessions`; `ChangePasswordRequestDto` — два поля (`includeIfNull: false` у токена); `AuthRepositoryImpl` читает refresh-токен из `TokenStorage`; `ChangePassword`, `ChangePasswordCubit`, `ChangePasswordForm` пробрасывают флаг; два ключа в `lib/l10n/app_en.arb`/`app_ru.arb`; `lib/testing/mock_server.dart` повторяет правило отзыва.
- `packages/e2e` — сценарий через настоящий процесс сервера: две сессии, смена пароля в одной, у второй refresh мёртв, у первой жив.
- Документация: `docs/architecture/auth.md`/`.ru.md`, `docs/api/`, `AGENTS.md` (утверждение «Смена пароля не рвёт сессию… refresh-токен при этом не отзывается» становится ложным).
- `structured_log_http`, `structured_log` и Flutter-скины не затрагиваются.
