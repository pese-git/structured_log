import '../../l10n/app_localizations.dart';

/// What a server refusal of a *chosen* password says, in words.
///
/// The server checks a password when it is set — created, reset, changed — and
/// answers `400 invalid_request` with `details: {field, reason, ...}`, where
/// `reason` is `too_short` (with `min_length`) or `too_long` (with
/// `max_bytes`). Its `message` is English, so it is never shown; this is what
/// is shown instead, on every screen that sets a password.
///
/// The limits are read out of the response rather than repeated here, so a
/// server that changes them is not contradicted by a stale copy. The constants
/// are only for a response that leaves the number out.
///
/// Returns `null` for anything that is not a password refusal, so the caller
/// falls through to its ordinary handling.
String? describePasswordRejection(
  AppLocalizations l10n,
  Map<String, dynamic>? details,
) {
  switch (details?['reason']) {
    case 'too_short':
      return l10n.commonPasswordTooShort(
        details?['min_length'] as int? ?? _defaultMinLength,
      );
    case 'too_long':
      return l10n.commonPasswordTooLong(
        details?['max_bytes'] as int? ?? _defaultMaxBytes,
      );
  }
  return null;
}

/// Whether [details] describe a refused password. For the layer that maps a
/// response to a failure and has no `AppLocalizations` in reach.
bool isPasswordRejection(Map<String, dynamic>? details) =>
    details?['reason'] == 'too_short' || details?['reason'] == 'too_long';

const _defaultMinLength = 8;
const _defaultMaxBytes = 72;
