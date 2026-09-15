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

  SessionController({bool signedIn = false}) : _signedIn = signedIn;

  bool get signedIn => _signedIn;

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

  /// A session could not be renewed. Called from the API client's interceptor
  /// after it clears the stored tokens.
  void expire() {
    if (!_signedIn && _expired) return;
    _signedIn = false;
    _expired = true;
    notifyListeners();
  }

  /// The user chose to leave. Distinct from [expire]: nothing went wrong, so
  /// the login screen shows no notice.
  void signedOutNow() {
    if (!_signedIn && !_expired) return;
    _signedIn = false;
    _expired = false;
    notifyListeners();
  }
}
