import 'package:cherrypick/cherrypick.dart';
import 'package:cherrypick_annotations/cherrypick_annotations.dart';

import 'database.dart';
import 'log_store.dart';

part 'storage_module.module.cherrypick.g.dart';

@module()
abstract class StorageModule extends Module {
  @singleton()
  @provide()
  LogStore logStore(StructuredLogDatabase db) => DriftLogStore(db);
}
