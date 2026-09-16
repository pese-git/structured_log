import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// One column of an [AdminTable]: its heading and how wide it is.
///
/// A width in pixels, or [flexible] for the one column that takes what is
/// left. That is how `AuditLog.dc.html` draws it — four fixed columns and a
/// details column that absorbs the rest — and it is the difference between a
/// table and a grid: nothing here sorts, resizes or reorders, because nothing
/// on the canvas offers to.
class AdminColumn {
  final String label;

  /// Fixed width in logical pixels. Null means this column is [flexible].
  final double? width;

  /// Whether the column takes the remaining room. At most one column should
  /// be flexible; a table with none simply leaves the tail empty.
  final bool flexible;

  const AdminColumn(this.label, {this.width}) : flexible = false;

  const AdminColumn.flexible(this.label)
      : width = null,
        flexible = true;
}

/// A column-aligned list with a heading row.
///
/// Not a data grid, and the distinction is deliberate: the canvas draws this
/// as flexed rows with fixed column widths, not as a `<table>`, and nothing in
/// it sorts or resizes. What it buys over a stack of [AdminResourceRow]s is
/// alignment — four pieces of a record that line up down the page, which is
/// what makes a log of actions scannable rather than merely readable.
///
/// [rows] are built by the caller, one [AdminTableRow] each, so the cells stay
/// whatever the screen needs them to be: a tag, a monospaced id, a sentence.
/// The table's job is the alignment and the frame.
class AdminTable extends StatelessWidget {
  final List<AdminColumn> columns;
  final List<AdminTableRow> rows;

  const AdminTable({super.key, required this.columns, required this.rows});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(AdminRadius.card),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AdminRadius.card),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Heading(columns: columns, colors: colors),
            for (final row in rows)
              _Row(columns: columns, row: row, colors: colors),
          ],
        ),
      ),
    );
  }
}

/// One record. [cells] line up with the table's columns, and a shorter list
/// simply leaves the remaining columns empty rather than throwing — a screen
/// rendering heterogeneous records (an audit log does) should not have to pad
/// them by hand.
class AdminTableRow {
  final List<Widget> cells;

  /// Tints the whole row. The canvas uses it to mark a record that is about
  /// the system rather than about a person — a throttling episode, a purge.
  final Color? background;

  const AdminTableRow({required this.cells, this.background});
}

class _Heading extends StatelessWidget {
  final List<AdminColumn> columns;
  final AdminColors colors;

  const _Heading({required this.columns, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AdminSpacing.x14,
        AdminSpacing.x8,
        AdminSpacing.x14,
        AdminSpacing.x8,
      ),
      decoration: BoxDecoration(
        color: colors.cardBg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          for (final (index, column) in columns.indexed) ...[
            if (index > 0) const SizedBox(width: AdminSpacing.x12),
            _cell(
              column,
              Text(
                column.label,
                overflow: TextOverflow.ellipsis,
                style: AdminTypography.caption.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final List<AdminColumn> columns;
  final AdminTableRow row;
  final AdminColors colors;

  const _Row({required this.columns, required this.row, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AdminSpacing.x14,
        vertical: AdminSpacing.x10,
      ),
      decoration: BoxDecoration(
        color: row.background,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        // Top-aligned: a details cell wraps onto several lines while its
        // neighbours stay one, and centring would leave the timestamp
        // floating in the middle of the row it belongs to.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, column) in columns.indexed) ...[
            if (index > 0) const SizedBox(width: AdminSpacing.x12),
            _cell(
              column,
              index < row.cells.length
                  ? row.cells[index]
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Gives a cell the width its column asked for.
Widget _cell(AdminColumn column, Widget child) {
  if (column.flexible) return Expanded(child: child);
  return SizedBox(width: column.width, child: child);
}
