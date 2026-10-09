# structured_log_drift

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

**See every query your drift database runs — its SQL, how long it took,
what it returned, and why it failed — as a structured log entry, with one
line of setup and no argument values leaking.**

Documentation: [structured-log.openidealab.com](https://structured-log.openidealab.com).

## Why

A screen that hangs or comes up empty is often a query that was slow or
failed, and nothing in the log says so. drift's own `logStatements: true`
prints every statement *with its argument values* through `print`: password
hashes, tokens and personal data go to the console, without a level, a
duration or the error. So it stays off in production, and the queries stay
invisible.

`StructuredLogDriftInterceptor` is a drift `QueryInterceptor`. Passed to
`interceptWith` once, it writes every query, batch, failure and transaction
end as a `structured_log` entry — the kind of query, its SQL, its duration,
the rows it returned or changed — and flags the slow ones. Argument values
stay out unless you ask for them.

## Features

### Coverage

- **One line to install** — `NativeDatabase(file).interceptWith(StructuredLogDriftInterceptor())`.
- **Every query** — `select`, `insert`, `update`, `delete` and custom
  statements, with `rows`, `affected_rows` or `insert_id`.
- **Durations that mean something** — `duration_ms` keeps microsecond
  precision, since a query against a local database usually takes less than
  a millisecond.
- **Slow queries flagged** — at or above a threshold (500 ms by default) a
  query is a `warning` with `slow: true`.
- **Batches as one entry** — a `batch` is one `db_batch`, not one entry per
  statement.
- **Failures with their stack** — and the exception still reaches your code
  exactly as drift threw it.
- **Transactions** — commits and rollbacks, nested ones timed on their own.
- **Any executor** — native, web, an isolate: it is drift's own interception
  point.

### Control

- **Its own category** — every entry carries `category: 'db'`, so a
  `LogSink` can route database traffic separately and the in-app log viewer
  offers it as a filter.
- **A level per kind of entry** — or `null` to turn it off.
- **A filter** — by kind and statement, to leave out `PRAGMA`s or a table.

### Safety

- **No argument values by default** — not in the entry, and not in the
  error's text either (see below).
- **Never changes a query** — logging that fails costs the entry, never the
  query's result or exception.
- **Costs little when off** — an entry no sink would take is never built.

## Where it fits

The interceptor needs nothing but
[`structured_log`](https://pub.dev/packages/structured_log) — no server, no
Flutter. Its entries flow to whatever sinks you have configured: the
console, a file, an in-app log viewer
([`structured_log_material`](https://pub.dev/packages/structured_log_material),
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) or
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino)),
where the `db` category becomes a filter, or a self-hosted
`structured_log_server` through
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync).
It is one of six adapters that log what your app's libraries already do;
the whole project is at
[structured-log.openidealab.com](https://structured-log.openidealab.com).

## Installation

Published on pub.dev as a pre-release. It needs drift 2.14.0 or later, where
`QueryInterceptor` appeared:

```yaml
dependencies:
  drift: ^2.14.0
  structured_log: ^0.3.0
  structured_log_drift: ^0.1.0-dev.1
```

## Quick Start

```dart
import 'package:drift/native.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_drift/structured_log_drift.dart';

void main() {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );

  final db = AppDatabase(
    NativeDatabase(file).interceptWith(StructuredLogDriftInterceptor()),
  );
  // ...
}
```

The same `interceptWith` works on any `QueryExecutor` or
`DatabaseConnection` — a `WasmDatabase` on the web, or the connection of a
`DriftIsolate`.

An insert with a token argument, a batch of two inserts, a select and a
failing transaction then log (timestamps dropped, error and stack trace
shortened):

```text
{"logger":"drift","category":"db","kind":"insert","statement":"INSERT INTO users (name, token) VALUES (?, ?)","duration_ms":1.796,"insert_id":1,"event":"db_query","level":"debug"}
{"logger":"drift","category":"db","statement_count":1,"execution_count":2,"duration_ms":0.491,"event":"db_batch","level":"debug"}
{"logger":"drift","category":"db","kind":"select","statement":"SELECT * FROM users","duration_ms":1.525,"rows":3,"event":"db_query","level":"debug"}
{"logger":"drift","category":"db","kind":"custom","statement":"INSERT INTO missing VALUES (1)","duration_ms":2.476,"error":"SqliteException(1): while executing, no such table: missing, …","error_type":"SqliteException","stack_trace":"…","event":"db_query_failed","level":"error"}
{"logger":"drift","category":"db","duration_ms":4.853,"event":"db_transaction_rolled_back","level":"warning"}
```

See [example/main.dart](example/main.dart) for a runnable version
(`dart run example/main.dart`).

## What gets logged

Every entry carries `category` (`db` by default) and `logger` (`drift` by
default).

| `event` | When | Default level | Fields |
|---|---|---|---|
| `db_query` | a query ran | `debug`; `warning` if slow | `kind`, `statement`, `duration_ms`; `rows` (select), `affected_rows` (update, delete), `insert_id` (insert); `slow: true` if slow; `arguments` if enabled |
| `db_batch` | a batch ran | `debug`; `warning` if slow | `statement_count` (distinct statements), `execution_count`, `duration_ms`; `slow: true` if slow |
| `db_query_failed` | a query or batch threw | `error` | `kind` (`batch` for a batch), `statement`, `duration_ms`, `error`, `error_type`, `stack_trace` |
| `db_transaction_committed` | a transaction committed | `trace` | `duration_ms` since it began |
| `db_transaction_rolled_back` | a transaction rolled back | `warning` | `duration_ms` since it began |

`kind` is `select`, `insert`, `update`, `delete` or `custom`. `statement` is
cut to 2000 characters.

drift runs every `batch` in a transaction of its own, so a batch is followed
by a `db_transaction_committed`. Commits are at `trace`, which a sink's
default `minLevel` (`debug`) filters out, so a batch is not logged twice.
Lower a sink's `minLevel` to see them.

What is **not** logged: migrations. drift runs them on the executor
underneath the interceptor before the database opens; a failing migration
shows up as the exception from opening it.

## Keeping secrets out of the log

The statements drift builds carry placeholders (`?`, `$1`), not values, and
**argument values are not written by default**. They are where password
hashes, tokens and personal data live.

They would also leak through an error: `sqlite3` ends its exception text
with every parameter of the failing statement, and a PostgreSQL unique
violation quotes the duplicate value. So while arguments are off, the
interceptor writes `error` itself, with the text scrubbed:

- the `parameters: …` that `sqlite3` appends becomes `parameters: <hidden>`;
- every string argument of 4 characters or more becomes `<argument>`
  wherever it appears. Shorter strings, numbers, dates and blobs are left
  alone — hiding every `1` would garble the message.

To write arguments anyway, pass `logArguments: true`: strings are cut to
1000 characters and blobs written as `<N bytes>`. A batch never writes its
arguments — there can be thousands of sets.

What the interceptor cannot see into is SQL you wrote yourself with values
inlined, such as `customStatement("UPDATE users SET token = 'abc'")`. Use
variables, or leave such statements out with `filter`.

## Configuration

```dart
StructuredLogDriftInterceptor(
  // Which entries are written, and at what level; null turns one off.
  levels: const DriftLogLevels(
    query: LogLevel.trace,
    committed: null,
  ),
  // From how long a query is flagged slow; null never flags one.
  slowQueryThreshold: const Duration(milliseconds: 200),
  // Leave out drift's own housekeeping and a sensitive table.
  filter: (kind, statement) =>
      !statement.startsWith('PRAGMA') && !statement.contains('sessions'),
  // Off by default; see above.
  logArguments: false,
  category: 'storage',
);
```

A stream from `watch()` reruns its query every time its tables change, and
each rerun is a `db_query`. If that is too much, lower `query` to `trace` or
filter the statement out: slow queries and failures still show.

With a `DriftIsolate`, the interceptor runs where you call `interceptWith` —
usually on the side that sends queries — so `duration_ms` includes the trip
to the isolate: how long your code waited.

## API Reference

| Symbol | Description |
|---|---|
| `StructuredLogDriftInterceptor({logger, loggerName, category, levels, slowQueryThreshold, logArguments, filter})` | The interceptor; pass it to `interceptWith`. Without `logger`, it calls `getLogger(loggerName)` on every entry. `category: null` binds no category. |
| `DriftLogLevels({query, batch, slow, failed, committed, rolledBack})` | A `LogLevel?` per kind of entry; `null` turns it off. |
| `defaultStatementMaxLength` | 2000 — the longest `statement` written. |
| `defaultArgumentMaxLength` | 1000 — the longest string argument written, with `logArguments` on. |

## Related packages

The rest of the `structured_log` family:

**Core**

- [`structured_log`](https://pub.dev/packages/structured_log) — structured JSON logging with context binding, processors and multi-sink routing

**In-app log viewer**

- [`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter) — headless viewer core: `LogBuffer` and `LogViewerController`
- [`structured_log_material`](https://pub.dev/packages/structured_log_material) — Material 3 log viewer
- [`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) — Fluent UI (WinUI-style) log viewer
- [`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino) — Cupertino (iOS-style) log viewer

**Shipping logs to a server**

- [`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync) — batching, retrying sink for a self-hosted `structured_log_server`

**Integrations**

- [`structured_log_bloc`](https://pub.dev/packages/structured_log_bloc) — `BlocObserver` for `bloc`/`flutter_bloc`
- [`structured_log_dio`](https://pub.dev/packages/structured_log_dio) — `dio` interceptor that logs HTTP calls
- [`structured_log_http_client`](https://pub.dev/packages/structured_log_http_client) — `package:http` client wrapper that logs HTTP calls
- [`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router) — logs `go_router` navigation
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — observer for the `cherrypick` DI container
- [`structured_log_logging`](https://pub.dev/packages/structured_log_logging) — bridge that routes `package:logging` records into `structured_log`

## License

MIT — see [LICENSE](LICENSE).
