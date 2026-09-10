# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

## 2026-09-10

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`structured_log` - `v0.2.0-dev.3`](#structured_log---v020-dev3)

---

#### `structured_log` - `v0.2.0-dev.3`

 - **FEAT**: add LogLevel.trace below debug.
 - **DOCS**: clean up CHANGELOG.md after melos version's auto-generated entry.

## 0.2.0-dev.3

 - **FEAT**: add LogLevel.trace below debug.
 - **DOCS**: clean up CHANGELOG.md after melos version's auto-generated entry.

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `LogLevel.trace` — a new level below `debug`, plus `BoundLogger.trace()`.
  Filtered out by a sink's default `minLevel` (`debug`) unless a sink
  explicitly sets `minLevel: LogLevel.trace`, so high-volume detail (e.g.
  raw protocol frames) can be gated purely by level, with no `category`
  tagging needed. `coloredConsoleOutput` renders it in grey.

## [0.2.0-dev.2] - 2026-09-10

### Added
- `test/integration_test.dart` — integration tests exercising the package
  as a whole system on real files (correlation + processors + multi-sink
  routing combined, mixed sync/async sinks, full rotation history across
  numbered backups, `coloredConsoleOutput`'s real printed format), as a
  complement to the existing component-level unit tests
- `AsyncFileOutput` and `AsyncRotatingFileOutput` — non-blocking
  counterparts of `fileOutput`/`rotatingFileOutput` that use async
  `dart:io` File APIs instead of `writeAsStringSync`, so logging doesn't
  block the calling isolate. Writes are serialized and delivered in order;
  a failing write is caught and reported to `stderr` without stopping the
  writes queued after it. Exposes a `flushed` future to await pending
  writes (e.g. in tests or before process exit)
- `doc/ARCHITECTURE.md` — internal design docs for contributors, with
  Mermaid class/sequence/flow diagrams of the log call lifecycle and
  multi-sink routing
- `doc/ARCHITECTURE.ru.md` — Russian translation of the architecture doc
- "How It Works" section in `README.md`/`README.ru.md` with a Mermaid
  flowchart of the logging pipeline for consumers
- Cross-links between the English/Russian README and architecture docs

## [0.2.0-dev.1] - 2026-09-09

### Added
- `LogCorrelation` and `BoundLogger.withCorrelation()` for typed correlation
  fields (`sessionId`, `requestId`, `connectionGeneration`, `toolCallId`,
  `messageId`, `operationId`), serialized under fixed snake_case keys and
  inherited/overridable through child loggers
- `LogSink` and `StructlogConfiguration(sinks: ...)` for multi-output
  routing: one log entry can be delivered to multiple destinations with
  independent `minLevel`/`categories` filtering, runtime enable/disable via
  `StructlogConfiguration.setSinkEnabled()`, and per-sink error isolation

### Changed
- Updated repository URL to `https://github.com/pese-git/structured_log.git`
- Added FVM (Flutter Version Management) configuration
- Added Melos scripts for development workflow (`analyze`, `format`, `test`, `lint`, `build`, `example`, `clean`)
- Added `.gitignore` for Dart/FVM project
- Removed unused imports from source files
- Removed deprecated `author` field from `pubspec.yaml`
- Formatted all source files with `dart format`

## [0.1.0] - 2026-04-27

### Added
- Initial release of `structured_log`
- `BoundLogger` with immutable `bind()` / `unbind()` context binding
- Log levels: `debug`, `info`, `warning`, `error`, `critical`
- Processors: `dropNullValues`, `addTimestamp`, `addLogLevel`, `jsonRenderer`, `logfmtRenderer`
- Output formats: default JSON console, colored console, file, rotating file
- Global configuration via `StructlogConfiguration.configure()`
- Example usage in `example/main.dart`
- Basic test suite

[Unreleased]: https://github.com/pese-git/structured_log.git/compare/v0.2.0-dev.2...HEAD
[0.2.0-dev.2]: https://github.com/pese-git/structured_log.git/compare/v0.2.0-dev.1...v0.2.0-dev.2
[0.2.0-dev.1]: https://github.com/pese-git/structured_log.git/compare/v0.1.0...v0.2.0-dev.1
[0.1.0]: https://github.com/pese-git/structured_log.git/releases/tag/v0.1.0
