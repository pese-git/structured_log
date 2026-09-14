import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../config/server_config.dart';
import '../storage/database.dart';
import 'hashing.dart';

/// The outcome of one [bootstrapAdmin] call — [created] is `false` for
/// every skip case `log-server-auth` treats as a normal outcome, not an
/// error (bootstrap disabled, database already non-empty, lost the
/// create-insert race to another process starting at the same time).
class BootstrapOutcome {
  final bool created;

  /// Only set when [created] is `true` and no password was supplied —
  /// the caller is expected to log it once, at `warning` level, and never
  /// again (`log-server-auth`: the one exception to never logging a
  /// secret).
  final String? generatedPassword;

  const BootstrapOutcome({required this.created, this.generatedPassword});
}

/// Auto-creates the first administrator on an empty `users` table, in the
/// same transaction as the emptiness check, before the server opens its
/// port (`log-server-auth`, `design.md` decision 49). [logWarning] is a
/// caller-supplied sink rather than a hard dependency on any particular
/// logging setup — self-logging (section 33) isn't built yet, and bin/
/// server.dart is free to route this through it once it is.
Future<BootstrapOutcome> bootstrapAdmin(
  StructuredLogDatabase db,
  ServerConfig config, {
  required void Function(String message) logWarning,
}) async {
  if (!config.bootstrapAdminEnabled) {
    if (await _usersTableIsEmpty(db)) {
      logWarning(
        'Bootstrap admin creation is disabled and the database has no '
        'users — run the create-admin command to create the first '
        'administrator.',
      );
    }
    return const BootstrapOutcome(created: false);
  }

  // Any explicitly-provided bootstrap parameter on a non-empty database is
  // a no-op, not silently ignored — see below. bootstrapAdminPassword has
  // no default (`null` iff never set), so its presence alone is decisive;
  // the username is compared against its own declared default.
  final explicitParams = config.bootstrapAdminPassword != null ||
      config.bootstrapAdminUsername != 'admin';

  try {
    return await db.transaction(() async {
      if (!await _usersTableIsEmpty(db)) {
        if (explicitParams) {
          logWarning(
            'Bootstrap admin parameters were set, but the database already '
            'has users — they were not applied. The existing '
            "administrator's password is unchanged.",
          );
        }
        return const BootstrapOutcome(created: false);
      }

      final password = config.bootstrapAdminPassword ?? generateRandomToken();
      final userId = await db.into(db.users).insert(
            UsersCompanion.insert(
              username: config.bootstrapAdminUsername,
              passwordHash: hashPassword(password),
              mustChangePassword: const Value(true),
              isPrimaryAdmin: const Value(true),
            ),
          );
      await db.into(db.roleAssignments).insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: userId,
              role: 'admin',
              scopeType: 'global',
            ),
          );

      final wasGenerated = config.bootstrapAdminPassword == null;
      if (wasGenerated) {
        logWarning(
          'Generated a temporary password for bootstrap administrator '
          '"${config.bootstrapAdminUsername}": $password — it must be '
          'changed at first login.',
        );
      }

      return BootstrapOutcome(
        created: true,
        generatedPassword: wasGenerated ? password : null,
      );
    });
  } on SqliteException {
    // Lost the race: another process's insert already claimed
    // is_primary_admin (the unique partial index from section 2.2) between
    // our emptiness check and our insert. Same outcome as finding the
    // table already non-empty — not an error.
    if (explicitParams) {
      logWarning(
        'Bootstrap admin parameters were set, but another process already '
        'created the first administrator — they were not applied.',
      );
    }
    return const BootstrapOutcome(created: false);
  }
}

Future<bool> _usersTableIsEmpty(StructuredLogDatabase db) async {
  final row =
      await db.customSelect('SELECT COUNT(*) AS c FROM users').getSingle();
  return row.read<int>('c') == 0;
}
