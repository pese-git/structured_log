import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../shared/api/dto/resource_dto.dart';
import '../../../shared/api/dto/user_dto.dart';
import 'project_detail_cubit.dart';
import 'resource_dialogs.dart';
import 'resource_failure_text.dart';
import 'resources_section.dart';

/// One project: what it may hold, how much of that it is holding, the keys
/// that let an application add to it, and who has a role on it
/// (`ProjectDetail.dc.html`).
///
/// Role assignments can still also be granted from the target user's own
/// screen (`lib/features/users/`) — the reduced grant UI there fixes the
/// subject and lets the admin pick the scope. This «Доступ» section is the
/// mirror: fixes the scope, lets the admin pick the subject (уточнение
/// 17.09.2026).
class ProjectDetailPage extends StatelessWidget {
  final String groupName;
  final bool isAdmin;
  final VoidCallback onBackToGroups;
  final void Function(int projectId, String projectName) onOpenLogs;

  const ProjectDetailPage({
    super.key,
    required this.groupName,
    required this.isAdmin,
    required this.onBackToGroups,
    required this.onOpenLogs,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
      builder: (context, state) {
        if (state.loading && state.project == null) {
          return const Center(child: AdminLoadingIndicator());
        }
        final project = state.project;
        if (project == null) {
          return AdminEmptyState(
            icon: FluentIcons.error_badge,
            title: 'Не удалось загрузить проект',
            description: state.failure == null
                ? 'Попробуйте ещё раз.'
                : describeApiFailure(state.failure!),
          );
        }

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
              _Header(
                project: project,
                groupName: groupName,
                onBackToGroups: onBackToGroups,
                onOpenLogs: () => onOpenLogs(project.id, project.name),
              ),
              if (project.isBlocked) ...[
                const SizedBox(height: AdminSpacing.x14),
                const AdminBanner(
                  message:
                      'Проект заблокирован администратором: приём новых логов '
                      'и запрос уже сохранённых логов этого проекта отключены '
                      'до разблокировки. Секретные ключи проекта не отозваны.',
                  tone: AdminBannerTone.warning,
                ),
              ],
              const SizedBox(height: AdminSpacing.x24),
              _Quota(project: project),
              const SizedBox(height: AdminSpacing.x24),
              _SecretKeys(project: project, state: state),
              const SizedBox(height: AdminSpacing.x24),
              _Access(project: project, isAdmin: isAdmin, state: state),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final ProjectDto project;
  final String groupName;
  final VoidCallback onBackToGroups;
  final VoidCallback onOpenLogs;

  const _Header({
    required this.project,
    required this.groupName,
    required this.onBackToGroups,
    required this.onOpenLogs,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResourceBreadcrumb(
          parts: [
            (label: 'Группы', onPressed: onBackToGroups),
            (label: groupName, onPressed: null),
            (label: project.name, onPressed: null),
          ],
        ),
        const SizedBox(height: AdminSpacing.x10),
        Row(
          children: [
            Flexible(
              child: Text(
                project.name,
                overflow: TextOverflow.ellipsis,
                style: AdminTypography.pageTitle.copyWith(color: colors.text),
              ),
            ),
            if (project.isBlocked) ...[
              const SizedBox(width: AdminSpacing.x12),
              const AdminStatusTag(
                label: 'Заблокирован',
                tone: AdminStatusTone.error,
              ),
            ],
            const Spacer(),
            AdminButton(
              label: project.isBlocked ? 'Разблокировать' : 'Заблокировать',
              size: AdminButtonSize.dialog,
              onPressed: () => _toggleBlocked(context, project),
            ),
            const SizedBox(width: AdminSpacing.x10),
            AdminButton(
              label: 'Открыть логи',
              icon: FluentIcons.search,
              variant: AdminButtonVariant.accent,
              size: AdminButtonSize.dialog,
              onPressed: onOpenLogs,
            ),
          ],
        ),
        const SizedBox(height: AdminSpacing.x4),
        Text(
          'Группа: $groupName',
          style: AdminTypography.bodySmall.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }

  Future<void> _toggleBlocked(BuildContext context, ProjectDto project) async {
    final cubit = context.read<ProjectDetailCubit>();
    if (project.isBlocked) {
      // Reversible and non-disruptive to confirm again — unblocking only
      // restores what blocking took away.
      await cubit.setBlocked(false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AdminConfirmDialog(
        title: 'Заблокировать проект «${project.name}»?',
        message:
            'Приём новых логов и запрос уже сохранённых логов этого проекта '
            'будут отключены до разблокировки. Секретные ключи проекта не '
            'отзываются.',
        confirmLabel: 'Заблокировать',
        destructive: true,
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    if (confirmed ?? false) await cubit.setBlocked(true);
  }
}

class _Quota extends StatelessWidget {
  final ProjectDto project;

  const _Quota({required this.project});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final entryCount = project.entryCount ?? 0;
    final totalBytes = project.totalBytes ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Квота и использование',
                overflow: TextOverflow.ellipsis,
                style: AdminTypography.label.copyWith(color: colors.text),
              ),
            ),
            const SizedBox(width: AdminSpacing.x12),
            AdminButton(
              label: 'Изменить квоту',
              icon: FluentIcons.edit,
              onPressed: () => _edit(context),
            ),
          ],
        ),
        const SizedBox(height: AdminSpacing.x12),
        Container(
          padding: const EdgeInsets.all(AdminSpacing.x18),
          decoration: BoxDecoration(
            color: colors.cardBg,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(AdminRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminKeyValueRow(
                label: 'Срок хранения (retention_days)',
                value: '${project.retentionDays} дней',
              ),
              const SizedBox(height: AdminSpacing.x14),
              // Usage beside the limit, never one without the other — the
              // spec asks for "842 / 1000" rather than either half alone.
              AdminQuotaBar(
                label: 'Записей (max_entries)',
                usageLabel: formatCount(entryCount),
                limitLabel: project.maxEntries == null
                    ? null
                    : formatCount(project.maxEntries!),
                fraction: project.maxEntries == null || project.maxEntries == 0
                    ? null
                    : entryCount / project.maxEntries!,
              ),
              const SizedBox(height: AdminSpacing.x14),
              AdminQuotaBar(
                label: 'Объём (max_bytes)',
                usageLabel: formatBytes(totalBytes),
                limitLabel: project.maxBytes == null
                    ? null
                    : formatBytes(project.maxBytes!),
                fraction: project.maxBytes == null || project.maxBytes == 0
                    ? null
                    : totalBytes / project.maxBytes!,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context) async {
    final cubit = context.read<ProjectDetailCubit>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: cubit,
        child: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
          builder: (builderContext, state) {
            return EditQuotaDialog(
              projectName: project.name,
              retentionDays: project.retentionDays,
              maxEntries: project.maxEntries,
              maxBytes: project.maxBytes,
              submitting: state.saving,
              errorText: state.actionFailure == null
                  ? null
                  : describeApiFailure(state.actionFailure!),
              onSave: (quota) async {
                await cubit.updateQuota(
                  retentionDays: quota.retentionDays,
                  maxEntries: quota.maxEntries,
                  maxBytes: quota.maxBytes,
                );
                if (!dialogContext.mounted) return;
                // Left open on a refusal so the reason is read where the
                // change was made.
                if (cubit.state.actionFailure == null) {
                  Navigator.of(dialogContext).pop();
                }
              },
              onCancel: () => Navigator.of(dialogContext).pop(),
            );
          },
        ),
      ),
    );
    cubit.clearActionFailure();
  }
}

class _SecretKeys extends StatelessWidget {
  final ProjectDto project;
  final ProjectDetailState state;

  const _SecretKeys({required this.project, required this.state});

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
                'Секретные ключи проекта',
                overflow: TextOverflow.ellipsis,
                style: AdminTypography.label.copyWith(color: colors.text),
              ),
            ),
            const SizedBox(width: AdminSpacing.x12),
            AdminButton(
              label: 'Создать ключ',
              icon: FluentIcons.add,
              variant: AdminButtonVariant.accent,
              onPressed: () => _create(context),
            ),
          ],
        ),
        const SizedBox(height: AdminSpacing.x12),
        if (state.keys.isEmpty)
          const AdminEmptyState(
            icon: FluentIcons.permissions,
            title: 'Секретных ключей пока нет',
            description:
                'Создайте первый, чтобы приложение могло присылать логи.',
          )
        else
          for (final key in state.keys) ...[
            AdminResourceRow(
              icon: FluentIcons.permissions,
              title: key.label,
              subtitle: 'Создан ${formatDate(key.createdAt)}',
              tags: [
                if (key.revokedAt == null)
                  const AdminStatusTag(
                    label: 'Активен',
                    tone: AdminStatusTone.success,
                  )
                else
                  AdminStatusTag(
                    label: 'Отозван ${formatDate(key.revokedAt!)}',
                    tone: AdminStatusTone.neutral,
                  ),
              ],
              actions: [
                if (key.revokedAt == null)
                  AdminButton(
                    label: 'Отозвать',
                    size: AdminButtonSize.tonal,
                    onPressed: () => _revoke(context, key),
                  ),
              ],
            ),
            const SizedBox(height: AdminSpacing.x10),
          ],
      ],
    );
  }

  Future<void> _create(BuildContext context) async {
    final cubit = context.read<ProjectDetailCubit>();
    var closing = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: cubit,
        child: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
          builder: (builderContext, state) {
            // As soon as the key exists, this dialog is replaced by the one
            // that shows it — the value is in memory and nowhere else.
            //
            // `closing` is not belt and braces. This builder runs on every
            // state change while the dialog is up, and creating a key emits
            // twice: once with the key, then again when the list behind it
            // reloads. Without the flag both builds queue a pop, the route is
            // still mounted through its exit animation so the second one is
            // not skipped either, and it pops whatever is on top by then —
            // which is the dialog showing the key. The value is answered once
            // by the server and kept nowhere, so that pop loses it for good.
            // Seen in a browser (2026-09-15); a widget test's clock does not
            // reproduce the interleaving.
            if (state.revealedKey != null && !closing) {
              closing = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              });
            }
            return NameDialog(
              title: 'Новый секретный ключ',
              fieldLabel: 'Метка',
              confirmLabel: 'Создать ключ',
              description:
                  'Метка нужна, чтобы потом понять, какое приложение им '
                  'пользуется. Значение ключа будет показано один раз.',
              submitting: state.saving,
              errorText: state.actionFailure == null
                  ? null
                  : describeApiFailure(state.actionFailure!),
              onSubmit: (label) {
                if (label.isNotEmpty) cubit.createKey(label);
              },
              onCancel: () => Navigator.of(dialogContext).pop(),
            );
          },
        ),
      ),
    );

    final revealed = cubit.state.revealedKey;
    if (revealed?.secret == null) {
      cubit.clearActionFailure();
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => SecretKeyRevealDialog(
        projectName: project.name,
        label: revealed!.label,
        secret: revealed.secret!,
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
    cubit.dismissRevealedKey();
  }

  Future<void> _revoke(BuildContext context, SecretKeyDto key) async {
    final cubit = context.read<ProjectDetailCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AdminConfirmDialog(
        title: 'Отозвать ключ «${key.label}»?',
        message:
            'Приложения, которые присылают логи с этим ключом, сразу получат '
            'отказ. Отзыв необратим — при необходимости создайте новый ключ.',
        confirmLabel: 'Отозвать',
        destructive: true,
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    if (confirmed ?? false) await cubit.revokeKey(key.id);
  }
}

class _Access extends StatelessWidget {
  final ProjectDto project;
  final bool isAdmin;
  final ProjectDetailState state;

  const _Access({
    required this.project,
    required this.isAdmin,
    required this.state,
  });

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
        // Only reaches the reader here for a revoke fired straight from a
        // row — a grant's refusal is shown inside `GrantAccessDialog` itself
        // while it's open, and clears with it either way when it closes.
        if (state.accessFailure != null) ...[
          AdminBanner(
            message: describeApiFailure(state.accessFailure!),
            tone: AdminBannerTone.error,
          ),
          const SizedBox(height: AdminSpacing.x12),
        ],
        if (state.roleAssignments.isEmpty)
          const AdminEmptyState(
            icon: FluentIcons.permissions,
            title: 'Доступа пока никому не выдано',
            description:
                'Предоставьте роль owner или user, чтобы открыть доступ к '
                'этому проекту.',
          )
        else
          for (final grant in state.roleAssignments) ...[
            AdminResourceRow(
              icon: FluentIcons.contact,
              title: subjectLabel(grant),
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
    final cubit = context.read<ProjectDetailCubit>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: cubit,
        child: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
          builder: (builderContext, state) {
            return GrantAccessDialog(
              scopeLabel: 'Проект: ${project.name}',
              submitting: state.grantingAccess,
              isGlobalAdmin: isAdmin,
              errorText: state.accessFailure == null
                  ? null
                  : describeApiFailure(state.accessFailure!),
              searchUsers: cubit.searchUsers,
              searchTeams: cubit.searchTeams,
              onGrant: (values) async {
                await cubit.grantAccess(
                  subjectType: values.subjectType,
                  subjectId: values.subjectId,
                  role: values.role,
                );
                if (!dialogContext.mounted) return;
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
    final cubit = context.read<ProjectDetailCubit>();
    final subject =
        grant.subjectName ??
        (grant.subjectType == 'team'
            ? 'команды #${grant.subjectId}'
            : 'пользователя #${grant.subjectId}');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AdminConfirmDialog(
        title: 'Отозвать доступ у «$subject»?',
        message:
            'Роль «${grant.role}» на этот проект будет отозвана немедленно.',
        confirmLabel: 'Отозвать',
        destructive: true,
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    if (confirmed ?? false) await cubit.revokeAccess(grant.id);
  }
}
