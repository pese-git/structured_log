import 'dart:convert';

import 'logger.dart';

/// Type definition for a processor function
typedef Processor = Map<String, dynamic>? Function(Map<String, dynamic> entry);

/// Type definition for output function
typedef OutputFunction = void Function(
    Map<String, dynamic> entry, LogLevel level);

/// Add timestamp to log entry
Map<String, dynamic>? addTimestamp(Map<String, dynamic> entry) {
  if (!entry.containsKey('timestamp')) {
    entry['timestamp'] = DateTime.now().toIso8601String();
  }
  return entry;
}

/// Add log level to entry
Map<String, dynamic>? addLogLevel(Map<String, dynamic> entry) {
  return entry;
}

/// Format entry as JSON string and print
Map<String, dynamic>? jsonRenderer(Map<String, dynamic> entry) {
  print(jsonEncode(entry));
  return entry;
}

/// Format entry as key=value pairs (logfmt style)
Map<String, dynamic>? logfmtRenderer(Map<String, dynamic> entry) {
  final pairs = entry.entries.map((e) {
    final value = e.value is String ? '"${e.value}"' : e.value.toString();
    return '${e.key}=$value';
  }).join(' ');
  print(pairs);
  return entry;
}

/// Filter out entries with null values
Map<String, dynamic>? dropNullValues(Map<String, dynamic> entry) {
  entry.removeWhere((key, value) => value == null);
  return entry;
}
