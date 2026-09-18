import 'app_localizations.dart';

/// `14 Feb 2025` / `14 фев 2025`, as the artboards write dates.
///
/// Built from the localized month abbreviation, not from `DateFormat`: the
/// artboard's short forms ("фев", "мая") are not what `intl` produces for
/// `ru` ("февр.", "мая"), and this way English and Russian follow the same
/// rule without depending on `intl`'s date data being initialized.
String formatDate(AppLocalizations l10n, DateTime utc) {
  final local = utc.toLocal();
  return l10n.formatDateShort(
    local.day,
    l10n.monthShort(local.month.toString()),
    local.year,
  );
}

/// `01 Sep` / `01 сен`, as the date-range boxes write a bound.
String formatDayMonth(AppLocalizations l10n, DateTime value) {
  final local = value.toLocal();
  return l10n.formatDayMonth(
    local.day.toString().padLeft(2, '0'),
    l10n.monthShort(local.month.toString()),
  );
}
