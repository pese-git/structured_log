import 'package:flutter/foundation.dart';

/// Whether the app is showing the login screen or what is behind it.
///
/// Lives outside the widget tree because two things drive it from different
/// places: the login screen, which reports a session it just created, and the
/// network layer, which reports one it could not renew — and the interceptor
/// has no `BuildContext` to work with.
class SessionController extends ChangeNotifier {
  bool _signedIn;
  bool _expired = false;
  bool _mustChangePassword = false;

  SessionController({bool signedIn = false}) : _signedIn = signedIn;

  bool get signedIn => _signedIn;

  /// The server is refusing everything until this account's password is
  /// changed (`403 must_change_password`). The session itself is fine — the
  /// sign-in succeeded and the tokens are held — so this is a third state
  /// rather than a kind of being signed out: the app shows the change-password
  /// screen and nothing else, except the way out
  /// (`specs/admin-client-auth`).
  bool get mustChangePassword => _mustChangePassword;

  /// True when the user is at the login screen because a session ended rather
  /// than because they opened the app. The screen says so; it is cleared on
  /// the next successful sign-in.
  bool get expired => _expired;

  void signedInNow() {
    if (_signedIn && !_expired) return;
    _signedIn = true;
    _expired = false;
    notifyListeners();
  }

  /// A request came back `403 must_change_password`. Raised by the API
  /// client's interceptor, from wherever in the app the request was made.
  void passwordChangeRequired() {
    if (_mustChangePassword) return;
    _mustChangePassword = true;
    notifyListeners();
  }

  /// The password was changed and the gate is behind us.
  void passwordChanged() {
    if (!_mustChangePassword) return;
    _mustChangePassword = false;
    notifyListeners();
  }

  /// A session could not be renewed. Called from the API client's interceptor
  /// after it clears the stored tokens.
  void expire() {
    if (!_signedIn && _expired) return;
    _signedIn = false;
    _expired = true;
    _mustChangePassword = false;
    notifyListeners();
  }

  /// The user chose to leave. Distinct from [expire]: nothing went wrong, so
  /// the login screen shows no notice.
  void signedOutNow() {
    if (!_signedIn && !_expired && !_mustChangePassword) return;
    _signedIn = false;
    _expired = false;
    _mustChangePassword = false;
    notifyListeners();
  }
}
