import 'package:cherrypick/cherrypick.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_cherrypick/structured_log_cherrypick.dart';

/// Sets up the container's global behaviour for a process: the observer, and
/// cycle detection in every scope, across scopes too.
///
/// The observer is `structured_log_cherrypick`'s, writing to the server's own
/// logger — the third journal, the one that must never be confused with the
/// other two (`design.md` decision 48). It never prints an instance, only the
/// name and type it is bound under: the graph holds the database and the
/// token settings, and an object printed is a secret printed
/// (`test/logging/diagnostics_isolation_test`).
///
/// Before the first scope is opened through the helper — a scope takes the
/// global observer when it is created. Cycle detection stays on in production: a
/// cycle is a mistake in the wiring, and the alternative to reporting it is a
/// stack overflow on startup.
///
/// Only scopes opened through `CherryPick` are reached; the isolated scopes tests
/// build for themselves are deliberately not.
void configureContainer(BoundLogger logger) {
  CherryPick.setGlobalObserver(StructuredLogCherryPickObserver(logger: logger));
  CherryPick.enableGlobalCycleDetection();
  CherryPick.enableGlobalCrossScopeCycleDetection();
}
