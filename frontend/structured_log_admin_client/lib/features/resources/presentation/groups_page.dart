import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

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
                          'Группы',
                          overflow: TextOverflow.ellipsis,
                          style: AdminTypography.pageTitle.copyWith(
                            color: colors.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: AdminSpacing.x12),
                      AdminButton(
                        label: compact ? 'Группа' : 'Создать группу',
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
        title: 'Не удалось загрузить группы',
        description: describeApiFailure(state.failure!),
      );
    }
    if (state.isEmpty) {
      return const AdminEmptyState(
        icon: FluentIcons.group,
        title: 'Групп пока нет',
        description:
            'Группа владеет проектами. Создайте первую, чтобы завести в ней '
            'проект и начать принимать логи.',
      );
    }

    return ListView.separated(
      itemCount: state.groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: AdminSpacing.x10),
      itemBuilder: (context, index) {
        final group = state.groups[index];
        return AdminResourceRow(
          icon: FluentIcons.group,
          title: group.name,
          subtitle: 'Создана ${formatDate(group.createdAt)}',
          onPressed: () => onOpen(group),
          actions: [
            AdminButton(
              label: 'Открыть',
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
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: cubit,
        child: BlocBuilder<GroupsCubit, GroupsState>(
          builder: (builderContext, state) {
            // Closing is driven by the state rather than by the caller of
            // `create`: the cubit reloads the list after a success, and the
            // dialog should be gone before that finishes.
            if (state.created) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              });
            }
            return NameDialog(
              title: 'Новая группа',
              fieldLabel: 'Название группы',
              confirmLabel: 'Создать группу',
              description:
                  'Проекты создаются внутри группы. Создавать группы может '
                  'только администратор.',
              submitting: state.creating,
              errorText: state.createFailure == null
                  ? null
                  : describeApiFailure(state.createFailure!),
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
