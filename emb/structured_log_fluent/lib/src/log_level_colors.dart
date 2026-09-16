import 'package:structured_log/structured_log.dart';

/// A short, upper-case abbreviation for [level] (`TRC`, `DBG`, `INF`,
/// `WRN`, `ERR`, `CRT`), used in the compact level badge next to each
/// entry — matching the density expected of a desktop list row.
///
/// (The level *color* palette — `logLevelColor` — lives in
/// `structured_log_flutter` now, shared across every skin; this
/// abbreviation stays here since it's specific to this package's compact
/// badge, not needed by `structured_log_material`/`structured_log_cupertino`.)
String logLevelAbbreviation(LogLevel level) {
  switch (level) {
    case LogLevel.trace:
      return 'TRC';
    case LogLevel.debug:
      return 'DBG';
    case LogLevel.info:
      return 'INF';
    case LogLevel.warning:
      return 'WRN';
    case LogLevel.error:
      return 'ERR';
    case LogLevel.critical:
      return 'CRT';
  }
}
