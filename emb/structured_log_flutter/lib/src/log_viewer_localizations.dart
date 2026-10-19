import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:structured_log/structured_log.dart';

import 'log_viewer_labels.dart';

/// Ready-made [LogViewerLabels] for English and Russian, delivered through
/// Flutter's [Localizations] — optional: register [delegate] and every log
/// viewer skin picks the labels up for the app's locale, with no labels
/// passed by hand.
///
/// ```dart
/// MaterialApp(
///   localizationsDelegates: const [
///     LogViewerLocalizations.delegate,
///     GlobalMaterialLocalizations.delegate,
///     // ...
///   ],
///   supportedLocales: const [Locale('en'), Locale('ru')],
///   // ...
/// )
/// ```
///
/// English is an empty [LogViewerLabels]: every skin keeps its own English
/// wording. Russian sets every field, one wording shared by all skins. A
/// `labels` passed to a viewer widget still wins, field by field (see
/// [resolve]), so an app can take Russian from here and change one phrase.
///
/// Needs neither `flutter_localizations` nor `intl`: the delegate is
/// hand-written and loads synchronously.
class LogViewerLocalizations {
  const LogViewerLocalizations(this.labels);

  /// The labels for this locale.
  final LogViewerLabels labels;

  /// The delegate to add to the app's `localizationsDelegates`. Supports the
  /// `en` and `ru` language codes; for any other language it isn't loaded
  /// and the viewer behaves as if it weren't registered.
  static const LocalizationsDelegate<LogViewerLocalizations> delegate =
      _LogViewerLocalizationsDelegate();

  /// The language codes [delegate] supports.
  static const supportedLanguageCodes = ['en', 'ru'];

  /// The localizations of the closest [Localizations] ancestor, or `null`
  /// when [delegate] isn't registered (or doesn't support the locale).
  static LogViewerLocalizations? of(BuildContext context) =>
      Localizations.of<LogViewerLocalizations>(
        context,
        LogViewerLocalizations,
      );

  /// [labels] with every `null` field filled from the registered
  /// [delegate]'s labels for [context]'s locale; [labels] unchanged when
  /// the delegate isn't registered. A field still `null` afterwards means
  /// "the skin's default".
  ///
  /// Every viewer skin widget that shows labels calls this, so resolving an
  /// already-resolved set is harmless.
  static LogViewerLabels resolve(
    BuildContext context,
    LogViewerLabels labels,
  ) {
    final fallback = of(context)?.labels;
    if (fallback == null) return labels;
    return LogViewerLabels(
      searchHint: labels.searchHint ?? fallback.searchHint,
      pause: labels.pause ?? fallback.pause,
      resume: labels.resume ?? fallback.resume,
      clear: labels.clear ?? fallback.clear,
      levelFilterLabel: labels.levelFilterLabel ?? fallback.levelFilterLabel,
      allCategories: labels.allCategories ?? fallback.allCategories,
      pageTitle: labels.pageTitle ?? fallback.pageTitle,
      emptyTitle: labels.emptyTitle ?? fallback.emptyTitle,
      emptyMessage: labels.emptyMessage ?? fallback.emptyMessage,
      noMatchesTitle: labels.noMatchesTitle ?? fallback.noMatchesTitle,
      noMatchesMessage: labels.noMatchesMessage ?? fallback.noMatchesMessage,
      clearFilters: labels.clearFilters ?? fallback.clearFilters,
      contextHeading: labels.contextHeading ?? fallback.contextHeading,
      copyContext: labels.copyContext ?? fallback.copyContext,
      close: labels.close ?? fallback.close,
      backToList: labels.backToList ?? fallback.backToList,
    );
  }

  /// English: nothing set, so every skin keeps its own wording.
  static const english = LogViewerLabels();

  /// Russian, one wording for every skin.
  static const russian = LogViewerLabels(
    searchHint: 'Поиск по событиям и категориям…',
    pause: 'Пауза',
    resume: 'Продолжить',
    clear: 'Очистить',
    levelFilterLabel: _russianLevelFilterLabel,
    allCategories: 'Все категории',
    pageTitle: 'Логи',
    emptyTitle: 'Логов пока нет',
    emptyMessage:
        'Записи появятся здесь, как только приложение запишет первое событие.',
    noMatchesTitle: 'Ничего не найдено по фильтру',
    noMatchesMessage:
        'Измените поисковый запрос или сбросьте фильтры, чтобы увидеть все записи.',
    clearFilters: 'Сбросить фильтры',
    contextHeading: 'КОНТЕКСТ',
    copyContext: 'Скопировать контекст',
    close: 'Закрыть',
    backToList: 'Назад к списку',
  );

  /// Level names are [LogLevel] identifiers and stay as they are; only "all"
  /// is translated.
  static String _russianLevelFilterLabel(LogLevel? minLevel) {
    if (minLevel == null) return 'Все';
    final name = minLevel.name;
    return '${name[0].toUpperCase()}${name.substring(1)}+';
  }
}

class _LogViewerLocalizationsDelegate
    extends LocalizationsDelegate<LogViewerLocalizations> {
  const _LogViewerLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      LogViewerLocalizations.supportedLanguageCodes
          .contains(locale.languageCode);

  @override
  Future<LogViewerLocalizations> load(Locale locale) => SynchronousFuture(
        LogViewerLocalizations(
          locale.languageCode == 'ru'
              ? LogViewerLocalizations.russian
              : LogViewerLocalizations.english,
        ),
      );

  @override
  bool shouldReload(_LogViewerLocalizationsDelegate old) => false;
}
