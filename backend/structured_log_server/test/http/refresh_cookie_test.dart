import 'package:structured_log_server/src/http/refresh_cookie.dart';
import 'package:test/test.dart';

void main() {
  group('buildRefreshCookie', () {
    test('carries every attribute the design requires', () {
      final header = buildRefreshCookie(
        'the-token',
        maxAge: const Duration(days: 30),
      );

      expect(header, startsWith('$refreshCookieName=the-token;'));
      expect(header, contains('HttpOnly'));
      expect(header, contains('Secure'));
      expect(header, contains('SameSite=Strict'));
      expect(header, contains('Path=/v1/auth'));
      expect(header, contains('Max-Age=${const Duration(days: 30).inSeconds}'));
    });

    test('the path covers change-password, not only the token endpoint', () {
      // `/v1/auth/change-password` identifies the caller's own session by the
      // same token; a narrower path would leave it without one and keep the
      // client-side workaround this change exists to delete.
      final path = RegExp(
        r'Path=([^;]*)',
      ).firstMatch(buildRefreshCookie('t', maxAge: Duration.zero))!.group(1)!;

      expect('/v1/auth/token'.startsWith(path), isTrue);
      expect('/v1/auth/change-password'.startsWith(path), isTrue);
    });

    test('clearing keeps the attributes but expires immediately', () {
      final header = clearRefreshCookie();

      expect(header, startsWith('$refreshCookieName=;'));
      expect(header, contains('Max-Age=0'));
      // A browser matches the cookie to delete by name/path/domain, so the
      // path must be the one it was set with or the dead cookie survives.
      expect(header, contains('Path=/v1/auth'));
      expect(header, contains('HttpOnly'));
    });
  });

  group('refreshCookieOf', () {
    test('reads the value out of a header holding several cookies', () {
      expect(
        refreshCookieOf('theme=dark; $refreshCookieName=abc123; lang=ru'),
        'abc123',
      );
    });

    test('tolerates missing spaces and finds a lone cookie', () {
      expect(refreshCookieOf('$refreshCookieName=abc123'), 'abc123');
      expect(refreshCookieOf('a=1;$refreshCookieName=abc123;b=2'), 'abc123');
    });

    test(
      'is null when the header is absent, empty or holds no such cookie',
      () {
        expect(refreshCookieOf(null), isNull);
        expect(refreshCookieOf(''), isNull);
        expect(refreshCookieOf('theme=dark'), isNull);
      },
    );

    test('does not match a cookie whose name merely ends the same way', () {
      expect(refreshCookieOf('x_$refreshCookieName=abc123'), isNull);
    });

    test('an empty value is no token at all, not an empty one', () {
      // A cleared cookie is sent back as `name=` until the browser drops it;
      // treating that as a token would send the empty string to the server's
      // hash lookup and answer `invalid_grant` where `invalid_request` is
      // meant.
      expect(refreshCookieOf('$refreshCookieName='), isNull);
    });
  });

  group('shouldSetRefreshCookie', () {
    const listed = {'https://admin.example.test'};

    test('off never sets it', () {
      for (final origin in [
        null,
        'https://admin.example.test',
        'https://x.test',
      ]) {
        expect(
          shouldSetRefreshCookie(
            RefreshCookieMode.off,
            origin: origin,
            allowedOrigins: listed,
          ),
          isFalse,
          reason: 'origin $origin',
        );
      }
    });

    test('on always sets it, including for an origin declared foreign', () {
      for (final origin in [
        null,
        'https://admin.example.test',
        'https://x.test',
      ]) {
        expect(
          shouldSetRefreshCookie(
            RefreshCookieMode.on,
            origin: origin,
            allowedOrigins: listed,
          ),
          isTrue,
          reason: 'origin $origin',
        );
      }
    });

    test('auto withholds it only from an origin on the allow-list', () {
      expect(
        shouldSetRefreshCookie(
          RefreshCookieMode.auto,
          origin: 'https://admin.example.test',
          allowedOrigins: listed,
        ),
        isFalse,
      );
      expect(
        shouldSetRefreshCookie(
          RefreshCookieMode.auto,
          origin: 'https://other.example.test',
          allowedOrigins: listed,
        ),
        isTrue,
        reason: 'an origin nobody declared foreign is presumed our own',
      );
      expect(
        shouldSetRefreshCookie(
          RefreshCookieMode.auto,
          origin: null,
          allowedOrigins: listed,
        ),
        isTrue,
        reason: 'no Origin at all is a non-browser caller — curl, a script',
      );
    });

    test('auto sets it in the bundled deployment, which lists no origin', () {
      // Same-origin POST does carry an `Origin` header (Fetch sends it for
      // everything but GET/HEAD), so presence alone must not withhold the
      // cookie — only presence *in the list* may.
      expect(
        shouldSetRefreshCookie(
          RefreshCookieMode.auto,
          origin: 'https://logs.example.test',
          allowedOrigins: const {},
        ),
        isTrue,
      );
    });
  });

  group('refreshCookieModeOf', () {
    test('maps the configured strings', () {
      expect(refreshCookieModeOf('auto'), RefreshCookieMode.auto);
      expect(refreshCookieModeOf('on'), RefreshCookieMode.on);
      expect(refreshCookieModeOf('off'), RefreshCookieMode.off);
    });

    test('a handler built without a config behaves as it always did', () {
      // `HttpSettings`'s contract: defaults are what a route used when nothing
      // configured it. Every route test builds a handler without a
      // `ServerConfig`, and none of them expected a cookie before this change.
      expect(refreshCookieModeOf(null), RefreshCookieMode.off);
    });
  });
}
