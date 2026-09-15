import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../shared/api/api_failure.dart';
import '../domain/log_filter.dart';
import 'log_browser_cubit.dart';
import 'log_browser_state.dart';
import 'log_entry_detail_pane.dart';
import 'log_level_mapping.dart';
import 'scope_selector.dart';

/// The log screen, as `LogBrowser.dc.html` draws it: filters across the top,
/// the feed on the left, one entry in full on the right.
///
/// The live subscription is section 22; this is the paged half. The feed is
/// already in reading order — oldest at the top — so the live edge will be
/// the bottom of the same list.
class LogBrowserPage extends StatefulWidget {
  const LogBrowserPage({super.key});

  @override
  State<LogBrowserPage> createState() => _LogBrowserPageState();
}

class _LogBrowserPageState extends State<LogBrowserPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    context.read<LogBrowserCubit>().start();
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  /// Older entries are fetched at the **top** — the feed reads as a history,
  /// so scrolling up goes back in time.
  void _onScroll() {
    if (_scroll.position.pixels > 200) return;
    context.read<LogBrowserCubit>().loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return BlocBuilder<LogBrowserCubit, LogBrowserState>(
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

        if (!state.hasScope) {
          return ScopeSelector(
            options: options,
            selected: state.scope,
            onSelected: context.read<LogBrowserCubit>().selectScope,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.x24),
              child: _FilterBar(state: state, search: _search),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: AdminSizes.masterListWidth,
                      child: _Feed(state: state, controller: _scroll),
                    ),
                    Container(width: 1, color: colors.border),
                    Expanded(child: _Detail(state: state)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _failureText(LogBrowserState state) {
    return switch (state.failure) {
      null => 'Попробуйте обновить страницу.',
      ForbiddenFailure() => 'Нет доступа к этой области.',
      NetworkFailure() => 'Сервер недоступен. Проверьте подключение.',
      _ => 'Попробуйте ещё раз.',
    };
  }
}

class _FilterBar extends StatelessWidget {
  final LogBrowserState state;
  final TextEditingController search;

  const _FilterBar({required this.state, required this.search});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LogBrowserCubit>();
    final filter = state.filter;

    return AdminFilterBar(
      leading: AdminSearchField(
        controller: search,
        placeholder: 'Поиск по событию',
        // Applied on submit rather than on every keystroke: each change is a
        // full query, and the server's `q` runs as a LIKE over stored JSON.
        onChanged: (_) {},
        onCleared: () => cubit.applyFilter(filter.copyWith(search: null)),
      ),
      filters: [
        AdminFilterChip(
          value: _levelLabel(filter.minLevel),
          hasMenu: true,
          selected: filter.minLevel != null,
          onPressed: () => _pickLevel(context, cubit, filter),
        ),
        if (filter.category != null)
          AdminFilterChip(
            label: 'Категория',
            value: filter.category!,
            selected: true,
            onCleared: () => cubit.applyFilter(filter.copyWith(category: null)),
          ),
        if (filter.logger != null)
          AdminFilterChip(
            label: 'Logger',
            value: filter.logger!,
            selected: true,
            onCleared: () => cubit.applyFilter(filter.copyWith(logger: null)),
          ),
        for (final entry in filter.context.entries)
          AdminFilterChip(
            label: entry.key,
            value: entry.value,
            selected: true,
            onCleared: () => cubit.applyFilter(
              filter.copyWith(context: {...filter.context}..remove(entry.key)),
            ),
          ),
      ],
      trailing: [
        AdminButton(
          label: 'Найти',
          variant: AdminButtonVariant.accent,
          onPressed: () => cubit.applyFilter(
            filter.copyWith(search: search.text.isEmpty ? null : search.text),
          ),
        ),
        if (filter.isActive)
          AdminButton(
            label: 'Сбросить',
            onPressed: () {
              search.clear();
              cubit.clearFilter();
            },
          ),
        AdminButton(
          label: 'Сменить область',
          onPressed: () => cubit.select(null),
          icon: FluentIcons.switch_widget,
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

  void _pickLevel(
    BuildContext context,
    LogBrowserCubit cubit,
    LogFilter filter,
  ) {
    // The level is a floor, not an equality: `warning` also returns errors
    // and criticals, which is what the labels say.
    const levels = [null, 'debug', 'info', 'warning', 'error', 'critical'];
    final next = levels[(levels.indexOf(filter.minLevel) + 1) % levels.length];
    cubit.applyFilter(filter.copyWith(minLevel: next));
  }
}

class _Feed extends StatelessWidget {
  final LogBrowserState state;
  final ScrollController controller;

  const _Feed({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LogBrowserCubit>();

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
          const Padding(
            padding: EdgeInsets.all(AdminSpacing.x8),
            child: AdminLoadingIndicator(inline: true),
          ),
        Expanded(
          child: ListView.builder(
            controller: controller,
            itemCount: state.entries.length,
            itemBuilder: (context, index) {
              final entry = state.entries[index];
              return AdminLogEntryRow(
                level: logLevelOf(entry.level),
                time: _time(entry.receivedAt),
                event: entry.event,
                category: entry.category,
                selected: state.selectedEntryId == entry.id,
                onPressed: () => cubit.select(entry.id),
              );
            },
          ),
        ),
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

class _Detail extends StatelessWidget {
  final LogBrowserState state;

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
      onClose: () => context.read<LogBrowserCubit>().select(null),
    );
  }
}
