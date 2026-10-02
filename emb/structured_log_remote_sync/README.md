# structured_log_remote_sync

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

Ships [`structured_log`](https://pub.dev/packages/structured_log) entries to a
[`structured_log_server`](../../backend/structured_log_server) over HTTP.

Formerly published as
[`structured_log_http`](https://pub.dev/packages/structured_log_http) — renamed
in 0.2.0; moving over is one dependency line, one import and one class name
(`HttpLogOutput` → `RemoteSyncLogOutput`), with no change in behaviour.

`RemoteSyncLogOutput` is an ordinary `OutputFunction`, so it plugs into a
`LogSink` with no change to the core package — and it never blocks the code that
logged: entries are queued and shipped in batches on a background future.

## Features

- **Non-blocking** — a slow or unreachable server never delays `log.info(...)`
- **Batching** — entries travel together, by size or by timeout, whichever comes first
- **Retry with backoff** — network failures, timeouts and 5xx are retried; 4xx is not
- **Bounded memory** — a configurable ceiling on unsent entries, oldest dropped first
- **`flushed`** — await delivery before the process exits
- **One dependency** — `structured_log`, and `dart:io` for the transport

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
to `stderr`, the same channel `structured_log`'s own async outputs use.

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

## License

MIT — see [LICENSE](LICENSE).
