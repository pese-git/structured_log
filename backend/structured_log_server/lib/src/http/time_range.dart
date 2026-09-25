import '../errors.dart';

/// The `from`/`to` bounds of a query, already checked.
typedef TimeRange = ({DateTime? from, DateTime? to});

/// Reads `from` and `to` from [params], refusing what cannot be read.
///
/// The same reasoning as `parsePageRequest`, and it has to be written down
/// because the failure was silent. `DateTime.tryParse` answers `null` for
/// "absent" and for "not a date" alike, and both routes asked it directly —
/// so a misspelled bound dropped the filter and the endpoint answered `200`
/// over the whole range it could see. That is not a smaller answer than the
/// caller asked for, it is a *larger* one wearing the caller's heading: the
/// audit log already refuses an unknown `action` on exactly this ground
/// ("no records" and "you misspelled it" look identical to a reader), and a
/// date is no different.
///
/// Call it after the role check and before touching storage, so a caller
/// without access gets `403` whatever their parameters look like.
TimeRange parseTimeRange(Map<String, String> params) =>
    (from: _timestamp(params, 'from'), to: _timestamp(params, 'to'));

/// The calendar fields of an ISO 8601 timestamp, as far as they decide
/// whether it names a moment that exists. The offset and any fraction are
/// left to `DateTime.parse`, which does refuse those when they are malformed.
final _calendarFields = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?',
);

/// A bound is optional; a bound that is present is a timestamp or an error.
///
/// What counts as a timestamp is whatever `DateTime.parse` accepts — ISO
/// 8601, with or without an offset. A value without one is read in the
/// server's local zone, which is the behaviour this endpoint already had and
/// is not changed here.
///
/// Refusing only what `DateTime.tryParse` answers `null` to would leave half
/// the hole open, because it does not reject an out-of-range component — it
/// *rolls it over*. `2026-13-40` comes back as 2027-02-09 and `2026-02-30`
/// as 2026-03-02, so the query runs over a range the caller never wrote
/// while the page still reads as the one they asked for. That is the same
/// failure as a dropped bound wearing better clothes, so the fields are
/// checked to survive the trip.
DateTime? _timestamp(Map<String, String> params, String field) {
  final raw = params[field];
  if (raw == null) return null;

  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw ApiError.invalidRequest(
      '$field must be an ISO 8601 timestamp.',
      details: {'field': field, 'reason': 'invalid'},
    );
  }

  final fields = _calendarFields.firstMatch(raw);
  if (fields != null && _rollsOver(fields)) {
    throw ApiError.invalidRequest(
      '$field names a date that does not exist.',
      details: {'field': field, 'reason': 'invalid'},
    );
  }

  return parsed;
}

/// Whether rebuilding [fields] moves any of them — which is how an
/// out-of-range component shows itself.
///
/// The probe is built in UTC deliberately: it is arithmetic over the
/// calendar, not the instant the caller meant, and a local probe would also
/// move an hour that a daylight-saving jump skips — refusing a bound for
/// where the server happens to stand.
bool _rollsOver(RegExpMatch fields) {
  final year = int.parse(fields[1]!);
  final month = int.parse(fields[2]!);
  final day = int.parse(fields[3]!);
  final hour = int.parse(fields[4] ?? '0');
  final minute = int.parse(fields[5] ?? '0');
  final second = int.parse(fields[6] ?? '0');

  final probe = DateTime.utc(year, month, day, hour, minute, second);
  return probe.year != year ||
      probe.month != month ||
      probe.day != day ||
      probe.hour != hour ||
      probe.minute != minute ||
      probe.second != second;
}
