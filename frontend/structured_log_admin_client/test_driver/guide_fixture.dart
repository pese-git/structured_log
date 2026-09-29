import 'package:structured_log_admin_client/testing/mock_server.dart';

/// The world the user guide's screenshots are taken in.
///
/// Kept beside `guide_app.dart` and apart from it so that what a picture
/// shows is data somebody can read, review and change — rather than whatever
/// a stand happened to hold on the afternoon the pictures were taken, which
/// is how the previous set was produced and why it could not be reproduced.
///
/// Dates are fixed for the same reason: a fixture with `DateTime.now()` in it
/// produces a different screenshot every run, and a reviewer cannot tell a
/// real change from the clock moving.
const temporaryPassword = 'temporary-password';
const operatorPassword = 'operator-password';

const administratorRoles = [
  {'role': 'admin', 'scope_type': 'global', 'scope_id': null},
];

/// One group and, separately, one directly granted project — the case the
/// guide photographs to show what a plain `user` sees in the navigation.
const plainUserRoles = [
  {'role': 'user', 'scope_type': 'group', 'scope_id': 1},
  {'role': 'user', 'scope_type': 'project', 'scope_id': 3},
];

void seedGuideWorld(MockServer server, {required bool asPlainUser}) {
  server.groups.addAll([
    {'id': 1, 'name': 'payments', 'created_at': '2026-02-14T00:00:00.000Z'},
    if (!asPlainUser)
      {'id': 2, 'name': 'platform', 'created_at': '2026-03-02T00:00:00.000Z'},
  ]);

  server.projects.addAll([
    _project(
      id: 1,
      groupId: 1,
      name: 'checkout',
      entries: 128_400,
      bytes: 41_582_336,
    ),
    if (!asPlainUser)
      _project(
        id: 2,
        groupId: 1,
        name: 'billing',
        entries: 9_112,
        bytes: 3_204_096,
      ),
    _project(
      id: 3,
      groupId: 2,
      name: 'gateway',
      entries: 51_233,
      bytes: 18_996_224,
    ),
  ]);

  server.teams.add({
    'id': 1,
    'group_id': 1,
    'name': 'on-call',
    'created_at': '2026-03-10T00:00:00.000Z',
  });

  // Accounts other than the signed-in one. `alice` still carries the password
  // an administrator gave her, which is what the Users list marks and what the
  // guide's caption points at.
  server.users.addAll([
    _user(id: 2, username: 'alice', displayName: 'Alice Ng', mustChange: true),
    _user(id: 3, username: 'carol', displayName: 'Carol Diaz'),
    _user(
      id: 4,
      username: 'root',
      displayName: 'Built-in administrator',
      isPrimaryAdmin: true,
    ),
  ]);

  server.teamMembers.add({'team_id': 1, 'user_id': 3});

  server.roleAssignments.addAll([
    {
      'id': 1,
      'subject_type': 'user',
      'subject_id': 3,
      'role': 'owner',
      'scope_type': 'group',
      'scope_id': 1,
      'created_at': '2026-03-01T00:00:00.000Z',
    },
    {
      'id': 2,
      'subject_type': 'team',
      'subject_id': 1,
      'role': 'user',
      'scope_type': 'project',
      'scope_id': 1,
      'created_at': '2026-03-11T00:00:00.000Z',
    },
  ]);

  // Carol owns `payments` alone, so deleting her is refused — the guide
  // photographs that refusal.
  server.simulateSoleGroupOwner(3, [
    {'id': 1, 'name': 'payments'},
  ]);

  server.logEntries.addAll(_checkoutEntries());

  server
    ..auditRetentionDays = 365
    ..authEventRetentionDays = 90;
  server.auditEntries.addAll(_auditTrail());
}

Map<String, dynamic> _project({
  required int id,
  required int groupId,
  required String name,
  required int entries,
  required int bytes,
}) {
  return {
    'id': id,
    'group_id': groupId,
    'name': name,
    'retention_days': 30,
    'max_entries': null,
    'max_bytes': null,
    'is_blocked': false,
    'created_at': '2026-02-14T00:00:00.000Z',
    'entry_count': entries,
    'total_bytes': bytes,
  };
}

Map<String, dynamic> _user({
  required int id,
  required String username,
  required String displayName,
  bool mustChange = false,
  bool isPrimaryAdmin = false,
}) {
  return {
    'id': id,
    'username': username,
    'display_name': displayName,
    'email': null,
    'email_verified_at': null,
    'must_change_password': mustChange,
    'is_active': true,
    'deleted_at': null,
    'is_primary_admin': isPrimaryAdmin,
    'created_at': '2026-02-14T00:00:00.000Z',
  };
}

/// A morning in `checkout`: mostly ordinary traffic, one warning and two
/// errors, so the guide's "Error and above" filter has something to narrow
/// to and the entry detail has application fields worth showing
/// (`gateway`, `order_id`, `reason` — the three its caption names).
List<Map<String, dynamic>> _checkoutEntries() {
  final start = DateTime.utc(2026, 9, 15, 9, 12);
  var id = 0;
  Map<String, dynamic> entry(
    String event,
    String level,
    int minute,
    Map<String, dynamic> context, {
    String logger = 'checkout.api',
  }) {
    return mockLogEntry(
      id: ++id,
      event: event,
      level: level,
      category: 'http',
      logger: logger,
      receivedAt: start.add(Duration(minutes: minute)),
      context: context,
    );
  }

  return [
    entry('order_received', 'info', 0, {'order_id': 'ord_44821', 'items': 3}),
    entry('payment_authorized', 'info', 1, {
      'order_id': 'ord_44821',
      'gateway': 'stripe',
      'amount_cents': 4990,
    }),
    entry('order_received', 'info', 2, {'order_id': 'ord_44822', 'items': 1}),
    entry('slow_gateway_response', 'warning', 3, {
      'order_id': 'ord_44822',
      'gateway': 'stripe',
      'duration_ms': 2140,
    }),
    entry('payment_failed', 'error', 4, {
      'order_id': 'ord_44822',
      'gateway': 'stripe',
      'reason': 'timeout',
    }),
    entry('order_received', 'info', 5, {'order_id': 'ord_44823', 'items': 7}),
    entry('payment_failed', 'error', 6, {
      'order_id': 'ord_44823',
      'gateway': 'adyen',
      'reason': 'card_declined',
    }),
    entry('order_shipped', 'info', 7, {
      'order_id': 'ord_44821',
      'carrier': 'dhl',
    }, logger: 'checkout.fulfilment'),
  ];
}

/// Shapes copied from a stand, as `app.dart`'s trail was: a quota change
/// carrying both halves, a key created and revoked without its value, a
/// failed sign-in under an account that exists and one under an account that
/// does not, and a throttling episode.
List<Map<String, dynamic>> _auditTrail() {
  final day = DateTime.utc(2026, 9, 15, 6);
  return [
    mockAuditEntry(
      id: 1,
      action: 'auth.login_succeeded',
      actorUserId: 1,
      targetId: 1,
      metadata: const {
        'client_ip': '203.0.113.7',
        'user_agent': 'structured_log_admin_client/0.1.0',
      },
      createdAt: day,
    ),
    mockAuditEntry(
      id: 2,
      action: 'group.created',
      targetType: 'group',
      actorUserId: 1,
      targetId: 1,
      metadata: const {'name': 'payments'},
      createdAt: day.add(const Duration(minutes: 4)),
    ),
    mockAuditEntry(
      id: 3,
      action: 'project.created',
      targetType: 'project',
      actorUserId: 1,
      targetId: 1,
      metadata: const {'name': 'checkout', 'group_id': 1},
      createdAt: day.add(const Duration(minutes: 6)),
    ),
    mockAuditEntry(
      id: 4,
      action: 'project.quota_changed',
      targetType: 'project',
      actorUserId: 1,
      targetId: 1,
      metadata: const {
        'before': {'retention_days': 7, 'max_entries': null},
        'after': {'retention_days': 30, 'max_entries': 500000},
      },
      createdAt: day.add(const Duration(minutes: 9)),
    ),
    mockAuditEntry(
      id: 5,
      action: 'secret_key.created',
      targetType: 'secret_key',
      actorUserId: 1,
      targetId: 1,
      metadata: const {'project_id': 1, 'label': 'checkout-prod'},
      createdAt: day.add(const Duration(minutes: 11)),
    ),
    mockAuditEntry(
      id: 6,
      action: 'auth.login_failed',
      actorUserId: 2,
      targetId: 2,
      metadata: const {
        'reason': 'bad_password',
        'client_ip': '198.51.100.44',
        'user_agent': 'curl/8.7.1',
      },
      createdAt: day.add(const Duration(minutes: 40)),
    ),
    mockAuditEntry(
      id: 7,
      action: 'auth.login_failed',
      metadata: const {
        'reason': 'unknown_user',
        'unknown_user': true,
        'client_ip': '198.51.100.44',
        'user_agent': 'curl/8.7.1',
      },
      createdAt: day.add(const Duration(minutes: 41)),
    ),
    mockAuditEntry(
      id: 8,
      action: 'auth.throttled',
      targetType: 'auth',
      metadata: const {
        'key_kind': 'ip',
        'path': '/v1/auth/token',
        'client_ip': '198.51.100.44',
      },
      createdAt: day.add(const Duration(minutes: 42)),
    ),
  ];
}
