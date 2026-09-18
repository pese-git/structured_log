import 'package:cherrypick/cherrypick.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../shared/api/dto/user_dto.dart';
import 'edit_user_page.dart';
import 'user_detail_page.dart';
import 'users_cubit.dart';
import 'users_page.dart';

/// Where inside the section the reader is — same shape as
/// `ResourcesSection`'s `_Location` stack, one place fewer deep: there is no
/// third level here the way a project sits under a group, so `_Edit` goes
/// straight back to `_Detail` rather than needing its own child location.
sealed class _Location {
  const _Location();
}

class _List extends _Location {
  const _List();
}

class _Detail extends _Location {
  final int userId;

  const _Detail(this.userId);
}

class _Edit extends _Location {
  final int userId;

  const _Edit(this.userId);
}

/// User management: the list, one user's detail, and editing it
/// (`Users.dc.html`/`UserDetail.dc.html`/`EditUser.dc.html`).
///
/// One `UsersCubit` for the whole section, not a fresh one per location —
/// its state already models "at most one open detail/edit page" (`saving`,
/// `actionFailure`, `roleAssignments`, `recentAudit`), the same shape the old
/// single edit dialog needed, just spread across two screens instead of one.
class UsersSection extends StatefulWidget {
  final Scope scope;

  /// Opens the audit log filtered to one user as actor —
  /// `UserDetailPage`'s "Открыть в аудите" link. The other section of the
  /// app, so `HomeShell` owns the actual navigation, same shape as
  /// `ResourcesSection.onOpenLogs`.
  final ValueChanged<int> onOpenAudit;

  const UsersSection({
    super.key,
    required this.scope,
    required this.onOpenAudit,
  });

  @override
  State<UsersSection> createState() => _UsersSectionState();
}

class _UsersSectionState extends State<UsersSection> {
  late final UsersCubit _cubit = widget.scope.resolve<UsersCubit>()..load();

  _Location _at = const _List();

  void _go(_Location location) => setState(() => _at = location);

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: switch (_at) {
        _List() => UsersPage(onOpen: (user) => _go(_Detail(user.id))),
        _Detail(:final userId) => UserDetailPage(
          key: ValueKey('user-detail-$userId'),
          user: _userOf(userId),
          onBack: () => _go(const _List()),
          onEdit: () => _go(_Edit(userId)),
          onOpenAudit: () => widget.onOpenAudit(userId),
        ),
        _Edit(:final userId) => EditUserPage(
          key: ValueKey('user-edit-$userId'),
          user: _userOf(userId),
          onBack: () => _go(_Detail(userId)),
        ),
      },
    );
  }

  /// The list is always loaded before a reader can reach `_Detail`/`_Edit`
  /// (both are only reached by tapping a row already drawn from it), so the
  /// id is always present.
  UserDto _userOf(int userId) =>
      _cubit.state.users.firstWhere((u) => u.id == userId);
}
