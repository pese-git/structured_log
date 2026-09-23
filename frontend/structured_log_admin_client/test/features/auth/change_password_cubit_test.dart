import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:structured_log_admin_client/features/auth/application/change_password.dart';
import 'package:structured_log_admin_client/features/auth/domain/auth_failure.dart';
import 'package:structured_log_admin_client/features/auth/domain/auth_repository.dart';
import 'package:structured_log_admin_client/features/auth/presentation/change_password_cubit.dart';

class _FakeRepository implements AuthRepository {
  Either<AuthFailure, Unit> answer = right(unit);
  final calls = <({String current, String next, bool keepOthers})>[];
  String? username = 'admin';

  @override
  Future<Either<AuthFailure, Unit>> changePassword({
    required String currentPassword,
    required String newPassword,
    required bool keepOtherSessions,
  }) async {
    calls.add((
      current: currentPassword,
      next: newPassword,
      keepOthers: keepOtherSessions,
    ));
    return answer;
  }

  @override
  Future<String?> currentUsername() async => username;

  @override
  Future<bool> isGlobalAdmin() async => false;

  @override
  Future<Either<AuthFailure, Unit>> signIn({
    required String username,
    required String password,
  }) async => right(unit);

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> hasSession() async => true;
}

void main() {
  late _FakeRepository repository;
  late ChangePasswordCubit cubit;

  setUp(() {
    repository = _FakeRepository();
    cubit = ChangePasswordCubit(
      changePassword: ChangePassword(repository),
      currentUsername: CurrentUsername(repository),
    );
  });

  tearDown(() => cubit.close());

  test('a successful change is reported once', () async {
    await cubit.submit(
      currentPassword: 'temporary',
      newPassword: 'chosen',
      repeatedPassword: 'chosen',
      keepOtherSessions: false,
    );

    expect(cubit.state.changed, isTrue);
    expect(cubit.state.failure, isNull);
    expect(repository.calls.single, (
      current: 'temporary',
      next: 'chosen',
      keepOthers: false,
    ));
  });

  test('a mismatch is caught here, not at the server', () async {
    await cubit.submit(
      currentPassword: 'temporary',
      newPassword: 'chosen',
      repeatedPassword: 'chsoen',
      keepOtherSessions: false,
    );

    expect(cubit.state.mismatch, isTrue);
    expect(cubit.state.changed, isFalse);
    expect(
      repository.calls,
      isEmpty,
      reason:
          'the server cannot tell the two copies apart, and a round trip '
          'to learn what the form knows would spend a rate-limited attempt',
    );
  });

  test('a wrong current password leaves the form where it was', () async {
    repository.answer = left(const AuthFailure.invalidCredentials());

    await cubit.submit(
      currentPassword: 'wrong',
      newPassword: 'chosen',
      repeatedPassword: 'chosen',
      keepOtherSessions: false,
    );

    expect(cubit.state.changed, isFalse);
    expect(cubit.state.failure, isA<InvalidCredentialsFailure>());
  });

  test(
    'a second submission is ignored once the password has changed',
    () async {
      await cubit.submit(
        currentPassword: 'temporary',
        newPassword: 'chosen',
        repeatedPassword: 'chosen',
        keepOtherSessions: false,
      );
      await cubit.submit(
        currentPassword: 'chosen',
        newPassword: 'again',
        repeatedPassword: 'again',
        keepOtherSessions: false,
      );

      expect(repository.calls, hasLength(1));
    },
  );

  test('the username comes from the session, for the screen to show', () async {
    await cubit.loadUsername();

    expect(cubit.state.username, 'admin');
  });

  group('keeping the other sessions', () {
    Future<void> submit({required bool keepOtherSessions}) => cubit.submit(
      currentPassword: 'old-password',
      newPassword: 'a-new-password-1',
      repeatedPassword: 'a-new-password-1',
      keepOtherSessions: keepOtherSessions,
    );

    test('the reader\'s choice reaches the repository', () async {
      await submit(keepOtherSessions: true);
      expect(repository.calls.single.keepOthers, isTrue);
    });

    test('and so does the default, which is to end them', () async {
      await submit(keepOtherSessions: false);
      expect(repository.calls.single.keepOthers, isFalse);
    });

    test('a mismatch is caught before the flag can travel', () async {
      await cubit.submit(
        currentPassword: 'old-password',
        newPassword: 'a-new-password-1',
        repeatedPassword: 'a-different-one',
        keepOtherSessions: false,
      );

      expect(cubit.state.mismatch, isTrue);
      expect(repository.calls, isEmpty);
    });
  });
}
