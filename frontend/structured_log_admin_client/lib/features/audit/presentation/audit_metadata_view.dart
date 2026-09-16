import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

/// One readable line of an audit record's `metadata`.
typedef AuditDetail = ({String key, String value});

/// `metadata` as pairs a person can read, rather than the JSON it arrived as.
///
/// The field is free-form by design — the server writes no schema for it — so
/// this renders whatever keys it finds instead of listing the ones it expects.
/// Two shapes get special treatment because the server actually produces them
/// and the literal rendering would lose the point:
///
/// - `before`/`after`, which a quota change writes: the value of that record is
///   the pair, so it reads as `max_entries: 2000 → без лимита` on one line
///   rather than as two unrelated nested objects;
/// - a `null` inside a quota, which means "no limit" and not "unknown".
///
/// Everything else is flattened one level with a dotted key, which keeps a
/// nested object legible without inventing a tree widget for a field that is
/// usually four scalars.
List<AuditDetail> readableMetadata(Map<String, dynamic> metadata) {
  final before = metadata['before'];
  final after = metadata['after'];
  if (before is Map && after is Map) {
    return _changes(before, after);
  }

  final details = <AuditDetail>[];
  for (final entry in metadata.entries) {
    final value = entry.value;
    if (value is Map) {
      for (final nested in value.entries) {
        details.add((
          key: '${entry.key}.${nested.key}',
          value: _scalar(nested.value),
        ));
      }
    } else {
      details.add((key: entry.key, value: _scalar(value)));
    }
  }
  return details;
}

/// The keys that changed, as `было → стало`.
///
/// Keys whose value did not move are left out: a quota record carries the whole
/// quota on both sides, and listing the two thirds of it that stayed put buries
/// the third that did not.
List<AuditDetail> _changes(
  Map<Object?, Object?> before,
  Map<Object?, Object?> after,
) {
  final keys = <String>{
    ...before.keys.map((k) => '$k'),
    ...after.keys.map((k) => '$k'),
  };
  final details = <AuditDetail>[];
  for (final key in keys) {
    final was = before[key];
    final now = after[key];
    if (was == now) continue;
    details.add((key: key, value: '${_limit(was)} → ${_limit(now)}'));
  }
  if (details.isEmpty) {
    // The endpoint was called and nothing moved. Saying so beats an empty cell,
    // which reads as a record with no details at all.
    details.add((key: 'изменений', value: 'нет'));
  }
  return details;
}

/// Inside a quota, `null` is a stated value — "no limit" — not a gap.
String _limit(Object? value) => value == null ? 'без лимита' : _scalar(value);

String _scalar(Object? value) => switch (value) {
  null => '—',
  true => 'да',
  false => 'нет',
  String() => value,
  List() => value.map(_scalar).join(', '),
  _ => '$value',
};

/// The details cell: the pairs from [readableMetadata], separated the way the
/// artboard separates them.
///
/// Wraps rather than scrolls or truncates — a `user_agent` is long, and an
/// audit record that shows two thirds of itself is the one kind of record that
/// is worse than none.
class AuditMetadataView extends StatelessWidget {
  final Map<String, dynamic> metadata;

  const AuditMetadataView({super.key, required this.metadata});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final details = readableMetadata(metadata);

    if (details.isEmpty) {
      return Text(
        '—',
        style: AdminTypography.bodySmall.copyWith(color: colors.textTertiary),
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          for (final (index, detail) in details.indexed) ...[
            if (index > 0)
              TextSpan(
                text: ' · ',
                style: TextStyle(color: colors.textTertiary),
              ),
            TextSpan(
              text: '${detail.key}: ',
              style: TextStyle(color: colors.textTertiary),
            ),
            TextSpan(text: detail.value),
          ],
        ],
      ),
      style: AdminTypography.bodySmall.copyWith(
        color: colors.textSecondary,
        height: 1.45,
      ),
    );
  }
}
