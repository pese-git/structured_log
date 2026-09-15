import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../shared/api/dto/resource_dto.dart';
import 'group_detail_cubit.dart';
import 'resource_dialogs.dart';
import 'resource_failure_text.dart';
import 'resources_section.dart';

/// One group and the projects inside it (`GroupDetail.dc.html`).
///
/// The artboard also draws teams and the group's role assignments. Neither is
/// here: the server has no endpoints for them in this stage, so the sections
/// would be empty frames promising something the app cannot do.
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
              ResourceBreadcrumb(
                parts: [
                  (label: 'Группы', onPressed: onBack),
                  (label: groupName, onPressed: null),
                ],
              ),
              const SizedBox(height: AdminSpacing.x10),
              Text(
                groupName,
                style: AdminTypography.pageTitle.copyWith(color: colors.text),
              ),
              const SizedBox(height: AdminSpacing.x24),
              Row(
                children: [
                  Text(
                    'Проекты',
                    style: AdminTypography.label.copyWith(color: colors.text),
                  ),
                  const Spacer(),
                  AdminButton(
                    label: 'Проект',
                    icon: FluentIcons.add,
                    onPressed: () => _create(context),
                  ),
                ],
              ),
              const SizedBox(height: AdminSpacing.x12),
              Expanded(child: _projects(context, state)),
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

    return ListView.separated(
      itemCount: state.projects.length,
      separatorBuilder: (_, _) => const SizedBox(height: AdminSpacing.x10),
      itemBuilder: (context, index) {
        final project = state.projects[index];
        return AdminResourceRow(
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
        );
      },
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
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: cubit,
        child: BlocBuilder<GroupDetailCubit, GroupDetailState>(
          builder: (builderContext, state) {
            if (state.created) {
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
