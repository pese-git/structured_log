import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Copies [entry]'s context (`key: value` per line, in [contextEntries]'
/// order) to the clipboard, then calls [onCopied] with [entry] — only once
/// the write succeeded and only while [context] is still mounted, so the app
/// never confirms a copy that didn't happen or for a view that's gone.
///
/// A failed write (the clipboard can be unavailable on the web) is reported
/// through [FlutterError.reportError] rather than left as an unhandled
/// `Future` error.
Future<void> copyEntryContext(
  BuildContext context,
  Map<String, dynamic> entry,
  List<MapEntry<String, dynamic>> contextEntries,
  void Function(Map<String, dynamic> entry)? onCopied,
) async {
  final text = contextEntries.map((e) => '${e.key}: ${e.value}').join('\n');
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'structured_log_fluent',
        context: ErrorDescription("while copying a log entry's context"),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  onCopied?.call(entry);
}
