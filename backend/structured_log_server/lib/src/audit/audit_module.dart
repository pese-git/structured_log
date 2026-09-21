import 'package:cherrypick/cherrypick.dart';
import 'package:cherrypick_annotations/cherrypick_annotations.dart';

import '../storage/database.dart';
import 'audit_writer.dart';

part 'audit_module.module.cherrypick.g.dart';

@module()
abstract class AuditModule extends Module {
  // One writer, handed to every route that mutates something. It holds no state
  // of its own — what makes a record atomic with its mutation is the transaction
  // the caller is already inside, not the writer (`audit_writer.dart`).
  @singleton()
  @provide()
  AuditWriter auditWriter(StructuredLogDatabase db) => AuditWriter(db);
}
