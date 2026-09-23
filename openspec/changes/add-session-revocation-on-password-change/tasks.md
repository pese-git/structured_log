## 1. Server: revoking

- [x] 1.1 Add `revokeRefreshTokensExcept(db, userId, {String? exceptTokenHash})` to `lib/src/auth/session.dart`, returning how many rows it revoked; leave already-revoked rows untouched (their `revoked_at` is when they died) and uncounted. Make `revokeAllRefreshTokens` its no-survivors case so its four existing call sites are unchanged.
- [x] 1.2 `test/auth/session_test.dart` (new): spares the named hash and revokes the rest; returns the count; a hash nobody holds spares nothing; an already-revoked row is neither re-stamped nor counted; another account is untouched; `revokeAllRefreshTokens` still revokes everything.

## 2. Server: the endpoint

- [x] 2.1 In `lib/src/http/routes/change_password_route.dart`, parse optional `keep_other_sessions` (boolean) and `current_refresh_token` (string); reject a wrong type as `400 invalid_request` with `details.field`, before `current_password` is verified so a malformed body does not spend a subject rate-limit attempt.
- [x] 2.2 Call the revocation inside the existing transaction, next to `incrementTokenVersion`, hashing the presented token with `hashToken`. Skip it entirely when `keep_other_sessions` is `true`.
- [x] 2.3 Put the count in the `password.changed` audit record as `metadata.other_sessions_revoked`; the presented token never appears.
- [x] 2.4 `test/http/routes/change_password_route_test.dart`: default revokes the others and spares the presented one; no token presented revokes everything; an unknown token spares nothing; `keep_other_sessions: true` revokes nothing; another account is untouched; a refused attempt revokes nothing; both wrong types are `400`; the audit metadata counts, and counts `0` for the opt-out. Update the existing "metadata is empty" assertion — this change gives the record one key.

## 3. Client: data layer

- [x] 3.1 `ChangePasswordRequestDto` gains `keepOtherSessions` (required) and `currentRefreshToken` (`String?`, `includeIfNull: false`).
- [x] 3.2 `AuthRepository.changePassword` gains a required `keepOtherSessions`; the doc comment stops promising the session simply survives.
- [x] 3.3 `AuthRepositoryImpl` reads the refresh token from its own `TokenStorage` — the cubit and the form never hold a credential.
- [x] 3.4 `test/features/auth/auth_repository_test.dart`: the body carries the flag and the held token; the opt-out travels; no token held omits the field rather than sending `null`.

## 4. Client: screens

- [x] 4.1 `ChangePassword` use case and `ChangePasswordCubit.submit` pass the flag through.
- [x] 4.2 `ChangePasswordForm` gains `offerKeepOtherSessions` (default `false`) and, when set, an unticked `Checkbox`; `submit` sends `false` whenever the box is not offered, so a screen that does not ask never answers for the reader.
- [x] 4.3 The settings page (`home_shell.dart`) passes `offerKeepOtherSessions: true`; the forced screen does not.
- [x] 4.4 `authKeepOtherSessions` in both ARBs; reword `shellPasswordHintForm`, `shellPasswordHintRow` and `shellPasswordChanged`, which all promised the session was the only thing at stake.
- [x] 4.5 `test/features/auth/change_password_cubit_test.dart`: the choice reaches the repository, both ways, and a mismatch stops it travelling. `test/features/auth/force_password_change_page_test.dart`: no checkbox there.

## 5. Client: the mock, and through it the integration tests

- [x] 5.1 `lib/testing/mock_server.dart`: `refreshTokenIsLive(token)`, and `_changePassword` applies the same rule as the server (including both `400`s), spelled out rather than assumed.
- [x] 5.2 `test/integration/account_settings_integration_test.dart`: changing the password from settings kills another device's session and keeps this one; the opt-out spares it; the form offers the box and no longer claims the change ends nothing.

## 6. End to end

- [x] 6.1 `packages/e2e/test/system_test.dart`: a second sign-in stands in for another device; after the change this session renews and that one is refused. Order matters — asking about the revoked token first trips the server's reuse detection, which revokes the whole chain.
- [x] 6.2 Every existing `ChangePasswordRequestDto` in `packages/e2e` names its own refresh token, the way the real client does — otherwise the suite's own sessions end mid-file.
- [x] 6.3 Raise `--rate-limit-bucket-capacity` in `packages/e2e/test/harness.dart`: the auth endpoints share one bucket per address, `change-password` spends from it too, and the suite was already three deep before its second test. The limiter has its own tests server-side.

## 7. Documentation

- [x] 7.1 `docs/api/http-api.md` / `.ru.md`: the two new fields, the default, and what happens to a caller that does not name its token.
- [x] 7.2 `docs/architecture/auth.md` / `.ru.md`: the sequence diagram's note, and a bullet beside the one that already explains why an admin reset revokes refresh tokens.
- [x] 7.3 `AGENTS.md`: the claim "смена пароля не рвёт сессию … refresh-токен при этом не отзывается" is now false.

## 8. Verification

- [x] 8.1 `dart analyze` clean for `structured_log_server`; `flutter analyze` clean for `structured_log_admin_client` and `structured_log_e2e`.
- [x] 8.2 `dart test --exclude-tags postgres` green for the server; `flutter test` green for the client; `flutter test` green for `packages/e2e`.
- [x] 8.3 `dart format --set-exit-if-changed .` clean in every touched package.
- [ ] 8.4 CI green on every job.
