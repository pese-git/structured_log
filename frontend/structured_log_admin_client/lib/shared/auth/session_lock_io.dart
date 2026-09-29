import 'session_lock.dart';

/// Nothing to serialise off the web: one process, no tabs.
SessionLock createSessionLock() => const NoSessionLock();
