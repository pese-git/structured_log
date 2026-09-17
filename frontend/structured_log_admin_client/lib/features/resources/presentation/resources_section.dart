import 'package:cherrypick/cherrypick.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../role_assignments/application/manage_role_assignments.dart';
import '../application/manage_resources.dart';
import 'group_detail_cubit.dart';
import 'group_detail_page.dart';
import 'groups_cubit.dart';
import 'groups_page.dart';
import 'project_detail_cubit.dart';
import 'project_detail_page.dart';

/// Where inside the section the reader is.
///
/// Three places, each reached from the one before, which is exactly what the
/// artboards' breadcrumb says: `Группы / Acme Corp / payments-api`.
sealed class _Location {
  const _Location();
}

class _Groups extends _Location {
  const _Groups();
}

class _GroupDetail extends _Location {
  final int groupId;
  final String groupName;

  const _GroupDetail(this.groupId, this.groupName);
}

class _ProjectDetail extends _Location {
  final int projectId;
  final String groupName;

  const _ProjectDetail(this.projectId, this.groupName);
}

/// The administration half of the app: groups, their projects, and the keys
/// an application sends logs with.
///
/// A stack kept in state rather than a nested `Navigator`. The breadcrumb is
/// the navigation here — it names every level at once — and a widget that
/// draws it wants the whole path, not just the top of a stack it cannot see
/// into.
class ResourcesSection extends StatefulWidget {
  final Scope scope;

  /// Opens the log browser on a project. The project screen's primary action
  /// is "Открыть логи", and logs are the other section of the app.
  final void Function(int projectId, String projectName) onOpenLogs;

  const ResourcesSection({
    super.key,
    required this.scope,
    required this.onOpenLogs,
  });

  @override
  State<ResourcesSection> createState() => _ResourcesSectionState();
}

class _ResourcesSectionState extends State<ResourcesSection> {
  _Location _at = const _Groups();

  void _go(_Location location) => setState(() => _at = location);

  @override
  Widget build(BuildContext context) {
    return switch (_at) {
      _Groups() => BlocProvider(
        key: const ValueKey('groups'),
        create: (_) =>
            GroupsCubit(widget.scope.resolve<ManageGroups>())..load(),
        child: GroupsPage(
          onOpen: (group) => _go(_GroupDetail(group.id, group.name)),
        ),
      ),
      _GroupDetail(:final groupId, :final groupName) => BlocProvider(
        key: ValueKey('group-$groupId'),
        create: (_) => GroupDetailCubit(
          projects: widget.scope.resolve<ManageProjects>(),
          roleAssignments: widget.scope.resolve<ManageRoleAssignments>(),
          groupId: groupId,
        )..load(),
        child: GroupDetailPage(
          groupName: groupName,
          onBack: () => _go(const _Groups()),
          onOpenProject: (project) =>
              _go(_ProjectDetail(project.id, groupName)),
        ),
      ),
      _ProjectDetail(:final projectId, :final groupName) => BlocProvider(
        key: ValueKey('project-$projectId'),
        create: (_) => ProjectDetailCubit(
          projects: widget.scope.resolve<ManageProjects>(),
          keys: widget.scope.resolve<ManageSecretKeys>(),
          roleAssignments: widget.scope.resolve<ManageRoleAssignments>(),
          projectId: projectId,
        )..load(),
        child: ProjectDetailPage(
          groupName: groupName,
          onBackToGroups: () => _go(const _Groups()),
          onOpenLogs: widget.onOpenLogs,
        ),
      ),
    };
  }
}

/// `Группы / Acme Corp / payments-api`, with every level but the last one
/// clickable.
class ResourceBreadcrumb extends StatelessWidget {
  /// Label and, for everything but the last, where it goes.
  final List<({String label, VoidCallback? onPressed})> parts;

  const ResourceBreadcrumb({super.key, required this.parts});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final children = <Widget>[];

    for (final (index, part) in parts.indexed) {
      if (index > 0) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.x6),
            child: Text(
              '/',
              style: AdminTypography.caption.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ),
        );
      }
      children.add(
        part.onPressed == null
            ? Text(
                part.label,
                style: AdminTypography.caption.copyWith(color: colors.text),
              )
            : HyperlinkButton(
                onPressed: part.onPressed,
                child: Text(
                  part.label,
                  style: AdminTypography.caption.copyWith(color: colors.accent),
                ),
              ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}
