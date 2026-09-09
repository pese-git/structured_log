# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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

[Unreleased]: https://github.com/pese-git/structured_log.git/compare/v0.2.0-dev.1...HEAD
[0.2.0-dev.1]: https://github.com/pese-git/structured_log.git/compare/v0.1.0...v0.2.0-dev.1
[0.1.0]: https://github.com/pese-git/structured_log.git/releases/tag/v0.1.0
