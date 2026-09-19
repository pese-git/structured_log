import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../l10n/l10n.dart';
import '../../../shared/api/dto/resource_dto.dart';
import '../../../shared/api/dto/user_dto.dart';
import 'group_detail_cubit.dart';
import 'resource_dialogs.dart';
import 'resource_failure_text.dart';
import 'resources_section.dart';

/// One group, the projects inside it, its teams, and who holds a role on it
/// (`GroupDetail.dc.html`).
///
/// Teams (13.2a) and role assignments (the artboard's «Доступ» section,
/// уточнение 17.09.2026) are both here: who is in which team, granted/
/// revoked from this side, the mirror of the reduced grant form on the
/// target user's own screen (`lib/features/users/`).
class GroupDetailPage extends StatelessWidget {
  final String groupName;
  final bool isAdmin;
  final VoidCallback onBack;
  final ValueChanged<ProjectDto> onOpenProject;

  const GroupDetailPage({
    super.key,
    required this.groupName,
    required this.isAdmin,
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
                  (label: context.l10n.resGroups, onPressed: onBack),
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
              // `GroupDetail.dc.html` puts Команды/Проекты side by side —
              // reproduced above `masterDetail`, the same threshold the
              // resource rows themselves use for their own width; below it,
              // stacked as before (narrow states are out of scope here, see
              // AGENTS.md on GroupDetail/ProjectDetail/AuditLog).
              LayoutBuilder(
                builder: (context, constraints) {
                  final teams = _Teams(groupName: groupName, state: state);
                  final projects = _Projects(
                    onOpenProject: onOpenProject,
                    onCreate: () => _create(context),
                    state: state,
                  );
                  if (constraints.maxWidth < AdminBreakpoints.masterDetail) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        teams,
                        const SizedBox(height: AdminSpacing.x24),
                        projects,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: teams),
                      const SizedBox(width: AdminSpacing.x18),
                      Expanded(child: projects),
                    ],
                  );
                },
              ),
              const SizedBox(height: AdminSpacing.x24),
              _Access(groupName: groupName, isAdmin: isAdmin, state: state),
            ],
          ),
        );
      },
    );
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
                  : describeApiFailure(
                      builderContext.l10n,
                      state.createFailure!,
                    ),
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

class _Teams extends StatelessWidget {
  final String groupName;
  final GroupDetailState state;

  const _Teams({required this.groupName, required this.state});

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
                context.l10n.resTeams,
                overflow: TextOverflow.ellipsis,
                style: AdminTypography.label.copyWith(color: colors.text),
              ),
            ),
            const SizedBox(width: AdminSpacing.x12),
            AdminButton(
              label: context.l10n.resTeam,
              icon: FluentIcons.add,
              onPressed: () => _create(context),
            ),
          ],
        ),
        const SizedBox(height: AdminSpacing.x12),
        if (state.teams.isEmpty)
          AdminEmptyState(
            icon: FluentIcons.people,
            title: context.l10n.resNoTeams,
            description: context.l10n.resNoTeamsHint,
          )
        else
          for (final team in state.teams) ...[
            AdminResourceRow(
              icon: FluentIcons.people,
              title: team.name,
              onPressed: () => _openMembers(context, team),
              actions: [
                AdminButton(
                  label: context.l10n.resMembers,
                  size: AdminButtonSize.tonal,
                  onPressed: () => _openMembers(context, team),
                ),
              ],
            ),
            const SizedBox(height: AdminSpacing.x10),
          ],
      ],
    );
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
            // Once only — same reasoning as `GroupDetailPage._create`.
            if (state.teamCreated && !closing) {
              closing = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              });
            }
            return NameDialog(
              title: builderContext.l10n.resNewTeam,
              fieldLabel: builderContext.l10n.resTeamNameLabel,
              confirmLabel: builderContext.l10n.resCreateTeam,
              groupLabel: groupName,
              description: builderContext.l10n.resNewTeamNote,
              submitting: state.creatingTeam,
              errorText: state.createTeamFailure == null
                  ? null
                  : describeApiFailure(
                      builderContext.l10n,
                      state.createTeamFailure!,
                    ),
              onSubmit: (name) {
                if (name.isNotEmpty) cubit.createTeam(name);
              },
              onCancel: () => Navigator.of(dialogContext).pop(),
            );
          },
        ),
      ),
    );
    cubit.teamDialogClosed();
  }

  Future<void> _openMembers(BuildContext context, TeamDto team) async {
    final cubit = context.read<GroupDetailCubit>();
    await cubit.openTeamMembers(team.id);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: cubit,
        child: BlocBuilder<GroupDetailCubit, GroupDetailState>(
          builder: (builderContext, state) {
            return TeamMembersDialog(
              teamName: team.name,
              groupName: groupName,
              members: state.teamMembers,
              loading: state.loadingTeamMembers,
              changing: state.changingTeamMembers,
              errorText: state.teamMembersFailure == null
                  ? null
                  : describeApiFailure(
                      builderContext.l10n,
                      state.teamMembersFailure!,
                    ),
              searchUsers: cubit.searchUsers,
              onAdd: cubit.addTeamMember,
              onRemove: cubit.removeTeamMember,
              onClose: () => Navigator.of(dialogContext).pop(),
            );
          },
        ),
      ),
    );
    cubit.closeTeamMembers();
  }
}

class _Projects extends StatelessWidget {
  final ValueChanged<ProjectDto> onOpenProject;
  final VoidCallback onCreate;
  final GroupDetailState state;

  const _Projects({
    required this.onOpenProject,
    required this.onCreate,
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
                context.l10n.resProjects,
                overflow: TextOverflow.ellipsis,
                style: AdminTypography.label.copyWith(color: colors.text),
              ),
            ),
            const SizedBox(width: AdminSpacing.x12),
            AdminButton(
              label: context.l10n.resProjectShort,
              icon: FluentIcons.add,
              onPressed: onCreate,
            ),
          ],
        ),
        const SizedBox(height: AdminSpacing.x12),
        _body(context),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (state.loading) {
      return const Center(child: AdminLoadingIndicator());
    }
    if (state.failure != null) {
      return AdminEmptyState(
        icon: FluentIcons.error_badge,
        title: context.l10n.resProjectsLoadFailed,
        description: describeApiFailure(context.l10n, state.failure!),
      );
    }
    if (state.isEmpty) {
      return AdminEmptyState(
        icon: FluentIcons.build_queue,
        title: context.l10n.resNoProjects,
        description: context.l10n.resNoProjectsHint,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final project in state.projects) ...[
          AdminResourceRow(
            icon: FluentIcons.build_queue,
            title: project.name,
            subtitle: _quotaLine(context.l10n, project),
            tags: [
              if (project.isBlocked)
                AdminStatusTag(
                  label: context.l10n.resBlocked,
                  tone: AdminStatusTone.error,
                ),
            ],
            onPressed: () => onOpenProject(project),
            actions: [
              AdminButton(
                label: context.l10n.resOpen,
                size: AdminButtonSize.tonal,
                onPressed: () => onOpenProject(project),
              ),
            ],
          ),
          const SizedBox(height: AdminSpacing.x10),
        ],
        if (state.hasMoreProjects)
          Padding(
            padding: const EdgeInsets.all(AdminSpacing.x12),
            child: Center(
              child: state.loadingMoreProjects
                  ? const AdminLoadingIndicator()
                  : AdminButton(
                      label: context.l10n.resShowMore,
                      icon: FluentIcons.chevron_down,
                      onPressed: context
                          .read<GroupDetailCubit>()
                          .loadMoreProjects,
                    ),
            ),
          ),
      ],
    );
  }

  /// The list endpoint carries no usage counters — only the project's own
  /// endpoint computes them — so this line states the limits, and the project
  /// screen states the usage against them.
  static String _quotaLine(AppLocalizations l10n, ProjectDto project) {
    final entries = project.maxEntries == null
        ? l10n.resQuotaNoEntryLimit
        : l10n.resQuotaEntryLimit(formatCount(project.maxEntries!));
    return l10n.resQuotaLine(entries, l10n.resDaysCount(project.retentionDays));
  }
}

class _Access extends StatelessWidget {
  final String groupName;
  final bool isAdmin;
  final GroupDetailState state;

  const _Access({
    required this.groupName,
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
                context.l10n.resAccess,
                overflow: TextOverflow.ellipsis,
                style: AdminTypography.label.copyWith(color: colors.text),
              ),
            ),
            const SizedBox(width: AdminSpacing.x12),
            AdminButton(
              label: context.l10n.resGrantAccess,
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
            message: describeApiFailure(context.l10n, state.accessFailure!),
            tone: AdminBannerTone.error,
          ),
          const SizedBox(height: AdminSpacing.x12),
        ],
        if (state.roleAssignments.isEmpty)
          AdminEmptyState(
            icon: FluentIcons.permissions,
            title: context.l10n.resNoAccess,
            description: context.l10n.resNoAccessGroupHint,
          )
        else
          for (final grant in state.roleAssignments) ...[
            AdminResourceRow(
              icon: FluentIcons.contact,
              title: subjectLabel(context.l10n, grant),
              subtitle: grant.role,
              actions: [
                AdminButton(
                  label: context.l10n.resRevoke,
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
              scopeLabel: builderContext.l10n.resGroupPrefix(groupName),
              submitting: state.grantingAccess,
              isGlobalAdmin: isAdmin,
              errorText: state.accessFailure == null
                  ? null
                  : describeApiFailure(
                      builderContext.l10n,
                      state.accessFailure!,
                    ),
              searchUsers: cubit.searchUsers,
              searchTeams: cubit.searchTeams,
              onGrant: (values) async {
                await cubit.grantAccess(
                  subjectType: values.subjectType,
                  subjectId: values.subjectId,
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
    final l10n = context.l10n;
    final subject =
        grant.subjectName ??
        (grant.subjectType == 'team'
            ? l10n.resSubjectTeamGen(grant.subjectId)
            : l10n.resSubjectUserGen(grant.subjectId));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AdminConfirmDialog(
        title: l10n.resRevokeAccessTitle(subject),
        message: l10n.resRevokeRoleGroup(grant.role),
        confirmLabel: l10n.resRevoke,
        cancelLabel: l10n.resCancel,
        destructive: true,
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    if (confirmed ?? false) await cubit.revokeAccess(grant.id);
  }
}
