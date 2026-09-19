import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../l10n/formatting.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/api/dto/resource_dto.dart';
import 'groups_cubit.dart';
import 'resource_dialogs.dart';
import 'resource_failure_text.dart';

/// The list of groups, and the way to add one (`Groups.dc.html`).
///
/// Creating a group is an administrator's privilege, and this client has no
/// way to know whether the caller is one: there is no endpoint that reports
/// the caller's own roles in this stage. So the action is offered and a
/// refusal is explained — the server stays the source of truth, which is what
/// `specs/admin-client-resource-management` asks for either way.
class GroupsPage extends StatelessWidget {
  final ValueChanged<GroupDto> onOpen;

  const GroupsPage({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return BlocBuilder<GroupsCubit, GroupsState>(
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
              LayoutBuilder(
                builder: (context, constraints) {
                  // Narrow, the action keeps its icon and loses most of its
                  // label; the title takes what is left rather than being
                  // painted over (`GroupsNarrow.dc.html`).
                  final compact =
                      constraints.maxWidth < AdminBreakpoints.masterDetail;
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.resGroups,
                          overflow: TextOverflow.ellipsis,
                          style: AdminTypography.pageTitle.copyWith(
                            color: colors.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: AdminSpacing.x12),
                      AdminButton(
                        label: compact
                            ? context.l10n.resGroup
                            : context.l10n.resCreateGroup,
                        icon: FluentIcons.add,
                        variant: AdminButtonVariant.accent,
                        size: AdminButtonSize.dialog,
                        onPressed: () => _create(context),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AdminSpacing.x18),
              Expanded(child: _body(context, state)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, GroupsState state) {
    if (state.loading) {
      return const Center(child: AdminLoadingIndicator());
    }
    if (state.failure != null) {
      return AdminEmptyState(
        icon: FluentIcons.error_badge,
        title: context.l10n.resGroupsLoadFailed,
        description: describeApiFailure(context.l10n, state.failure!),
      );
    }
    if (state.isEmpty) {
      return AdminEmptyState(
        icon: FluentIcons.group,
        title: context.l10n.resNoGroups,
        description: context.l10n.resNoGroupsHint,
      );
    }

    return ListView.separated(
      // One extra slot at the end for the "show more" row, while there is
      // more to show.
      itemCount: state.groups.length + (state.hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: AdminSpacing.x10),
      itemBuilder: (context, index) {
        if (index == state.groups.length) {
          return Padding(
            padding: const EdgeInsets.all(AdminSpacing.x18),
            child: Center(
              child: state.loadingMore
                  ? const AdminLoadingIndicator()
                  : AdminButton(
                      label: context.l10n.resShowMore,
                      icon: FluentIcons.chevron_down,
                      onPressed: context.read<GroupsCubit>().loadMore,
                    ),
            ),
          );
        }
        final group = state.groups[index];
        return AdminResourceRow(
          icon: FluentIcons.group,
          title: group.name,
          subtitle: context.l10n.resCreatedOn(
            formatDate(context.l10n, group.createdAt),
          ),
          onPressed: () => onOpen(group),
          actions: [
            AdminButton(
              label: context.l10n.resOpen,
              size: AdminButtonSize.tonal,
              onPressed: () => onOpen(group),
            ),
          ],
        );
      },
    );
  }

  Future<void> _create(BuildContext context) async {
    final cubit = context.read<GroupsCubit>();
    var closing = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: cubit,
        child: BlocBuilder<GroupsCubit, GroupsState>(
          builder: (builderContext, state) {
            // Closing is driven by the state rather than by the caller of
            // `create`: the cubit reloads the list after a success, and the
            // dialog should be gone before that finishes.
            //
            // Once, though — `closing` is what makes it once. This builder
            // runs on every state change while the dialog is up, and that
            // reload is itself a second change, so without the flag two pops
            // are queued and the second one takes whatever is on top by then.
            // The same shape cost the secret-key dialog the only copy of a
            // key it will ever show (`project_detail_page.dart`).
            if (state.created && !closing) {
              closing = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              });
            }
            return NameDialog(
              title: builderContext.l10n.resNewGroup,
              fieldLabel: builderContext.l10n.resGroupNameLabel,
              confirmLabel: builderContext.l10n.resCreateGroup,
              description: builderContext.l10n.resNewGroupNote,
              submitting: state.creating,
              errorText: state.createFailure == null
                  ? null
                  : describeApiFailure(
                      builderContext.l10n,
                      state.createFailure!,
                    ),
              onSubmit: (name) {
                if (name.isNotEmpty) cubit.create(name);
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
