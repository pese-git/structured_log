import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../shared/api/dto/resource_dto.dart';
import 'project_detail_cubit.dart';
import 'resource_dialogs.dart';
import 'resource_failure_text.dart';
import 'resources_section.dart';

/// One project: what it may hold, how much of that it is holding, and the
/// keys that let an application add to it (`ProjectDetail.dc.html`).
///
/// The artboard's block/unblock button is not here. It needs
/// `POST /v1/projects/:id/block`, which this stage's server does not have —
/// but the *indicator* is, because a blocked project has to look blocked to
/// everyone who can see it (`specs/admin-client-resource-management`).
/// Role assignments are absent for the same reason as the endpoint.
class ProjectDetailPage extends StatelessWidget {
  final String groupName;
  final VoidCallback onBackToGroups;
  final void Function(int projectId, String projectName) onOpenLogs;

  const ProjectDetailPage({
    super.key,
    required this.groupName,
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
            Text(
              project.name,
              style: AdminTypography.pageTitle.copyWith(color: colors.text),
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
            Text(
              'Квота и использование',
              style: AdminTypography.label.copyWith(color: colors.text),
            ),
            const Spacer(),
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
            Text(
              'Секретные ключи проекта',
              style: AdminTypography.label.copyWith(color: colors.text),
            ),
            const Spacer(),
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
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: cubit,
        child: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
          builder: (builderContext, state) {
            // As soon as the key exists, this dialog is replaced by the one
            // that shows it — the value is in memory and nowhere else.
            if (state.revealedKey != null) {
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
