import 'dart:io';

import 'package:shelf/shelf.dart';

/// Resolves the address a request should be rate-limited by
/// (`log-server-rate-limit`).
///
/// The socket address is the default and the only thing trusted out of the
/// box. `X-Forwarded-For` is client-supplied and trivially forged, so
/// honoring it unconditionally would hand an attacker an unlimited supply
/// of rate-limit keys — one per made-up address. It is read only when the
/// operator states how many reverse proxies actually sit in front
/// ([trustedProxyHops]).
///
/// Counting from the *end* is what makes that safe. Each proxy appends the
/// address it saw, so the rightmost entries are the ones added by
/// infrastructure the operator controls, and everything to their left is
/// whatever the client sent. With one trusted hop the client address is the
/// last entry; with two, the second from the end.
String resolveClientIp(Request request, {required int trustedProxyHops}) {
  if (trustedProxyHops > 0) {
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null) {
      final hops = forwarded
          .split(',')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      final index = hops.length - trustedProxyHops;
      if (index >= 0 && index < hops.length) return hops[index];
      // Fewer entries than configured hops: the header didn't come through
      // the expected chain, so it says nothing trustworthy about the client
      // and the socket address stands.
    }
  }

  return socketAddressOf(request) ?? 'unknown';
}

/// The peer address `shelf_io` recorded for this request, or `null` when the
/// request didn't come over a socket (in-process tests).
String? socketAddressOf(Request request) {
  final info = request.context['shelf.io.connection_info'];
  if (info is HttpConnectionInfo) return info.remoteAddress.address;
  return null;
}
