# Architecture

*Читать на [русском](ARCHITECTURE.ru.md).*

This document describes the internal design of `structured_log` for
contributors extending or maintaining the package. For usage as a
consumer, see [README.md](../README.md) (or [README.ru.md](../README.ru.md)).

## Design goals

- **No wrapper ceremony.** A `BoundLogger` is a thin, immutable value —
  `bind()`/`unbind()`/`withCorrelation()` all return a new instance rather
  than mutating state, so passing a logger around a call chain is safe.
- **One global configuration, many local loggers.** `StructlogConfiguration`
  is a process-wide singleton; individual `BoundLogger` instances only carry
  the context/correlation data specific to their scope.
- **Everything in the pipeline is a plain function.** Processors
  (`Map<String, dynamic>? Function(Map<String, dynamic>)`) and outputs
  (`void Function(Map<String, dynamic>, LogLevel)`) are typedef'd function
  types, not classes to subclass — custom behavior is just a closure.
- **Additive evolution.** Correlation and multi-sink routing were added
  without changing any existing method signature (see [CHANGELOG.md](../CHANGELOG.md)).

## Components

| File | Responsibility |
|------|----------------|
| [lib/src/logger.dart](../lib/src/logger.dart) | `LogLevel`, `BoundLogger` — binds context/correlation, runs the processor pipeline, delivers to sinks |
| [lib/src/configuration.dart](../lib/src/configuration.dart) | `StructlogConfiguration` — global processors/sinks/initialContext, `configure()`/`reset()`/`setSinkEnabled()` |
| [lib/src/correlation.dart](../lib/src/correlation.dart) | `LogCorrelation` — typed, mergeable correlation fields |
| [lib/src/sink.dart](../lib/src/sink.dart) | `LogSink` — one output destination with level/category filtering and a runtime enable switch |
| [lib/src/processors.dart](../lib/src/processors.dart) | `Processor` typedef + built-ins (`dropNullValues`, `addTimestamp`, `addLogLevel`, `jsonRenderer`, `logfmtRenderer`) |
| [lib/src/formatters.dart](../lib/src/formatters.dart) | `OutputFunction` typedef + built-in outputs (console, colored console, file, rotating file) |

### Component relationships

```mermaid
classDiagram
    class BoundLogger {
        -Map~String,dynamic~ _context
        -LogCorrelation? _correlation
        -StructlogConfiguration _config
        +bind(context) BoundLogger
        +unbind(keys) BoundLogger
        +withCorrelation(...) BoundLogger
        +debug(event, context)
        +info(event, context)
        +warning(event, context)
        +error(event, context)
        +critical(event, context)
        -tryLog(level, event, context)
        -_processEntry(entry, level) Map?
    }

    class StructlogConfiguration {
        +List~Processor~ processors
        +List~LogSink~ sinks
        +Map initialContext
        +configure(...)$
        +reset()$
        +setSinkEnabled(name, enabled)$
        +current StructlogConfiguration$
    }

    class LogCorrelation {
        +String? sessionId
        +String? requestId
        +int? connectionGeneration
        +String? toolCallId
        +String? messageId
        +String? operationId
        +merge(other) LogCorrelation
        +toContext() Map
    }

    class LogSink {
        +String name
        +OutputFunction output
        +LogLevel minLevel
        +Set~String~? categories
        +bool enabled
        +accepts(level, category) bool
    }

    class Processor {
        <<typedef>>
        Map? Function(Map entry)
    }

    class OutputFunction {
        <<typedef>>
        void Function(Map entry, LogLevel level)
    }

    BoundLogger --> StructlogConfiguration : reads at construction
    BoundLogger --> LogCorrelation : holds 0..1
    StructlogConfiguration --> "0..*" LogSink : holds
    StructlogConfiguration --> "0..*" Processor : holds
    LogSink --> OutputFunction : wraps one
```

`getLogger()` reads `StructlogConfiguration.current` **once**, at the moment
it's called, and stores that reference in the new `BoundLogger`. A logger
obtained before a later `configure()` call keeps seeing the *old*
configuration object unless that call reuses the same `sinks`/`processors`
list — see [Runtime toggling and the config snapshot](#runtime-toggling-and-the-config-snapshot).

## Log call lifecycle

Calling e.g. `log.info('event', context: {...})` walks through
`tryLog()` → `_processEntry()` → per-sink delivery:

```mermaid
sequenceDiagram
    participant Caller
    participant BoundLogger
    participant Processors as processors pipeline
    participant Sink as LogSink (for each)

    Caller->>BoundLogger: info(event, context: {...})
    BoundLogger->>BoundLogger: tryLog(level, event, context)
    Note over BoundLogger: merge order:<br/>bound _context<br/>→ inline context<br/>→ correlation.toContext() (wins on conflict)<br/>→ event
    BoundLogger->>Processors: _processEntry(mergedContext, level)
    Note over Processors: adds level + timestamp,<br/>then runs each Processor in order
    alt a processor returns null
        Processors-->>BoundLogger: null (entry dropped)
        BoundLogger-->>Caller: return (nothing delivered)
    else entry survives the pipeline
        Processors-->>BoundLogger: final entry Map
        loop for each sink in config.sinks
            BoundLogger->>Sink: accepts(level, entry['category'])?
            alt disabled, below minLevel, or category mismatch
                Sink-->>BoundLogger: false (skip)
            else accepted
                BoundLogger->>Sink: output(entry, level)
                alt output throws
                    Sink-->>BoundLogger: exception caught
                    BoundLogger->>BoundLogger: stderr.writeln(diagnostic)
                else
                    Sink-->>BoundLogger: delivered
                end
            end
        end
    end
```

Key invariants from this flow:

- **Typed correlation wins.** Correlation fields are merged *after* the
  inline `context` map, so a same-named key from `context:` never shadows a
  bound correlation field.
- **A processor returning `null` drops the entry entirely** — no sink sees
  it, and no diagnostic is printed (this is the standard filtering
  mechanism, e.g. for level-based suppression written as a custom
  processor).
- **Sink failures are isolated.** Each `sink.output()` call is wrapped in
  its own `try/catch`; one broken sink (e.g. an unwritable file path) never
  stops delivery to the others and never throws out of `tryLog()`.

## Multi-sink routing

`category` is not a first-class parameter on any logging method — it's
just a conventional context key (`'category'`), set via `bind()` or inline
`context:` like any other value. `LogSink.categories` matches against it:

```mermaid
flowchart TD
    A["entry = {..., category: 'protocol'}"] --> B{"sink 'console'<br/>categories: null"}
    A --> C{"sink 'protocol'<br/>categories: {'protocol'}"}
    B -->|"null = no restriction"| D["console output"]
    C -->|"category matches"| E["protocol.log output"]
```

`categories: null` (the default) means "no restriction" — the sink accepts
every category. A sink with a non-null `categories` set rejects entries
that have no `category` key or a non-matching one.

### Runtime toggling and the config snapshot

`LogSink.enabled` is a mutable field (not `final`) specifically so
`StructlogConfiguration.setSinkEnabled(name, enabled: ...)` can flip it in
place on the *existing* `LogSink` object — no new `StructlogConfiguration`
or `BoundLogger` needs to be created for the toggle to take effect.

This only works because `configure()` reuses the same `sinks` list (and
thus the same `LogSink` instances) when the caller doesn't pass a new
`sinks:` argument — see the `nextSinks` fallback in
[configuration.dart](../lib/src/configuration.dart). If a later `configure(sinks: [...])`
call *replaces* the list wholesale, any `BoundLogger` still holding the old
`StructlogConfiguration` instance keeps delivering to the old sinks — this
mirrors the pre-existing behavior of `processors`/`initialContext`
(loggers capture a `StructlogConfiguration` reference at creation time, not
a live pointer to `StructlogConfiguration.current`).

## Extension points

Everything pluggable is a plain function or a `LogSink`, so no interface to
implement:

- **Custom processor** — `Map<String, dynamic>? Function(Map<String, dynamic>)`.
  Return `null` to drop the entry; otherwise return the (possibly mutated)
  map. Order matters — processors run sequentially, each seeing the
  previous one's output.
- **Custom output** — `void Function(Map<String, dynamic>, LogLevel)`. Used
  directly via `configure(output: ...)` or wrapped in a `LogSink` for
  filtered/multi-destination delivery.
- **Custom sink** — construct a `LogSink` with any `OutputFunction`,
  `minLevel`, and `categories`; no subclassing needed.

## Testing approach

[test/structlog_test.dart](../test/structlog_test.dart) favors capturing
entries via a custom `OutputFunction`/`LogSink` closure that appends to a
local `List`/variable, rather than asserting on stdout or the filesystem —
this keeps assertions on the exact `Map<String, dynamic>` produced by the
pipeline. Tests that call `StructlogConfiguration.configure()` always
`tearDown(StructlogConfiguration.reset)` to avoid bleeding global state
into other tests.
