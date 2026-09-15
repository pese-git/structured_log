import 'dart:io';

import 'config_source.dart';
import 'param_spec.dart';

/// The outcome of resolving one secret [ParamSpec] — either a value (with
/// its source) or an error message, never both.
class SecretResolution {
  final String? value;
  final ConfigSource? source;
  final String? error;

  const SecretResolution.value(this.value, this.source) : error = null;
  const SecretResolution.error(this.error)
      : value = null,
        source = null;
  const SecretResolution.unset()
      : value = null,
        source = null,
        error = null;

  bool get isError => error != null;
  bool get isUnset => value == null && error == null;
}

/// Resolves one secret parameter from its plain env var and `_FILE`
/// sibling (`log-server-config`) — secrets have no CLI flag at all, so this
/// is intentionally separate from [ConfigResolver]'s CLI/env/default path
/// for ordinary params.
SecretResolution resolveSecret(ParamSpec spec, Map<String, String> env) {
  assert(spec.isSecret, 'resolveSecret called on a non-secret ParamSpec');

  final direct = env[spec.envVarName];
  final fileVarName = '${spec.envVarName}_FILE';
  final filePath = env[fileVarName];

  final hasDirect = direct != null && direct.isNotEmpty;
  final hasFile = filePath != null && filePath.isNotEmpty;

  if (hasDirect && hasFile) {
    return SecretResolution.error(
      '${spec.envVarName} and $fileVarName are both set — only one may be '
      'used for a single secret.',
    );
  }

  if (hasDirect) {
    return SecretResolution.value(direct, ConfigSource.env);
  }

  if (hasFile) {
    final file = File(filePath);
    if (!file.existsSync()) {
      return SecretResolution.error(
        '$fileVarName points to a file that does not exist: $filePath',
      );
    }
    final String contents;
    try {
      contents = file.readAsStringSync();
    } on FileSystemException {
      return SecretResolution.error(
        '$fileVarName points to a file that could not be read: $filePath',
      );
    }
    return SecretResolution.value(
      _stripTrailingNewline(contents),
      ConfigSource.file,
    );
  }

  return const SecretResolution.unset();
}

String _stripTrailingNewline(String value) {
  if (value.endsWith('\r\n')) return value.substring(0, value.length - 2);
  if (value.endsWith('\n')) return value.substring(0, value.length - 1);
  return value;
}
