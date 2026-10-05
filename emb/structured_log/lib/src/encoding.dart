import 'dart:convert';

/// Encodes [entry] as JSON, turning every value `jsonEncode` refuses into one
/// it accepts instead of failing the whole entry.
///
/// Every built-in output writes through this, so a value nobody thought to
/// convert costs the entry nothing: a `DateTime` becomes ISO-8601 in UTC, an
/// enum its `name`, a `Duration` its microseconds, and anything else its
/// `toString()` — or `'<TypeName>'` when that throws. The conversion happens
/// only here; [entry] itself, and so whatever processors and in-memory sinks
/// see, keeps the original objects.
///
/// An entry that cannot be encoded even so — one that contains itself — is
/// replaced by a stub carrying the fields that say which entry it was
/// (`event`, `level`, `timestamp`, `logger`, `category`, where they are
/// strings) and `encoding_failed` naming the error. Nothing else of it is
/// kept: the rest is exactly what could not be written.
///
/// Pass [indent] to pretty-print.
///
/// ```dart
/// encodeLogEntry({'event': 'e', 'at': DateTime.utc(2026, 10, 2)});
/// // {"event":"e","at":"2026-10-02T00:00:00.000Z"}
/// ```
String encodeLogEntry(Map<String, dynamic> entry, {String? indent}) {
  final encoder = indent == null
      ? const JsonEncoder(toEncodableValue)
      : JsonEncoder.withIndent(indent, toEncodableValue);
  try {
    return encoder.convert(entry);
  } catch (error) {
    return encoder.convert({
      ...identifyingFields(entry),
      'encoding_failed': error.runtimeType.toString(),
    });
  }
}

/// The fields of [entry] that say which entry it was, and nothing else:
/// what a stub keeps when the rest cannot be delivered.
///
/// Only string values are kept — anything else here is already unusual, and
/// a stub has to be writable no matter what the entry held.
Map<String, String> identifyingFields(Map<String, dynamic> entry) => {
      for (final key in const [
        'event',
        'level',
        'timestamp',
        'logger',
        'category',
      ])
        if (entry[key] case final String value) key: value,
    };

/// [value] as JSON, or `'<TypeName>'` when even the conversions of
/// [encodeLogEntry] cannot make it encodable (a list that contains itself).
String encodeValue(Object? value) {
  try {
    return const JsonEncoder(toEncodableValue).convert(value);
  } catch (_) {
    return '<${value.runtimeType}>';
  }
}

/// What [encodeLogEntry] writes in place of a value `jsonEncode` refuses.
Object? toEncodableValue(Object? value) => switch (value) {
      DateTime() => value.toUtc().toIso8601String(),
      Duration() => value.inMicroseconds,
      Enum() => value.name,
      Set() => value.toList(),
      _ => jsonOf(value),
    };

/// What [value]'s `toJson()` returns, as `jsonEncode` would use it, or
/// [describeValue] when it has none or it throws.
///
/// `jsonEncode` calls `toJson()` itself, but only when no `toEncodable` is
/// given — and [encodeLogEntry] gives one, so without this a DTO from
/// `json_serializable` or `freezed` would be written as its `toString()`.
Object? jsonOf(Object? value) {
  try {
    return (value as dynamic).toJson();
  } catch (_) {
    // `NoSuchMethodError` when there is no `toJson()`, anything at all
    // when there is one and it fails.
    return describeValue(value);
  }
}

/// [value]'s `toString()`, or `'<TypeName>'` when that throws.
String describeValue(Object? value) {
  try {
    return value.toString();
  } catch (_) {
    return '<${value.runtimeType}>';
  }
}
