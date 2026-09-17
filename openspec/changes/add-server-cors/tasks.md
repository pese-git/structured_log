## 1. Configuration

- [x] 1.1 Add `cors-allowed-origins` to `serverConfigParams` (`lib/src/config/server_config.dart`): `ParamType.string`, default `''`, description documents the comma-separated format.
- [x] 1.2 Add `Set<String> corsAllowedOrigins` to `ServerConfig`, populated in `ServerConfig.fromResolved` by splitting the raw string on `,`, trimming each segment, and dropping empty segments (an unset/empty value yields an empty set).
- [x] 1.3 Update `_expectedParamNames` in `test/config/server_config_test.dart` to include `cors-allowed-origins`.
- [x] 1.4 Add a test (in `test/config/server_config_test.dart` or `config_resolver_test.dart`, matching existing file conventions) covering: unset → empty set; `"http://a.test, http://b.test"` → `{http://a.test, http://b.test}` (trimmed); a trailing comma or blank segment is dropped, not kept as an empty string.

## 2. Middleware

- [x] 2.1 Write `lib/src/http/cors_middleware.dart`: `Middleware corsMiddleware(Set<String> allowedOrigins)`. For a request whose `Origin` header is not in `allowedOrigins` (including no `Origin` at all), pass through unchanged. For a matching `Origin`: on `OPTIONS` with `Access-Control-Request-Method` present, short-circuit with `204`, `Access-Control-Allow-Origin: <origin>`, `Access-Control-Allow-Methods: GET, POST, PATCH, DELETE, OPTIONS`, `Access-Control-Allow-Headers: Authorization, Content-Type`, `Vary: Origin` — without calling the inner handler; on any other request, call the inner handler and add `Access-Control-Allow-Origin: <origin>` + `Vary: Origin` to whatever response comes back (success or error).
- [x] 2.2 Wire it into `buildHandler`'s `Pipeline` in `lib/src/http/server.dart`, immediately after the request-logging middleware and before `errorHandlingMiddleware` — ahead of rate limiting and principal resolution, per `design.md`. Add it only `if (config != null)`, using `config.corsAllowedOrigins` (mirrors the existing `rateLimitMiddleware` gating; an empty set makes it a no-op).

## 3. Tests

- [x] 3.1 In `test/http/cors_test.dart`: keep the three existing tests unchanged (they call `buildHandler` without a `config`, so CORS stays off — must keep passing verbatim).
- [x] 3.2 Add tests for CORS enabled with a `ServerConfig` whose `corsAllowedOrigins` contains one origin: a public endpoint response carries `Access-Control-Allow-Origin` for that origin; an endpoint that answers 401/403 still carries the header on the error response; a preflight `OPTIONS` for that origin returns `204` with the three CORS headers.
- [x] 3.3 Add a test proving the preflight short-circuit actually skips downstream middleware: a preflight on a rate-limited path (e.g. `POST /v1/auth/token`) does not consume a rate-limit token — send enough preflights to exceed the configured bucket, then confirm a real `POST` still succeeds (isn't `429`).
- [x] 3.4 Add a test for an origin outside the configured list, with CORS otherwise enabled for a *different* origin: no `Access-Control-Allow-Origin` on a normal response, and `OPTIONS` on a real route still falls through unmatched (same assertion style as the existing "a preflight is not a case the server knows" test).

## 4. Documentation

- [x] 4.1 `backend/structured_log_server/README.md` / `README.ru.md`: add `cors-allowed-origins` to the configuration table, and adjust the status blurb if it references "no CORS" absolutely.
- [x] 4.2 `docs/operations/configuration.md` / `.ru.md`: add a row to the Reference table (`--cors-allowed-origins`, default unset/empty, note: comma-separated origin list, empty = no CORS).
- [x] 4.3 `AGENTS.md` (root): update the `deploy/` section's "CORS в сервере нет вообще: ни middleware, ни упоминания в спеках и design.md" — it now has a middleware and a spec requirement, off by default. Reword to state the default-off, explicit-opt-in behavior without losing the point that single-origin remains the deployment default.
- [x] 4.4 Update the backend `structured_log_server` status blurb in `AGENTS.md` if it enumerates capabilities in a way this change extends.

## 5. Verification

- [x] 5.1 `dart analyze` clean for `structured_log_server`.
- [x] 5.2 `dart test` (unit + integration tags) green.
- [x] 5.3 `dart format --set-exit-if-changed .` clean.
- [x] 5.4 Manually verify against the host-only local stand from the previous session: rebuild the admin client with an absolute `STRUCTURED_LOG_BASE_URL` pointing at the server's own port, start the server with `--cors-allowed-origins` set to the client's origin, and confirm login succeeds without the temporary proxy shim.
