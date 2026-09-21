import 'dart:convert';

import 'package:drift/drift.dart';

import '../storage/database.dart';
import 'audit_action.dart';

/// Writes one audit record.
///
/// **Where is the transaction?** Nowhere in this signature, and that is the
/// design rather than an omission. `drift`'s `db.transaction(...)` is
/// zone-scoped: every call made on the same database instance inside the
/// callback already joins that transaction. So a caller that wraps its mutation
/// and its [write] in one `transaction` gets the atomicity
/// `specs/log-server-audit` requires — a mutation that rolls back takes its
/// audit record with it — without threading an executor through.
///
/// Taking an executor parameter instead, as `tasks.md` 19.1 suggests, would add
/// an argument to every call site that can only ever hold one correct value,
/// and would create a way to get it wrong that does not currently exist:
/// passing the executor of some *other* transaction would silently write the
/// record outside the one it is supposed to be atomic with. The guarantee is
/// better served by there being nothing to pass.
///
/// Not every action is under that rule — `auth.*` and `audit.purged` have no
/// resource mutation to be atomic with (`action_classes.dart`).
class AuditWriter {
  final StructuredLogDatabase _db;

  const AuditWriter(this._db);

  /// Records that [action] happened.
  ///
  /// [actorUserId] is null when nobody was authenticated — a failed login under
  /// a username that does not exist, a throttled request, the server's own
  /// purge pass. That is a fact about the event, not missing data.
  ///
  /// [metadata] is whatever the action needs a reader to know later, and is
  /// stored as JSON. It is the one field with no schema, so it is also the one
  /// that can leak: **nothing that authenticates anybody goes in it** — no
  /// password, no token, no secret key, and not the username submitted to a
  /// failed login, which is regularly someone's password typed into the wrong
  /// box (`specs/log-server-audit`).
  Future<void> write({
    required AuditAction action,
    required AuditTargetType targetType,
    int? actorUserId,
    int? targetId,
    Map<String, Object?> metadata = const {},
  }) {
    return _db
        .into(_db.auditLogEntries)
        .insert(
          AuditLogEntriesCompanion.insert(
            actorUserId: Value(actorUserId),
            action: action.wire,
            targetType: targetType.wire,
            targetId: Value(targetId),
            metadata: jsonEncode(metadata),
          ),
        );
  }
}
