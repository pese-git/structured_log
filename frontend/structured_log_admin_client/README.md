# structured_log_admin_client

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

**The web admin for
[`structured_log_server`](../../backend/structured_log_server/): where
operators and their teams read, search and live-tail their logs and
decide who may see what.**

Not published — it is an application, not a library.

## Why

The server speaks HTTP and JSON, which is fine for scripts and painful for
people: nobody wants to investigate an incident by assembling `curl`
commands, copying tokens by hand and paging through JSON. The admin client
puts the whole server in a browser tab — the log feed with filters and a
live tail, the groups, projects and keys behind it, and the users, teams
and roles that decide access — so an operator signs in and works, and a
developer granted access to one project sees that project's logs and
nothing else.

## Features

- **Sign-in and password changes** — a temporary password set by an
  administrator must be changed before anything else opens; later the
  password can be changed from account settings, optionally keeping other
  devices signed in.
- **Dashboard** — the groups and projects you can reach, with entry counts
  and a shortcut to each project's logs.
- **Groups, projects and secret keys** — create groups and projects, set a
  project's quota and retention, block and unblock a project, issue keys
  (the value is shown exactly once) and revoke them.
- **Log browser** — pick a project or a group, filter by level, category,
  logger, time range and correlation id, search by event, and open any
  entry to see every field the application sent, with copy.
- **Live feed** — new entries appear at the bottom as they arrive; pause
  it to read without the list moving, then resume where you left off.
  Reconnects after a dropped connection happen on their own, without gaps.
- **Users** — administrators create, edit, block, unblock and delete
  accounts.
- **Teams and roles** — a group's teams and their members; the **Access**
  section of a group or project grants `owner`/`user` to a user or a whole
  team and revokes it.
- **Audit log** — for administrators: administrative actions and sign-in
  attempts in one table under one set of filters.
- **Account settings** — profile, password, language, and deleting your
  own account.
- **English and Russian** — follows the browser's language until you pick
  one.

## Status

Every screen above works against the server today. Self-registration,
password recovery and email verification are not here, because the server
does not have them yet — and a screen that opens onto nothing is worse
than one that is not offered.
[tasks.md](../../openspec/changes/add-structured-log-server/tasks.md) says
exactly what is and isn't done.

## Where it fits

Applications ship logs to
[`structured_log_server`](../../backend/structured_log_server/) with
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync);
this client is how people read them and manage who may. It is a Flutter
web app built on the
[`structured_log_admin_ui`](../structured_log_admin_ui/) component library,
served as static files beside the API — [deploy/](../../deploy/) runs both
behind one nginx on one origin with `./deploy.sh`. Guides on
[structured-log.openidealab.com](https://structured-log.openidealab.com):
[User](https://structured-log.openidealab.com/guides/user-guide/)
(working in this client, with screenshots),
[Administrator](https://structured-log.openidealab.com/guides/admin-guide/)
(running the server and the client),
[Developer](https://structured-log.openidealab.com/guides/developer-guide/)
(shipping logs from your app).

**One thing to know before running it against a server on another host: by
default you cannot.** The server sends no CORS headers unless the operator
explicitly turns them on (`--cors-allowed-origins`, see the server's own
README) — with CORS off, a browser refuses the request before it leaves the
page. The client is served beside the API behind one origin
([deploy/](../../deploy/)), and its bundle is built with an empty base URL;
that stays the reference deployment even where CORS is available.

## Development

For contributors to this app; the repository-wide commands and conventions
are in [AGENTS.md](../../AGENTS.md).

### Running

```bash
flutter run -d chrome --dart-define=STRUCTURED_LOG_BASE_URL=https://logs.example.com
```

The base URL is a compile-time define, defaulting to `http://localhost:8080`.

### Code generation

`*.g.dart` and `*.freezed.dart` are not committed:

```bash
dart run build_runner build --delete-conflicting-outputs
```

or `dart run melos run generate` from the repository root. CI runs it before
analyze and test.

### Languages

The app follows the browser's language (English for any other) until
someone picks one under **Account settings → Language** (or the English /
Русский switch in the corner of the sign-in and forced password change
screens); the choice is kept in the browser's `localStorage`. Texts live in
`lib/l10n/*.arb` and are read through `context.l10n`; after editing them run
`flutter gen-l10n` (the generated files are committed).

### Access hints, not enforcement

Role assignment in a group's or project's **Access** section narrows its
role choices to what the caller's own token claims allow — a hint, not
enforcement: the server decides regardless. The reduced form on a user's own
screen stays `admin`-only, one user at a time.

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
API documents; a human-readable name in the interface's current language is
the tooltip.

### Architecture

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
| Session | access token in `sessionStorage` (per tab); refresh token in the server's `HttpOnly` cookie when it sets one, otherwise `flutter_secure_storage`; never shared preferences | `lib/shared/auth/` |
| Diagnostics | `structured_log` | `lib/shared/logging/` |

#### Three Dio instances, not one

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

## License

MIT — see [LICENSE](LICENSE).
