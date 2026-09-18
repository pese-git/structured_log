import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../shared/api/dto/user_dto.dart';
import '../../resources/presentation/resources_section.dart'
    show ResourceBreadcrumb;
import 'user_failure_text.dart';
import 'users_cubit.dart';

/// Display name and password — the fields `UserDetailPage` does not already
/// own itself (`EditUser.dc.html`).
///
/// The mockup's email row — with its own change flow, a "подтверждён"/"уже
/// занят другой учётной записью" state, and a banner about the new address
/// needing confirmation — is not built: nothing in this stage ever collects
/// an email for a user (`CreateUserDialog` has no field for one, so
/// `UserDto.email` stays `null` for every account there is), so there is no
/// honest "current value" to show a change against. Shown read-only instead,
/// same as the username row, until account creation grows an email field of
/// its own to change it into.
///
/// Username, roles, block/unblock and delete stay on `UserDetailPage` — each
/// has its own authorization rule or its own confirmation, and mixing them
/// into this form would blur which button does which (mirrors the mockup's
/// own closing note: "Блокировка, удаление и выдача ролей выполняются на
/// экране пользователя").
class EditUserPage extends StatefulWidget {
  final UserDto user;
  final VoidCallback onBack;

  const EditUserPage({super.key, required this.user, required this.onBack});

  @override
  State<EditUserPage> createState() => _EditUserPageState();
}

class _EditUserPageState extends State<EditUserPage> {
  late final _displayName = TextEditingController(
    text: widget.user.displayName ?? '',
  );
  final _newPassword = TextEditingController();

  // Same reasoning as `UserDetailPage`'s: captured once, in `initState`,
  // rather than `context.read` inside `dispose()` — by then this page is
  // already deactivated (`UsersSection`'s `_go` swaps the whole subtree in
  // one frame), and Provider refuses to look up an ancestor through a
  // context in that state.
  late final UsersCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<UsersCubit>();
  }

  @override
  void dispose() {
    _displayName.dispose();
    _newPassword.dispose();
    _cubit.clearActionFailure();
    super.dispose();
  }

  Future<void> _save(BuildContext context) async {
    final displayName = _displayName.text.trim();
    final password = _newPassword.text;
    await _cubit.update(
      userId: widget.user.id,
      displayName: displayName.isEmpty ? null : displayName,
      password: password.isEmpty ? null : password,
    );
    // Stays on the page to show the reason on a refusal; a success has
    // nothing left to do here, so it returns to the detail page it came
    // from, the same way the mockup's own "Отмена" does.
    if (_cubit.state.actionFailure == null) widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final user = widget.user;
    final name = user.displayName ?? user.username;

    return BlocBuilder<UsersCubit, UsersState>(
      builder: (context, state) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AdminSpacing.x24,
            AdminSpacing.x18,
            AdminSpacing.x24,
            AdminSpacing.x24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ResourceBreadcrumb(
                parts: [
                  (label: 'Пользователи', onPressed: widget.onBack),
                  (label: name, onPressed: widget.onBack),
                  (label: 'Изменить', onPressed: null),
                ],
              ),
              const SizedBox(height: AdminSpacing.x10),
              Text(
                'Изменить учётную запись',
                style: AdminTypography.pageTitle.copyWith(color: colors.text),
              ),
              const SizedBox(height: AdminSpacing.x4),
              Text(
                'Доступно только администратору. Имя пользователя и роли этим '
                'экраном не меняются.',
                style: AdminTypography.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: AdminSpacing.x18),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (state.actionFailure != null) ...[
                      AdminBanner(
                        message: describeUserFailure(state.actionFailure!),
                        tone: AdminBannerTone.error,
                      ),
                      const SizedBox(height: AdminSpacing.x14),
                    ],
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
                            label: 'Имя пользователя',
                            value: user.username,
                            monospaceValue: true,
                          ),
                          AdminKeyValueRow(
                            label: 'Email',
                            value: user.email ?? '—',
                          ),
                          const SizedBox(height: AdminSpacing.x4),
                          AdminTextField(
                            label: 'Отображаемое имя',
                            controller: _displayName,
                          ),
                          const SizedBox(height: AdminSpacing.x14),
                          Text(
                            'Новый пароль (необязательно)',
                            style: AdminTypography.label.copyWith(
                              color: colors.text,
                            ),
                          ),
                          const SizedBox(height: AdminSpacing.x6),
                          Text(
                            'Немедленно завершит текущую сессию пользователя — '
                            'при следующем входе потребуется сменить этот '
                            'пароль на свой.',
                            style: AdminTypography.caption.copyWith(
                              color: colors.textSecondary,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: AdminSpacing.x10),
                          AdminTextField(
                            label: 'Пароль',
                            controller: _newPassword,
                            obscure: true,
                            placeholder: 'Не менять',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AdminSpacing.x14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AdminButton(
                          label: 'Отмена',
                          size: AdminButtonSize.dialog,
                          onPressed: state.saving ? null : widget.onBack,
                        ),
                        const SizedBox(width: AdminSpacing.x10),
                        AdminButton(
                          label: 'Сохранить изменения',
                          variant: AdminButtonVariant.accent,
                          size: AdminButtonSize.dialog,
                          onPressed: state.saving ? null : () => _save(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
