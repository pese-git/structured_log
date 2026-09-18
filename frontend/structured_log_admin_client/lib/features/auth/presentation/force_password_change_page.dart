import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../l10n/l10n.dart';
import '../../../shared/l10n/locale_controller.dart';
import 'auth_language_switch.dart';
import 'auth_brand_panel.dart';
import 'change_password_cubit.dart';
import 'change_password_form.dart';

/// The screen the server puts in front of everything else while an account
/// still carries the password an administrator gave it.
///
/// It is not a dialog over the app: the app is not reachable. Every
/// management and query endpoint answers `403 must_change_password` until the
/// password is replaced, so the only two ways off this screen are changing it
/// and signing out (`specs/admin-client-auth`, `ForcePasswordChange.dc.html`).
///
/// This is also the very first thing a fresh deployment shows: the server
/// creates its first administrator with a generated password and that
/// password is temporary by construction (design.md decisions 42/49).
class ForcePasswordChangePage extends StatefulWidget {
  /// Raised once the password is changed — the gate is behind us and the app
  /// takes over. The session survives the change: the server retires the
  /// access token in hand, and the refresh token renews it on the next
  /// request.
  final VoidCallback onChanged;

  final VoidCallback onSignOut;

  /// The language switcher in the corner. Absent, there is no switcher.
  final LocaleController? localeController;

  const ForcePasswordChangePage({
    super.key,
    required this.onChanged,
    required this.onSignOut,
    this.localeController,
  });

  @override
  State<ForcePasswordChangePage> createState() =>
      _ForcePasswordChangePageState();
}

class _ForcePasswordChangePageState extends State<ForcePasswordChangePage> {
  @override
  void initState() {
    super.initState();
    context.read<ChangePasswordCubit>().loadUsername();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    final scroller = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: MediaQuery.sizeOf(context).width),
        child: SizedBox(
          width: 1160,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthBrandPanel(
                description: context.l10n.authForceBrandDescription,
              ),
              Expanded(
                child: ColoredBox(
                  color: colors.surface,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        vertical: AdminSpacing.x24,
                      ),
                      child: SizedBox(width: 340, child: _body(colors)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // The switcher lives outside the horizontal scroller: inside it, in a
    // window narrower than the artboard, it would sit past the right edge
    // and be reachable only by scrolling.
    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: Stack(
        children: [
          scroller,
          if (widget.localeController case final controller?)
            Positioned(
              top: AdminSpacing.x12,
              right: AdminSpacing.x18,
              child: AuthLanguageSwitch(controller: controller),
            ),
        ],
      ),
    );
  }

  Widget _body(AdminColors colors) {
    return BlocBuilder<ChangePasswordCubit, ChangePasswordState>(
      builder: (context, state) {
        if (state.changed) return _Changed(onContinue: widget.onChanged);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(FluentIcons.lock, size: 22, color: colors.accent),
                const SizedBox(width: AdminSpacing.x12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.authForceTitle,
                        style: AdminTypography.sectionTitle.copyWith(
                          color: colors.text,
                        ),
                      ),
                      const SizedBox(height: AdminSpacing.x6),
                      Text(
                        context.l10n.authForceIntro,
                        style: AdminTypography.bodySmall.copyWith(
                          color: colors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AdminSpacing.x24),
            ChangePasswordForm(submitLabel: context.l10n.authForceSubmit),
            const SizedBox(height: AdminSpacing.x18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    state.username == null
                        ? context.l10n.authSignedIn
                        : context.l10n.authSignedInAs(state.username!),
                    style: AdminTypography.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                HyperlinkButton(
                  onPressed: widget.onSignOut,
                  child: Text(
                    context.l10n.authSignOut,
                    style: AdminTypography.caption.copyWith(
                      color: colors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Changed extends StatelessWidget {
  final VoidCallback onContinue;

  const _Changed({required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(FluentIcons.completed, size: 28, color: colors.successFg),
        const SizedBox(height: AdminSpacing.x14),
        Text(
          context.l10n.authChangedTitle,
          textAlign: TextAlign.center,
          style: AdminTypography.sectionTitle.copyWith(color: colors.text),
        ),
        const SizedBox(height: AdminSpacing.x8),
        Text(
          context.l10n.authChangedBody,
          textAlign: TextAlign.center,
          style: AdminTypography.bodySmall.copyWith(
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AdminSpacing.x24),
        AdminButton(
          label: context.l10n.authChangedContinue,
          variant: AdminButtonVariant.accent,
          size: AdminButtonSize.dialog,
          onPressed: onContinue,
        ),
      ],
    );
  }
}
