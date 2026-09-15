/// Atomic Design component library for `structured_log_admin_client`.
///
/// Three levels, no `templates`/`pages`: those assemble a whole screen around
/// real data and so belong to the client's own presentation layer
/// (design.md decision 39). Everything here takes primitives, enums and
/// callbacks — never a domain model or a Bloc state.
library;

export 'src/atoms/atoms.dart';
export 'src/molecules/molecules.dart';
export 'src/organisms/organisms.dart';
export 'src/tokens/tokens.dart';
