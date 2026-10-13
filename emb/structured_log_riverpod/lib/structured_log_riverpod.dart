/// Logs what Riverpod providers do through `structured_log`.
///
/// See [StructuredLogRiverpodObserver] — a `ProviderObserver` to pass to
/// `ProviderContainer(observers: [...])` or `ProviderScope(observers: [...])`.
/// It depends on `package:riverpod` only, so it works the same in a
/// `flutter_riverpod` app and in pure Dart. Riverpod 3 only.
library;

export 'src/riverpod_observer.dart'
    show
        RiverpodLogLevels,
        RiverpodValueDescriber,
        StructuredLogRiverpodObserver,
        defaultRiverpodValueMaxLength,
        describeRiverpodValue;
