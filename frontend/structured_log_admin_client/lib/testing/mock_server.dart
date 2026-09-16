import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A stand-in for `structured_log_server`, speaking its HTTP contract.
///
/// **Under `lib/` rather than `test/`, and not by preference.** An
/// `integration_test/` target is compiled with its own directory as the
/// application root, so a relative import reaching back into `test/` is not
/// found at all on web — `package:` reaches only into `lib/`, and both the
/// widget tests and the driven-app flow need this same mock. Nothing in the
/// application imports it, which is not left to good intentions:
/// `test/testing_boundary_test.dart` fails if anything does, and an unreferenced
/// library is not in the bundle either way. This package is never published.
///
/// The seam is `HttpClientAdapter`, which is as low as this client's network
/// layer goes: everything above it — `dio`, the auth interceptor and its
/// refresh, the generated `retrofit` clients, the hand-written SSE parser, the
/// failure mapper, the DTOs — is the real thing, running against bytes rather
/// than against a stub of itself. That is the whole point of these tests: the
/// repository fakes used by the screen tests answer *above* the layer where
/// both of the defects of 15.09.2026 lived (a collection envelope the client
/// never parsed, a stream the web adapter could not deliver), so no test that
/// substitutes a repository could have caught either.
///
/// It keeps state rather than answering from a script, because the flows worth
/// testing are sequences: create a group and it appears in the next list,
/// change a password and the gate stops answering 403, revoke a key and it
/// comes back revoked. [script] and [override] are there for the answers a
/// working server would not give on its own — a refusal, a limiter, a socket
/// that never answers.
class MockServer implements HttpClientAdapter {
  MockServer({this.username = 'root', this.password = 'correct'});

  /// The one account. Users, teams and roles have no endpoints in this stage,
  /// so a second account would have nothing to be different about.
  final String username;

  /// Replaced by `POST /v1/auth/change-password`, which is what makes the
  /// forced-change flow testable end to end.
  String password;

  /// While true, every authenticated route but `change-password` answers
  /// `403 must_change_password` — the gate the server puts in front of an
  /// account still carrying the password an administrator gave it.
  bool mustChangePassword = false;

  /// Rows, in the shape the server puts on the wire. Maps rather than DTOs on
  /// purpose: a mock that answered with the client's own model classes could
  /// not disagree with the client about the wire format, and disagreeing about
  /// the wire format is precisely the bug class this exists to catch.
  final groups = <Map<String, dynamic>>[];
  final projects = <Map<String, dynamic>>[];
  final secretKeys = <Map<String, dynamic>>[];

  /// Oldest first; `GET /v1/logs` reverses them, as the server does.
  final logEntries = <Map<String, dynamic>>[];

  /// Secret keys in the form an application would present them, by id. Kept
  /// so [acceptEntry] can check the one it is handed.
  final _issuedSecrets = <String>{};

  /// Every request that reached the adapter, in order.
  final requests = <RecordedRequest>[];

  /// Every live subscription opened, in order — a reconnect appends another.
  final streams = <MockLogStream>[];

  /// The subscription currently open, or the last one there was.
  MockLogStream get stream => streams.last;

  /// Answers queued for one route, consumed in order and outranking the state
  /// machine while any remain.
  final _scripted = <String, Queue<MockReply>>{};

  /// A standing answer for anything at all, consulted before the routes.
  /// Returning `null` lets the request through.
  ///
  /// Not named `override`: a member by that name shadows `dart:core`'s
  /// annotation inside this class, and `@override` stops compiling.
  MockReply? Function(RecordedRequest request)? standingAnswer;

  /// Queues one answer for `METHOD path`, e.g.
  /// `script('POST', '/v1/groups', MockReply(403, body: {'error': 'forbidden'}))`.
  void script(String method, String path, MockReply reply) => _scripted
      .putIfAbsent('${method.toUpperCase()} $path', () => Queue())
      .add(reply);

  // ---------------------------------------------------------------- tokens

  var _sequence = 0;
  final _liveAccess = <String>{};
  final _liveRefresh = <String>{};

  /// Signs the account in without going through the screen, for tests that
  /// are about what happens afterwards.
  ({String accessToken, String refreshToken}) issueSession() {
    final pair = _issuePair();
    return (
      accessToken: pair['access_token']!,
      refreshToken: pair['refresh_token']!,
    );
  }

  /// Every access token issued so far stops being accepted; refresh tokens
  /// still are. This is what a token that has simply aged out looks like from
  /// the client, and it is the only way to make the interceptor's
  /// refresh-and-replay actually run.
  void expireAccessTokens() => _liveAccess.clear();

  /// The session cannot be renewed: the refresh grant now answers
  /// `400 invalid_grant`, the way a spent or revoked token is refused.
  void revokeRefreshTokens() => _liveRefresh.clear();

  Map<String, String> _issuePair() {
    final access = _issueAccess();
    final refresh = 'refresh-${++_sequence}';
    _liveRefresh.add(refresh);
    return {'access_token': access, 'refresh_token': refresh};
  }

  /// A real-shaped JWT, unsigned. The client reads `preferred_username` out of
  /// it to put a name on the screen and deliberately does not verify the
  /// signature (`access_token_claims.dart`), so an unsigned one exercises the
  /// same path a real one would.
  String _issueAccess() {
    String segment(Map<String, dynamic> claims) =>
        base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');
    final token =
        '${segment({'alg': 'none', 'typ': 'JWT'})}.'
        '${segment({'preferred_username': username, 'jti': ++_sequence})}.'
        'signature-is-never-checked-by-this-client';
    _liveAccess.add(token);
    return token;
  }

  // --------------------------------------------------------------- adapter

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final request = await RecordedRequest._read(options, requestStream);
    requests.add(request);

    final reply = _answer(request, cancelFuture);
    if (reply is ResponseBody) return reply;
    return _encode(reply as MockReply, request);
  }

  @override
  void close({bool force = false}) {
    for (final stream in streams) {
      stream.drop();
    }
  }

  /// [MockReply], or a [ResponseBody] already built — which only the live
  /// subscription needs, because its body is a stream that stays open.
  Object _answer(RecordedRequest request, Future<void>? cancelFuture) {
    final scripted = _scripted['${request.method} ${request.path}'];
    if (scripted != null && scripted.isNotEmpty) return scripted.removeFirst();

    final forced = standingAnswer?.call(request);
    if (forced != null) return forced;

    try {
      return _route(request, cancelFuture);
    } on _Refusal catch (refusal) {
      return refusal.reply;
    }
  }

  ResponseBody _encode(MockReply reply, RecordedRequest request) {
    if (reply.statusCode < 0) {
      throw DioException.connectionError(
        requestOptions: request.options,
        reason: 'The mock server was unreachable.',
      );
    }
    if (reply.body == null) {
      // No content type either: dio only tries to decode a body it was told is
      // JSON, and `Future<void>` endpoints answer with nothing at all.
      return ResponseBody.fromString(
        '',
        reply.statusCode,
        headers: reply.headers,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...reply.headers,
      },
    );
  }

  // ---------------------------------------------------------------- routes

  Object _route(RecordedRequest request, Future<void>? cancelFuture) {
    final path = request.segments;

    return switch ((request.method, path)) {
      ('POST', ['v1', 'auth', 'token']) => _token(request),
      ('DELETE', ['v1', 'auth', 'token']) => _signOut(request),
      ('POST', ['v1', 'auth', 'change-password']) => _changePassword(request),

      ('GET', ['v1', 'groups']) => _listGroups(request),
      ('POST', ['v1', 'groups']) => _createGroup(request),
      ('POST', ['v1', 'groups', final id, 'projects']) => _createProject(
        request,
        int.parse(id),
      ),

      ('GET', ['v1', 'projects']) => _listProjects(request),
      ('GET', ['v1', 'projects', final id]) => _getProject(
        request,
        int.parse(id),
      ),
      ('PATCH', ['v1', 'projects', final id]) => _patchProject(
        request,
        int.parse(id),
      ),

      ('GET', ['v1', 'projects', final id, 'secret-keys']) => _listKeys(
        request,
        int.parse(id),
      ),
      ('POST', ['v1', 'projects', final id, 'secret-keys']) => _createKey(
        request,
        int.parse(id),
      ),
      ('DELETE', ['v1', 'projects', final id, 'secret-keys', final keyId]) =>
        _revokeKey(request, int.parse(id), int.parse(keyId)),

      ('GET', ['v1', 'logs']) => _queryLogs(request),
      ('GET', ['v1', 'logs', 'stream']) => _openStream(request, cancelFuture),

      _ => MockReply(
        404,
        body: {
          'error': 'not_found',
          'message': 'No route for ${request.method} ${request.path}.',
        },
      ),
    };
  }

  /// RFC 6749, which is what the token endpoint follows: a form body, and an
  /// `{"error": ...}` envelope that is not the API's general one.
  MockReply _token(RecordedRequest request) {
    final form = request.form;
    switch (form['grant_type']) {
      case 'password':
        if (form['username'] != username || form['password'] != password) {
          return const MockReply(400, body: {'error': 'invalid_grant'});
        }
      case 'refresh_token':
        final presented = form['refresh_token'];
        if (presented == null || !_liveRefresh.remove(presented)) {
          return const MockReply(400, body: {'error': 'invalid_grant'});
        }
      default:
        return const MockReply(400, body: {'error': 'unsupported_grant_type'});
    }

    return MockReply(
      200,
      body: {..._issuePair(), 'token_type': 'Bearer', 'expires_in': 900},
    );
  }

  /// Answers 200 whether or not the token was any good — a caller learns
  /// nothing about tokens it does not hold.
  MockReply _signOut(RecordedRequest request) {
    _liveRefresh.remove(request.form['refresh_token']);
    return const MockReply(204);
  }

  /// The one route the forced-change gate does not cover, and the way out of
  /// it. A wrong current password is `401 invalid_grant` — not the
  /// `unauthorized` a stale token gets, which is what keeps the interceptor
  /// from replaying the attempt.
  MockReply _changePassword(RecordedRequest request) {
    _requireSession(request);
    final body = request.json;
    if (body['current_password'] != password) {
      return const MockReply(
        401,
        body: {
          'error': 'invalid_grant',
          'message': 'Current password is incorrect.',
        },
      );
    }
    password = body['new_password'] as String;
    mustChangePassword = false;
    // The server retires the access token in hand but leaves the refresh token
    // alone, which is why changing a password does not end the session: the
    // next request renews through the interceptor.
    _liveAccess.clear();
    return const MockReply(204);
  }

  MockReply _listGroups(RecordedRequest request) {
    _requireUser(request);
    return MockReply(200, body: {'items': groups});
  }

  MockReply _createGroup(RecordedRequest request) {
    _requireUser(request);
    final group = {
      'id': _nextId(groups),
      'name': request.json['name'],
      'created_at': _now(),
    };
    groups.add(group);
    return MockReply(201, body: group);
  }

  MockReply _listProjects(RecordedRequest request) {
    _requireUser(request);
    final groupId = request.query['group_id'];
    final visible = groupId == null
        ? projects
        : projects.where((p) => p['group_id'] == int.parse(groupId)).toList();
    // The list endpoint carries no usage counters — only `GET /v1/projects/{id}`
    // computes them — and stripping them here is what makes the client's
    // "keep the counters we already showed" behaviour testable.
    return MockReply(200, body: {'items': visible.map(_withoutUsage).toList()});
  }

  MockReply _getProject(RecordedRequest request, int id) {
    _requireUser(request);
    return MockReply(200, body: _project(id));
  }

  MockReply _createProject(RecordedRequest request, int groupId) {
    _requireUser(request);
    final body = request.json;
    final project = {
      'id': _nextId(projects),
      'group_id': groupId,
      'name': body['name'],
      'retention_days': body['retention_days'],
      'max_entries': body['max_entries'],
      'max_bytes': body['max_bytes'],
      'is_blocked': false,
      'created_at': _now(),
      'entry_count': 0,
      'total_bytes': 0,
    };
    projects.add(project);
    return MockReply(201, body: _withoutUsage(project));
  }

  MockReply _patchProject(RecordedRequest request, int id) {
    _requireUser(request);
    final project = _project(id);
    final body = request.json;
    // `containsKey`, not a null check: the server distinguishes "leave this
    // alone" from "make this unlimited" by whether the key is on the wire at
    // all, and that distinction is the reason the update DTO exists.
    for (final field in ['retention_days', 'max_entries', 'max_bytes']) {
      if (body.containsKey(field)) project[field] = body[field];
    }
    return MockReply(200, body: _withoutUsage(project));
  }

  MockReply _listKeys(RecordedRequest request, int projectId) {
    _requireUser(request);
    final mine = secretKeys.where((k) => k['project_id'] == projectId);
    // Never the value: only the response that created a key carries `secret`.
    return MockReply(
      200,
      body: {
        'items': [
          for (final key in mine) {...key}..remove('secret'),
        ],
      },
    );
  }

  MockReply _createKey(RecordedRequest request, int projectId) {
    _requireUser(request);
    final id = _nextId(secretKeys);
    final key = {
      'id': id,
      'project_id': projectId,
      'label': request.json['label'],
      'created_at': _now(),
      'revoked_at': null,
    };
    secretKeys.add(key);
    final secret = 'slk_live_$id';
    _issuedSecrets.add(secret);
    return MockReply(201, body: {...key, 'secret': secret});
  }

  MockReply _revokeKey(RecordedRequest request, int projectId, int keyId) {
    _requireUser(request);
    final key = secretKeys.firstWhere(
      (k) => k['id'] == keyId && k['project_id'] == projectId,
      orElse: () =>
          throw _Refusal(const MockReply(404, body: {'error': 'not_found'})),
    );
    // The row stays so the audit trail keeps its subject.
    key['revoked_at'] = _now();
    return const MockReply(204);
  }

  /// Newest first, cursor walking backwards in time — the order and the paging
  /// the client's feed is built around.
  MockReply _queryLogs(RecordedRequest request) {
    _requireUser(request);
    final query = request.query;
    var matching = logEntries.reversed.where((entry) {
      if (query['project_id'] != null &&
          entry['project_id'] != int.parse(query['project_id']!)) {
        return false;
      }
      if (query['level'] != null &&
          _levelRank(entry['level'] as String) < _levelRank(query['level']!)) {
        return false;
      }
      if (query['category'] != null && entry['category'] != query['category']) {
        return false;
      }
      // `q` runs as a LIKE over the event and the raw stored JSON, so it
      // matches key names as well as values.
      if (query['q'] != null &&
          !jsonEncode(
            entry,
          ).toLowerCase().contains(query['q']!.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    final cursor = query['cursor'];
    if (cursor != null) {
      matching = matching
          .where((entry) => (entry['id'] as int) < int.parse(cursor))
          .toList();
    }

    final limit = int.tryParse(query['limit'] ?? '') ?? 50;
    final page = matching.take(limit).toList();
    final more = matching.length > page.length;

    return MockReply(
      200,
      body: {'items': page, 'next_cursor': more ? '${page.last['id']}' : null},
    );
  }

  /// A body that stays open. Everything above it — dio's stream response type,
  /// the frame parser, the reconnect loop — is the client's own.
  ResponseBody _openStream(
    RecordedRequest request,
    Future<void>? cancelFuture,
  ) {
    _requireUser(request);
    final stream = MockLogStream._(request.query);
    streams.add(stream);
    // dio hands the adapter the cancellation of the request's `CancelToken`,
    // and the client cancels one per attempt. Without honouring it the body
    // would outlive the subscription that asked for it.
    unawaited(cancelFuture?.whenComplete(stream.drop));
    return ResponseBody(
      stream._controller.stream,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  // ----------------------------------------------------------------- guards

  /// Whoever is calling holds a token this server issued and has not retired.
  ///
  /// Two refusals, and the difference between them is load-bearing: a token
  /// that aged out is `unauthorized`, which the interceptor renews against,
  /// while the forced-change gate is a 403 the session survives.
  void _requireUser(RecordedRequest request) {
    _requireSession(request);
    if (mustChangePassword) {
      throw _Refusal(
        const MockReply(
          403,
          body: {
            'error': 'must_change_password',
            'message':
                'This account must change its password before continuing.',
          },
        ),
      );
    }
  }

  void _requireSession(RecordedRequest request) {
    final presented = request.bearer;
    if (presented == null || !_liveAccess.contains(presented)) {
      throw _Refusal(const MockReply(401, body: {'error': 'unauthorized'}));
    }
  }

  Map<String, dynamic> _project(int id) => projects.firstWhere(
    (p) => p['id'] == id,
    orElse: () =>
        throw _Refusal(const MockReply(404, body: {'error': 'not_found'})),
  );

  static Map<String, dynamic> _withoutUsage(Map<String, dynamic> project) =>
      {...project}
        ..removeWhere((key, _) => key == 'entry_count' || key == 'total_bytes');

  static int _nextId(List<Map<String, dynamic>> rows) => rows.isEmpty
      ? 1
      : (rows.map((row) => row['id'] as int).reduce((a, b) => a > b ? a : b)) +
            1;

  static String _now() => DateTime.utc(2026, 9, 15, 12).toIso8601String();

  static const _levels = [
    'trace',
    'debug',
    'info',
    'warning',
    'error',
    'critical',
  ];

  /// The level is a floor, not an equality: `warning` also returns errors.
  static int _levelRank(String level) {
    final index = _levels.indexOf(level);
    return index == -1 ? 0 : index;
  }
}

extension MockIngest on MockServer {
  /// What an instrumented application does to a project, from outside the
  /// client entirely.
  ///
  /// Deliberately a method rather than a `POST /v1/logs` route: the admin
  /// client never ships logs — `structured_log_http` does, from someone
  /// else's process — and a route the code under test cannot reach would be
  /// fiction dressed as coverage. The key is still checked, so a flow that
  /// takes the value out of the reveal dialog and hands it here keeps the two
  /// tied together: an application holding some other string stores nothing.
  ///
  /// Delivers to every open subscription on the project as well, because that
  /// is what the server does with an accepted entry — which is the difference
  /// between an entry a reader has to reload for and one that simply appears.
  void acceptEntry(Map<String, dynamic> entry, {required String secret}) {
    if (!_issuedSecrets.contains(secret)) {
      throw ArgumentError.value(secret, 'secret', 'no such project key');
    }
    logEntries.add(entry);
    for (final stream in streams) {
      if (!stream.isOpen) continue;
      if (stream.query['project_id'] != '${entry['project_id']}') continue;
      stream.send(entry);
    }
  }
}

/// One canned answer. A negative status means the request never arrived —
/// dio raises a connection error, which is what an unreachable server is.
class MockReply {
  final int statusCode;
  final Object? body;
  final Map<String, List<String>> headers;

  const MockReply(this.statusCode, {this.body, this.headers = const {}});

  const MockReply.unreachable()
    : statusCode = -1,
      body = null,
      headers = const {};
}

class _Refusal implements Exception {
  final MockReply reply;

  const _Refusal(this.reply);
}

/// One request as it actually went out — read from the encoded body, not from
/// `RequestOptions.data`, so a DTO that serializes wrongly is caught here
/// rather than agreed with.
class RecordedRequest {
  final RequestOptions options;
  final String method;
  final String path;
  final Map<String, String> query;
  final String? body;

  RecordedRequest._({
    required this.options,
    required this.method,
    required this.path,
    required this.query,
    required this.body,
  });

  static Future<RecordedRequest> _read(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
  ) async {
    final chunks = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        chunks.addAll(chunk);
      }
    }
    return RecordedRequest._(
      options: options,
      method: options.method.toUpperCase(),
      path: options.uri.path,
      query: options.uri.queryParameters,
      body: chunks.isEmpty ? null : utf8.decode(chunks),
    );
  }

  List<String> get segments =>
      path.split('/').where((segment) => segment.isNotEmpty).toList();

  Map<String, dynamic> get json =>
      body == null ? const {} : jsonDecode(body!) as Map<String, dynamic>;

  /// The token endpoints are form-encoded, following RFC 6749.
  Map<String, String> get form =>
      body == null ? const {} : Uri.splitQueryString(body!);

  /// The access token this request carried, or `null` if it carried none.
  String? get bearer {
    final header = options.headers['Authorization'];
    if (header is! String || !header.startsWith('Bearer ')) return null;
    return header.substring('Bearer '.length);
  }

  /// Whether the JSON body has this key at all — which for the quota update is
  /// a different question from whether its value is null.
  bool carries(String key) => json.containsKey(key);
}

/// One live subscription, from the server's side.
class MockLogStream {
  MockLogStream._(this.query);

  /// The parameters the subscription was opened with. The list and the stream
  /// must agree on them, and `since_id` is how a reconnect resumes.
  final Map<String, String> query;

  final _controller = StreamController<Uint8List>();

  bool get isOpen => !_controller.isClosed;

  /// `since_id`, as an int, or `null` when the subscription started from now.
  int? get sinceId => int.tryParse(query['since_id'] ?? '');

  /// Delivers one entry, in the flat shape `GET /v1/logs` uses.
  void send(Map<String, dynamic> entry) =>
      _write('id: ${entry['id']}\nevent: log\ndata: ${jsonEncode(entry)}\n\n');

  /// The keep-alive comment. It carries no field and exists only to prove the
  /// connection is alive — a client that mistook it for a frame would break.
  void keepAlive() => _write(': keep-alive\n\n');

  /// Closes the subscription the way the server does, naming a reason. Some
  /// reasons the client reconnects through (`token_revoked`, `server_shutdown`)
  /// and some it reports (`project_blocked`).
  void end(String reason) {
    _write('event: end\ndata: ${jsonEncode({'reason': reason})}\n\n');
    unawaited(_controller.close());
  }

  /// The socket simply goes away, with no closing frame — a dropped
  /// connection, which the client answers with a reconnect.
  void drop() {
    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
  }

  void _write(String frame) {
    if (_controller.isClosed) return;
    _controller.add(Uint8List.fromList(utf8.encode(frame)));
  }
}

/// One log entry in the shape the server puts on the wire: the stored context
/// spread across the top level, with `id`, `project_id` and `received_at` over
/// it. Three names are reserved for exactly that reason.
Map<String, dynamic> mockLogEntry({
  required int id,
  int projectId = 1,
  String event = 'Something happened',
  String level = 'info',
  String? category,
  String? logger,
  String? requestId,
  DateTime? receivedAt,
  Map<String, dynamic> context = const {},
}) {
  return {
    ...context,
    'id': id,
    'project_id': projectId,
    'received_at': (receivedAt ?? DateTime.utc(2026, 9, 15, 9, 12, 55))
        .toIso8601String(),
    'event': event,
    'level': level,
    'category': ?category,
    'logger': ?logger,
    'request_id': ?requestId,
  };
}
