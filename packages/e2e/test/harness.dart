import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A `structured_log_server` running for the duration of a test file.
///
/// A real OS process against a real socket, not a handler built in-isolate.
/// Everything this package exists to check lives in the gap between the two:
/// whether the wire shapes agree, whether a body that streams actually
/// streams, whether the server resolves its own configuration. A handler
/// assembled in the test would answer all of those by construction.
class ServerProcess {
  final Process _process;
  final Directory _directory;

  /// Where the API is, as a client would spell it.
  final String baseUrl;

  /// The password the server generated for its first administrator, printed
  /// once at `warning` level and available nowhere else
  /// (`log-server-auth`, design.md decision 42).
  final String bootstrapPassword;

  ServerProcess._(
    this._process,
    this._directory, {
    required this.baseUrl,
    required this.bootstrapPassword,
  });

  /// Starts a server on an empty database and waits until it answers.
  static Future<ServerProcess> start() async {
    final directory = Directory.systemTemp.createTempSync('structured_log_e2e');
    final port = await _freePort();

    final serverDirectory = _locateServer();
    final process = await Process.start(
      'dart',
      [
        'run',
        'bin/server.dart',
        'serve',
        '--db-path=${directory.path}/e2e.sqlite',
        '--http-port=$port',
        // The auth endpoints share one bucket per client address, and every
        // test here comes from the same one: sign-ins, token renewals and
        // password changes all spend from it. At the default of 10 the suite
        // was already three deep before its second test, and a file that adds
        // a couple of sign-ins starts failing tests that have nothing to do
        // with throttling. Raised rather than worked around, because what this
        // suite is for is the seams between the packages — the limiter itself
        // has its own tests, against a server configured for it
        // (`test/http/rate_limit_middleware_test.dart`).
        '--rate-limit-bucket-capacity=200',
      ],
      workingDirectory: serverDirectory,
      environment: {
        // Never a flag: an argument is visible in the process list to anyone
        // on the host (design.md decision 47).
        'STRUCTURED_LOG_JWT_SECRET': 'end-to-end-test-secret',
        // JSON, so the bootstrap password can be read out of a field rather
        // than scraped out of a sentence.
        'STRUCTURED_LOG_LOG_FORMAT': 'json',
      },
    );

    final lines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    // Kept so a failure can say what the server was doing.
    final transcript = <String>[];
    lines.listen(transcript.add);
    final stderrLines = <String>[];
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(stderrLines.add);

    String? password;
    var ready = false;
    try {
      await for (final line in lines.timeout(const Duration(seconds: 60))) {
        password ??= _bootstrapPasswordOf(line);
        if (line.contains('Listening on')) {
          ready = true;
          break;
        }
      }
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      throw StateError(
        'the server did not start in time\n'
        '${transcript.join('\n')}\n${stderrLines.join('\n')}',
      );
    }

    if (!ready || password == null) {
      process.kill(ProcessSignal.sigkill);
      throw StateError(
        'the server started without announcing a bootstrap password\n'
        '${transcript.join('\n')}\n${stderrLines.join('\n')}',
      );
    }

    return ServerProcess._(
      process,
      directory,
      baseUrl: 'http://localhost:$port',
      bootstrapPassword: password,
    );
  }

  Future<void> stop() async {
    _process.kill(ProcessSignal.sigterm);
    await _process.exitCode.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    if (_directory.existsSync()) _directory.deleteSync(recursive: true);
  }

  /// Binds port 0 briefly to be told a free one. Racy in principle, and the
  /// alternative — a fixed port — is worse: it collides with whatever else
  /// the developer is running, which is how the first attempt at this failed.
  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  /// The password out of `bootstrap.warning`, whose message embeds it in a
  /// sentence rather than a field of its own.
  static String? _bootstrapPasswordOf(String line) {
    if (!line.contains('bootstrap.warning')) return null;
    try {
      final entry = jsonDecode(line);
      if (entry is! Map<String, dynamic>) return null;
      final message = entry['message'];
      if (message is! String) return null;
      return RegExp(r'"admin": (\S+) —').firstMatch(message)?.group(1);
    } on FormatException {
      return null;
    }
  }

  /// `backend/structured_log_server`, found by walking up from wherever the
  /// test runner happens to have started.
  static String _locateServer() {
    var directory = Directory.current;
    for (var depth = 0; depth < 6; depth++) {
      final candidate = Directory(
        '${directory.path}/backend/structured_log_server',
      );
      if (candidate.existsSync()) return candidate.path;
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
    throw StateError(
      'backend/structured_log_server was not found above ${Directory.current.path}',
    );
  }
}
