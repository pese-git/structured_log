/// How an entry's `timestamp` is written. Either way it names one instant
/// unambiguously — wherever it is read, by whoever reads it.
///
/// ```dart
/// StructlogConfiguration.configure(timestampMode: TimestampMode.utc);
/// // "timestamp": "2026-10-02T09:30:15.250Z"
///
/// StructlogConfiguration.configure(
///   timestampMode: TimestampMode.localWithOffset,
/// );
/// // "timestamp": "2026-10-02T12:30:15.250+03:00"
/// ```
enum TimestampMode {
  /// ISO-8601 in UTC, ending in `Z`. The default: entries from devices in
  /// different time zones sort and compare as written.
  utc,

  /// ISO-8601 in the device's local time, ending in its offset (`+03:00`).
  /// The wall clock a person on that device saw, still the same instant
  /// everywhere else.
  localWithOffset,
}

/// [time] written as [mode] says.
///
/// `DateTime.toIso8601String()` on a local time writes no offset at all, and
/// whoever parses it reads it as *their own* local time — a server in
/// another zone files the entry hours away from when it happened. That
/// format is therefore not one of the modes.
String formatTimestamp(DateTime time, TimestampMode mode) => switch (mode) {
      TimestampMode.utc => time.toUtc().toIso8601String(),
      TimestampMode.localWithOffset => _local(time.toLocal()),
    };

String _local(DateTime local) =>
    '${local.toIso8601String()}${formatOffset(local.timeZoneOffset)}';

/// [offset] as ISO-8601 writes it: sign, two-digit hours, colon, minutes.
String formatOffset(Duration offset) {
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  return '$sign${twoDigits(minutes ~/ 60)}:${twoDigits(minutes % 60)}';
}
