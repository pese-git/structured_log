## 1. Схема

- [x] 1.1 `refresh_tokens.revoked_reason` (текст, nullable) в `lib/src/storage/database.dart`; `schemaVersion` 3; шаг `onUpgrade` `from < 3` — `addColumn`, существующие строки остаются `NULL`.
- [x] 1.2 `test/storage/database_test.dart` и `test/storage/postgres_migration_test.dart`: переход v2→v3 добавляет колонку и не выдумывает причину у уже отозванной строки; тест v1→v2 удаляет колонку перед откатом версии.

## 2. Причина отзыва

- [x] 2.1 `RevocationReason` в `lib/src/auth/session.dart` (`wire`, `signalsReuse`: `true` только для `rotated`, `NULL` и неизвестного значения).
- [x] 2.2 `revokeRefreshTokensExcept`/`revokeAllRefreshTokens` принимают обязательный `reason` и пишут его вместе с `revoked_at`; уже отозванные строки не трогаются.
- [x] 2.3 Вызовы: смена пароля — `password_changed`, сброс пароля администратором — `password_reset`, блокировка — `blocked`, удаление — `deleted`.
- [x] 2.4 `TokenService`: ротация — `rotated`, выход — `signed_out`, отзыв цепочки — через общий хелпер с `reuse_detected`.

## 3. Обнаружение повторного использования

- [x] 3.1 `refreshTokenGrant`: отозванный токен — `invalid_grant` всегда, отзыв цепочки — только если `signalsReuse`.
- [x] 3.2 Проигравший в гонке перечитывает причину и отзывает цепочку по тому же правилу.
- [x] 3.3 `test/auth/token_service_test.dart`: ротация пишет `rotated`; подметённый сменой пароля токен не гасит пощажённую сессию; вышедший — не гасит другие; `password_reset`/`blocked`/`deleted` не гасят вход после них; ротированный по-прежнему гасит всё (`reuse_detected`); `reuse_detected` не гасит свежий вход; строка без причины гасит всё. Мутацией проверено: безусловный отзыв — шесть тестов красные.
- [x] 3.4 `test/auth/session_test.dart`: причина пишется на отозванные строки и не переписывается на уже отозванных; `signalsReuse` по всем значениям. Причина проверяется и в тестах маршрутов (`change_password_route_test`, `users_route_test`) и `delete_user_test`.

## 4. End to end

- [x] 4.1 `packages/e2e/test/system_test.dart`: после смены пароля подметённое устройство обновляется первым и получает отказ, затем сменивший пароль обновляется дважды. Мутацией проверено: с безусловным отзывом тест красный.
- [x] 4.2 Встречный тест: ротированный токен, предъявленный снова, гасит своего преемника.

## 5. Документация

- [x] 5.1 `docs/architecture/auth.md`/`.ru.md` — кражей считается только возврат ротированного токена.
- [x] 5.2 `docs/architecture/data-model.md`/`.ru.md` — `revoked_reason`.

## 6. Проверка

- [x] 6.1 `dart analyze`, `dart format --set-exit-if-changed` (FVM) — чисто.
- [x] 6.2 `dart test` по умолчанию, `--tags integration`, `--tags postgres --concurrency=1` — зелёные; `flutter test` в `packages/e2e` — зелёный.
