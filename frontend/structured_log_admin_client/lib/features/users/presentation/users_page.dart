import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../l10n/formatting.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/api/dto/user_dto.dart';
import 'user_actions.dart';
import 'user_dialogs.dart';
import 'user_failure_text.dart';
import 'users_cubit.dart';

/// The list of users, and the way to create one; block/unblock, delete and
/// edit move to `UserDetailPage`/`EditUserPage` once a row is open
/// (`Users.dc.html`).
///
/// Offered only to a reader whose access token carries the global admin
/// role — but that decides what to offer, never what to allow: the server
/// answers 403 to every one of these endpoints for anyone else, and this
/// screen renders that refusal rather than assuming it cannot happen
/// (`HomeShell._isAdmin`).
class UsersPage extends StatelessWidget {
  final ValueChanged<UserDto> onOpen;

  const UsersPage({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return BlocBuilder<UsersCubit, UsersState>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AdminSpacing.x24,
            AdminSpacing.x18,
            AdminSpacing.x24,
            AdminSpacing.x24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.usersPageTitle,
                      overflow: TextOverflow.ellipsis,
                      style: AdminTypography.pageTitle.copyWith(
                        color: colors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: AdminSpacing.x12),
                  AdminButton(
                    label: context.l10n.usersCreateUser,
                    icon: FluentIcons.add,
                    variant: AdminButtonVariant.accent,
                    size: AdminButtonSize.dialog,
                    onPressed: () => _create(context),
                  ),
                ],
              ),
              const SizedBox(height: AdminSpacing.x18),
              Expanded(child: _body(context, state)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, UsersState state) {
    if (state.loading) {
      return const Center(child: AdminLoadingIndicator());
    }
    if (state.failure != null && state.users.isEmpty) {
      return AdminEmptyState(
        icon: FluentIcons.error_badge,
        title: context.l10n.usersLoadFailedTitle,
        description: describeUserFailure(context.l10n, state.failure!),
      );
    }
    if (state.isEmpty) {
      return AdminEmptyState(
        icon: FluentIcons.contact,
        title: context.l10n.usersEmptyTitle,
        description: context.l10n.usersEmptyDescription,
      );
    }

    return ListView(
      children: [
        for (final user in state.users) ...[
          _UserRow(user: user, onOpen: onOpen),
          const SizedBox(height: AdminSpacing.x10),
        ],
        if (state.hasMore)
          Padding(
            padding: const EdgeInsets.all(AdminSpacing.x18),
            child: Center(
              child: state.loadingMore
                  ? const AdminLoadingIndicator()
                  : AdminButton(
                      label: context.l10n.usersShowMore,
                      icon: FluentIcons.chevron_down,
                      onPressed: context.read<UsersCubit>().loadMore,
                    ),
            ),
          ),
      ],
    );
  }

  Future<void> _create(BuildContext context) async {
    final cubit = context.read<UsersCubit>();
    var closing = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: cubit,
        child: BlocBuilder<UsersCubit, UsersState>(
          builder: (builderContext, state) {
            // Once only — see the identical guard in `GroupsPage._create` for
            // why: this builder runs again when the created account is
            // prepended to the list, and without the flag that second build
            // would queue a second pop.
            if (state.created && !closing) {
              closing = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              });
            }
            return CreateUserDialog(
              submitting: state.creating,
              errorText: state.createFailure == null
                  ? null
                  : describeUserFailure(
                      builderContext.l10n,
                      state.createFailure!,
                    ),
              onCreate: (username, password, displayName) => cubit.create(
                username: username,
                password: password,
                displayName: displayName,
              ),
              onCancel: () => Navigator.of(dialogContext).pop(),
            );
          },
        ),
      ),
    );
    cubit.dialogClosed();
  }
}

class _UserRow extends StatelessWidget {
  final UserDto user;
  final ValueChanged<UserDto> onOpen;

  const _UserRow({required this.user, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return AdminResourceRow(
      icon: FluentIcons.contact,
      identifier: user.username,
      title: user.displayName ?? user.username,
      subtitle: context.l10n.usersCreatedOn(
        formatDate(context.l10n, user.createdAt),
      ),
      onPressed: () => onOpen(user),
      tags: [
        if (user.isDeleted)
          AdminStatusTag(
            label: context.l10n.usersStatusDeleted,
            tone: AdminStatusTone.neutral,
          )
        else if (user.isBlocked)
          AdminStatusTag(
            label: context.l10n.usersStatusBlocked,
            tone: AdminStatusTone.error,
          )
        else
          AdminStatusTag(
            label: context.l10n.usersStatusActive,
            tone: AdminStatusTone.success,
          ),
        if (user.isPrimaryAdmin)
          AdminTag(label: context.l10n.usersPrimaryAdmin),
        if (user.mustChangePassword && !user.isDeleted)
          AdminStatusTag(
            label: context.l10n.usersTemporaryPassword,
            tone: AdminStatusTone.warning,
          ),
      ],
      // "Изменить" is not offered here any more — "Открыть" (and the row
      // itself, `onPressed` above) reaches `UserDetailPage`, and editing
      // lives there now. Block/unblock and delete stay as a row shortcut,
      // matching `Users.dc.html`.
      actions: [
        AdminButton(
          label: context.l10n.usersOpen,
          size: AdminButtonSize.tonal,
          onPressed: () => onOpen(user),
        ),
        if (!user.isDeleted) ...[
          AdminButton(
            label: user.isBlocked
                ? context.l10n.usersUnblock
                : context.l10n.usersBlock,
            size: AdminButtonSize.tonal,
            onPressed: () =>
                toggleUserBlocked(context, context.read<UsersCubit>(), user),
          ),
          // Deleting the primary administrator is refused server-side
          // unconditionally, so the action is not offered at all — an
          // absent action reads more honestly than one that always fails
          // (`AdminResourceRow`'s own rule).
          if (!user.isPrimaryAdmin)
            AdminButton(
              label: context.l10n.usersDelete,
              size: AdminButtonSize.tonal,
              onPressed: () =>
                  deleteUser(context, context.read<UsersCubit>(), user),
            ),
        ],
      ],
    );
  }
}
