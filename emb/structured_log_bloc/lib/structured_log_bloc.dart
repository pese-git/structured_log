/// Logs what blocs and cubits do through `structured_log`.
///
/// See [StructuredLogBlocObserver] — a `BlocObserver` to install as
/// `Bloc.observer`. It depends on `package:bloc` only, so it works the same
/// in a `flutter_bloc` app and in pure Dart.
library;

export 'src/bloc_observer.dart'
    show
        BlocLogLevels,
        BlocValueDescriber,
        StructuredLogBlocObserver,
        defaultBlocValueMaxLength,
        describeBlocValue;
