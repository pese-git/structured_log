import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/shared/l10n/locale_controller.dart';

void main() {
  test('follows the browser until a language is chosen', () {
    final controller = LocaleController(store: InMemoryLocaleStore());

    expect(controller.locale, isNull);
  });

  test('a remembered language is used from the first frame', () {
    final controller = LocaleController(store: InMemoryLocaleStore('ru'));

    expect(controller.locale, const Locale('ru'));
  });

  test('a remembered language the client has no translation of is ignored', () {
    final controller = LocaleController(store: InMemoryLocaleStore('de'));

    expect(controller.locale, isNull);
  });

  test('choosing stores the choice and tells the app', () {
    final store = InMemoryLocaleStore();
    final controller = LocaleController(store: store);
    var notified = 0;
    controller.addListener(() => notified++);

    controller.select(const Locale('en'));

    expect(controller.locale, const Locale('en'));
    expect(store.read(), 'en');
    expect(notified, 1);
  });

  test('going back to the browser default forgets the choice', () {
    final store = InMemoryLocaleStore('ru');
    final controller = LocaleController(store: store);

    controller.select(null);

    expect(controller.locale, isNull);
    expect(store.read(), isNull);
  });

  test('choosing what is already chosen is not a change', () {
    final controller = LocaleController(store: InMemoryLocaleStore('ru'));
    var notified = 0;
    controller.addListener(() => notified++);

    controller.select(const Locale('ru'));

    expect(notified, 0);
  });
}
