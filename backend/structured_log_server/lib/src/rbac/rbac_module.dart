import 'package:cherrypick/cherrypick.dart';
import 'package:cherrypick_annotations/cherrypick_annotations.dart';

import '../storage/database.dart';
import 'authorizer.dart';

part 'rbac_module.module.cherrypick.g.dart';

@module()
abstract class RbacModule extends Module {
  @singleton()
  @provide()
  Authorizer authorizer(StructuredLogDatabase db) => Authorizer(db);
}
