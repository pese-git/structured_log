import '../../../l10n/l10n.dart';
import '../../../shared/api/api_failure.dart';

/// What to tell someone about a refused request.
///
/// One place, because the same handful of refusals reach every screen in this
/// section and each of them means something specific here: a 403 is almost
/// always "you are not an administrator", and a 409 is almost always a name
/// already taken.
String describeApiFailure(AppLocalizations l10n, ApiFailure failure) =>
    switch (failure) {
      ForbiddenFailure() => l10n.resFailForbidden,
      ConflictFailure() => l10n.resFailConflict,
      InvalidRequestFailure(:final message) => message ?? l10n.resFailInvalid,
      NotFoundFailure() => l10n.resFailNotFound,
      UnauthorizedFailure() => l10n.resFailUnauthorized,
      RateLimitedFailure(:final retryAfter) => l10n.resFailRateLimited(
        retryAfter.inSeconds,
      ),
      NetworkFailure() => l10n.resFailNetwork,
      ServerFailure(:final statusCode) => l10n.resFailServer(statusCode),
    };

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
String formatBytes(AppLocalizations l10n, int bytes) {
  const megabyte = 1024 * 1024;
  if (bytes >= megabyte) return l10n.resBytesMb(formatCount(bytes ~/ megabyte));
  return l10n.resBytesKb(formatCount(bytes ~/ 1024));
}
