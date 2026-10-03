/// The file outputs of `structured_log`, which need `dart:io`.
///
/// Kept apart from `package:structured_log/structured_log.dart` so that the
/// main library compiles — and is marked as supported — on every platform,
/// the web included. Import this alongside it where entries go to a file:
///
/// ```dart
/// import 'package:structured_log/io.dart';
/// import 'package:structured_log/structured_log.dart';
///
/// StructlogConfiguration.configure(output: fileOutput('logs/app.log'));
/// ```
library;

export 'src/async_file_output.dart';
export 'src/file_output.dart';
