import 'package:cherrypick/cherrypick.dart';

import '../auth/hash_worker_pool.dart';
import '../auth/hashing.dart' show hashWorkerPool;
import '../storage/database.dart';

/// The database and the hash workers: what everything else is built on, and so
/// what goes down after all of it.
///
/// Whether the scope *owns* them is the caller's to say. A test builds many
/// handlers, each on a database it closes itself, and they share one hash pool
/// for the whole isolate — closing either with a scope would pull it out from
/// under the next test. A process owns both and hands them over: bound through
/// providers, because a scope closes what its bindings *create*.
class InfraModule extends Module {
  final StructuredLogDatabase db;
  final bool owned;

  InfraModule({required this.db, required this.owned});

  @override
  void builder(Scope currentScope) {
    if (owned) {
      bind<StructuredLogDatabase>().toProvide(() => db).singleton();
      bind<HashWorkerPool>().toProvide(() => hashWorkerPool).singleton();
    } else {
      bind<StructuredLogDatabase>().toInstance(db);
    }
  }
}
