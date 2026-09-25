import 'dart:convert';

import 'logger.dart';

/// A function that transforms (or drops) a log entry before it reaches any
/// sink.
///
/// Every [BoundLogger] call runs the current
/// `StructlogConfiguration.processors` list on the merged entry, in order,
/// each processor receiving the previous one's output. Returning the [entry]
/// unchanged (or a modified copy) passes it on to the next processor and,
/// eventually, to every accepting [LogSink]. Returning `null` drops the
/// entry — no processor after it runs, and no sink is called.
///
/// Processors should be pure functions of their input and not depend on
/// call order relative to other processors, unless that ordering is
/// documented (as it is for the enrich-then-render pattern below).
///
/// ```dart
/// // A custom processor that redacts a sensitive key.
/// Map<String, dynamic>? redactPassword(Map<String, dynamic> entry) {
///   if (entry.containsKey('password')) entry['password'] = '***';
///   return entry;
/// }
///
/// // A custom processor that drops noisy debug entries entirely.
/// Map<String, dynamic>? dropDebugNoise(Map<String, dynamic> entry) {
///   if (entry['level'] == 'debug' && entry['event'] == 'heartbeat') {
///     return null; // dropped — no later processor or sink sees it
///   }
///   return entry;
/// }
///
/// StructlogConfiguration.configure(
///   processors: [dropNullValues, redactPassword, dropDebugNoise],
/// );
/// ```
typedef Processor = Map<String, dynamic>? Function(Map<String, dynamic> entry);

/// A function that delivers a fully-processed log [entry] (at the given
/// [level]) to a concrete destination — stdout, a file, a test-capture
/// variable, anything.
///
/// This is the type every built-in output in this library
/// ([defaultOutput], [fileOutput], [rotatingFileOutput],
/// [coloredConsoleOutput]) and [LogSink.output] share; write your own to
/// integrate with a destination this package doesn't cover directly:
///
/// ```dart
/// // Send every entry to an in-memory list (handy in tests).
/// final captured = <Map<String, dynamic>>[];
/// OutputFunction captureOutput = (entry, level) => captured.add(entry);
///
/// StructlogConfiguration.configure(output: captureOutput);
/// getLogger().info('event');
/// print(captured.single['event']); // 'event'
/// ```
typedef OutputFunction = void Function(
    Map<String, dynamic> entry, LogLevel level);

/// Adds an ISO-8601 `timestamp` to [entry] if it doesn't already have one.
///
/// Not needed in the default pipeline — [BoundLogger.tryLog] already stamps
/// every entry with `timestamp` before running processors — but useful as
/// a building block for custom processor pipelines that construct entries
/// another way.
///
/// ```dart
/// final entry = <String, dynamic>{'event': 'custom'};
/// addTimestamp(entry);
/// print(entry['timestamp']); // e.g. '2026-09-10T12:00:00.000'
/// ```
Map<String, dynamic>? addTimestamp(Map<String, dynamic> entry) {
  if (!entry.containsKey('timestamp')) {
    entry['timestamp'] = DateTime.now().toIso8601String();
  }
  return entry;
}

/// A no-op processor kept for pipelines that want to document, in the
/// `processors:` list itself, that the entry's `level` key is expected to
/// already be present (as it always is — [BoundLogger.tryLog] sets it
/// before any processor runs) rather than to actually add it.
///
/// ```dart
/// StructlogConfiguration.configure(
///   processors: [dropNullValues, addLogLevel], // addLogLevel is a no-op
/// );
/// ```
Map<String, dynamic>? addLogLevel(Map<String, dynamic> entry) {
  return entry;
}

/// Prints [entry] as a single-line JSON string via [print] and returns it
/// unchanged, so it can be chained with other processors or reach a sink
/// afterwards.
///
/// ```dart
/// jsonRenderer({'event': 'startup', 'pid': 123});
/// // stdout: {"event":"startup","pid":123}
/// ```
Map<String, dynamic>? jsonRenderer(Map<String, dynamic> entry) {
  print(jsonEncode(entry));
  return entry;
}

/// Prints [entry] as space-separated `key=value` pairs (logfmt style) via
/// [print] and returns it unchanged. String values are wrapped in double
/// quotes; other values use their `toString()`.
///
/// ```dart
/// logfmtRenderer({'event': 'startup', 'pid': 123});
/// // stdout: event="startup" pid=123
/// ```
Map<String, dynamic>? logfmtRenderer(Map<String, dynamic> entry) {
  final pairs = entry.entries.map((e) {
    final value = e.value is String ? '"${e.value}"' : e.value.toString();
    return '${e.key}=$value';
  }).join(' ');
  print(pairs);
  return entry;
}

/// Removes every key in [entry] whose value is `null`, in place, and
/// returns the same map. This is the default (and only default) processor
/// in `StructlogConfiguration.processors` — it keeps entries with optional,
/// unset context fields (e.g. `context: {'user_id': maybeNull}`) free of
/// noisy `null` keys in the rendered output.
///
/// ```dart
/// final entry = {'event': 'login', 'user_id': 42, 'session': null};
/// dropNullValues(entry);
/// print(entry); // {event: login, user_id: 42}
/// ```
Map<String, dynamic>? dropNullValues(Map<String, dynamic> entry) {
  entry.removeWhere((key, value) => value == null);
  return entry;
}

/// Key names [redactKeys] replaces by default, compared without regard to
/// case.
///
/// Deliberately short and literal. Every name here is one whose value is a
/// credential in every system that uses it, so redacting it cannot destroy
/// information anybody wanted; a name that is *sometimes* a secret belongs
/// in a caller's own set instead, where the caller knows.
///
/// The correlation fields this package produces — `session_id`,
/// `request_id`, `connection_generation`, `tool_call_id`, `message_id`,
/// `operation_id` — are deliberately absent. They exist to be read: a
/// default that gutted them would break the feature next door to this one.
const defaultSensitiveKeys = <String>{
  'password',
  'passwd',
  'pwd',
  'token',
  'access_token',
  'refresh_token',
  'id_token',
  'secret',
  'client_secret',
  'api_key',
  'apikey',
  'authorization',
  'proxy-authorization',
  'cookie',
  'set-cookie',
  'private_key',
};

/// A [Processor] that replaces sensitive values anywhere in the entry —
/// including inside nested maps and lists — with [placeholder].
///
/// A value is replaced when **any** of three independent criteria says so,
/// which is what lets them be combined or used one at a time:
///
/// - its key is in [keys] (compared without regard to case; pass `const {}`
///   to switch this off, and note that passing a set *replaces*
///   [defaultSensitiveKeys] rather than adding to it);
/// - [matchesKey] answers `true` for its key — for families of names a set
///   cannot enumerate, like `(key) => key.endsWith('_token')`;
/// - [matchesValue] answers `true` for its value. Only `String` values are
///   offered to it: guessing at an `int` would cost every entry that
///   carries numbers, and [looksLikeJwtOrBearer] or [looksLikeCardNumber]
///   have nothing to say about one. This is the only criterion that finds a
///   secret under an innocent name.
///
/// ```dart
/// StructlogConfiguration.configure(
///   processors: [
///     redactKeys(
///       keys: {...defaultSensitiveKeys, 'x-internal-signature'},
///       matchesKey: (key) => key.endsWith('_token'),
///       matchesValue: looksLikeJwtOrBearer,
///     ),
///     dropNullValues,
///   ],
/// );
/// ```
///
/// **Place it before any renderer.** [jsonRenderer] and [logfmtRenderer]
/// print as they go, so a redactor after one of them has already lost.
///
/// The entry is rebuilt rather than edited, and only along the path where
/// something was replaced — an entry with nothing to redact comes back as
/// the very same map. That is not only about cost (processors run on every
/// entry, before any sink decides whether it wants it): `BoundLogger` copies
/// its bound context shallowly, so a nested map in the entry is the *same
/// object* the application is still holding. A redactor that assigned in
/// place would take the caller's own token away, and that is the mistake
/// this function exists to stop anyone from writing again.
///
/// The walk assumes the entry is acyclic — as [jsonRenderer] already does,
/// since `jsonEncode` refuses a cycle outright.
Processor redactKeys({
  Set<String> keys = defaultSensitiveKeys,
  bool Function(String key)? matchesKey,
  bool Function(String value)? matchesValue,
  String placeholder = '***',
}) {
  final names = {for (final key in keys) key.toLowerCase()};

  bool matches(String? key, Object? value) {
    if (key != null) {
      if (names.contains(key.toLowerCase())) return true;
      if (matchesKey != null && matchesKey(key)) return true;
    }
    return value is String && matchesValue != null && matchesValue(value);
  }

  return (entry) =>
      _redact(null, entry, matches, placeholder) as Map<String, dynamic>;
}

/// Returns [value] redacted, or [value] itself when nothing in it matched.
///
/// [key] is the name [value] was found under, or `null` when it has no name
/// — the entry itself, or an element of a list.
Object? _redact(
  String? key,
  Object? value,
  bool Function(String?, Object?) matches,
  String placeholder,
) {
  if (matches(key, value)) return placeholder;

  if (value is Map<String, dynamic>) {
    Map<String, dynamic>? copy;
    for (final field in value.entries) {
      final next = _redact(field.key, field.value, matches, placeholder);
      if (identical(next, field.value)) continue;
      (copy ??= Map<String, dynamic>.of(value))[field.key] = next;
    }
    return copy ?? value;
  }

  if (value is Map) {
    Map<Object?, Object?>? copy;
    for (final field in value.entries) {
      final name = field.key is String ? field.key as String : null;
      final next = _redact(name, field.value, matches, placeholder);
      if (identical(next, field.value)) continue;
      (copy ??= Map<Object?, Object?>.of(value))[field.key] = next;
    }
    return copy ?? value;
  }

  if (value is List) {
    List<Object?>? copy;
    for (var i = 0; i < value.length; i++) {
      final next = _redact(null, value[i], matches, placeholder);
      if (identical(next, value[i])) continue;
      // Widened to `List<Object?>` rather than copied at its own type: a
      // placeholder does not fit a `List<int>`. Only a list holding strings
      // can match at all, so nothing else is ever widened.
      (copy ??= List<Object?>.of(value))[i] = next;
    }
    return copy ?? value;
  }

  return value;
}

/// A JWT, or the value of an `Authorization: Bearer …` header, written
/// where nobody named it a secret — a message, a URL, a `note` field.
///
/// Pass it as [redactKeys]'s `matchesValue`. Both shapes are anchored on
/// purpose: `bearer` has to be the whole first word (so "bearers of bad
/// news" is prose, not a credential), and a JWT has to start with the `eyJ`
/// that base64 gives every `{"` — without that, a dotted version string
/// like `1.2.3` would read as a token.
bool looksLikeJwtOrBearer(String value) =>
    _bearer.hasMatch(value) || _jwt.hasMatch(value);

final _bearer = RegExp(r'^bearer\s+\S+$', caseSensitive: false);
final _jwt = RegExp(r'^eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$');

/// A payment card number, by length and by the Luhn check digit.
///
/// Deliberately **not** in the defaults, and offered separately so that
/// including it is a decision. Length alone matches order ids, phone
/// numbers and internal identifiers; Luhn is what keeps most of them out,
/// and it still cannot know that a 16-digit number nobody spends is not a
/// card. Redacting one of those destroys data the operator wanted, which is
/// the opposite failure from the one this file is about — so the caller
/// chooses.
bool looksLikeCardNumber(String value) {
  final digits = value.replaceAll(RegExp(r'[ -]'), '');
  if (digits.length < 13 || digits.length > 19) return false;

  var sum = 0;
  var double = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    final code = digits.codeUnitAt(i) - 0x30;
    if (code < 0 || code > 9) return false;
    var digit = code;
    if (double) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
    double = !double;
  }
  return sum % 10 == 0;
}
