export 'session_store_io.dart'
    if (dart.library.js_interop) 'session_store_web.dart';

/// Storage scoped to one browser tab.
///
/// Holds the access token, and only it. The access token lives fifteen
/// minutes and is sent on every request as a header, so it has to be readable
/// by this page; what it must not be is *shared*, which is what `localStorage`
/// would make it.
///
/// Per-tab and surviving a reload is the combination that matters. A reload
/// keeps its token and never asks the server, so refreshing a page costs
/// nothing and — more importantly — cannot race another tab doing the same.
/// Only a genuinely new tab has to restore the session, and that is rare
/// enough for the lock around it to be enough
/// (`add-refresh-token-cookie/design.md`, decisions 7 and 8).
abstract interface class SessionStore {
  String? read();

  void write(String? value);
}

/// For tests, for the component gallery, and for any host that is not a
/// browser.
class InMemorySessionStore implements SessionStore {
  String? _value;

  InMemorySessionStore([this._value]);

  @override
  String? read() => _value;

  @override
  void write(String? value) => _value = value;
}
