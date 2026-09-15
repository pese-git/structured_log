import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

part 'database.g.dart';

/// A registered administrator/end user of the server.
///
/// `username` is the only login identifier (`log-server-auth`); `email` is
/// nullable and only used for password recovery. Uniqueness of `username`
/// and `email` (when set) — including across soft-deleted rows — and the
/// at-most-one `is_primary_admin` invariant are enforced by indexes created
/// in [StructuredLogDatabase.migration], not by column constraints alone.
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text()();
  TextColumn get passwordHash => text()();
  TextColumn get displayName => text().nullable()();
  TextColumn get email => text().nullable()();
  DateTimeColumn get emailVerifiedAt => dateTime().nullable()();
  BoolColumn get mustChangePassword =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get isPrimaryAdmin =>
      boolean().withDefault(const Constant(false))();
  IntColumn get tokenVersion => integer().withDefault(const Constant(0))();
}

/// Owns a set of [Projects]; the top-level multi-tenancy boundary.
class Groups extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// A named set of [Users] within exactly one [Groups], used only for
/// granting the same [RoleAssignments] to several users at once.
class Teams extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get groupId => integer().references(Groups, #id)();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Many-to-many membership of [Users] in [Teams].
class TeamMembers extends Table {
  IntColumn get teamId => integer().references(Teams, #id)();
  IntColumn get userId => integer().references(Users, #id)();

  @override
  Set<Column> get primaryKey => {teamId, userId};
}

/// A log-ingestion tenant, always owned by exactly one [Groups].
class Projects extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get groupId => integer().references(Groups, #id)();
  TextColumn get name => text()();
  IntColumn get retentionDays => integer()();
  IntColumn get maxEntries => integer().nullable()();
  IntColumn get maxBytes => integer().nullable()();
  BoolColumn get isBlocked => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// A bearer secret authenticating `POST /v1/logs` for one [Projects]; stored
/// as a hash, never in plaintext (`design.md` decision 11).
class ProjectSecretKeys extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get projectId => integer().references(Projects, #id)();
  TextColumn get keyHash => text()();
  TextColumn get label => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get revokedAt => dateTime().nullable()();
}

/// Grants `role` on `(scopeType, scopeId)` to either a single user or every
/// current member of a team (`subjectType`/`subjectId`) — `design.md`
/// decision 6. `role` is one of `admin`/`owner`/`user`; `subjectType` is one
/// of `user`/`team`; `scopeType` is one of `global`/`group`/`project`.
class RoleAssignments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get subjectType => text()();
  IntColumn get subjectId => integer()();
  TextColumn get role => text()();
  TextColumn get scopeType => text()();
  IntColumn get scopeId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// An issued, revocable refresh token for a [Users] session
/// (`log-server-auth`). `tokenHash` is a hash of the token, never the token
/// itself.
class RefreshTokens extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().references(Users, #id)();
  TextColumn get tokenHash => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get expiresAt => dateTime()();
  DateTimeColumn get revokedAt => dateTime().nullable()();
}

/// A one-time password-recovery token (`log-server-password-reset`).
/// `tokenHash` is a hash of the token, never the token itself.
class PasswordResetTokens extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().references(Users, #id)();
  TextColumn get tokenHash => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get expiresAt => dateTime()();
  DateTimeColumn get usedAt => dateTime().nullable()();
}

/// A one-time email-confirmation token (`log-server-email-verification`).
/// `tokenHash` is a hash of the token, never the token itself. Structurally
/// identical to [PasswordResetTokens] — kept as a separate table because the
/// two token kinds are issued/consumed by unrelated flows.
class EmailVerificationTokens extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().references(Users, #id)();
  TextColumn get tokenHash => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get expiresAt => dateTime()();
  DateTimeColumn get usedAt => dateTime().nullable()();
}

/// A record of one administrative mutation (`log-server-audit`), written in
/// the same transaction as the mutation it describes.
class AuditLogEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get actorUserId => integer().nullable()();
  TextColumn get action => text()();
  TextColumn get targetType => text()();
  IntColumn get targetId => integer().nullable()();
  TextColumn get metadata => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Cached current storage usage for one [Projects], updated atomically
/// alongside batch ingestion and retention purge so quota checks are a
/// cheap point-lookup rather than an aggregate over [LogEntries]
/// (`log-server-quotas`).
class ProjectUsage extends Table {
  IntColumn get projectId => integer().references(Projects, #id)();
  IntColumn get entryCount => integer().withDefault(const Constant(0))();
  IntColumn get totalBytes => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {projectId};
}

/// One ingested structured_log entry (`log-server-storage`). `contextJson`
/// is the full original record (including arbitrary user fields not lifted
/// into a typed column below) — the source of truth for round-trip fidelity.
class LogEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get projectId => integer().references(Projects, #id)();
  DateTimeColumn get receivedAt => dateTime()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get level => text()();
  TextColumn get event => text()();
  TextColumn get category => text().nullable()();
  TextColumn get logger => text().nullable()();
  TextColumn get sessionId => text().nullable()();
  TextColumn get requestId => text().nullable()();
  IntColumn get connectionGeneration => integer().nullable()();
  TextColumn get toolCallId => text().nullable()();
  TextColumn get messageId => text().nullable()();
  TextColumn get operationId => text().nullable()();
  IntColumn get sizeBytes => integer()();
  TextColumn get contextJson => text()();
}

@DriftDatabase(
  tables: [
    Users,
    Groups,
    Teams,
    TeamMembers,
    Projects,
    ProjectSecretKeys,
    RoleAssignments,
    RefreshTokens,
    PasswordResetTokens,
    EmailVerificationTokens,
    AuditLogEntries,
    ProjectUsage,
    LogEntries,
  ],
)
class StructuredLogDatabase extends _$StructuredLogDatabase {
  StructuredLogDatabase(super.executor);

  /// Opens (creating if absent) the SQLite database file at [path] in WAL
  /// mode (`log-server-storage` — reads must not block on concurrent
  /// ingestion writes).
  factory StructuredLogDatabase.open(String path) {
    return StructuredLogDatabase(
      NativeDatabase.createInBackground(
        File(path),
        setup: (Database db) {
          db.execute('PRAGMA journal_mode=WAL;');
          db.execute('PRAGMA foreign_keys=ON;');
        },
      ),
    );
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          for (final statement in _additionalIndexStatements) {
            await customStatement(statement);
          }
        },
      );

  /// Indexes beyond what a single-column/table-level constraint expresses:
  /// composite, and partial (`WHERE`-qualified) indexes — `log-server-storage`.
  static const _additionalIndexStatements = <String>[
    'CREATE INDEX idx_log_entries_project_id ON log_entries (project_id);',
    'CREATE INDEX idx_log_entries_timestamp ON log_entries (timestamp);',
    'CREATE INDEX idx_log_entries_level ON log_entries (level);',
    'CREATE INDEX idx_log_entries_category ON log_entries (category);',
    'CREATE INDEX idx_log_entries_session_id ON log_entries (session_id);',
    'CREATE INDEX idx_log_entries_request_id ON log_entries (request_id);',
    'CREATE INDEX idx_log_entries_project_level_timestamp '
        'ON log_entries (project_id, level, timestamp);',
    'CREATE UNIQUE INDEX idx_users_username ON users (username);',
    'CREATE UNIQUE INDEX idx_users_email ON users (email) '
        'WHERE email IS NOT NULL;',
    'CREATE UNIQUE INDEX idx_users_is_primary_admin ON users (is_primary_admin) '
        'WHERE is_primary_admin = 1;',
    'CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens (user_id);',
    'CREATE INDEX idx_password_reset_tokens_user_id '
        'ON password_reset_tokens (user_id);',
    'CREATE INDEX idx_email_verification_tokens_user_id '
        'ON email_verification_tokens (user_id);',
    'CREATE INDEX idx_audit_log_entries_actor_user_id '
        'ON audit_log_entries (actor_user_id);',
    'CREATE INDEX idx_audit_log_entries_action ON audit_log_entries (action);',
    'CREATE INDEX idx_audit_log_entries_target '
        'ON audit_log_entries (target_type, target_id);',
    'CREATE INDEX idx_audit_log_entries_created_at '
        'ON audit_log_entries (created_at);',
  ];
}
