import 'dart:io';

/// Where `dart:io` exists, internal failures go to `stderr`.
void platformReport(String message) => stderr.writeln(message);
