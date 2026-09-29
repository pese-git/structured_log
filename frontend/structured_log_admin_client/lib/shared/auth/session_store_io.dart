import 'session_store.dart';

/// Off the web there are no tabs, so there is nothing to scope storage to —
/// this client is built for the browser only, and everything else is a test.
SessionStore createSessionStore() => InMemorySessionStore();
