import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../audit/audit_action.dart';
import '../../errors.dart';
import '../../rbac/access_check.dart';
import '../../rbac/authorizer.dart';
import '../../storage/audit_query.dart';
import '../../storage/database.dart';
import '../json_response.dart';
import '../page_request.dart';
import '../principal_middleware.dart';

part 'audit_log_route.g.dart';

/// How long records of each class are kept, as the running server is
/// configured.
///
/// Answered alongside the page rather than from a separate endpoint: a reader
/// looking at an empty result needs to know whether the range they asked for is
/// simply outside what is kept, and that question arrives with the result
/// (`specs/log-server-audit`, `specs/admin-client-audit-log`). `null` means no
/// limit — records are kept indefinitely, which is the default.
class AuditRetention {
  final int? auditRetentionDays;
  final int? authEventRetentionDays;

  const AuditRetention({this.auditRetentionDays, this.authEventRetentionDays});
}

Map<String, Object?> auditEntryJson(AuditLogEntry entry) {
  return {
    'id': entry.id,
    'actor_user_id': entry.actorUserId,
    'action': entry.action,
    'target_type': entry.targetType,
    'target_id': entry.targetId,
    'metadata': jsonDecode(entry.metadata),
    'created_at': toIso8601Utc(entry.createdAt),
  };
}

class AuditLogRoutes {
  final StructuredLogDatabase _db;
  final Authorizer _authorizer;
  final AuditRetention _retention;

  AuditLogRoutes(
    this._db,
    this._authorizer, {
    AuditRetention retention = const AuditRetention(),
  }) : _retention = retention;

  Router get router => _$AuditLogRoutesRouter(this);

  /// `admin` only (`specs/log-server-audit`).
  ///
  /// Not `owner` of anything, and not scoped: the log spans every tenant, and
  /// an owner reading the slice about their own group would still be reading
  /// which administrator acted on it and from which address. There is no
  /// filtered view that is safe to offer, so there is none.
  @Route.get('/v1/audit-log')
  Future<Response> queryAuditLog(Request request) async {
    final identity = request.requireUser();
    final roles = await resolveRoles(_authorizer, identity);
    if (!isGlobalAdmin(roles)) throw ApiError.forbidden();

    final params = request.url.queryParameters;
    final paging = parsePageRequest(params);

    AuditAction? action;
    final rawAction = params['action'];
    if (rawAction != null) {
      action = AuditAction.fromWire(rawAction);
      if (action == null) {
        // Refused rather than answered with an empty page. The set is closed
        // and published, so a value outside it is a typo — and a typo that
        // answers "no records" reads exactly like "nothing happened", which is
        // the one answer an audit log must never give by accident.
        throw ApiError.invalidRequest(
          'Unknown action.',
          details: {'field': 'action', 'reason': 'unknown'},
        );
      }
    }

    final page = await runAuditQuery(
      _db,
      AuditQuery(
        actorUserId: params['actor_user_id'] != null
            ? int.tryParse(params['actor_user_id']!)
            : null,
        action: action,
        targetType: params['target_type'],
        targetId: params['target_id'] != null
            ? int.tryParse(params['target_id']!)
            : null,
        from: params['from'] != null
            ? DateTime.tryParse(params['from']!)
            : null,
        to: params['to'] != null ? DateTime.tryParse(params['to']!) : null,
        limit: paging.limit,
        cursor: paging.cursor,
      ),
    );

    return jsonOk({
      'items': page.entries.map(auditEntryJson).toList(),
      'next_cursor': page.nextCursor?.toString(),
      'audit_retention_days': _retention.auditRetentionDays,
      'auth_event_retention_days': _retention.authEventRetentionDays,
    });
  }
}
