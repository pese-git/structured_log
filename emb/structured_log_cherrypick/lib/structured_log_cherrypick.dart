/// Logs what the cherrypick DI container does through `structured_log`.
///
/// See [StructuredLogCherryPickObserver] — a `CherryPickObserver` to install
/// with `CherryPick.setGlobalObserver` or hand to a `Scope`.
library;

export 'src/cherrypick_observer.dart'
    show DiLogLevels, StructuredLogCherryPickObserver;
