import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:test/test.dart';

void main() {
  group('ApiError.toResponse', () {
    test('renders the general envelope without details when absent', () async {
      final response = ApiError.notFound('Project not found.').toResponse();
      expect(response.statusCode, 404);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body, {'error': 'not_found', 'message': 'Project not found.'});
    });

    test('includes details when present', () async {
      final response = ApiError.invalidRequest(
        'name is required.',
        details: {'field': 'name', 'reason': 'required'},
      ).toResponse();
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['details'], {'field': 'name', 'reason': 'required'});
    });
  });

  group('errorHandlingMiddleware', () {
    test('renders a thrown ApiError as its JSON response', () async {
      final handler = const Pipeline()
          .addMiddleware(errorHandlingMiddleware())
          .addHandler((req) => throw ApiError.forbidden());

      final response = await handler(Request('GET', Uri.parse('http://x/y')));
      expect(response.statusCode, 403);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'forbidden');
    });

    test('lets a successful response through unchanged', () async {
      final handler = const Pipeline()
          .addMiddleware(errorHandlingMiddleware())
          .addHandler((req) => Response.ok('ok'));

      final response = await handler(Request('GET', Uri.parse('http://x/y')));
      expect(response.statusCode, 200);
    });
  });
}
