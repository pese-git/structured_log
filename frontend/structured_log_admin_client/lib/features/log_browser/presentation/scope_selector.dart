import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../domain/log_scope.dart';

/// Picks the one scope to read.
///
/// Stands in place of the list until something is chosen, and nothing is
/// queried before that (`specs/admin-client-log-browser`). Groups and
/// projects are offered side by side because a role can be granted on either,
/// and neither list implies the other.
class ScopeSelector extends StatelessWidget {
  final ScopeOptions options;
  final LogScope? selected;
  final ValueChanged<LogScope> onSelected;

  const ScopeSelector({
    super.key,
    required this.options,
    required this.onSelected,
    this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    if (options.isEmpty) {
      return const AdminEmptyState(
        icon: FluentIcons.search,
        title: 'Нет доступных областей',
        description:
            'Логи видны в проектах и группах, на которые у вас есть '
            'роль. Попросите администратора выдать доступ.',
      );
    }

    return Center(
      child: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Выберите область',
              style: AdminTypography.sectionTitle.copyWith(color: colors.text),
            ),
            const SizedBox(height: AdminSpacing.x4),
            Text(
              'Логи запрашиваются по одному проекту или одной группе — '
              'без объединения нескольких.',
              style: AdminTypography.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
            ),
            if (options.projects.isNotEmpty) ...[
              const SizedBox(height: AdminSpacing.x18),
              _Group(
                title: 'Проекты',
                children: [
                  for (final project in options.projects)
                    _ScopeTile(
                      label: project.name,
                      icon: FluentIcons.folder_horizontal,
                      selected: selected == project,
                      // Offered, but marked: the server answers 403 for a
                      // blocked project, and hiding it would read as its
                      // deletion.
                      blocked: options.blockedProjectIds.contains(project.id),
                      onPressed: () => onSelected(project),
                    ),
                ],
              ),
            ],
            if (options.groups.isNotEmpty) ...[
              const SizedBox(height: AdminSpacing.x18),
              _Group(
                title: 'Группы',
                children: [
                  for (final group in options.groups)
                    _ScopeTile(
                      label: group.name,
                      icon: FluentIcons.group,
                      selected: selected == group,
                      onPressed: () => onSelected(group),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Group({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AdminTypography.caption.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: AdminSpacing.x8),
        Wrap(
          spacing: AdminSpacing.x8,
          runSpacing: AdminSpacing.x8,
          children: children,
        ),
      ],
    );
  }
}

class _ScopeTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool blocked;
  final VoidCallback onPressed;

  const _ScopeTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.blocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return HoverButton(
      onPressed: onPressed,
      builder: (context, states) => Container(
        height: AdminSizes.controlHeight,
        padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.x10),
        decoration: BoxDecoration(
          color: selected
              ? colors.accentTint
              : (states.isHovered ? colors.cardBg : colors.surface),
          border: Border.all(
            color: selected ? colors.accent : colors.borderStrong,
          ),
          borderRadius: BorderRadius.circular(AdminRadius.control),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colors.textSecondary),
            const SizedBox(width: AdminSpacing.x6),
            Text(
              label,
              style: AdminTypography.bodySmall.copyWith(
                color: selected ? colors.accentDark : colors.text,
              ),
            ),
            if (blocked) ...[
              const SizedBox(width: AdminSpacing.x6),
              const AdminStatusTag(
                label: 'заблокирован',
                tone: AdminStatusTone.error,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
