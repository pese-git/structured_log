// The whole point of this package is the deprecated names it still answers
// to, so using them here is the test, not a slip.
// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package

import 'package:structured_log/structured_log.dart' show LogLevel;
import 'package:structured_log_http/structured_log_http.dart';
import 'package:structured_log_remote_sync/structured_log_remote_sync.dart'
    show RemoteSyncLogOutput;
import 'package:test/test.dart';

void main() {
  test('HttpLogOutput builds the renamed RemoteSyncLogOutput', () async {
    final delivered = <Map<String, dynamic>>[];
    final output = HttpLogOutput(
      serverUrl: 'https://logs.example.com',
      projectSecretKey: 'slk_test',
      batchSize: 1,
      sender: (entries) async {
        delivered.addAll(entries);
        return const BatchResult.delivered();
      },
    );
    expect(output, isA<RemoteSyncLogOutput>());

    output({'event': 'startup'}, LogLevel.info);
    await output.flushed;
    expect(delivered.single['event'], 'startup');
    await output.close();
  });
}
