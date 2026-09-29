import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';

import 'harness.dart';

/// The refresh token as an `HttpOnly` cookie, against the real server.
///
/// Deliberately below the admin client: these speak HTTP directly, the way
/// `curl` and an operator's script do, because the two things worth proving
/// here are what the server puts on the wire and that a caller keeping no
/// cookies is unaffected. The client's own behaviour is covered by
/// `test/integration/` in the admin client, and what a *browser* does with
/// the cookie by `integration_test/` in Chrome — no VM test can show that,
/// since `HttpClient` here stores nothing on its own.
void main() {
  setUpAll(
    () => StructlogConfiguration.configure(
      sinks: [LogSink(name: 'silent', output: (_, _) {})],
    ),
  );
  tearDownAll(StructlogConfiguration.reset);

  final client = HttpClient();
  tearDownAll(() => client.close(force: true));

  /// One form-encoded request, with the headers as they came back.
  Future<({int status, Map<String, Object?> body, List<String> setCookie})>
  post(
    String url, {
    required Map<String, String> form,
    String? cookie,
    String method = 'POST',
  }) async {
    final request = await client.openUrl(method, Uri.parse(url));
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
    );
    if (cookie != null) request.headers.set(HttpHeaders.cookieHeader, cookie);
    request.write(
      form.entries
          .map(
            (e) =>
                '${Uri.encodeQueryComponent(e.key)}='
                '${Uri.encodeQueryComponent(e.value)}',
          )
          .join('&'),
    );
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return (
      status: response.statusCode,
      body: text.isEmpty
          ? const <String, Object?>{}
          : jsonDecode(text) as Map<String, Object?>,
      setCookie: response.headers[HttpHeaders.setCookieHeader] ?? const [],
    );
  }

  /// The cookie's value, out of a `Set-Cookie` header — the one line of
  /// browser behaviour this file has to imitate.
  String? cookieValue(List<String> setCookie) {
    for (final header in setCookie) {
      if (!header.startsWith('structured_log_refresh=')) continue;
      final value = header.split(';').first.split('=').last;
      return value.isEmpty ? null : value;
    }
    return null;
  }

  test('a grant sets the cookie and still answers with the token', () async {
    final server = await ServerProcess.start(
      extraArgs: const ['--refresh-token-cookie=on'],
    );
    addTearDown(server.stop);

    final signIn = await post(
      '${server.baseUrl}/v1/auth/token',
      form: {
        'grant_type': 'password',
        'username': 'admin',
        'password': server.bootstrapPassword,
      },
    );

    expect(signIn.status, 200);
    final header = signIn.setCookie.firstWhere(
      (h) => h.startsWith('structured_log_refresh='),
    );
    expect(header, contains('HttpOnly'));
    expect(header, contains('Secure'));
    expect(header, contains('SameSite=Strict'));
    expect(header, contains('Path=/v1/auth'));
    expect(
      signIn.body['refresh_token'],
      isNotNull,
      reason:
          'the body is what keeps every non-browser caller working — the '
          'cookie is added beside it, never instead of it',
    );
    expect(signIn.body['refresh_token_cookie_set'], isTrue);
  });

  test('the cookie renews, and the form outranks it', () async {
    final server = await ServerProcess.start(
      extraArgs: const ['--refresh-token-cookie=on'],
    );
    addTearDown(server.stop);

    final signIn = await post(
      '${server.baseUrl}/v1/auth/token',
      form: {
        'grant_type': 'password',
        'username': 'admin',
        'password': server.bootstrapPassword,
      },
    );
    final firstCookie = cookieValue(signIn.setCookie)!;

    // No field at all: exactly what the browser client sends.
    final renewed = await post(
      '${server.baseUrl}/v1/auth/token',
      form: {'grant_type': 'refresh_token'},
      cookie: 'structured_log_refresh=$firstCookie',
    );
    expect(renewed.status, 200);
    final secondCookie = cookieValue(renewed.setCookie)!;
    expect(secondCookie, isNot(firstCookie), reason: 'rotation still happens');

    // The spent cookie is spent, cookie or not — the reuse detector does not
    // soften because of where the token came from.
    final reused = await post(
      '${server.baseUrl}/v1/auth/token',
      form: {'grant_type': 'refresh_token'},
      cookie: 'structured_log_refresh=$firstCookie',
    );
    expect(reused.status, 400);
    expect(reused.body['error'], 'invalid_grant');
  });

  test('a caller that names a token gets that token, not the cookie', () async {
    final server = await ServerProcess.start(
      extraArgs: const ['--refresh-token-cookie=on'],
    );
    addTearDown(server.stop);

    Future<(String body, String cookie)> session() async {
      final signIn = await post(
        '${server.baseUrl}/v1/auth/token',
        form: {
          'grant_type': 'password',
          'username': 'admin',
          'password': server.bootstrapPassword,
        },
      );
      return (
        signIn.body['refresh_token'] as String,
        cookieValue(signIn.setCookie)!,
      );
    }

    final (namedToken, _) = await session();
    final (_, otherCookie) = await session();

    final renewed = await post(
      '${server.baseUrl}/v1/auth/token',
      form: {'grant_type': 'refresh_token', 'refresh_token': namedToken},
      cookie: 'structured_log_refresh=$otherCookie',
    );
    expect(renewed.status, 200);

    // The cookie's session is untouched: its token still renews.
    final untouched = await post(
      '${server.baseUrl}/v1/auth/token',
      form: {'grant_type': 'refresh_token', 'refresh_token': otherCookie},
    );
    expect(
      untouched.status,
      200,
      reason: 'naming one session must not end another',
    );
  });

  test('signing out through the cookie clears it', () async {
    final server = await ServerProcess.start(
      extraArgs: const ['--refresh-token-cookie=on'],
    );
    addTearDown(server.stop);

    final signIn = await post(
      '${server.baseUrl}/v1/auth/token',
      form: {
        'grant_type': 'password',
        'username': 'admin',
        'password': server.bootstrapPassword,
      },
    );
    final cookie = cookieValue(signIn.setCookie)!;

    final signOut = await post(
      '${server.baseUrl}/v1/auth/token',
      form: const {},
      cookie: 'structured_log_refresh=$cookie',
      method: 'DELETE',
    );

    expect(signOut.status, 200);
    expect(
      signOut.setCookie.any((h) => h.contains('Max-Age=0')),
      isTrue,
      reason:
          'a browser left holding a revoked cookie would keep presenting '
          'it until its nominal 30 days were up',
    );
    final reuse = await post(
      '${server.baseUrl}/v1/auth/token',
      form: {'grant_type': 'refresh_token', 'refresh_token': cookie},
    );
    expect(reuse.status, 400);
  });

  test('off behaves exactly as the server did before the cookie', () async {
    final server = await ServerProcess.start(
      extraArgs: const ['--refresh-token-cookie=off'],
    );
    addTearDown(server.stop);

    final signIn = await post(
      '${server.baseUrl}/v1/auth/token',
      form: {
        'grant_type': 'password',
        'username': 'admin',
        'password': server.bootstrapPassword,
      },
    );

    expect(signIn.setCookie, isEmpty);
    expect(signIn.body['refresh_token_cookie_set'], isFalse);

    final renewed = await post(
      '${server.baseUrl}/v1/auth/token',
      form: {
        'grant_type': 'refresh_token',
        'refresh_token': signIn.body['refresh_token'] as String,
      },
    );
    expect(renewed.status, 200);
  });

  test('the default sets it, without the operator asking', () async {
    // `auto` with no allow-list: the bundled single-origin deployment, which
    // is the one an upgrade lands on.
    final server = await ServerProcess.start();
    addTearDown(server.stop);

    final signIn = await post(
      '${server.baseUrl}/v1/auth/token',
      form: {
        'grant_type': 'password',
        'username': 'admin',
        'password': server.bootstrapPassword,
      },
    );

    expect(signIn.body['refresh_token_cookie_set'], isTrue);
  });

  test('an origin the operator declared foreign gets no cookie', () async {
    final server = await ServerProcess.start(
      extraArgs: const ['--cors-allowed-origins=https://admin.example.test'],
    );
    addTearDown(server.stop);

    final request = await client.postUrl(
      Uri.parse('${server.baseUrl}/v1/auth/token'),
    );
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
    );
    request.headers.set('origin', 'https://admin.example.test');
    request.write(
      'grant_type=password&username=admin&password='
      '${Uri.encodeQueryComponent(server.bootstrapPassword)}',
    );
    final response = await request.close();
    final body =
        jsonDecode(await response.transform(utf8.decoder).join())
            as Map<String, Object?>;

    expect(response.headers[HttpHeaders.setCookieHeader], isNull);
    expect(body['refresh_token_cookie_set'], isFalse);
    expect(
      body['refresh_token'],
      isNotNull,
      reason: 'that deployment keeps holding the token itself',
    );
  });
}
