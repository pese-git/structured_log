# structured_log_admin_client

Self-hosted admin client for
[`structured_log_server`](../../backend/structured_log_server): sign-in,
projects and their secret keys, and the log browser.

Not published — it is an application, not a library.

## State

The data layer is in place; the screens are not. Sections 12–14 and 22 of the
`add-structured-log-server` change build sign-in, resource management and the
log browser on top of what is here. Running it today shows a placeholder.

## Architecture

Clean-ish layering per feature — `domain` / `application` / `infrastructure` /
`presentation` — with `lib/shared/` for what crosses features. Directories
appear as the first file lands in them rather than being created empty.

| Concern | Choice | Where |
|---|---|---|
| UI kit | `fluent_ui`, composed from `structured_log_admin_ui` | `lib/app/`, feature `presentation/` |
| HTTP | `dio` + `retrofit`; SSE by hand on the same instance | `lib/shared/api/` |
| Expected failures | `fpdart` `Either`, never for programmer errors | `lib/shared/api/api_failure.dart` |
| Models | `freezed` + `json_serializable` | `lib/shared/api/dto/` |
| DI | `cherrypick` | `lib/shared/di/` |
| State | `flutter_bloc` | feature `presentation/` |
| Tokens | `flutter_secure_storage`, never shared preferences | `lib/shared/auth/` |
| Diagnostics | `structured_log` | `lib/shared/logging/` |

### Three Dio instances, not one

Worth knowing before touching `ApiClient`:

- the main one carries the auth interceptor — it attaches the access token and
  renews it once on a 401;
- the refresh client has no interceptor, because a refresh answered with 401 on
  the main instance would re-enter the interceptor that issued it;
- the retry client replays the original request with the new token.

The token endpoint is exempt by path as well as by flag: a 401 from it means a
wrong password or a spent refresh token, and refreshing in response to either
turns a failed sign-in into a renewal attempt.

Concurrent 401s share one refresh. Without that, parallel requests each spend
the refresh token, and on a server that rotates them all but the first present
one that was just revoked.

## Running

```bash
flutter run -d chrome --dart-define=STRUCTURED_LOG_BASE_URL=https://logs.example.com
```

The base URL is a compile-time define, defaulting to `http://localhost:8080`.

## Code generation

`*.g.dart` and `*.freezed.dart` are not committed:

```bash
dart run build_runner build --delete-conflicting-outputs
```

or `dart run melos run generate` from the repository root. CI runs it before
analyze and test.

---

Russian version: [README.ru.md](README.ru.md)
