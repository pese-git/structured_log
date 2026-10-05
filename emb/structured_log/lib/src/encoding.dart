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
/// An object with a `toJson()` is written as what it returns; one whose
/// `toJson()` returns the object itself, or leads back to it, is written as
/// its `toString()` instead.
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
    // A `toJson()` that returns its own object, or one that leads back to
    // it, fails the whole entry, and `JsonEncoder` cannot say which value
    // did it. Checking every `toJson()` on its own finds it, at a cost paid
    // only here, on the failure path.
    try {
      return encoder.convert(_checkToJson(entry, Set.identity()));
    } catch (_) {
      return encoder.convert({
        ...identifyingFields(entry),
        'encoding_failed': error.runtimeType.toString(),
      });
    }
  }
}

/// [value] with every object in it replaced by what its `toJson()` returns,
/// walked the same way, or by its [describeValue] when that cannot be
/// written: it leads back to an object on the path down to it, or it has
/// no `toJson()` at all.
///
/// A map or list that contains itself still throws: that is the entry's own
/// cycle, not a value's, and it costs the entry as before. [ancestors] holds
/// what is on the path down to [value], compared by identity.
Object? _checkToJson(Object? value, Set<Object> ancestors) {
  if (value == null ||
      value is String ||
      value is num ||
      value is bool ||
      value is DateTime ||
      value is Duration ||
      value is Enum) {
    return value;
  }
  if (!ancestors.add(value)) throw _CycleError();
  try {
    if (value is Map) {
      // A map with keys other than strings is written as its `toString()`
      // by the encoder; there is nothing here to walk.
      if (value.keys.any((key) => key is! String)) return value;
      return {
        for (final field in value.entries)
          field.key: _checkToJson(field.value, ancestors),
      };
    }
    if (value is List || value is Set) {
      return [
        for (final element in value as Iterable)
          _checkToJson(element, ancestors),
      ];
    }
    try {
      return _checkToJson((value as dynamic).toJson(), ancestors);
    } catch (_) {
      return describeValue(value);
    }
  } finally {
    ancestors.remove(value);
  }
}

/// What [_checkToJson] throws on a cycle; the error [encodeLogEntry] names in
/// a stub is the encoder's own.
class _CycleError extends Error {}

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
