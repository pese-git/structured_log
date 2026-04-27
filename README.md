# structured_log

Structured logging for Dart, inspired by [Python's structlog](https://www.structlog.org/).

Log JSON with context binding, processors, and flexible output destinations.

## Features

- **Structured JSON output** — logs are machine-readable by default
- **Context binding** — immutable `bind()` / `unbind()` for attaching metadata to loggers
- **Processors** — transform log entries before output (filter, enrich, format)
- **Multiple outputs** — stdout, file, rotating file, or custom
- **Colored console** — human-readable development output
- **Configurable** — global configuration with `StructlogConfiguration.configure()`
- **Zero dependencies** — only Dart SDK

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  structured_log:
    # or pub.dev when published
```

## Quick Start

```dart
import 'package:structured_log/structured_log.dart';

void main() {
  final log = getLogger();
  log.info('user_login', context: {'user_id': 42, 'ip': '127.0.0.1'});
}
```

Output:

```json
{
  "user_id": 42,
  "ip": "127.0.0.1",
  "event": "user_login",
  "level": "info",
  "timestamp": "2026-04-27T12:00:00.000000"
}
```

## API Reference

### Getting a Logger

```dart
// Default logger
final log = getLogger();

// Named logger (adds 'logger' key to context)
final log = getLogger('auth');
```

### Log Levels

| Method     | Level    | Color (console) |
|------------|----------|-----------------|
| `debug()`  | debug    | cyan            |
| `info()`   | info     | green           |
| `warning()`| warning  | yellow          |
| `error()`  | error    | red             |
| `critical()`| critical| magenta         |

```dart
log.debug('cache miss', context: {'key': 'session:42'});
log.info('request completed', context: {'duration_ms': 150});
log.warning('slow query', context: {'sql': 'SELECT ...', 'ms': 2000});
log.error('payment failed', context: {'error': 'timeout', 'order_id': 123});
log.critical('database down', context: {'host': 'db-primary'});
```

### Context Binding

`bind()` returns a **new** logger instance with merged context (immutable pattern):

```dart
final baseLog = getLogger();

// Bind request-level context
final requestLog = baseLog.bind({'request_id': 'abc-123', 'trace_id': 'xyz'});

// Bind user-level context on top
final userLog = requestLog.bind({'user_id': 42});

userLog.info('purchase');
// → {"request_id": "abc-123", "trace_id": "xyz", "user_id": 42, "event": "purchase", ...}
```

`unbind()` removes keys:

```dart
final cleanLog = userLog.unbind(['user_id']);
```

### Inline Context

Pass per-call context directly:

```dart
log.info('event', context: {'one_off': true});
```

Context is merged in order: `initialContext` → `bind()` → inline `context`.

## Configuration

### Global Configuration

```dart
StructlogConfiguration.configure(
  processors: [dropNullValues, myCustomProcessor],
  output: fileOutput('logs/app.log'),
  initialContext: {'app': 'my_app', 'version': '1.0.0'},
);
```

| Parameter        | Type                  | Default           | Description                     |
|------------------|-----------------------|-------------------|---------------------------------|
| `processors`     | `List<Processor>`     | `[dropNullValues]`| Pipeline to transform entries   |
| `output`         | `OutputFunction`      | `defaultOutput`   | Where to send log entries       |
| `initialContext` | `Map<String, dynamic>`| `{}`              | Context added to all loggers    |

Reset to defaults:

```dart
StructlogConfiguration.reset();
```

### Outputs

#### Console (default)

Pretty-printed JSON to stdout:

```dart
StructlogConfiguration.configure(output: defaultOutput);
```

#### Colored Console

Human-readable with ANSI colors:

```dart
StructlogConfiguration.configure(output: coloredConsoleOutput);
```

Output:

```
[2026-04-27T12:00:00.000000] INFO: user_login {"user_id": 42}
```

#### File

Append JSON lines (JSONL) to a file. Directories are created automatically:

```dart
StructlogConfiguration.configure(
  output: fileOutput('logs/app.log'),
);
```

#### Rotating File

Automatically rotates when file exceeds size limit:

```dart
StructlogConfiguration.configure(
  output: rotatingFileOutput(
    'logs/app.log',
    maxSizeBytes: 10 * 1024 * 1024, // 10MB
    maxBackups: 5,                   // keep 5 rotated files
  ),
);
```

Rotated files: `app.log`, `app.log.0`, `app.log.1`, ... `app.log.4`

#### Custom Output

Implement your own:

```dart
void myOutput(Map<String, dynamic> entry, LogLevel level) {
  // Send to Sentry, CloudWatch, etc.
}

StructlogConfiguration.configure(output: myOutput);
```

## Processors

Processors are functions that transform log entries before output. Return `null` to drop the entry.

### Built-in Processors

| Processor        | Description                    |
|------------------|--------------------------------|
| `dropNullValues` | Removes keys with `null` value |
| `addTimestamp`   | Adds ISO 8601 timestamp        |
| `addLogLevel`    | Ensures level key exists       |
| `jsonRenderer`   | Prints entry as JSON           |
| `logfmtRenderer` | Prints as `key=value` pairs    |

### Custom Processor

```dart
Map<String, dynamic>? maskPasswords(Map<String, dynamic> entry) {
  if (entry.containsKey('password')) {
    entry['password'] = '***';
  }
  return entry;
}

StructlogConfiguration.configure(
  processors: [dropNullValues, maskPasswords],
);
```

Processor order matters — they run sequentially:

```dart
processors: [
  dropNullValues,      // 1. Clean nulls
  maskPasswords,       // 2. Mask secrets
  addCorrelationId,    // 3. Enrich
]
```

## Examples

### Web Server Request Logging

```dart
import 'package:structured_log/structured_log.dart';

void handleRequest(Request req) {
  final log = getLogger().bind({
    'request_id': req.id,
    'method': req.method,
    'path': req.path,
    'ip': req.remoteAddress,
  });

  log.info('request started');

  try {
    final response = processRequest(req);
    log.info('request completed', context: {
      'status': response.status,
      'duration_ms': response.duration,
    });
  } catch (e, st) {
    log.error('request failed', context: {
      'error': e.toString(),
      'stack_trace': st.toString(),
    });
    rethrow;
  }
}
```

### Multiple Loggers (file + console)

```dart
// Console logger for development
final consoleLog = getLogger('console');
consoleLog.info('app started');

// Switch to file output
StructlogConfiguration.configure(output: fileOutput('logs/production.log'));
final fileLog = getLogger('production');
fileLog.info('same event, different output');
```

### Async-Safe Logging

The library uses synchronous file I/O, making it safe for use in any context:

```dart
Future<void> asyncTask() async {
  final log = getLogger().bind({'task': 'background_job'});
  log.info('task started');

  await Future.delayed(Duration(seconds: 1));

  log.info('task completed');
}
```

## Comparison with Python structlog

| Feature              | Python structlog | Dart structured_log |
|----------------------|------------------|----------------|
| Context binding      | `bind()`         | `bind()`       |
| Processors           | Yes              | Yes            |
| JSON output          | Yes              | Yes            |
| Console output       | Yes              | Yes (colored)  |
| File output          | Via stdlib       | Built-in       |
| Rotating file        | Via handlers     | Built-in       |
| Async support        | Yes              | Sync I/O       |
| Wrapper classes      | Yes              | No (simple)    |

## License

MIT
