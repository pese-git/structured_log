import 'locale_controller.dart';

/// Off the web there is nowhere to keep a preference — this client is built
/// for the browser only — so the choice lasts as long as the process does.
LocaleStore createLocaleStore() => InMemoryLocaleStore();
