import '../../../shared/api/api_failure.dart';

/// What to tell an administrator about a refused audit query.
///
/// Its own copy rather than `describeApiFailure` from the resources section,
/// because the same status codes mean different things here: a 403 on this
/// screen is never "you are not the owner of that group" — the endpoint is
/// global-admin only, full stop — and a 400 is almost always an `action` the
/// server does not know, which is a bug in this client rather than something
/// the reader typed.
String describeAuditFailure(ApiFailure failure) => switch (failure) {
  ForbiddenFailure() =>
    'Журнал аудита доступен только администратору. Он охватывает все группы и '
        'проекты, поэтому частичного доступа к нему нет.',
  InvalidRequestFailure(:final message) =>
    message ?? 'Сервер не принял запрос с такими фильтрами.',
  NotFoundFailure() => 'Эндпоинт аудита недоступен на этом сервере.',
  UnauthorizedFailure() => 'Сессия истекла. Войдите заново.',
  ConflictFailure() => 'Сервер ответил конфликтом. Повторите запрос.',
  RateLimitedFailure(:final retryAfter) =>
    'Слишком много запросов. Попробуйте через ${retryAfter.inSeconds} с.',
  NetworkFailure() => 'Сервер недоступен. Проверьте подключение.',
  ServerFailure(:final statusCode) =>
    'Сервер ответил ошибкой ($statusCode). Попробуйте ещё раз.',
};

/// A retention period as the screen states it, telling "kept forever" from a
/// configured limit — which is the distinction the empty state turns on
/// (`specs/admin-client-audit-log`).
String describeRetention(int? days) =>
    days == null ? 'без ограничения срока' : _plural(days);

String _plural(int days) {
  final tail = days % 100;
  if (tail >= 11 && tail <= 14) return '$days дней';
  return switch (days % 10) {
    1 => '$days день',
    2 || 3 || 4 => '$days дня',
    _ => '$days дней',
  };
}

/// `13.09.2026 09:41`, as the artboard writes a timestamp in the table — local
/// time, because the reader is looking for something that happened to them.
String formatAuditTime(DateTime utc) {
  final local = utc.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// `01 сен`, as the date-range boxes write a bound.
String formatAuditDate(DateTime value) {
  const months = [
    'янв',
    'фев',
    'мар',
    'апр',
    'мая',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек',
  ];
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')} ${months[local.month - 1]}';
}
