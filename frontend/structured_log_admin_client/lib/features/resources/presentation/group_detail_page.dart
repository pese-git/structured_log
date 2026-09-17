import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../shared/api/dto/resource_dto.dart';
import '../../../shared/api/dto/user_dto.dart';
import 'group_detail_cubit.dart';
import 'resource_dialogs.dart';
import 'resource_failure_text.dart';
import 'resources_section.dart';

/// One group and the projects inside it (`GroupDetail.dc.html`).
///
/// The artboard also draws teams — still not here, the server has no
/// endpoints for them in this stage. Role assignments (the artboard's
/// «Доступ» section) are here now (уточнение 17.09.2026): who holds a role
/// on this group, granted/revoked from this side, the mirror of the reduced
/// grant form on the target user's own screen (`lib/features/users/`).
class GroupDetailPage extends StatelessWidget {
  final String groupName;
  final VoidCallback onBack;
  final ValueChanged<ProjectDto> onOpenProject;

  const GroupDetailPage({
    super.key,
    required this.groupName,
    required this.onBack,
    required this.onOpenProject,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return BlocBuilder<GroupDetailCubit, GroupDetailState>(
      builder: (context, state) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AdminSpacing.x24,
            AdminSpacing.x18,
            AdminSpacing.x24,
            AdminSpacing.x24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ResourceBreadcrumb(
                parts: [
                  (label: 'Группы', onPressed: onBack),
                  (label: groupName, onPressed: null),
                ],
              ),
              const SizedBox(height: AdminSpacing.x10),
              Text(
                groupName,
                overflow: TextOverflow.ellipsis,
                style: AdminTypography.pageTitle.copyWith(color: colors.text),
              ),
              const SizedBox(height: AdminSpacing.x24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Проекты',
                      overflow: TextOverflow.ellipsis,
                      style: AdminTypography.label.copyWith(color: colors.text),
                    ),
                  ),
                  const SizedBox(width: AdminSpacing.x12),
                  AdminButton(
                    label: 'Проект',
                    icon: FluentIcons.add,
                    onPressed: () => _create(context),
                  ),
                ],
              ),
              const SizedBox(height: AdminSpacing.x12),
              _projects(context, state),
              const SizedBox(height: AdminSpacing.x24),
              _Access(groupName: groupName, state: state),
            ],
          ),
        );
      },
    );
  }

  Widget _projects(BuildContext context, GroupDetailState state) {
    if (state.loading) {
      return const Center(child: AdminLoadingIndicator());
    }
    if (state.failure != null) {
      return AdminEmptyState(
        icon: FluentIcons.error_badge,
        title: 'Не удалось загрузить проекты',
        description: describeApiFailure(state.failure!),
      );
    }
    if (state.isEmpty) {
      return const AdminEmptyState(
        icon: FluentIcons.build_queue,
        title: 'Проектов пока нет',
        description:
            'Создайте первый — он будет принимать логи по '
            'секретному ключу.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final project in state.projects) ...[
          AdminResourceRow(
            icon: FluentIcons.build_queue,
            title: project.name,
            subtitle: _quotaLine(project),
            tags: [
              if (project.isBlocked)
                const AdminStatusTag(
                  label: 'Заблокирован',
                  tone: AdminStatusTone.error,
                ),
            ],
            onPressed: () => onOpenProject(project),
            actions: [
              AdminButton(
                label: 'Открыть',
                size: AdminButtonSize.tonal,
                onPressed: () => onOpenProject(project),
              ),
            ],
          ),
          const SizedBox(height: AdminSpacing.x10),
        ],
      ],
    );
  }

  /// The list endpoint carries no usage counters — only the project's own
  /// endpoint computes them — so this line states the limits, and the project
  /// screen states the usage against them.
  static String _quotaLine(ProjectDto project) {
    final entries = project.maxEntries == null
        ? 'без лимита записей'
        : 'лимит ${formatCount(project.maxEntries!)} записей';
    return '$entries · retention ${project.retentionDays} дней';
  }

  Future<void> _create(BuildContext context) async {
    final cubit = context.read<GroupDetailCubit>();
    var closing = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: cubit,
        child: BlocBuilder<GroupDetailCubit, GroupDetailState>(
          builder: (builderContext, state) {
            // Once only: the cubit reloads the project list after a
            // success, and a builder that queued a pop on every state change
            // would queue a second one for whatever is on top by then. See
            // `project_detail_page.dart`, where that cost a secret key.
            if (state.created && !closing) {
              closing = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              });
            }
            return CreateProjectDialog(
              groupName: groupName,
              submitting: state.creating,
              errorText: state.createFailure == null
                  ? null
                  : describeApiFailure(state.createFailure!),
              onCreate: (name, quota) {
                if (name.isEmpty) return;
                cubit.create(
                  name: name,
                  retentionDays: quota.retentionDays,
                  maxEntries: quota.maxEntries,
                  maxBytes: quota.maxBytes,
                );
              },
              onCancel: () => Navigator.of(dialogContext).pop(),
            );
          },
        ),
      ),
    );
    cubit.dialogClosed();
  }
}

class _Access extends StatelessWidget {
  final String groupName;
  final GroupDetailState state;

  const _Access({required this.groupName, required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Доступ',
                overflow: TextOverflow.ellipsis,
                style: AdminTypography.label.copyWith(color: colors.text),
              ),
            ),
            const SizedBox(width: AdminSpacing.x12),
            AdminButton(
              label: 'Предоставить доступ',
              icon: FluentIcons.add,
              onPressed: () => _grant(context),
            ),
          ],
        ),
        const SizedBox(height: AdminSpacing.x12),
        if (state.roleAssignments.isEmpty)
          const AdminEmptyState(
            icon: FluentIcons.permissions,
            title: 'Доступа пока никому не выдано',
            description:
                'Предоставьте роль owner или user, чтобы открыть доступ к '
                'этой группе и её проектам.',
          )
        else
          for (final grant in state.roleAssignments) ...[
            AdminResourceRow(
              icon: FluentIcons.contact,
              title: grant.subjectName ?? 'Пользователь #${grant.subjectId}',
              subtitle: grant.role,
              actions: [
                AdminButton(
                  label: 'Отозвать',
                  size: AdminButtonSize.tonal,
                  onPressed: () => _revoke(context, grant),
                ),
              ],
            ),
            const SizedBox(height: AdminSpacing.x10),
          ],
      ],
    );
  }

  Future<void> _grant(BuildContext context) async {
    final cubit = context.read<GroupDetailCubit>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: cubit,
        child: BlocBuilder<GroupDetailCubit, GroupDetailState>(
          builder: (builderContext, state) {
            return GrantAccessDialog(
              scopeLabel: 'Группа: $groupName',
              submitting: state.grantingAccess,
              errorText: state.accessFailure == null
                  ? null
                  : describeApiFailure(state.accessFailure!),
              searchUsers: cubit.searchUsers,
              onGrant: (values) async {
                await cubit.grantAccess(
                  userId: values.userId,
                  role: values.role,
                );
                if (!dialogContext.mounted) return;
                // Left open on a refusal so the reason is read where the
                // grant was attempted (`_Quota._edit`, same pattern).
                if (cubit.state.accessFailure == null) {
                  Navigator.of(dialogContext).pop();
                }
              },
              onCancel: () => Navigator.of(dialogContext).pop(),
            );
          },
        ),
      ),
    );
    cubit.clearAccessFailure();
  }

  Future<void> _revoke(BuildContext context, RoleAssignmentDto grant) async {
    final cubit = context.read<GroupDetailCubit>();
    final subject = grant.subjectName ?? 'пользователя #${grant.subjectId}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AdminConfirmDialog(
        title: 'Отозвать доступ у «$subject»?',
        message:
            'Роль «${grant.role}» на эту группу будет отозвана немедленно.',
        confirmLabel: 'Отозвать',
        destructive: true,
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    if (confirmed ?? false) await cubit.revokeAccess(grant.id);
  }
}
