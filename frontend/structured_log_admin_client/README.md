# structured_log_admin_client

Self-hosted admin client for
[`structured_log_server`](../../backend/structured_log_server): sign-in,
groups and projects and their secret keys, users, the log browser, and the
audit log.

Not published — it is an application, not a library.

## State

Working today: sign-in (including the forced first-login password change),
groups, projects and their quotas, secret keys, the log browser with its live
feed, account settings, the audit log, and user management — create, edit,
block/unblock, delete, plus a reduced role-grant form (`admin` only,
one user at a time; there is no endpoint yet to list a user's existing
grants).

Not here: teams, the full role-assignment rule (an `owner` granting roles
within their own group), self-registration, password recovery and email
verification. The server has no endpoints behind them yet, and a screen that
opens onto nothing is worse than one that is not offered —
[tasks.md](../../openspec/changes/add-structured-log-server/tasks.md) says
exactly what is and isn't done.

**One thing to know before running it against a server on another host: you
cannot.** The server sends no CORS headers at all, so a browser refuses the
request before it leaves the page. The client is served beside the API behind
one origin ([deploy/](../../deploy/)), and its bundle is built with an empty
base URL. Opening the API up is a change to the server, not a proxy setting.

### The audit screen

Administrative acts and authentication events in one table under one set of
filters — an operator investigating an incident is asking a single question,
and the login that preceded a change is part of the answer.

The nav item appears only for a token whose `roles` claim carries `admin` at
global scope. That claim is read without checking the signature, which is
legitimate for exactly one reason: it decides what to **offer**, never what to
allow. The server re-derives roles on every request and answers 403 regardless,
and the screen renders that as a refusal. A forged token buys a menu item and
an error message. One consequence worth stating: the claim is a snapshot from
when the token was issued, so a role revoked mid-session leaves the item in
place until the token is renewed.

A record with no actor says which kind of nobody it was — an attempt under a
username that does not exist, or the server itself — and no request goes out to
resolve a name, because there is no account to resolve. The action tag shows the
wire value (`project.quota_updated`), which is what you filter by and what the
API documents; the Russian name is the tooltip.

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
