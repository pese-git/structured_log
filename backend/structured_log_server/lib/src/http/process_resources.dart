import '../logging/setup.dart';

/// What only a running process has, and so only a running process passes: the
/// scope it opens then *owns* the database, the hash worker pool and the
/// logging, and closes them as it goes down.
///
/// Left out (tests, which build many handlers on databases of their own and
/// close those themselves, and share one hash pool between them), the scope owns
/// none of them and closing it touches nothing outside it.
class ProcessResources {
  final ServerLogging logging;

  const ProcessResources({required this.logging});
}
