import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../shared/api/api_failure.dart';
import '../domain/log_filter.dart';
import '../domain/log_scope.dart';
import 'log_entry_detail_pane.dart';
import 'log_feed_bloc.dart';
import 'log_feed_event.dart';
import 'log_feed_state.dart';
import 'log_level_mapping.dart';
import 'scope_selector.dart';

/// The log screen, as `LogBrowser.dc.html` draws it: the scope and its
/// filters across the top, the feed on the left, one entry in full on the
/// right, and a strip under the feed saying what the live subscription is
/// doing.
///
/// The list is **reversed**, which is the one structural decision worth
/// knowing before reading the rest. Index 0 is the bottom — the newest entry —
/// so the live edge is offset 0 and the oldest entry held is at
/// `maxScrollExtent`. Everything the feed has to do falls out of that: an
/// entry appended while the reader is up in the history does not move the
/// viewport, an older page prepended at the far end does not move it either,
/// and returning to the live edge is a scroll to zero. A forward list would
/// need the scroll offset corrected by hand after every insertion, which is
/// where "the list jumped" bugs come from.
class LogBrowserPage extends StatefulWidget {
  const LogBrowserPage({super.key});

  @override
  State<LogBrowserPage> createState() => _LogBrowserPageState();
}

class _LogBrowserPageState extends State<LogBrowserPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  /// How close to either end counts as being there. One row's height, so the
  /// live edge is reached by scrolling to it rather than exactly onto it.
  static const _edgeSlack = 48.0;

  /// The last thing reported to the bloc, so a scroll gesture raises one event
  /// at its boundary instead of one per frame.
  bool? _atLiveEdge;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    context.read<LogFeedBloc>().add(const LogFeedEvent.started());
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final bloc = context.read<LogFeedBloc>();

    // Reversed list: the far end is the oldest entry held, so reaching it is
    // the request for the page before it.
    if (position.pixels >= position.maxScrollExtent - 200) {
      bloc.add(const LogFeedEvent.olderRequested());
    }

    final atEdge = position.pixels <= _edgeSlack;
    if (atEdge == _atLiveEdge) return;
    _atLiveEdge = atEdge;
    bloc.add(
      atEdge
          ? const LogFeedEvent.scrolledToBottom()
          : const LogFeedEvent.scrolledAwayFromBottom(),
    );
  }

  void _toLiveEdge() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return BlocConsumer<LogFeedBloc, LogFeedState>(
      // Following the live edge means staying at offset 0 as entries arrive.
      // Usually the reversed list keeps it there on its own; this covers the
      // case where it does not — a row taller than the viewport's remainder,
      // or an entry that landed while the list was settling.
      listenWhen: (before, after) =>
          after.mode is FeedFollowing &&
          after.entries.length > before.entries.length,
      listener: (context, state) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _toLiveEdge();
        });
      },
      builder: (context, state) {
        if (state.loadingOptions) {
          return const Center(child: AdminLoadingIndicator());
        }

        final options = state.options;
        if (options == null) {
          return AdminEmptyState(
            icon: FluentIcons.error_badge,
            title: 'Не удалось загрузить список областей',
            description: _failureText(state),
          );
        }

        final scope = state.scope;
        if (scope == null) {
          return ScopeSelector(
            options: options,
            selected: null,
            onSelected: (picked) => context.read<LogFeedBloc>().add(
              LogFeedEvent.scopeSelected(picked),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AdminSpacing.x24,
                AdminSpacing.x18,
                AdminSpacing.x24,
                AdminSpacing.x12,
              ),
              child: _Header(scope: scope),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.x24),
              child: _FilterBar(state: state, search: _search),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Its own width, not the window's: this pane sits beside
                    // a navigation rail whose width is not fixed, so the
                    // window says nothing useful about the room here
                    // (`AdminBreakpoints`, and the same rule as the viewer
                    // skins in `emb/`).
                    final split =
                        constraints.maxWidth >= AdminBreakpoints.masterDetail;
                    if (split) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: AdminSizes.masterListWidth,
                            child: _Feed(
                              state: state,
                              controller: _scroll,
                              onToLiveEdge: _toLiveEdge,
                            ),
                          ),
                          Container(width: 1, color: colors.border),
                          Expanded(child: _Detail(state: state)),
                        ],
                      );
                    }

                    // Narrow: the detail replaces the feed rather than
                    // squeezing beside it, and says how to get back
                    // (`LogBrowserNarrow.dc.html`).
                    if (state.selectedEntry != null) {
                      return _NarrowDetail(state: state);
                    }
                    return _Feed(
                      state: state,
                      controller: _scroll,
                      onToLiveEdge: _toLiveEdge,
                      showsDisclosure: true,
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _failureText(LogFeedState state) {
    return switch (state.failure) {
      null => 'Попробуйте обновить страницу.',
      ForbiddenFailure() => 'Нет доступа к этой области.',
      NetworkFailure() => 'Сервер недоступен. Проверьте подключение.',
      _ => 'Попробуйте ещё раз.',
    };
  }
}

/// Title, the scope being read, and the way back to the selector.
class _Header extends StatelessWidget {
  final LogScope scope;

  const _Header({required this.scope});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final label = switch (scope) {
      ProjectScope(:final name) => 'Проект: $name',
      GroupScope(:final name) => 'Группа: $name',
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        // Narrow, the pill gives up its width and the action gives up its
        // label — the header stays one line either way
        // (`LogBrowserNarrow.dc.html`).
        final compact = constraints.maxWidth < AdminBreakpoints.masterDetail;
        final pill = Container(
          height: AdminSizes.controlHeight,
          padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.x10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.accentTint,
            borderRadius: BorderRadius.circular(AdminRadius.control),
          ),
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: AdminTypography.label.copyWith(
              color: colors.accentDark,
              fontSize: 13,
            ),
          ),
        );

        return Row(
          children: [
            Text(
              'Логи',
              style: AdminTypography.pageTitle.copyWith(color: colors.text),
            ),
            SizedBox(width: compact ? AdminSpacing.x12 : AdminSpacing.x24),
            if (compact) Flexible(child: pill) else pill,
            const SizedBox(width: AdminSpacing.x10),
            if (compact)
              Tooltip(
                message: 'Изменить область',
                child: AdminButton(
                  label: '',
                  icon: FluentIcons.switch_widget,
                  onPressed: () => context.read<LogFeedBloc>().add(
                    const LogFeedEvent.scopeCleared(),
                  ),
                ),
              )
            else
              AdminButton(
                label: 'Изменить область',
                onPressed: () => context.read<LogFeedBloc>().add(
                  const LogFeedEvent.scopeCleared(),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  final LogFeedState state;
  final TextEditingController search;

  const _FilterBar({required this.state, required this.search});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<LogFeedBloc>();
    final filter = state.filter;
    void apply(LogFilter next) => bloc.add(LogFeedEvent.filterChanged(next));

    final paused = state.mode.isPaused;

    return AdminFilterBar(
      leading: AdminSearchField(
        controller: search,
        placeholder: 'Поиск по событию',
        // Applied on submit rather than on every keystroke: each change is a
        // full query plus a new subscription, and the server's `q` runs as a
        // LIKE over stored JSON.
        onChanged: (_) {},
        onCleared: () => apply(filter.copyWith(search: null)),
      ),
      filters: [
        AdminFilterChip(
          value: _levelLabel(filter.minLevel),
          hasMenu: true,
          selected: filter.minLevel != null,
          onPressed: () => _pickLevel(bloc, filter),
        ),
        if (filter.category != null)
          AdminFilterChip(
            label: 'Категория',
            value: filter.category!,
            selected: true,
            onCleared: () => apply(filter.copyWith(category: null)),
          ),
        if (filter.logger != null)
          AdminFilterChip(
            label: 'Logger',
            value: filter.logger!,
            selected: true,
            onCleared: () => apply(filter.copyWith(logger: null)),
          ),
        for (final entry in filter.context.entries)
          AdminFilterChip(
            label: entry.key,
            value: entry.value,
            selected: true,
            onCleared: () => apply(
              filter.copyWith(context: {...filter.context}..remove(entry.key)),
            ),
          ),
        AdminTimeRangeField(
          from: filter.from,
          to: filter.to,
          formatTime: _formatTime,
          onFromChanged: (value) => apply(filter.copyWith(from: value)),
          onToChanged: (value) => apply(filter.copyWith(to: value)),
        ),
        for (final field in _CorrelationField.values)
          if (field.read(filter) case final value?)
            AdminFilterChip(
              label: field.label,
              value: value,
              selected: true,
              onCleared: () => apply(field.clear(filter)),
            ),
        if (_CorrelationField.values.any((field) => field.read(filter) == null))
          AdminButton(
            label: '+ correlation id',
            onPressed: () => _addCorrelationId(context, bloc, filter),
          ),
      ],
      trailing: [
        AdminButton(
          label: 'Найти',
          variant: AdminButtonVariant.accent,
          onPressed: () => apply(
            filter.copyWith(search: search.text.isEmpty ? null : search.text),
          ),
        ),
        if (filter.isActive)
          AdminButton(
            label: 'Сбросить',
            onPressed: () {
              search.clear();
              apply(const LogFilter());
            },
          ),
        AdminLivePill(
          label: paused ? 'На паузе' : 'В реальном времени',
          tone: paused ? AdminLiveTone.paused : AdminLiveTone.live,
        ),
        AdminButton(
          label: paused ? 'Возобновить' : 'Пауза',
          onPressed: () => bloc.add(
            paused
                ? const LogFeedEvent.resumeRequested()
                : const LogFeedEvent.pauseRequested(),
          ),
        ),
      ],
    );
  }

  static String _levelLabel(String? level) {
    return switch (level) {
      null => 'Любой уровень',
      'trace' => 'Trace и выше',
      'debug' => 'Debug и выше',
      'info' => 'Info и выше',
      'warning' => 'Warning и выше',
      'error' => 'Error и выше',
      'critical' => 'Только critical',
      _ => level,
    };
  }

  void _pickLevel(LogFeedBloc bloc, LogFilter filter) {
    // The level is a floor, not an equality: `warning` also returns errors
    // and criticals, which is what the labels say.
    const levels = [null, 'debug', 'info', 'warning', 'error', 'critical'];
    final next = levels[(levels.indexOf(filter.minLevel) + 1) % levels.length];
    bloc.add(LogFeedEvent.filterChanged(filter.copyWith(minLevel: next)));
  }

  /// `09:00`, in the reader's own timezone — the boxes name a time, not an
  /// instant, and the reader is asking about their own day.
  static String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _addCorrelationId(
    BuildContext context,
    LogFeedBloc bloc,
    LogFilter filter,
  ) async {
    final available = [
      for (final field in _CorrelationField.values)
        if (field.read(filter) == null) field,
    ];
    if (available.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _CorrelationIdDialog(
        available: available,
        onAdd: (field, value) {
          Navigator.of(dialogContext).pop();
          bloc.add(LogFeedEvent.filterChanged(field.write(filter, value)));
        },
        onCancel: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }
}

/// One of the six identifiers `LogFilter` narrows by beyond level/category/
/// logger/search — `LogBrowser.dc.html`'s bare "+ correlation id" button
/// gives no interaction design to copy, so the shape here (pick a field, add
/// it as a removable chip) mirrors the arbitrary `context` filter chips
/// `_FilterBar` already draws immediately above it.
enum _CorrelationField {
  session('session_id'),
  request('request_id'),
  toolCall('tool_call_id'),
  message('message_id'),
  operation('operation_id'),
  // The one field that isn't a string — `LogFilter.connectionGeneration` is
  // an `int?`, so setting it goes through `int.parse` rather than a bare
  // assignment (`write` below), and the dialog only offers "Добавить" once
  // the typed value actually parses.
  connectionGeneration('connection_generation');

  const _CorrelationField(this.label);

  /// The wire name, which is also what an operator recognises from the
  /// entry detail pane's own "СТАНДАРТНЫЕ ПОЛЯ" section — shown as-is
  /// rather than translated, the same choice `_ActionTag` makes for audit
  /// actions.
  final String label;

  String? read(LogFilter filter) => switch (this) {
    _CorrelationField.session => filter.sessionId,
    _CorrelationField.request => filter.requestId,
    _CorrelationField.toolCall => filter.toolCallId,
    _CorrelationField.message => filter.messageId,
    _CorrelationField.operation => filter.operationId,
    _CorrelationField.connectionGeneration =>
      filter.connectionGeneration?.toString(),
  };

  LogFilter clear(LogFilter filter) => switch (this) {
    _CorrelationField.session => filter.copyWith(sessionId: null),
    _CorrelationField.request => filter.copyWith(requestId: null),
    _CorrelationField.toolCall => filter.copyWith(toolCallId: null),
    _CorrelationField.message => filter.copyWith(messageId: null),
    _CorrelationField.operation => filter.copyWith(operationId: null),
    _CorrelationField.connectionGeneration => filter.copyWith(
      connectionGeneration: null,
    ),
  };

  /// [value] is assumed valid for this field already — [_CorrelationIdDialog]
  /// only enables its submit button once it is.
  LogFilter write(LogFilter filter, String value) => switch (this) {
    _CorrelationField.session => filter.copyWith(sessionId: value),
    _CorrelationField.request => filter.copyWith(requestId: value),
    _CorrelationField.toolCall => filter.copyWith(toolCallId: value),
    _CorrelationField.message => filter.copyWith(messageId: value),
    _CorrelationField.operation => filter.copyWith(operationId: value),
    _CorrelationField.connectionGeneration => filter.copyWith(
      connectionGeneration: int.parse(value),
    ),
  };
}

class _CorrelationIdDialog extends StatefulWidget {
  final List<_CorrelationField> available;
  final void Function(_CorrelationField field, String value) onAdd;
  final VoidCallback onCancel;

  const _CorrelationIdDialog({
    required this.available,
    required this.onAdd,
    required this.onCancel,
  });

  @override
  State<_CorrelationIdDialog> createState() => _CorrelationIdDialogState();
}

class _CorrelationIdDialogState extends State<_CorrelationIdDialog> {
  late _CorrelationField _field = widget.available.first;
  final _value = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  bool get _isNumberField => _field == _CorrelationField.connectionGeneration;

  String? get _errorText {
    if (!_isNumberField) return null;
    final text = _value.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text) == null ? 'Значение должно быть числом' : null;
  }

  bool get _canSubmit {
    final text = _value.text.trim();
    if (text.isEmpty) return false;
    return !_isNumberField || int.tryParse(text) != null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return StatefulBuilder(
      builder: (context, setDialogState) => ContentDialog(
        constraints: const BoxConstraints(maxWidth: 420),
        title: Text(
          'Фильтр по correlation id',
          style: AdminTypography.sectionTitle.copyWith(color: colors.text),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Поле',
                style: AdminTypography.label.copyWith(color: colors.text),
              ),
              const SizedBox(height: AdminSpacing.x6),
              ComboBox<_CorrelationField>(
                value: _field,
                isExpanded: true,
                items: [
                  for (final field in widget.available)
                    ComboBoxItem(value: field, child: Text(field.label)),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => _field = value);
                },
              ),
              const SizedBox(height: AdminSpacing.x14),
              AdminTextField(
                label: 'Значение',
                controller: _value,
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
                errorText: _errorText,
              ),
            ],
          ),
        ),
        actions: [
          AdminButton(
            label: 'Отмена',
            size: AdminButtonSize.dialog,
            onPressed: widget.onCancel,
          ),
          AdminButton(
            label: 'Добавить',
            variant: AdminButtonVariant.accent,
            size: AdminButtonSize.dialog,
            onPressed: _canSubmit
                ? () => widget.onAdd(_field, _value.text.trim())
                : null,
          ),
        ],
      ),
    );
  }
}

class _Feed extends StatelessWidget {
  final LogFeedState state;
  final ScrollController controller;
  final VoidCallback onToLiveEdge;

  /// A chevron on every row. Only when tapping one leads somewhere — which
  /// on a narrow screen it does, because the detail takes the whole pane.
  final bool showsDisclosure;

  const _Feed({
    required this.state,
    required this.controller,
    required this.onToLiveEdge,
    this.showsDisclosure = false,
  });

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<LogFeedBloc>();

    if (state.loading) {
      return const Center(child: AdminLoadingIndicator());
    }

    if (state.entries.isEmpty) {
      // Two different things to say: a filter that matched nothing is not an
      // empty project.
      return AdminEmptyState(
        icon: FluentIcons.search,
        title: state.filter.isActive ? 'Ничего не найдено' : 'Записей пока нет',
        description: state.filter.isActive
            ? 'Под текущие фильтры не подходит ни одна запись.'
            : 'Как только приложение пришлёт первую запись, она появится здесь.',
      );
    }

    return Column(
      children: [
        if (state.loadingMore)
          const AdminFeedStatusStrip.loadingOlder(
            message: 'Загружаются более ранние записи…',
          ),
        Expanded(
          child: ListView.builder(
            controller: controller,
            // Index 0 is the bottom of the viewport — see the class doc.
            reverse: true,
            itemCount: state.entries.length,
            itemBuilder: (context, index) {
              final entry = state.entries[state.entries.length - 1 - index];
              return AdminLogEntryRow(
                level: logLevelOf(entry.level),
                time: _time(entry.receivedAt),
                event: entry.event,
                category: entry.category,
                selected: state.selectedEntryId == entry.id,
                onPressed: () => bloc.add(LogFeedEvent.entrySelected(entry.id)),
              );
            },
          ),
        ),
        _FeedStatus(state: state, onToLiveEdge: onToLiveEdge),
      ],
    );
  }

  /// `HH:mm:ss` in the reader's own timezone — the date is the same for
  /// everything on screen far more often than not.
  static String _time(DateTime utc) {
    final local = utc.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

/// The one strip under the feed. Which of the five it is, is the whole of
/// what the live half has to report.
class _FeedStatus extends StatelessWidget {
  final LogFeedState state;
  final VoidCallback onToLiveEdge;

  const _FeedStatus({required this.state, required this.onToLiveEdge});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<LogFeedBloc>();

    // A subscription the server closed for good outranks the mode: the feed
    // is not following anything, whatever the reader last asked for.
    final ended = state.liveEndReason;
    if (ended != null) {
      return AdminFeedStatusStrip.stalled(
        message: 'Живая трансляция остановлена',
        description: ended == 'project_blocked'
            ? 'Проект заблокирован — новые записи по нему больше не приходят. '
                  'Показанное ниже осталось от последней загрузки.'
            : 'Сервер закрыл подписку ($ended). Список ниже остался от '
                  'последней загрузки.',
        actionLabel: 'Перезагрузить и продолжить',
        onAction: () => bloc.add(const LogFeedEvent.reloadRequested()),
      );
    }

    return switch (state.mode) {
      FeedFollowing() => const AdminFeedStatusStrip.live(
        message: 'Лента в реальном времени — новые записи появляются снизу',
      ),
      FeedScrolledUp(:final unseen) when unseen > 0 =>
        AdminFeedStatusStrip.unseen(
          message: '$unseen ${_newEntries(unseen)} · перейти к свежим',
          onAction: () {
            onToLiveEdge();
            bloc.add(const LogFeedEvent.scrolledToBottom());
          },
        ),
      FeedScrolledUp() => const AdminFeedStatusStrip.live(
        message: 'Лента в реальном времени — новые записи появляются снизу',
      ),
      FeedPaused(overflowed: true) => AdminFeedStatusStrip.stalled(
        message: 'Пауза длилась слишком долго',
        description:
            'Часть событий не поместилась в буфер. Возобновление перезагрузит '
            'свежую страницу целиком, а не покажет неполный список.',
        actionLabel: 'Перезагрузить и продолжить',
        onAction: () => bloc.add(const LogFeedEvent.resumeRequested()),
      ),
      FeedPaused(:final buffered) => AdminFeedStatusStrip.held(
        message: 'Лента на паузе · накоплено $buffered ${_entries(buffered)}',
        actionLabel: 'Возобновить',
        onAction: () {
          bloc.add(const LogFeedEvent.resumeRequested());
          onToLiveEdge();
        },
      ),
    };
  }

  /// Russian needs three forms: "12 новых записей" reads wrong for 1 and
  /// for 22, and the canvas shows the count in both strips.
  static String _newEntries(int count) => switch (_form(count)) {
    _Plural.one => 'новая запись',
    _Plural.few => 'новые записи',
    _Plural.many => 'новых записей',
  };

  static String _entries(int count) => switch (_form(count)) {
    _Plural.one => 'запись',
    _Plural.few => 'записи',
    _Plural.many => 'записей',
  };

  static _Plural _form(int count) {
    final lastTwo = count % 100;
    final last = count % 10;
    if (lastTwo >= 11 && lastTwo <= 14) return _Plural.many;
    if (last == 1) return _Plural.one;
    if (last >= 2 && last <= 4) return _Plural.few;
    return _Plural.many;
  }
}

enum _Plural { one, few, many }

/// The selected entry, filling the pane, with the way back to the feed.
class _NarrowDetail extends StatelessWidget {
  final LogFeedState state;

  const _NarrowDetail({required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AdminSpacing.x14,
            AdminSpacing.x12,
            AdminSpacing.x14,
            AdminSpacing.x12,
          ),
          child: Row(
            children: [
              AdminButton(
                label: 'К ленте',
                icon: FluentIcons.back,
                onPressed: () => context.read<LogFeedBloc>().add(
                  const LogFeedEvent.entrySelected(null),
                ),
              ),
            ],
          ),
        ),
        Container(height: 1, color: colors.border),
        Expanded(child: _Detail(state: state)),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  final LogFeedState state;

  const _Detail({required this.state});

  @override
  Widget build(BuildContext context) {
    final entry = state.selectedEntry;
    if (entry == null) {
      return const AdminEmptyState(
        icon: FluentIcons.preview,
        title: 'Выберите запись',
        description:
            'Слева — лента; здесь будет запись целиком, вместе с '
            'произвольными полями, которые прислало приложение.',
      );
    }
    return LogEntryDetailPane(
      entry: entry,
      onClose: () => context.read<LogFeedBloc>().add(
        const LogFeedEvent.entrySelected(null),
      ),
    );
  }
}
