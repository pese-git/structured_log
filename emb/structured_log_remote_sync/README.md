# structured_log_remote_sync

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

**Get the logs from every install of your app onto your own server —
batched, retried, and without ever slowing down the code that logged.**

Documentation: [structured-log.openidealab.com](https://structured-log.openidealab.com).

## Why

A log that stays on the device is a log you never read. When a user reports
"it broke yesterday", the console output that would explain it is on their
phone, in a desktop install on the other side of the world, or gone with the
process that wrote it. Collecting it means sending it somewhere — and doing
that from inside an app is easy to get wrong: a slow network that stalls a
`log.info(...)`, a queue that grows without limit while the server is down,
a batch lost to one value that would not encode.

`RemoteSyncLogOutput` is a `structured_log` output that does this properly.
Each entry is queued the moment it is logged and returns at once; a
background pump ships entries in batches to a self-hosted
[`structured_log_server`](https://github.com/pese-git/structured_log/tree/master/backend/structured_log_server),
retries what may yet succeed, and keeps memory bounded however long the
server is unreachable.

Formerly published as
[`structured_log_http`](https://pub.dev/packages/structured_log_http), now
discontinued — renamed in 0.2.0; moving over is one dependency line, one
import and one class name (`HttpLogOutput` → `RemoteSyncLogOutput`), with no
change in behaviour. Ask for `^0.2.0`: under `0.x`, `^0.1.0` means `<0.2.0`
and matches no release published under this name.

## Features

### Delivery

- **Never blocks the caller** — logging enqueues and returns; a slow or
  unreachable server never delays `log.info(...)`.
- **Batching** — entries travel together in one `POST /v1/logs`, by size or
  by timeout, whichever comes first.
- **In order** — batches never overlap, so entries reach the server in the
  order they were logged.
- **`flushed` and `close()`** — await delivery before the process exits.

### Resilience

- **Retry with backoff** — network failures, timeouts and 5xx are retried
  with a doubling delay; a 4xx is not, except `408` and `429`.
- **`Retry-After` honoured** — both the seconds and the HTTP-date form, up to
  a ceiling you set, and the wait holds the whole sender, not one batch.
- **Bounded memory** — a configurable ceiling on unsent entries; past it the
  oldest are dropped, and the episode is reported once, not per entry.
- **Encoded at log time** — each entry becomes a JSON string the moment it
  is logged, with `structured_log`'s `encodeLogEntry`. A `DateTime` or an
  exception in the context is encoded rather than costing the batch, a map
  changed after the call doesn't change what is sent, and an entry that
  cannot be read at all is dropped alone.
- **Failures reported, never thrown** — to `stderr` by default, or to a
  callback of your own.

### Fit

- **Just another output** — `RemoteSyncLogOutput` *is* an `OutputFunction`,
  so it goes into a `LogSink` next to the console or a file, with its own
  level and category filter.
- **One dependency** — `structured_log`; the transport is `dart:io`'s
  `HttpClient`, so it runs on the Dart VM and in Flutter on mobile and
  desktop, but not on the web.

## Where it fits

This package is the bridge between `structured_log` in your app and the
self-hosted
[`structured_log_server`](https://github.com/pese-git/structured_log/tree/master/backend/structured_log_server),
where your team searches and live-tails the logs in a web admin. It is the
only package in the family that needs the server — the core library, the
in-app viewers and the adapters all work without one — and adding it changes
no logging call: entries from your own code and from the adapters
(`bloc`, `dio`, `http`, `go_router`, `cherrypick`) flow to it like to any
other sink. Setting up the server side — projects, secret keys, what the API
accepts — is covered in the
[Developer Guide](https://structured-log.openidealab.com/guides/developer-guide/);
the whole project is at
[structured-log.openidealab.com](https://structured-log.openidealab.com).

## Installation

```yaml
dependencies:
  structured_log: ^0.3.0
  structured_log_remote_sync: ^0.2.0
```

`structured_log_remote_sync` needs `structured_log` 0.3.0 or later — it encodes
entries with that release's `encodeLogEntry`.

## Quick Start

```dart
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_remote_sync/structured_log_remote_sync.dart';

Future<void> main() async {
  final output = RemoteSyncLogOutput(
    serverUrl: 'https://logs.example.com',
    // From POST /v1/projects/:id/secret-keys — shown once, on creation.
    projectSecretKey: 'slk_...',
  );

  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'server', output: output)],
  );

  getLogger().info('startup', context: {'version': '1.4.0'});

  // Without this the process can exit with entries still queued.
  await output.flushed;
}
```

Keep a reference to the instance rather than passing it inline as `output:`,
so you can `await flushed` — that is the only way to know a queued entry
actually left.

### Alongside a local sink

A server sink is usually not the only one you want: keeping the console
output means you can still see what happened when the network cannot.

```dart
StructlogConfiguration.configure(
  sinks: [
    LogSink(name: 'console', output: coloredConsoleOutput),
    LogSink(name: 'server', output: output, minLevel: LogLevel.info),
  ],
);
```

Each sink filters independently, so shipping only `info` and above while the
console keeps `debug` costs nothing extra.

## Configuration

| Parameter | Default | What it controls |
|---|---|---|
| `serverUrl` | — | Base URL; `/v1/logs` is appended. Must be `http://` or `https://` and name a host |
| `projectSecretKey` | — | Sent as `Authorization: Bearer <key>` |
| `batchSize` | `50` | Entries that trigger a send without waiting |
| `batchTimeout` | `5s` | How long a partial batch waits before going out |
| `maxBufferedEntries` | `10000` | Ceiling on unsent entries held in memory |
| `maxAttempts` | `4` | Attempts per batch, including the first |
| `retryBackoff` | `500ms` | Delay before the second attempt; doubles thereafter |
| `maxRetryAfter` | `5m` | Longest `Retry-After` honoured; `Duration.zero` ignores the header |
| `requestTimeout` | `30s` | How long one attempt may take |
| `report` | writes to `stderr` | Where failures, evictions and clamped waits are reported |
| `sender` | HTTP transport | A `BatchSender` that replaces the transport — a seam for tests; you own its lifetime |

A value that cannot mean anything is refused with an `ArgumentError` at
construction rather than absorbed: a buffer smaller than a batch, fewer than
one attempt, a negative duration, a `requestTimeout` of zero, a `serverUrl`
whose scheme is not `http`/`https` or that names no host. A missing scheme is
refused rather than repaired — prepending `https://` would mean picking the
transport on your behalf. Where zero does
mean something it stays legal — `maxRetryAfter: Duration.zero` is how
honouring the header is switched off, and a zero `retryBackoff` is "retry at
once".

## Behaviour worth knowing

**Retry is decided by whether the answer can change.** A network failure, a
timeout and a 5xx are retried with a doubling delay. A 4xx is not: a 401 from
a revoked project key will answer 401 forever, and retrying it only delays
the entries queued behind it. `408` and `429` are the exceptions — they mean
"later", not "never".

**`Retry-After` is obeyed, and it holds the whole sender.** A refusal that
names a moment to come back at is waited out instead of the backoff, and the
wait applies to every batch, not only the refused one — a limiter saying "not
before T" is talking about the connection. Without that, a throttled sender
keeps hammering: the batch exhausts its attempts, gives up, and the next one
starts over at once. The header is not this server's, incidentally —
ingestion is deliberately not throttled by `structured_log_server`, so a
`429` here was written by a proxy or gateway in front of it, which is why
both the delay-seconds and HTTP-date forms are read. A wait longer than
`maxRetryAfter` is clamped to it and said on `stderr`; a header that is
missing, unparseable, zero or already past leaves the backoff alone. On
`close()` a wait still outstanding is abandoned rather than sat out — a
process on its way out holds neither for minutes nor sends a burst it was
told not to — and the entries it was holding are reported as dropped.

**Memory is bounded, and the oldest entries lose.** If the server is
unreachable for long enough, the buffer fills and the oldest unsent entries
are dropped. The alternative — growing without limit — turns an outage in
the log pipeline into an outage in the application, which is precisely
backwards. Eviction is reported on `stderr` once when it starts and once
with a total when it ends.

**Failures are reported, never thrown.** Nothing this package does can make
a `log.info(...)` call fail. Batches that cannot be delivered are reported
to `stderr` — the same channel `structured_log`'s own async outputs use — or
to the `report` callback, when you pass one. An entry logged after `close()`
is reported and discarded.

**An entry is encoded when it is logged, not when its batch is sent.** The
sink turns each entry into JSON the moment it is called, with
`structured_log`'s `encodeLogEntry`, and the buffer holds those strings. Two
things follow. A value `jsonEncode` would refuse — a `DateTime`, an exception,
an enum — is written the way `encodeLogEntry` writes it instead of costing
anything: before, one such value lost the whole batch it travelled in, up to
`batchSize` entries. And an entry travels as it was at log time — a map
changed after the call does not change what reaches the server. An entry that
cannot be read at all is dropped on its own and reported on `stderr`; the
batch it would have joined goes without it. A custom `BatchSender` still
receives maps — the entries decoded back from that JSON. Strings are also
several times smaller than the maps they came from, so a full buffer costs
less memory than it did.

**Batches never overlap.** Delivery is serialized, so entries reach the
server in the order they were logged.

## API Reference

| Symbol | Description |
|---|---|
| `RemoteSyncLogOutput({serverUrl, projectSecretKey, batchSize, batchTimeout, maxBufferedEntries, maxAttempts, retryBackoff, maxRetryAfter, requestTimeout, sender, report})` | The output. Pass the instance as a `LogSink`'s `output`; calling it enqueues one entry and returns. |
| `flushed` | Completes once everything enqueued before the call has been delivered or given up on. |
| `close()` | Stops accepting entries, sends what is buffered, and releases the HTTP client. |
| `BatchSender` | `Future<BatchResult> Function(List<Map<String, dynamic>> entries)` — the transport seam; entries arrive decoded from the JSON they were queued as. |
| `BatchResult` | One attempt's outcome: `.delivered()`, `.retryable(error, {retryAfter})` or `.rejected(error)`. |

## Related packages

The rest of the `structured_log` family:

**Core**

- [`structured_log`](https://pub.dev/packages/structured_log) — structured JSON logging with context binding, processors and multi-sink routing

**In-app log viewer**

- [`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter) — headless viewer core: `LogBuffer` and `LogViewerController`
- [`structured_log_material`](https://pub.dev/packages/structured_log_material) — Material 3 log viewer
- [`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) — Fluent UI (WinUI-style) log viewer
- [`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino) — Cupertino (iOS-style) log viewer

**Integrations**

- [`structured_log_bloc`](https://pub.dev/packages/structured_log_bloc) — `BlocObserver` for `bloc`/`flutter_bloc`
- [`structured_log_dio`](https://pub.dev/packages/structured_log_dio) — `dio` interceptor that logs HTTP calls
- [`structured_log_http_client`](https://pub.dev/packages/structured_log_http_client) — `package:http` client wrapper that logs HTTP calls
- [`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router) — logs `go_router` navigation
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — observer for the `cherrypick` DI container
- [`structured_log_drift`](https://pub.dev/packages/structured_log_drift) — drift `QueryInterceptor` that logs queries, failures and transactions
- [`structured_log_logging`](https://pub.dev/packages/structured_log_logging) — bridge that routes `package:logging` records into `structured_log`

## License

MIT — see [LICENSE](LICENSE).
