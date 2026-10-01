# structured_log_http

*Читать на [русском](README.ru.md).*

> **This package has been renamed to
> [`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync)
> and is discontinued.** It receives no further releases. This last version
> contains no code of its own: it re-exports `structured_log_remote_sync`, so
> existing code keeps compiling and behaves exactly as before, while the
> analyzer points every use at the new name.

## Moving over

Behaviour does not change — only the package, the import and one class name.

1. In `pubspec.yaml`:

   ```yaml
   dependencies:
     structured_log_remote_sync: ^0.1.0   # was: structured_log_http
   ```

2. In code:

   ```dart
   // was: import 'package:structured_log_http/structured_log_http.dart';
   import 'package:structured_log_remote_sync/structured_log_remote_sync.dart';

   // was: HttpLogOutput(...)
   final output = RemoteSyncLogOutput(
     serverUrl: 'https://logs.example.com',
     projectSecretKey: 'slk_...',
   );
   ```

`BatchSender` and `BatchResult` keep their names.

Documentation, configuration and the full API now live with
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync)
and on the [project site](https://structured-log.openidealab.com).

## License

MIT — see [LICENSE](LICENSE).
