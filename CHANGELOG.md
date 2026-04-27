# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/pese-git/structured_log.git/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/pese-git/structured_log.git/releases/tag/v0.1.0
