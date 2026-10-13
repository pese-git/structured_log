import 'package:riverpod/legacy.dart';
import 'package:riverpod/riverpod.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_riverpod/structured_log_riverpod.dart';

/// A named provider: its entries say `provider: counter`.
final counterProvider = StateProvider<int>((ref) => 0, name: 'counter');

/// A family: the argument lands in `provider_argument`.
final userProvider = Provider.family<String, int>(
  (ref, id) => 'user #$id',
  name: 'user',
);

/// A provider that fails: one `provider_failed` entry, with the stack trace.
final profileProvider = FutureProvider<String>(
  (ref) async => throw StateError('offline'),
  name: 'profile',
);

Future<void> main() async {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'json', output: jsonLineOutput)],
  );

  final container = ProviderContainer(
    observers: [
      StructuredLogRiverpodObserver(
        // The counter updates on every keystroke in a real app: keep it out.
        levels: const RiverpodLogLevels(updated: null),
      ),
    ],
  );

  container.read(counterProvider);
  container.read(counterProvider.notifier).state = 1;
  container.read(userProvider(42));

  container.listen(profileProvider, (_, _) {}, onError: (_, _) {});
  await Future<void>.delayed(const Duration(milliseconds: 50));

  container.dispose();
}
