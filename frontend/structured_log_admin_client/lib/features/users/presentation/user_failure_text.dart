import '../../../shared/api/api_failure.dart';

/// What to tell someone about a refused request on the users screen.
///
/// A separate function from `resource_failure_text.dart`'s
/// `describeApiFailure`, not a shared one: there a 409 is almost always a
/// name already taken, but here a 409 might just as well be
/// `sole_group_owner` or `deleted_account` — codes that need their own words,
/// not the resources screen's generic "name taken".
String describeUserFailure(ApiFailure failure) => switch (failure) {
  ForbiddenFailure(:final code) when code == 'cannot_delete_primary_admin' =>
    'Основного администратора удалить нельзя — эта учётная запись защищена '
        'навсегда, независимо от того, сколько других администраторов есть '
        'в системе.',
  ForbiddenFailure() =>
    'Недостаточно прав. Это действие доступно только администратору.',
  ConflictFailure(:final code) when code == 'username_taken' =>
    'Такое имя пользователя уже занято. Выберите другое.',
  ConflictFailure(:final code) when code == 'deleted_account' =>
    'Учётная запись удалена — разблокировать её нельзя. Удаление необратимо.',
  ConflictFailure(:final code) when code == 'sole_group_owner' =>
    'Пользователь — единственный владелец одной или нескольких групп. '
        'Сначала назначьте другого владельца.',
  ConflictFailure() => 'Конфликт при сохранении. Попробуйте ещё раз.',
  InvalidRequestFailure(:final code) when code == 'self_deletion_requires_me' =>
    'Нельзя удалить самого себя этим способом.',
  InvalidRequestFailure(:final message) =>
    message ?? 'Проверьте заполненные поля.',
  NotFoundFailure() =>
    'Пользователь не найден — возможно, уже удалён кем-то другим.',
  UnauthorizedFailure() => 'Сессия истекла. Войдите заново.',
  RateLimitedFailure(:final retryAfter) =>
    'Слишком много попыток. Попробуйте через ${retryAfter.inSeconds} с.',
  NetworkFailure() => 'Сервер недоступен. Проверьте подключение.',
  ServerFailure(:final statusCode) =>
    'Сервер ответил ошибкой ($statusCode). Попробуйте ещё раз.',
};

/// The groups a `409 sole_group_owner` names as blocked by the deletion —
/// `{"blocking_groups": [{"id": ..., "name": ..., "created_at": ...}, ...]}`
/// (`docs/api/errors.md`), read directly out of `ConflictFailure.details`
/// rather than through a DTO: this is the one place this client ever reads
/// this shape, and a `GroupDto.fromJson` round-trip would buy nothing a
/// direct map read does not already have.
List<String> blockingGroupNames(ApiFailure failure) {
  if (failure is! ConflictFailure) return const [];
  final groups = failure.details?['blocking_groups'];
  if (groups is! List) return const [];
  return [
    for (final group in groups)
      if (group is Map && group['name'] is String) group['name'] as String,
  ];
}
