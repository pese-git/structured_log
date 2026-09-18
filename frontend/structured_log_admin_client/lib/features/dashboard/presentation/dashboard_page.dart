import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../shared/api/dto/resource_dto.dart';
import '../../resources/presentation/resource_failure_text.dart';
import 'dashboard_cubit.dart';

/// The landing overview for an administrator: every group on the server, and
/// a handful of projects across them (`Main.dc.html`).
///
/// **`admin` only.** The mockup also draws an `owner`/`user` variant — a role
/// badge on each group card, "Мои группы" instead of "Все группы сервера" —
/// but there is no endpoint that answers "what is my role on group X"
/// without the right to read that group's role assignments, and only
/// `admin` or that group's own `owner` has that right
/// (`role_assignments_route.dart`'s `canReadRoleAssignmentsForScope`). An
/// `admin`'s role on every group is always `admin`, which is the one variant
/// buildable without new backend work — `HomeShell` does not offer this
/// screen to any other role.
///
/// Two more mockup fields are dropped for the same reason — no server
/// response carries them: a project card's `lastActivity` ("2 мин назад"),
/// and a group card's project/team counts (would cost two extra requests
/// per group shown, for a count no other screen shows either).
class DashboardPage extends StatelessWidget {
  final String username;
  final void Function(int groupId, String groupName) onOpenGroup;
  final void Function(int projectId, String projectName) onOpenLogs;

  const DashboardPage({
    super.key,
    required this.username,
    required this.onOpenGroup,
    required this.onOpenLogs,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return BlocBuilder<DashboardCubit, DashboardState>(
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
              Text(
                'Дашборд',
                style: AdminTypography.pageTitle.copyWith(color: colors.text),
              ),
              const SizedBox(height: AdminSpacing.x18),
              Expanded(child: _body(context, state, colors)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, DashboardState state, AdminColors colors) {
    if (state.loading) {
      return const Center(child: AdminLoadingIndicator());
    }
    if (state.failure != null) {
      return AdminEmptyState(
        icon: FluentIcons.error_badge,
        title: 'Не удалось загрузить дашборд',
        description: describeApiFailure(state.failure!),
      );
    }

    // Admin sees every group, so a project's group is always among them —
    // no extra request needed to name it on its card.
    final groupNames = {for (final g in state.groups) g.id: g.name};

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Здравствуйте, $username',
            style: AdminTypography.sectionTitle.copyWith(color: colors.text),
          ),
          const SizedBox(height: AdminSpacing.x4),
          Text(
            'Администратор · быстрый доступ к тому, чем вы управляете и что '
            'можете просматривать',
            style: AdminTypography.bodySmall.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AdminSpacing.x24),
          Text(
            'Все группы сервера',
            style: AdminTypography.label.copyWith(color: colors.text),
          ),
          const SizedBox(height: AdminSpacing.x12),
          if (state.groups.isEmpty)
            const AdminEmptyState(
              icon: FluentIcons.group,
              title: 'Групп пока нет',
              description:
                  'Группы появятся здесь, как только кто-то их создаст.',
            )
          else
            Wrap(
              spacing: AdminSpacing.x14,
              runSpacing: AdminSpacing.x14,
              children: [
                for (final group in state.groups)
                  _GroupCard(
                    group: group,
                    onOpen: () => onOpenGroup(group.id, group.name),
                  ),
              ],
            ),
          const SizedBox(height: AdminSpacing.x24),
          Text(
            'Проекты',
            style: AdminTypography.label.copyWith(color: colors.text),
          ),
          const SizedBox(height: AdminSpacing.x12),
          if (state.projects.isEmpty)
            const AdminEmptyState(
              icon: FluentIcons.database,
              title: 'Проектов пока нет',
              description:
                  'Проекты появятся здесь, как только кто-то заведёт их внутри группы.',
            )
          else
            Wrap(
              spacing: AdminSpacing.x14,
              runSpacing: AdminSpacing.x14,
              children: [
                for (final project in state.projects)
                  _ProjectCard(
                    project: project,
                    groupName: groupNames[project.groupId] ?? '—',
                    onOpenLogs: () => onOpenLogs(project.id, project.name),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final GroupDto group;
  final VoidCallback onOpen;

  const _GroupCard({required this.group, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return Container(
      width: 300,
      padding: const EdgeInsets.all(AdminSpacing.x18),
      decoration: BoxDecoration(
        color: colors.cardBg,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(AdminRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  group.name,
                  overflow: TextOverflow.ellipsis,
                  style: AdminTypography.label.copyWith(color: colors.text),
                ),
              ),
              const SizedBox(width: AdminSpacing.x8),
              AdminTag(label: 'admin', foreground: colors.accentDark),
            ],
          ),
          const SizedBox(height: AdminSpacing.x6),
          Text(
            'Создана ${formatDate(group.createdAt)}',
            style: AdminTypography.caption.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AdminSpacing.x10),
          AdminButton(
            label: 'Открыть',
            icon: FluentIcons.chevron_right,
            size: AdminButtonSize.tonal,
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final ProjectDto project;
  final String groupName;
  final VoidCallback onOpenLogs;

  const _ProjectCard({
    required this.project,
    required this.groupName,
    required this.onOpenLogs,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final entryCount = project.entryCount ?? 0;
    return Container(
      width: 300,
      padding: const EdgeInsets.all(AdminSpacing.x18),
      decoration: BoxDecoration(
        color: colors.cardBg,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(AdminRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            project.name,
            overflow: TextOverflow.ellipsis,
            style: AdminTypography.label.copyWith(color: colors.text),
          ),
          const SizedBox(height: AdminSpacing.x4),
          Text(
            groupName,
            overflow: TextOverflow.ellipsis,
            style: AdminTypography.caption.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AdminSpacing.x10),
          AdminQuotaBar(
            label: 'Записей',
            usageLabel: formatCount(entryCount),
            limitLabel: project.maxEntries == null
                ? null
                : formatCount(project.maxEntries!),
            fraction: project.maxEntries == null || project.maxEntries == 0
                ? null
                : entryCount / project.maxEntries!,
          ),
          const SizedBox(height: AdminSpacing.x10),
          AdminButton(
            label: 'Смотреть логи',
            icon: FluentIcons.search,
            size: AdminButtonSize.tonal,
            onPressed: onOpenLogs,
          ),
        ],
      ),
    );
  }
}
