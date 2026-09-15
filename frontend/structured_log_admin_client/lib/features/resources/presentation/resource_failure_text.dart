import '../../../shared/api/api_failure.dart';

/// What to tell someone about a refused request.
///
/// One place, because the same handful of refusals reach every screen in this
/// section and each of them means something specific here: a 403 is almost
/// always "you are not an administrator", and a 409 is almost always a name
/// already taken.
String describeApiFailure(ApiFailure failure) => switch (failure) {
  ForbiddenFailure() =>
    'Недостаточно прав. Это действие доступно администратору, а для проектов '
        'внутри группы — ещё и её владельцу.',
  ConflictFailure() => 'Такое имя уже занято. Выберите другое.',
  InvalidRequestFailure(:final message) =>
    message ?? 'Проверьте заполненные поля.',
  NotFoundFailure() => 'Объект не найден — возможно, он уже удалён.',
  UnauthorizedFailure() => 'Сессия истекла. Войдите заново.',
  RateLimitedFailure(:final retryAfter) =>
    'Слишком много попыток. Попробуйте через ${retryAfter.inSeconds} с.',
  NetworkFailure() => 'Сервер недоступен. Проверьте подключение.',
  ServerFailure(:final statusCode) =>
    'Сервер ответил ошибкой ($statusCode). Попробуйте ещё раз.',
};

/// `14 фев 2025`, as the artboards write dates.
String formatDate(DateTime utc) {
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
  final local = utc.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

/// `1 000 000`, grouped as the artboards group numbers.
///
/// The separator is a non-breaking space (`\u00A0`) on purpose: a plain one
/// lets a number wrap across lines, and "1 000" split over two lines reads as
/// two numbers.
String formatCount(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('\u00A0');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Bytes as the quota dialog states them — megabytes, because that is the
/// unit the field is labelled in. The space before the unit is non-breaking
/// for the same reason as the digit grouping: "5" and "МБ" are one value.
String formatBytes(int bytes) {
  const megabyte = 1024 * 1024;
  if (bytes >= megabyte) return '${formatCount(bytes ~/ megabyte)}\u00A0МБ';
  return '${formatCount(bytes ~/ 1024)}\u00A0КБ';
}
