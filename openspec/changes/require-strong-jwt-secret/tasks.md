## 1. The rule

- [x] 1.1 `minJwtSecretBytes` (32) and `jwtSecretPolicyMessage(String)` in `lib/src/auth/token_settings.dart`, beside `TokenSettings` — the file whose subject is the signing secret. The message names the limit and a way to generate one, and never the value.
- [x] 1.2 `test/auth/token_settings_test.dart` (new): at the minimum, above it, below it by one byte, empty, what the deployment scripts generate, a Cyrillic secret that is long in bytes and half that in characters, and an assertion that the offending value is not echoed back.

## 2. Wiring

- [x] 2.1 `validator: jwtSecretPolicyMessage` on the `jwt-secret` `ParamSpec`, and the limit in its `description`.
- [x] 2.2 `test/config/server_config_test.dart`: a short secret is `ConfigParseOutcome.errors` naming `STRUCTURED_LOG_JWT_SECRET` and the limit; the error text does not contain the secret; a long enough one parses; `create-admin` is held to the same rule when a secret is set, and unaffected when none is.
- [x] 2.3 `test/bin/server_integration_test.dart`: the real binary exits non-zero, prints the variable name and the limit, never the value, and creates no database. Mirrors the bootstrap-password case beside it. **Mutation-checked** — removing the `validator:` line makes it red.

## 3. Fixtures the floor now excludes

- [x] 3.1 `server_integration_test.dart` (15 uses), `server_config_test.dart` (6), `logging/setup_test.dart` (3), `packages/e2e/test/harness.dart` (1) — each secret lengthened, keeping its old name so the diff reads as "made long enough" rather than "renamed". In `setup_test.dart` the value stays recognisable, because the assertion there is that it does *not* appear in the output.

## 4. Documentation

- [x] 4.1 `docs/operations/configuration.md` / `.ru.md`: the reference row states the minimum; the development example that set `dev-only-secret` would no longer start and was replaced.
- [x] 4.2 `docs/guides/admin-guide.md` / `.ru.md`: the deployment-checklist row states the minimum, and the troubleshooting table gains the new message, with the warning that replacing a secret signs everyone out.
- [x] 4.3 `backend/structured_log_server/README.md` / `.ru.md`: the environment table states the minimum, and the two quick-start examples that exported a secret too short to boot now generate one.

## 5. Verification

- [x] 5.1 `dart analyze` clean, `dart format --set-exit-if-changed` clean, `dart test --exclude-tags postgres` green for `structured_log_server` (947).
- [x] 5.2 `flutter test` green for `packages/e2e` (12) — its harness starts the real binary, so its secret had to clear the floor too.
- [ ] 5.3 CI green on every job, including the `postgres` tag.
