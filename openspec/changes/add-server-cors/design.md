## Context

`buildHandler` (`lib/src/http/server.dart`) assembles a `Pipeline`: request logging → error handling → rate limiting (only when a `ServerConfig` is supplied) → principal resolution → the mounted route table. `test/http/cors_test.dart` pins the current absence of CORS as intentional (`specs/log-server-api`): no `Access-Control-Allow-*` header on any response, and `OPTIONS` is not a route any handler answers, so it 404s.

Configuration is declared once, in `serverConfigParams` (`lib/src/config/server_config.dart`) — a list of `ParamSpec` that `ConfigResolver` turns into CLI flags, `STRUCTURED_LOG_*` env vars, `--help` and `--print-config` output. `ParamType` is deliberately just `{string, int, bool}`; there is no list type, so a multi-value setting is a `string` field parsed by the consumer, the same way `logLevel`/`logFormat` are strings with a closed `allowedValues` set rather than an enum type.

## Goals / Non-Goals

**Goals:**
- Let an operator explicitly enable CORS for a configured list of origins, for deployments where the client is not served behind the same reverse proxy as the API (this change's motivating case: local host-only development).
- Leave the zero-config path — no flag, no env var — byte-for-byte identical to today: no headers, `OPTIONS` still unmatched, `test/http/cors_test.dart`'s three existing tests pass unmodified.
- Keep the allow-list exact and auditable: an origin either matches a configured string exactly or gets nothing.

**Non-Goals:**
- No wildcard/glob origins, no `*`, no regex matching. A deployment that needs that can front the server with a reverse proxy that does.
- No `Access-Control-Allow-Credentials`. The client authenticates via `Authorization: Bearer <...>`, never cookies, so credentialed CORS is never needed — adding it would only widen the risk surface for no benefit.
- No change to `deploy/docker-compose.yml` or the single-origin deployment story. CORS is an opt-in escape hatch, not a replacement recommendation.

## Decisions

**A dedicated `cors_middleware.dart`, wired into the `Pipeline` immediately after request logging, before `errorHandlingMiddleware`.**
Two requirements only this position satisfies: (1) a preflight `OPTIONS` must be answered without reaching rate limiting or `principalMiddleware` — a preflight carries no `Authorization` and must not spend a rate-limit token or be counted as an unauthenticated request; (2) the `Access-Control-Allow-Origin` header must be attachable to *every* response the pipeline can produce for a real request, including ones `errorHandlingMiddleware` renders (a 401, a 500) — a browser needs the header on the error response itself to let the page read the error. Sitting outermost (bar logging) lets the middleware short-circuit preflights before anything else runs, and wrap every other response on the way out.

**Configuration is one `string` param, `cors-allowed-origins`, holding a comma-separated list — not a new `ParamType.list`.**
Every other multi-valued setting in this codebase (`logLevel`'s `allowedValues`, `rateLimitedEndpoints`) is either a closed enum or a `const` Dart list baked into source, never an operator-supplied list. Adding a whole new `ParamType` for one parameter is more machinery than the problem needs, and `ParamType`'s own doc comment already states the small set is deliberate. `ServerConfig.fromResolved` splits and trims the raw string into a `Set<String>` — mirroring how `logFormat`'s single string is validated against `allowedValues` rather than parsed into a richer type.

**Origin matching is exact string equality against the configured set — no scheme/host normalization.**
The `Origin` header is already a normalized `scheme://host[:port]` per its spec; asking the operator to list it exactly as the browser sends it (e.g. `https://logs.example.test:5173`) keeps the allow-list a literal, greppable value with no hidden normalization rules to get wrong. Trailing slashes are not tolerated (an origin has none by definition) — a misconfigured entry simply matches nothing, which fails safe.

**Unlisted origins get no headers and no preflight response — even when CORS is otherwise enabled.**
A non-matching `Origin` leaves the middleware a no-op and the request continues down the pipeline exactly as it does today: `OPTIONS` on a real route still 404s, `GET`/`POST` responses carry no CORS headers, so an unlisted origin is browser-blocked whether or not `cors-allowed-origins` is set. This is what lets the change be additive: it only ever *adds* capability for the origins named, never widens what an unnamed origin can do.

**`Access-Control-Allow-Origin` echoes the exact matched origin, never `*`.**
The response also gets `Vary: Origin` whenever the header is added, so a caching layer between the server and the browser (if one is ever introduced) does not serve one origin's CORS-enabled response to another.

**Preflight response:** `204 No Content`, `Access-Control-Allow-Origin: <matched origin>`, `Access-Control-Allow-Methods: GET, POST, PATCH, DELETE, OPTIONS`, `Access-Control-Allow-Headers: Authorization, Content-Type`, `Vary: Origin`. The methods/headers lists are fixed constants, not reflected from `Access-Control-Request-Method`/`-Headers` — every route this server has uses only those methods and only those two request headers, so there is nothing gained by echoing the request's ask back.

**`buildHandler` gates the middleware the same way it gates rate limiting: only added when `config != null`.**
`test/http/cors_test.dart`'s existing three tests call `buildHandler(db, signingSecret: ..., issuer: ...)` with no `config` — that must keep behaving exactly as before. When `config` is supplied but `corsAllowedOrigins` is empty (the default), the middleware is still added but is a no-op for every request, which is simpler than a second conditional and is exercised by the route/server tests that already pass a `config`.

## Risks / Trade-offs

- **[Risk] An operator adds an origin they don't control (e.g. a shared preview-deploy domain) and unknowingly grants it read access to every authenticated endpoint.** → Mitigation: the setting is off by default, requires an explicit, auditable list (visible in `--print-config`), and the design doc/README call out that this is for development, not a substitute for the single-origin deployment.
- **[Risk] Comma-separated string parsing silently drops a malformed entry (stray space, empty segment from a trailing comma).** → Mitigation: trim each segment and drop empty ones during parsing, same as an operator would expect from any comma-separated CLI value; document the exact format in `--help`.
- **[Trade-off] No credentialed CORS support.** Acceptable because the client never relies on cookies; revisit only if a future auth mechanism introduces one.

## Migration Plan

Purely additive — no default-config behavior change, no data migration. Deploying the new binary with no new flag/env var set is a no-op. Rollback is deploying the previous binary; no state was written.
