import 'package:drift/drift.dart';

import '../storage/database.dart';
import 'hashing.dart';

/// The outcome of one [createAdmin] call.
class CreateAdminOutcome {
  final bool success;
  final String? error;

  /// Set only when [success] and the caller didn't supply a password —
  /// same one-time-log contract as `bootstrapAdmin`'s generated password.
  final String? generatedPassword;

  const CreateAdminOutcome.success({this.generatedPassword})
    : success = true,
      error = null;
  const CreateAdminOutcome.failure(this.error)
    : success = false,
      generatedPassword = null;
}

/// `create-admin` (`bin/server.dart` subcommand, `design.md` decisions
/// 12/49): re-bootstrap on a database that already has users, or with
/// auto-bootstrap disabled. Distinct rules from [bootstrapAdmin]:
///
/// - "Already has an admin" only counts **active, non-deleted**
///   administrators (`is_active = true`, `deleted_at IS NULL`) — so
///   recovery stays possible even if the sole admin deleted their own
///   account (`design.md` decisions 12/27).
/// - `is_primary_admin` is set only if no user in the table, deleted or
///   not, has ever had it (`design.md` decision 28; also enforced by the
///   unique partial index from section 2.2, as a second line of defense).
/// - [password] unset means the same generate-and-require-change behavior
///   as auto-bootstrap; supplied means the operator chose it themselves,
///   so `must_change_password` is left `false`.
Future<CreateAdminOutcome> createAdmin(
  StructuredLogDatabase db, {
  required String username,
  String? password,
}) async {
  // The same rule the API applies, refused before anything is written. The
  // configuration check catches the command line path; this covers callers
  // that reach the function some other way.
  if (password != null) {
    final problem = passwordPolicyMessage(password);
    if (problem != null) return CreateAdminOutcome.failure(problem);
  }
  return db.transaction(() async {
    if (await _activeAdminExists(db)) {
      return const CreateAdminOutcome.failure(
        'An active administrator already exists.',
      );
    }

    final primaryAdminAlreadyAssigned = await _anyPrimaryAdminEverExisted(db);
    final resolvedPassword = password ?? generateRandomToken();
    final wasGenerated = password == null;

    final userId = await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            username: username,
            passwordHash: hashPassword(resolvedPassword),
            isPrimaryAdmin: Value(!primaryAdminAlreadyAssigned),
            mustChangePassword: Value(wasGenerated),
          ),
        );
    await db
        .into(db.roleAssignments)
        .insert(
          RoleAssignmentsCompanion.insert(
            subjectType: 'user',
            subjectId: userId,
            role: 'admin',
            scopeType: 'global',
          ),
        );

    return CreateAdminOutcome.success(
      generatedPassword: wasGenerated ? resolvedPassword : null,
    );
  });
}

Future<bool> _activeAdminExists(StructuredLogDatabase db) async {
  final row = await db
      .customSelect(
        'SELECT COUNT(*) AS c FROM role_assignments ra '
        'JOIN users u ON u.id = ra.subject_id '
        "WHERE ra.subject_type = 'user' AND ra.role = 'admin' "
        "AND ra.scope_type = 'global' "
        'AND u.is_active = 1 AND u.deleted_at IS NULL',
      )
      .getSingle();
  return row.read<int>('c') > 0;
}

Future<bool> _anyPrimaryAdminEverExisted(StructuredLogDatabase db) async {
  final row = await db
      .customSelect(
        'SELECT COUNT(*) AS c FROM users WHERE is_primary_admin = 1',
      )
      .getSingle();
  return row.read<int>('c') > 0;
}
