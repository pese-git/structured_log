## 1. The ceiling itself

- [x] 1.1 `lib/src/live/subscription_limit.dart`: `SubscriptionLimiter` with a per-account and a process ceiling, `0` meaning none, handing out a `SubscriptionSlot` whose `release()` is idempotent. A refusal spends nothing. An account holding nothing is dropped from the map rather than left at zero.
- [x] 1.2 `test/live/subscription_limit_test.dart`: both ceilings, independence between accounts, release freeing a slot, a refusal by the total not consuming the account, **three releases counting as one**, the map not growing, and `0` meaning unlimited on each ceiling separately.

## 2. The route

- [x] 2.1 Take a slot in `streamLogs` after authorization and after the query is parsed, so a caller who would be refused anyway cannot occupy the ceiling by being refused.
- [x] 2.2 Release it in `stop()` — the route's single teardown, which runs twice on the paths where the server ends the stream itself. This is what `SubscriptionSlot`'s idempotence is for.
- [x] 2.3 `ApiError.tooManySubscriptions`: `429`, code `too_many_subscriptions`, the configured limits in `details`, and deliberately no `Retry-After` — the wait is on somebody else's disconnect, which the server cannot put a number on.
- [x] 2.4 `test/http/routes/log_stream_route_test.dart`: refusal past each ceiling with the wire shape, independence between accounts, a disconnect freeing the slot, a server-ended stream releasing exactly once, and a refusal counting against nobody.

## 3. Configuration

- [x] 3.1 `max-live-subscriptions-per-user` (10) and `max-live-subscriptions` (1000) in `serverConfigParams`, `minValue: 0`; fields on `ServerConfig`; carried to the route through `HttpSettings` and `routes_module`.
- [x] 3.2 `HttpSettings` defaults to no ceiling, so a handler built without a `ServerConfig` — every route test — behaves as it did.
- [x] 3.3 The seven test fixtures that build a `ServerConfig` by hand pass `0`, keeping their behaviour unchanged. They had to be touched at all because every field of `ServerConfig` is `required` — which is the point: a new field makes each site decide.
- [x] 3.4 `test/config/server_config_test.dart`: the names are in `_expectedParamNames`, the defaults arrive, `0` is accepted as "no ceiling", and a negative value is a configuration error.

## 4. Documentation

- [x] 4.1 `docs/operations/configuration.md` / `.ru.md` and `backend/structured_log_server/README.md` / `.ru.md`: both settings with their defaults.
- [x] 4.2 `docs/api/errors.md` / `.ru.md`: the new `429`, and why it is the one that carries no `Retry-After`.

## 5. Verification

- [x] 5.1 `dart analyze`, `dart format --set-exit-if-changed`, `dart test --exclude-tags postgres` for `structured_log_server`.
- [x] 5.2 Exercise it against a running server: two subscriptions fill an account's ceiling of two, the third is `429 too_many_subscriptions` with `details` naming both limits, and a disconnect returns the place.
- [x] 5.2a Chase down what that run first looked like. With the default heartbeat the place did not come back within a second, which reads exactly like the counter leak this design is built to avoid. It is not: TCP does not tell the server a client is gone, so the server finds out on its next write to the socket. Re-run with a one-second heartbeat — the place came back in 1.0 s. Written down in the limiter's doc comment, the spec and the configuration reference, because the number alone promises more than it delivers.
- [ ] 5.3 CI green on every job.
