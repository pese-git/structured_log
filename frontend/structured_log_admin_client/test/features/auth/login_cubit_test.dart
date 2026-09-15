import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:structured_log_admin_client/features/auth/application/sign_in.dart';
import 'package:structured_log_admin_client/features/auth/domain/auth_failure.dart';
import 'package:structured_log_admin_client/features/auth/domain/auth_repository.dart';
import 'package:structured_log_admin_client/features/auth/presentation/login_cubit.dart';

/// Answers whatever the test tells it to, and records what it was asked.
class _FakeRepository implements AuthRepository {
  Either<AuthFailure, Unit> answer = right(unit);
  final calls = <({String username, String password})>[];

  @override
  Future<Either<AuthFailure, Unit>> signIn({
    required String username,
    required String password,
  }) async {
    calls.add((username: username, password: password));
    return answer;
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> hasSession() async => false;
}

void main() {
  late _FakeRepository repository;
  late LoginCubit cubit;

  setUp(() {
    repository = _FakeRepository();
    cubit = LoginCubit(SignIn(repository));
  });

  tearDown(() => cubit.close());

  test('a successful sign-in reports it and stops submitting', () async {
    await cubit.submit(username: 'root', password: 'correct');

    expect(cubit.state.signedIn, isTrue);
    expect(cubit.state.submitting, isFalse);
    expect(cubit.state.failure, isNull);
  });

  test('the username is trimmed, the password is not', () async {
    await cubit.submit(username: '  root \n', password: '  spaces  ');

    expect(repository.calls.single.username, 'root');
    expect(
      repository.calls.single.password,
      '  spaces  ',
      reason: 'whitespace can be part of a password',
    );
  });

  test('a refusal is shown and nothing is reported as signed in', () async {
    repository.answer = left(const AuthFailure.invalidCredentials());

    await cubit.submit(username: 'root', password: 'wrong');

    expect(cubit.state.failure, const AuthFailure.invalidCredentials());
    expect(cubit.state.signedIn, isFalse);
  });

  test('editing a field dismisses the message', () async {
    repository.answer = left(const AuthFailure.invalidCredentials());
    await cubit.submit(username: 'root', password: 'wrong');

    cubit.clearFailure();

    expect(cubit.state.failure, isNull);
  });

  test('a rate limit blocks submission and counts down', () async {
    repository.answer = left(
      const AuthFailure.rateLimited(Duration(seconds: 2)),
    );

    await cubit.submit(username: 'root', password: 'ok');

    expect(cubit.state.retryAfter, const Duration(seconds: 2));
    expect(cubit.state.canSubmit, isFalse);

    // Typing does not appease a limiter.
    cubit.clearFailure();
    expect(cubit.state.failure, isA<RateLimitedAuthFailure>());

    // Sending again while it counts is simply ignored — no second request.
    repository.calls.clear();
    await cubit.submit(username: 'root', password: 'ok');
    expect(repository.calls, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 2400));
    expect(cubit.state.retryAfter, Duration.zero);
    expect(cubit.state.canSubmit, isTrue);
    expect(
      cubit.state.failure,
      isNull,
      reason: 'a "please wait" that outlives the wait is wrong',
    );
  });

  test(
    'a previous failure is cleared while the next attempt is in flight',
    () async {
      repository.answer = left(const AuthFailure.invalidCredentials());
      await cubit.submit(username: 'root', password: 'wrong');

      final seen = <bool>[];
      final subscription = cubit.stream.listen((state) {
        if (state.submitting) seen.add(state.failure != null);
      });
      addTearDown(subscription.cancel);

      repository.answer = right(unit);
      await cubit.submit(username: 'root', password: 'correct');

      expect(seen, [
        false,
      ], reason: 'an old error beside a spinner reads as a fresh rejection');
    },
  );
}
