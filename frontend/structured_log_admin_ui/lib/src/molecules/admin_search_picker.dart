import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// One result [AdminSearchPicker] can show and select.
class AdminSearchPickerItem<T> {
  final T? _value;
  final String label;

  /// A line that says something about the results instead of being one —
  /// "showing the first 20, type more to narrow it down". Shown last, greyed,
  /// and never selectable.
  final bool isHint;

  const AdminSearchPickerItem({required T value, required this.label})
      : _value = value,
        isHint = false;

  /// Appended by the caller when the search matched more than it returned:
  /// a result list that is silently cut reads as "these are all there are".
  const AdminSearchPickerItem.hint(this.label)
      : _value = null,
        isHint = true;

  /// The picked value. A hint has none, and the picker never reports one.
  T get value {
    assert(!isHint, 'A hint carries no value.');
    return _value as T;
  }
}

/// A labelled field that resolves a reference (a group, a project, …) by
/// name instead of by an id the reader is never expected to know —
/// `RoleAssignment.dc.html`'s "Область" field shows the resolved name behind
/// a chevron, not a raw id; this is that field, made to search rather than
/// assume a small enough list to draw as a plain dropdown.
///
/// Wraps [AutoSuggestBox]: results come from [onSearch], not a static list,
/// because the set of groups/projects an admin might pick from is exactly
/// the set this dialog cannot know in advance. [onSearch] is called with an
/// empty string on first focus — so opening the field shows something before
/// the reader types a character, matching a click-to-open dropdown — and
/// again, debounced, on every keystroke after.
///
/// A custom [sorter] that returns [items] unchanged: [onSearch] already did
/// the filtering (server-side, `?name=`), and `AutoSuggestBox`'s own
/// default label-contains sorter would otherwise re-filter results a second
/// time against whatever partial text is in the box — redundant at best,
/// and a source of results silently disappearing if the two filters ever
/// disagree.
class AdminSearchPicker<T> extends StatefulWidget {
  final String label;
  final String placeholder;

  /// Seeds the field with an already-known selection — e.g. reopening a form
  /// that remembers what was picked last time.
  final AdminSearchPickerItem<T>? initialItem;

  final Future<List<AdminSearchPickerItem<T>>> Function(String query) onSearch;

  /// Fired with `null` the moment the reader edits the text after having
  /// picked something — the old selection no longer matches what's in the
  /// box, and a caller that kept using it would silently act on a value the
  /// field no longer shows.
  final ValueChanged<AdminSearchPickerItem<T>?> onSelected;

  final String? errorText;
  final bool enabled;

  const AdminSearchPicker({
    super.key,
    required this.label,
    required this.onSearch,
    required this.onSelected,
    this.placeholder = 'Start typing a name…',
    this.initialItem,
    this.errorText,
    this.enabled = true,
  });

  @override
  State<AdminSearchPicker<T>> createState() => _AdminSearchPickerState<T>();
}

class _AdminSearchPickerState<T> extends State<AdminSearchPicker<T>> {
  late final _controller = TextEditingController(
    text: widget.initialItem?.label ?? '',
  );
  final _focusNode = FocusNode();
  final _autoSuggestKey = GlobalKey<AutoSuggestBoxState<T>>();
  List<AutoSuggestBoxItem<T>> _items = const [];
  Timer? _debounce;
  bool _openedOnce = false;

  /// What was typed when the last search ran — put back if a hint is chosen.
  String _lastQuery = '';

  /// The hint lines currently offered, to recognise one being chosen.
  Set<String> _hintLabels = const {};

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus && !_openedOnce) {
      _openedOnce = true;
      _search(_controller.text);
    }
  }

  void _onChanged(String text, TextChangedReason reason) {
    // `AutoSuggestBox` writes a chosen item's label into the field. For a hint
    // that is a sentence about the results, not something to search for, and
    // the next keystroke would extend it — so it is put back, a frame later,
    // once the box has finished writing.
    if (_hintLabels.contains(text)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller.value = TextEditingValue(
          text: _lastQuery,
          selection: TextSelection.collapsed(offset: _lastQuery.length),
        );
      });
      return;
    }
    if (reason != TextChangedReason.userInput) return;
    widget.onSelected(null);
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(text),
    );
  }

  Future<void> _search(String query) async {
    _lastQuery = query;
    final results = await widget.onSearch(query);
    if (!mounted) return;
    setState(() {
      _hintLabels = {
        for (final r in results)
          if (r.isHint) r.label,
      };
      _items = [
        for (final r in results)
          if (r.isHint)
            AutoSuggestBoxItem<T>(value: null, label: r.label)
          else
            AutoSuggestBoxItem<T>(value: r.value, label: r.label),
      ];
    });
    // `AutoSuggestBox` (fluent_ui 4.15.1) only ever paints the items list it
    // had at the moment its overlay was first opened: a later `items` update
    // reaches the already-open overlay through a stream listener that
    // assigns a field without calling `setState`, so the popup silently
    // keeps showing whatever it started with — usually nothing, since the
    // overlay opens before this search has a result to show. A fresh
    // `dismissOverlay()` + `showOverlay()` forces it to rebuild from
    // scratch, which does pick up the current `items`. Deferred a frame so
    // it runs after the `setState` above has actually rebuilt `AutoSuggestBox`
    // with the new list — calling it in the same frame would still capture
    // the stale one.
    if (!_focusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      _autoSuggestKey.currentState
        ?..dismissOverlay()
        ..showOverlay();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final hasError = widget.errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label,
          style: AdminTypography.bodySmall.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: AdminSpacing.x6),
        AutoSuggestBox<T>(
          key: _autoSuggestKey,
          controller: _controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          items: _items,
          sorter: (text, items) => items,
          placeholder: widget.placeholder,
          onChanged: _onChanged,
          onSelected: (item) {
            // A hint is a sentence, not a choice.
            if (item.value == null) return;
            _controller.text = item.label;
            widget.onSelected(
              AdminSearchPickerItem(value: item.value as T, label: item.label),
            );
          },
          style: AdminTypography.body.copyWith(
            color: widget.enabled ? colors.text : colors.textTertiary,
          ),
          placeholderStyle: AdminTypography.body.copyWith(
            color: colors.textTertiary,
          ),
          decoration: WidgetStateProperty.all(
            BoxDecoration(
              color: widget.enabled ? colors.surface : colors.cardBg,
              border: Border.all(
                color: hasError ? colors.errorFg : colors.borderStrong,
              ),
              borderRadius: BorderRadius.circular(AdminRadius.control),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: AdminSpacing.x4),
          Text(
            widget.errorText!,
            style: AdminTypography.caption.copyWith(color: colors.errorFg),
          ),
        ],
      ],
    );
  }
}
