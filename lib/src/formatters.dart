import 'dart:convert';
import 'dart:io';

import 'logger.dart';
import 'processors.dart';

/// Default output: print JSON to stdout
void defaultOutput(Map<String, dynamic> entry, LogLevel level) {
  final encoder = JsonEncoder.withIndent('  ');
  print(encoder.convert(entry));
}

/// File output: append JSON lines to a file
OutputFunction fileOutput(String filePath) {
  final file = File(filePath);
  final dir = file.parent;
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return (Map<String, dynamic> entry, LogLevel level) {
    file.writeAsStringSync(
      '${jsonEncode(entry)}\n',
      mode: FileMode.append,
    );
  };
}

/// File output with rotation: creates new file when size exceeds maxSizeBytes
OutputFunction rotatingFileOutput(
  String filePath, {
  int maxSizeBytes = 10 * 1024 * 1024, // 10MB default
  int maxBackups = 5,
}) {
  final file = File(filePath);
  final dir = file.parent;
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  void rotate() {
    // Delete oldest backup
    final oldest = File('$filePath.${maxBackups - 1}');
    if (oldest.existsSync()) {
      oldest.deleteSync();
    }
    // Shift backups
    for (var i = maxBackups - 2; i >= 0; i--) {
      final src = File('$filePath.$i');
      final dst = File('$filePath.${i + 1}');
      if (src.existsSync()) {
        src.renameSync(dst.path);
      }
    }
    // Move current to .0
    if (file.existsSync()) {
      file.renameSync('$filePath.0');
    }
  }

  return (Map<String, dynamic> entry, LogLevel level) {
    if (file.existsSync() && file.lengthSync() >= maxSizeBytes) {
      rotate();
    }
    file.writeAsStringSync(
      '${jsonEncode(entry)}\n',
      mode: FileMode.append,
    );
  };
}

/// Console colored output
void coloredConsoleOutput(Map<String, dynamic> entry, LogLevel level) {
  final event = entry['event'] ?? '';
  final context = Map<String, dynamic>.from(entry)..remove('event')..remove('level')..remove('timestamp');
  
  String colorCode;
  switch (level) {
    case LogLevel.debug:
      colorCode = '\x1B[36m'; // cyan
      break;
    case LogLevel.info:
      colorCode = '\x1B[32m'; // green
      break;
    case LogLevel.warning:
      colorCode = '\x1B[33m'; // yellow
      break;
    case LogLevel.error:
      colorCode = '\x1B[31m'; // red
      break;
    case LogLevel.critical:
      colorCode = '\x1B[35m'; // magenta
      break;
  }
  
  const reset = '\x1B[0m';
  final timestamp = entry['timestamp'] ?? '';
  final contextStr = context.isNotEmpty ? ' ${jsonEncode(context)}' : '';
  
  print('$colorCode[$timestamp] ${level.name.toUpperCase()}: $event$reset$contextStr');
}
