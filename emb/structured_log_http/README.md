# structured_log_http

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

Ships [`structured_log`](https://pub.dev/packages/structured_log) entries to a
[`structured_log_server`](../../backend/structured_log_server) over HTTP.

`HttpLogOutput` is an ordinary `OutputFunction`, so it plugs into a `LogSink`
with no change to the core package — and it never blocks the code that
logged: entries are queued and shipped in batches on a background future.

## Features

- **Non-blocking** — a slow or unreachable server never delays `log.info(...)`
- **Batching** — entries travel together, by size or by timeout, whichever comes first
- **Retry with backoff** — network failures, timeouts and 5xx are retried; 4xx is not
- **Bounded memory** — a configurable ceiling on unsent entries, oldest dropped first
- **`flushed`** — await delivery before the process exits
- **One dependency** — `structured_log`, and `dart:io` for the transport

## Installation

Not yet published to pub.dev (`0.1.0-dev.0`) — depend on it as a path or
git dependency for now:

```yaml
dependencies:
  structured_log: ^0.2.0
  structured_log_http:
    path: ../structured_log_http # within this monorepo
```

## Quick Start

```dart
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_http/structured_log_http.dart';

Future<void> main() async {
  final output = HttpLogOutput(
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
| `serverUrl` | — | Base URL; `/v1/logs` is appended |
| `projectSecretKey` | — | Sent as `Authorization: Bearer <key>` |
| `batchSize` | `50` | Entries that trigger a send without waiting |
| `batchTimeout` | `5s` | How long a partial batch waits before going out |
| `maxBufferedEntries` | `10000` | Ceiling on unsent entries held in memory |
| `maxAttempts` | `4` | Attempts per batch, including the first |
| `retryBackoff` | `500ms` | Delay before the second attempt; doubles thereafter |
| `requestTimeout` | `30s` | How long one attempt may take |

## Behaviour worth knowing

**Retry is decided by whether the answer can change.** A network failure, a
timeout and a 5xx are retried with a doubling delay. A 4xx is not: a 401 from
a revoked project key will answer 401 forever, and retrying it only delays
the entries queued behind it. `408` and `429` are the exceptions — they mean
"later", not "never".

**Memory is bounded, and the oldest entries lose.** If the server is
unreachable for long enough, the buffer fills and the oldest unsent entries
are dropped. The alternative — growing without limit — turns an outage in
the log pipeline into an outage in the application, which is precisely
backwards. Eviction is reported on `stderr` once when it starts and once
with a total when it ends.

**Failures are reported, never thrown.** Nothing this package does can make
a `log.info(...)` call fail. Batches that cannot be delivered are reported
to `stderr`, the same channel `structured_log`'s own async outputs use.

**Batches never overlap.** Delivery is serialized, so entries reach the
server in the order they were logged.

## License

MIT — see [LICENSE](LICENSE).
