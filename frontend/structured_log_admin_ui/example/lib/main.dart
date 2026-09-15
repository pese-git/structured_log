import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

/// Live documentation for `structured_log_admin_ui`: every atom, molecule and
/// organism drawn with a few sets of parameters, in both themes.
///
/// Serves the same purpose as `structured_log_material_example` and
/// `structured_log_fluent_example` do for the viewer skins — a place to see a
/// component before using it, and to check it against the Claude Design
/// canvas by eye.
void main() => runApp(const GalleryApp());

class GalleryApp extends StatefulWidget {
  const GalleryApp({super.key});

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  var _brightness = Brightness.light;

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'structured_log_admin_ui',
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.of(_brightness),
      home: GalleryPage(
        brightness: _brightness,
        onBrightnessChanged: (value) => setState(() => _brightness = value),
      ),
    );
  }
}

class GalleryPage extends StatefulWidget {
  final Brightness brightness;
  final ValueChanged<Brightness> onBrightnessChanged;

  const GalleryPage({
    super.key,
    required this.brightness,
    required this.onBrightnessChanged,
  });

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  final _search = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _email = TextEditingController();
  var _navIndex = 0;
  var _selectedRow = 1;

  @override
  void dispose() {
    _search.dispose();
    _username.dispose();
    _password.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(widget.brightness);

    return AdminAppShell(
      title: 'Галерея компонентов',
      accountName: 'Jana Novak',
      accountRole: 'Администратор',
      selectedIndex: _navIndex,
      onSelected: (index) => setState(() => _navIndex = index),
      sections: const [
        AdminNavSection(
          title: 'Обзор',
          items: [
            AdminNavItem(icon: FluentIcons.view_dashboard, label: 'Дашборд'),
          ],
        ),
        AdminNavSection(
          title: 'Администрирование',
          items: [
            AdminNavItem(icon: FluentIcons.people, label: 'Пользователи'),
            AdminNavItem(icon: FluentIcons.group, label: 'Группы'),
          ],
        ),
        AdminNavSection(
          title: 'Логи',
          items: [
            AdminNavItem(icon: FluentIcons.search, label: 'Поиск логов'),
          ],
        ),
      ],
      content: ListView(
        padding: const EdgeInsets.fromLTRB(
          AdminSpacing.x24,
          0,
          AdminSpacing.x24,
          AdminSpacing.x28,
        ),
        children: [
          _Section(
            title: 'Тема',
            child: AdminLabeledToggle(
              label: 'Тёмная тема',
              description: 'Канвас светлый; тёмные значения выведены',
              value: widget.brightness == Brightness.dark,
              onChanged: (value) => widget.onBrightnessChanged(
                value ? Brightness.dark : Brightness.light,
              ),
            ),
          ),
          _Section(
            title: 'Atoms · AdminLogLevelBadge',
            child: Wrap(
              spacing: AdminSpacing.x8,
              runSpacing: AdminSpacing.x8,
              children: [
                for (final level in AdminLogLevel.values)
                  AdminLogLevelBadge(level: level),
              ],
            ),
          ),
          _Section(
            title: 'Atoms · AdminButton',
            child: Wrap(
              spacing: AdminSpacing.x8,
              runSpacing: AdminSpacing.x8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AdminButton(
                  label: 'Создать',
                  onPressed: () {},
                  variant: AdminButtonVariant.accent,
                ),
                AdminButton(label: 'Обновить', onPressed: () {}),
                AdminButton(
                  label: 'Удалить',
                  onPressed: () {},
                  variant: AdminButtonVariant.danger,
                  size: AdminButtonSize.dialog,
                ),
                AdminButton(
                  label: 'Открыть',
                  onPressed: () {},
                  size: AdminButtonSize.tonal,
                  icon: FluentIcons.open_in_new_window,
                ),
                const AdminButton(label: 'Недоступно', onPressed: null),
              ],
            ),
          ),
          _Section(
            title: 'Atoms · AdminTag, AdminLoadingIndicator',
            child: Row(
              children: [
                const AdminTag(label: 'owner'),
                const SizedBox(width: AdminSpacing.x8),
                AdminTag(label: 'admin', foreground: colors.accentDark),
                const SizedBox(width: AdminSpacing.x18),
                const AdminLoadingIndicator(inline: true),
                const SizedBox(width: AdminSpacing.x18),
                const AdminLoadingIndicator(),
              ],
            ),
          ),
          _Section(
            title: 'Molecules · AdminTextField',
            child: SizedBox(
              width: 340,
              child: Column(
                children: [
                  AdminTextField(
                    label: 'Имя пользователя',
                    controller: _username,
                    placeholder: 'dana.kim',
                  ),
                  const SizedBox(height: AdminSpacing.x18),
                  AdminTextField(
                    label: 'Пароль',
                    controller: _password,
                    obscure: true,
                    labelAction: Text(
                      'Забыли пароль?',
                      style: AdminTypography.bodySmall.copyWith(
                        color: colors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: AdminSpacing.x18),
                  AdminTextField(
                    label: 'Email',
                    controller: _email,
                    errorText: 'Укажите email — он понадобится для '
                        'восстановления пароля',
                  ),
                ],
              ),
            ),
          ),
          _Section(
            title: 'Molecules · AdminBanner',
            child: SizedBox(
              width: 480,
              child: Column(
                children: [
                  const AdminBanner(
                    tone: AdminBannerTone.error,
                    message: 'Неверное имя пользователя или пароль. '
                        'Попробуйте ещё раз.',
                  ),
                  const SizedBox(height: AdminSpacing.x10),
                  const AdminBanner(
                    tone: AdminBannerTone.warning,
                    message: 'Слишком много попыток входа. Следующая будет '
                        'принята через 00:43.',
                  ),
                  const SizedBox(height: AdminSpacing.x10),
                  AdminBanner(
                    message: 'Email этой учётной записи ещё не подтверждён.',
                    action: AdminButton(
                      label: 'Отправить письмо ещё раз',
                      onPressed: () {},
                      size: AdminButtonSize.tonal,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _Section(
            title: 'Molecules · AdminStatusTag',
            child: Wrap(
              spacing: AdminSpacing.x8,
              runSpacing: AdminSpacing.x8,
              children: const [
                AdminStatusTag(label: 'Активен', tone: AdminStatusTone.success),
                AdminStatusTag(
                  label: 'Временный пароль',
                  tone: AdminStatusTone.warning,
                ),
                AdminStatusTag(
                  label: 'Заблокирован',
                  tone: AdminStatusTone.error,
                ),
                AdminStatusTag(label: 'Черновик'),
              ],
            ),
          ),
          _Section(
            title: 'Molecules · AdminQuotaBar',
            child: Column(
              children: [
                const AdminQuotaBar(
                  label: 'Записей (max_entries)',
                  usageLabel: '842',
                  limitLabel: '1 000',
                  fraction: 0.84,
                ),
                const SizedBox(height: AdminSpacing.x18),
                const AdminQuotaBar(
                  label: 'Объём (max_bytes)',
                  usageLabel: '128 МБ',
                  limitLabel: '500 МБ',
                  fraction: 0.26,
                ),
                const SizedBox(height: AdminSpacing.x18),
                const AdminQuotaBar(
                  label: 'Объём (квота не задана)',
                  usageLabel: '128 МБ',
                ),
              ],
            ),
          ),
          _Section(
            title: 'Molecules · AdminKeyValueRow',
            child: Column(
              children: const [
                AdminKeyValueRow(label: 'category', value: 'webhooks'),
                AdminKeyValueRow(
                  label: 'request_id',
                  value: '9f2c-4ab1-8e77',
                  monospaceValue: true,
                ),
                AdminKeyValueRow(label: 'status_code', value: '504'),
              ],
            ),
          ),
          _Section(
            title: 'Organisms · AdminFilterBar',
            child: AdminFilterBar(
              leading: AdminSearchField(
                controller: _search,
                placeholder: 'Поиск по событию',
              ),
              filters: [
                const AdminFilterChip(
                  value: 'Warning and above',
                  hasMenu: true,
                ),
                const AdminFilterChip(
                  label: 'Категория',
                  value: 'payments',
                  selected: true,
                ),
                AdminFilterChip(
                  label: 'Logger',
                  value: 'webhook.sender',
                  onCleared: () {},
                ),
              ],
            ),
          ),
          _Section(
            title: 'Molecules · AdminLivePill',
            child: Row(
              children: const [
                AdminLivePill(label: 'В реальном времени'),
                SizedBox(width: AdminSpacing.x10),
                AdminLivePill(label: 'На паузе', tone: AdminLiveTone.paused),
              ],
            ),
          ),
          _Section(
            title: 'Organisms · AdminFeedStatusStrip',
            child: Column(
              children: [
                const AdminFeedStatusStrip.live(
                  message:
                      'Лента в реальном времени — новые записи появляются снизу',
                ),
                const SizedBox(height: AdminSpacing.x10),
                AdminFeedStatusStrip.unseen(
                  message: '12 новых записей · перейти к свежим',
                  onAction: () {},
                ),
                const SizedBox(height: AdminSpacing.x10),
                AdminFeedStatusStrip.held(
                  message: 'Лента на паузе · накоплено 38 записей',
                  actionLabel: 'Возобновить',
                  onAction: () {},
                ),
                const SizedBox(height: AdminSpacing.x10),
                AdminFeedStatusStrip.stalled(
                  message: 'Пауза длилась слишком долго',
                  description:
                      'Часть событий не поместилась в буфер. Возобновление '
                      'перезагрузит свежую страницу целиком, а не покажет '
                      'неполный список.',
                  actionLabel: 'Перезагрузить и продолжить',
                  onAction: () {},
                ),
                const SizedBox(height: AdminSpacing.x10),
                const AdminFeedStatusStrip.loadingOlder(
                  message: 'Загружаются более ранние записи…',
                ),
              ],
            ),
          ),
          _Section(
            title: 'Organisms · AdminLogEntryRow',
            child: Column(
              children: [
                const AdminLogEntryRow(
                  level: AdminLogLevel.error,
                  time: '09:12:55',
                  event: 'Webhook delivery failed after 3 attempts',
                  category: 'webhooks',
                  selected: true,
                ),
                AdminLogEntryRow(
                  level: AdminLogLevel.info,
                  time: '09:13:18',
                  event: 'Refund requested',
                  category: 'payments',
                  onPressed: () {},
                ),
                // Narrow layouts open an entry on its own screen instead of
                // beside the list, and the chevron is what says so.
                AdminLogEntryRow(
                  level: AdminLogLevel.warning,
                  time: '09:13:44',
                  event: 'Slow query',
                  category: 'db',
                  showsDisclosure: true,
                  onPressed: () {},
                ),
              ],
            ),
          ),
          _Section(
            title: 'Organisms · AdminResourceRow',
            child: Column(
              children: [
                AdminResourceRow(
                  identifier: 'j.novak',
                  title: 'Jana Novak',
                  subtitle: 'admin · payments-api',
                  selected: _selectedRow == 0,
                  onPressed: () => setState(() => _selectedRow = 0),
                  tags: const [
                    AdminStatusTag(
                      label: 'Активен',
                      tone: AdminStatusTone.success,
                    ),
                  ],
                  actions: [
                    AdminButton(
                      label: 'Изменить',
                      onPressed: () {},
                      size: AdminButtonSize.tonal,
                    ),
                  ],
                ),
                AdminResourceRow(
                  identifier: 'r.silva',
                  title: 'Rita Silva',
                  subtitle: 'user · mobile-ios',
                  selected: _selectedRow == 1,
                  onPressed: () => setState(() => _selectedRow = 1),
                  tags: const [
                    AdminStatusTag(
                      label: 'Заблокирован',
                      tone: AdminStatusTone.error,
                    ),
                  ],
                  actions: [
                    AdminButton(
                      label: 'Разблокировать',
                      onPressed: () {},
                      size: AdminButtonSize.tonal,
                    ),
                  ],
                ),
                const AdminResourceRow(
                  icon: FluentIcons.permissions,
                  title: 'CI pipeline',
                  subtitle: 'создан 12.09.2026',
                ),
              ],
            ),
          ),
          _Section(
            title: 'Organisms · AdminConfirmDialog',
            child: Row(
              children: [
                AdminButton(
                  label: 'Отозвать ключ',
                  onPressed: () => _showConfirm(context, destructive: true),
                  variant: AdminButtonVariant.danger,
                ),
                const SizedBox(width: AdminSpacing.x8),
                AdminButton(
                  label: 'Подтвердить действие',
                  onPressed: () => _showConfirm(context, destructive: false),
                ),
              ],
            ),
          ),
          _Section(
            title: 'Atoms · AdminEmptyState',
            // The empty state is drawn centred in a whole content pane and
            // carries that pane's 64px breathing room; the gallery gives it a
            // comparable box rather than squeezing it into a section-sized
            // one.
            child: SizedBox(
              height: 360,
              child: AdminEmptyState(
                icon: FluentIcons.group,
                title: 'Групп пока нет',
                description:
                    'Создайте первую группу, чтобы начать управлять командами '
                    'и проектами',
                action: AdminButton(
                  label: 'Создать группу',
                  onPressed: () {},
                  variant: AdminButtonVariant.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showConfirm(BuildContext context, {required bool destructive}) {
    showDialog<void>(
      context: context,
      builder: (context) => AdminConfirmDialog(
        title: destructive ? 'Отозвать секретный ключ?' : 'Применить квоту?',
        message: destructive
            ? 'Ключ «CI pipeline» перестанет приниматься сервером немедленно. '
                'Действие необратимо.'
            : 'Новые значения вступят в силу сразу; уже принятые записи не '
                'удаляются.',
        confirmLabel: destructive ? 'Отозвать' : 'Применить',
        destructive: destructive,
        onConfirm: () => Navigator.of(context).pop(),
        onCancel: () => Navigator.of(context).pop(),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return Padding(
      padding: const EdgeInsets.only(bottom: AdminSpacing.x28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AdminTypography.label.copyWith(color: colors.text),
          ),
          const SizedBox(height: AdminSpacing.x12),
          child,
        ],
      ),
    );
  }
}
