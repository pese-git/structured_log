import '../../../l10n/l10n.dart';
import '../../../shared/api/api_failure.dart';

/// What to tell an administrator about a refused audit query.
///
/// Its own copy rather than `describeApiFailure` from the resources section,
/// because the same status codes mean different things here: a 403 on this
/// screen is never "you are not the owner of that group" — the endpoint is
/// global-admin only, full stop — and a 400 is almost always an `action` the
/// server does not know, which is a bug in this client rather than something
/// the reader typed.
String describeAuditFailure(AppLocalizations l10n, ApiFailure failure) =>
    switch (failure) {
      ForbiddenFailure() => l10n.auditFailureForbidden,
      InvalidRequestFailure(:final message) =>
        message ?? l10n.auditFailureInvalidRequest,
      NotFoundFailure() => l10n.auditFailureNotFound,
      UnauthorizedFailure() => l10n.auditFailureUnauthorized,
      ConflictFailure() => l10n.auditFailureConflict,
      RateLimitedFailure(:final retryAfter) => l10n.auditFailureRateLimited(
        retryAfter.inSeconds,
      ),
      NetworkFailure() => l10n.auditFailureNetwork,
      ServerFailure(:final statusCode) => l10n.auditFailureServer(statusCode),
    };

/// A retention period as the screen states it, telling "kept forever" from a
/// configured limit — which is the distinction the empty state turns on
/// (`specs/admin-client-audit-log`).
String describeRetention(AppLocalizations l10n, int? days) =>
    days == null ? l10n.auditRetentionForever : l10n.auditRetentionDays(days);

/// `13.09.2026 09:41`, as the artboard writes a timestamp in the table — local
/// time, because the reader is looking for something that happened to them.
String formatAuditTime(DateTime utc) {
  final local = utc.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
