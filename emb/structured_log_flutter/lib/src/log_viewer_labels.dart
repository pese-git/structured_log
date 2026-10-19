import 'package:flutter/foundation.dart' show immutable;
import 'package:structured_log/structured_log.dart';

/// The user-visible strings of a log viewer skin (`structured_log_material`,
/// `structured_log_fluent`, `structured_log_cupertino`), so an app can show
/// the viewer in its own language.
///
/// Every field is optional: `null` means "the skin's own default", and the
/// defaults deliberately differ between skins (each picked wording that fits
/// its design system — e.g. Fluent's level filter reads "Debug and above"
/// where Material's reads "Debug+"). Each field's documentation lists the
/// default of every skin that shows it. A field a skin doesn't show
/// ([close] outside Material, [backToList] outside Fluent) is simply not
/// read, so one object fits all three skins.
///
/// This package ships no translations and depends on no localization
/// framework: fill the fields from whatever the app already uses (`gen-l10n`,
/// constants, ...).
///
/// ```dart
/// MaterialLogViewer(
///   controller: controller,
///   labels: LogViewerLabels(
///     searchHint: 'Поиск по событиям и категориям…',
///     pause: 'Пауза',
///     resume: 'Продолжить',
///     clear: 'Очистить',
///     levelFilterLabel: (level) => level == null ? 'Все' : '${level.name}+',
///   ),
/// )
/// ```
@immutable
class LogViewerLabels {
  const LogViewerLabels({
    this.searchHint,
    this.pause,
    this.resume,
    this.clear,
    this.levelFilterLabel,
    this.allCategories,
    this.pageTitle,
    this.emptyTitle,
    this.emptyMessage,
    this.noMatchesTitle,
    this.noMatchesMessage,
    this.clearFilters,
    this.contextHeading,
    this.copyContext,
    this.close,
    this.backToList,
  });

  /// The search field's placeholder.
  ///
  /// Material, Cupertino: `Search events, categories…`. Fluent: `Search`.
  final String? searchHint;

  /// The label of the action that pauses the live stream.
  ///
  /// Material, Fluent: a tooltip. Cupertino: the icon button's semantics
  /// label. Default in all three: `Pause`.
  final String? pause;

  /// The label of the action that resumes a paused live stream.
  ///
  /// Shown the same way as [pause]. Default in all three: `Resume`.
  final String? resume;

  /// The label of the action that clears every entry.
  ///
  /// Shown the same way as [pause]. Default in all three: `Clear all`.
  final String? clear;

  /// The label of a level-filter option: `minLevel` is the option's minimum
  /// level, or `null` for the option that shows every level.
  ///
  /// Called once per option the skin offers. Material, Cupertino: `All`,
  /// `Debug+`, `Info+`, `Warning+`, `Error+`. Fluent: `All levels`,
  /// `Debug and above`, ... `Error and above`.
  final String Function(LogLevel? minLevel)? levelFilterLabel;

  /// The category filter's "every category" option.
  ///
  /// Material, Cupertino: `All`. Fluent: `All types`. A non-null `allLabel`
  /// passed straight to the category filter widget wins over this.
  final String? allCategories;

  /// The full-screen page's title (`*LogViewerPage`). Default in all three:
  /// `Logs`.
  final String? pageTitle;

  /// The empty state's title when nothing has been logged yet. Default in
  /// all three: `No logs yet`.
  final String? emptyTitle;

  /// The empty state's explanation when nothing has been logged yet.
  ///
  /// Default in all three: `Logs will appear here as soon as your app emits
  /// its first event.`
  final String? emptyMessage;

  /// The empty state's title when entries exist but none pass the filters.
  ///
  /// Material, Cupertino: `No logs match the current filter`. Fluent:
  /// `No results found`.
  final String? noMatchesTitle;

  /// The empty state's explanation when entries exist but none pass the
  /// filters.
  ///
  /// Material, Cupertino: `Try a different search term, or clear the active
  /// filters to see everything.` Fluent: `No log entries match the current filter.`
  final String? noMatchesMessage;

  /// The action that resets every filter. Default in all three:
  /// `Clear filters`.
  final String? clearFilters;

  /// The heading above the context key/value list in the detail view.
  /// Default in all three: `CONTEXT`.
  final String? contextHeading;

  /// The detail view's action that copies the entry's context.
  ///
  /// Material: `Copy context`. Fluent, Cupertino: `Copy`.
  final String? copyContext;

  /// The Material detail sheet's close action. Default: `Close`. Not shown
  /// by Fluent or Cupertino.
  final String? close;

  /// The tooltip of Fluent's "back to the list" button in the narrow
  /// layout. Default: `Back to list`. Not shown by Material or Cupertino
  /// (Cupertino's back button belongs to `CupertinoNavigationBar` and is
  /// localized through the app's `CupertinoLocalizations`).
  final String? backToList;

  /// A copy of these labels with the given fields replaced.
  LogViewerLabels copyWith({
    String? searchHint,
    String? pause,
    String? resume,
    String? clear,
    String Function(LogLevel? minLevel)? levelFilterLabel,
    String? allCategories,
    String? pageTitle,
    String? emptyTitle,
    String? emptyMessage,
    String? noMatchesTitle,
    String? noMatchesMessage,
    String? clearFilters,
    String? contextHeading,
    String? copyContext,
    String? close,
    String? backToList,
  }) {
    return LogViewerLabels(
      searchHint: searchHint ?? this.searchHint,
      pause: pause ?? this.pause,
      resume: resume ?? this.resume,
      clear: clear ?? this.clear,
      levelFilterLabel: levelFilterLabel ?? this.levelFilterLabel,
      allCategories: allCategories ?? this.allCategories,
      pageTitle: pageTitle ?? this.pageTitle,
      emptyTitle: emptyTitle ?? this.emptyTitle,
      emptyMessage: emptyMessage ?? this.emptyMessage,
      noMatchesTitle: noMatchesTitle ?? this.noMatchesTitle,
      noMatchesMessage: noMatchesMessage ?? this.noMatchesMessage,
      clearFilters: clearFilters ?? this.clearFilters,
      contextHeading: contextHeading ?? this.contextHeading,
      copyContext: copyContext ?? this.copyContext,
      close: close ?? this.close,
      backToList: backToList ?? this.backToList,
    );
  }
}
