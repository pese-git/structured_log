import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../l10n/l10n.dart';
import '../../../shared/l10n/locale_controller.dart';
import 'auth_language_switch.dart';
import '../domain/auth_failure.dart';
import 'auth_brand_panel.dart';
import 'login_cubit.dart';
import 'login_state.dart';

/// The sign-in screen, as `Login.dc.html` draws it: a brand panel on the left,
/// the form centred in the surface on the right.
///
/// The artboard also carries links to "Забыли пароль?" and
/// "Зарегистрироваться". Neither is here: password recovery is section 18 and
/// self-registration section 12.2, both later stages, and the endpoints behind
/// them do not exist yet. A link that goes nowhere is worse than its absence.
///
/// The layout is the canvas's desktop one, with no narrow variant — see task
/// 23.9. Below the width it was drawn at, the page scrolls sideways rather
/// than overflowing; that is a fallback, not a designed state.
class LoginPage extends StatefulWidget {
  /// The deployment this window talks to, shown under the form as the
  /// artboard does — an operator running several needs to see which one this
  /// is. `null` hides the line rather than leaving a label with nothing after
  /// it.
  final String? serverLabel;

  /// Set when the user arrives here because a session could not be renewed,
  /// rather than by opening the app. The artboard has its own banner for it.
  final bool sessionExpired;

  /// The language switcher in the corner. Absent, there is no switcher.
  final LocaleController? localeController;

  const LoginPage({
    super.key,
    required this.serverLabel,
    this.sessionExpired = false,
    this.localeController,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<LoginCubit>().submit(
      username: _username.text,
      password: _password.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.sizeOf(context).width,
          ),
          child: SizedBox(
            width: 1160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthBrandPanel(
                  description: context.l10n.authLoginBrandDescription,
                ),
                Expanded(
                  child: ColoredBox(
                    color: colors.surface,
                    child: Stack(
                      children: [
                        Center(
                          child: SizedBox(
                            width: 340,
                            child: _buildForm(colors),
                          ),
                        ),
                        if (widget.localeController case final controller?)
                          Positioned(
                            top: AdminSpacing.x12,
                            right: AdminSpacing.x18,
                            child: AuthLanguageSwitch(controller: controller),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(AdminColors colors) {
    return BlocBuilder<LoginCubit, LoginState>(
      builder: (context, state) {
        final cubit = context.read<LoginCubit>();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.authLoginTitle,
              style: AdminTypography.pageTitle.copyWith(color: colors.text),
            ),
            const SizedBox(height: AdminSpacing.x4),
            Text(
              context.l10n.authLoginSubtitle,
              style: AdminTypography.body.copyWith(color: colors.textSecondary),
            ),
            // The expiry notice yields to a failure from an actual attempt:
            // once the user has tried and been refused, why they got here is
            // no longer the useful thing to say.
            if (state.failure != null) ...[
              const SizedBox(height: AdminSpacing.x18),
              _FailureBanner(
                failure: state.failure!,
                retryAfter: state.retryAfter,
              ),
            ] else if (widget.sessionExpired) ...[
              const SizedBox(height: AdminSpacing.x18),
              AdminBanner(message: context.l10n.authSessionExpiredBanner),
            ],
            const SizedBox(height: AdminSpacing.x18),
            AdminTextField(
              label: context.l10n.authUsernameLabel,
              controller: _username,
              autofocus: true,
              enabled: !state.submitting,
              onChanged: (_) => cubit.clearFailure(),
              onSubmitted: _submit,
            ),
            const SizedBox(height: AdminSpacing.x18),
            AdminTextField(
              label: context.l10n.authPasswordLabel,
              controller: _password,
              obscure: true,
              enabled: !state.submitting,
              onChanged: (_) => cubit.clearFailure(),
              onSubmitted: _submit,
            ),
            const SizedBox(height: AdminSpacing.x18),
            AdminButton(
              label: _submitLabel(context.l10n, state),
              variant: AdminButtonVariant.accent,
              // A null callback is how the button renders disabled — while a
              // request is in flight, and while a limiter is counting down.
              onPressed: state.canSubmit ? _submit : null,
            ),
            if (widget.serverLabel != null) ...[
              const SizedBox(height: AdminSpacing.x18),
              Text(
                context.l10n.authServerLine(widget.serverLabel!),
                textAlign: TextAlign.center,
                style: AdminTypography.caption.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _submitLabel(AppLocalizations l10n, LoginState state) {
    if (state.submitting) return l10n.authSubmittingLabel;
    if (state.retryAfter > Duration.zero) {
      return l10n.authSignInWithWait(_formatWait(state.retryAfter));
    }
    return l10n.authSignIn;
  }
}

/// `mm:ss`, as the artboard shows the countdown.
String _formatWait(Duration duration) {
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class _FailureBanner extends StatelessWidget {
  final AuthFailure failure;
  final Duration retryAfter;

  const _FailureBanner({required this.failure, required this.retryAfter});

  @override
  Widget build(BuildContext context) {
    return switch (failure) {
      InvalidCredentialsFailure() => AdminBanner(
        tone: AdminBannerTone.error,
        // Which of the two was wrong is not said — the server does not say
        // either, and naming it would let anyone enumerate accounts.
        message: context.l10n.authInvalidCredentials,
      ),
      EmailNotVerifiedFailure() => AdminBanner(
        message: context.l10n.authEmailNotVerified,
      ),
      RateLimitedAuthFailure() => AdminBanner(
        tone: AdminBannerTone.warning,
        message: context.l10n.authRateLimited(_formatWait(retryAfter)),
      ),
      // Neither of the next two interpolates the failure's `message`. It is
      // the HTTP client's or the server's own diagnostic — English, long, and
      // about CORS preflights — which belongs in the log, not in front of
      // someone trying to sign in.
      NetworkAuthFailure() => AdminBanner(
        tone: AdminBannerTone.error,
        message: context.l10n.authNetworkFailure,
      ),
      UnexpectedAuthFailure() => AdminBanner(
        tone: AdminBannerTone.error,
        message: context.l10n.authUnexpectedFailure,
      ),
    };
  }
}
