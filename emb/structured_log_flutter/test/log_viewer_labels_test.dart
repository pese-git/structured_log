import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

void main() {
  group('LogViewerLabels', () {
    test('an empty set leaves every label to the skin', () {
      const labels = LogViewerLabels();

      expect(
        [
          labels.searchHint,
          labels.pause,
          labels.resume,
          labels.clear,
          labels.levelFilterLabel,
          labels.allCategories,
          labels.pageTitle,
          labels.emptyTitle,
          labels.emptyMessage,
          labels.noMatchesTitle,
          labels.noMatchesMessage,
          labels.clearFilters,
          labels.contextHeading,
          labels.copyContext,
          labels.close,
          labels.backToList,
        ],
        everyElement(isNull),
      );
    });

    test('copyWith replaces only the given field', () {
      String levelLabel(LogLevel? level) => level?.name ?? 'все';
      final original = LogViewerLabels(
        searchHint: 'Поиск',
        pause: 'Пауза',
        levelFilterLabel: levelLabel,
      );

      final copy = original.copyWith(pause: 'Стоп');

      expect(copy.pause, 'Стоп');
      expect(copy.searchHint, 'Поиск');
      expect(copy.levelFilterLabel, same(levelLabel));
      expect(copy.resume, isNull);
      expect(original.pause, 'Пауза');
    });

    test('every field survives copyWith without arguments', () {
      String levelLabel(LogLevel? level) => '';
      final original = LogViewerLabels(
        searchHint: '1',
        pause: '2',
        resume: '3',
        clear: '4',
        levelFilterLabel: levelLabel,
        allCategories: '5',
        pageTitle: '6',
        emptyTitle: '7',
        emptyMessage: '8',
        noMatchesTitle: '9',
        noMatchesMessage: '10',
        clearFilters: '11',
        contextHeading: '15',
        copyContext: '12',
        close: '13',
        backToList: '14',
      );

      final copy = original.copyWith();

      expect(
        [
          copy.searchHint,
          copy.pause,
          copy.resume,
          copy.clear,
          copy.allCategories,
          copy.pageTitle,
          copy.emptyTitle,
          copy.emptyMessage,
          copy.noMatchesTitle,
          copy.noMatchesMessage,
          copy.clearFilters,
          copy.contextHeading,
          copy.copyContext,
          copy.close,
          copy.backToList,
        ],
        [
          '1',
          '2',
          '3',
          '4',
          '5',
          '6',
          '7',
          '8',
          '9',
          '10',
          '11',
          '15',
          '12',
          '13',
          '14'
        ],
      );
      expect(copy.levelFilterLabel, same(levelLabel));
    });
  });
}
