# structured_log_http

*Read in [English](README.md).*

> **Пакет переименован в
> [`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync)
> и больше не развивается.** Новых версий не будет. В этой последней версии нет
> собственного кода: она реэкспортирует `structured_log_remote_sync`, поэтому
> существующий код продолжает собираться и работает как прежде, а анализатор
> указывает на новое имя при каждом использовании.

## Переход

Поведение не меняется — только пакет, импорт и одно имя класса.

1. В `pubspec.yaml`:

   ```yaml
   dependencies:
     structured_log_remote_sync: ^0.2.0   # было: structured_log_http
   ```

2. В коде:

   ```dart
   // было: import 'package:structured_log_http/structured_log_http.dart';
   import 'package:structured_log_remote_sync/structured_log_remote_sync.dart';

   // было: HttpLogOutput(...)
   final output = RemoteSyncLogOutput(
     serverUrl: 'https://logs.example.com',
     projectSecretKey: 'slk_...',
   );
   ```

`BatchSender` и `BatchResult` сохранили свои имена.

Документация, настройки и полный API теперь живут у
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync)
и на [сайте проекта](https://structured-log.openidealab.com).

## Лицензия

MIT — см. [LICENSE](LICENSE).
