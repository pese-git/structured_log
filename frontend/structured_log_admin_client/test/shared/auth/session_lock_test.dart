import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/shared/auth/session_lock.dart';

void main() {
  test('the stub runs the body and hands back its value', () async {
    // Everything but a browser gets this one, including every test above.
    // It must not change the behaviour it wraps: there are no other tabs to
    // take turns with off the web.
    expect(await const NoSessionLock().synchronized(() async => 7), 7);
  });

  test('the stub does not swallow a failure', () async {
    // A renewal that throws has to surface: the interceptor reads a failed
    // renewal as the end of the session.
    expect(
      const NoSessionLock().synchronized(() async => throw StateError('no')),
      throwsStateError,
    );
  });

  test('off the web, the created lock is the stub', () {
    // `flutter test` runs on the VM, so this is what every test above got.
    // On the web the conditional import swaps in the Web Locks one, which
    // only a real browser can exercise (`integration_test/`).
    expect(createSessionLock(), isA<NoSessionLock>());
  });
}
