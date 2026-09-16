# structured_log_admin_ui

Component library for [`structured_log_admin_client`](../structured_log_admin_client),
structured as Atomic Design: **tokens**, **atoms**, **molecules**, **organisms**.

Not published to pub.dev, and not meant to be: it carries one client's
aesthetic and vocabulary — its atoms include things like a log-level badge —
rather than being a general-purpose Fluent kit.

## Why a separate package

The dependency runs one way: the client depends on this package, never the
reverse. This package depends on nothing but the Flutter SDK and `fluent_ui` —
no `flutter_bloc`, `cherrypick`, `dio`, `fpdart` or `freezed`, and nothing from
the client itself.

That makes "these widgets cannot reach business logic" a build error rather
than a convention, which a directory inside the client could not do.

## What is here

| Level | Contents |
|---|---|
| `tokens` | `AdminColors`, `AdminTypography`, `AdminSpacing`/`AdminRadius`/`AdminSizes`, `AdminLogLevel` + `AdminLogLevelColors`, `AdminTheme` |
| `atoms` | `AdminLogLevelBadge`, `AdminButton`, `AdminTag`, `AdminLoadingIndicator`, `AdminEmptyState` |
| `molecules` | `AdminSearchField`, `AdminFilterChip`, `AdminKeyValueRow`, `AdminQuotaBar`, `AdminStatusTag`, `AdminLabeledToggle`, `AdminTextField`, `AdminBanner`, `AdminLivePill`, `AdminDateRangeField` |
| `organisms` | `AdminAppShell`, `AdminResourceRow`, `AdminFilterBar`, `AdminConfirmDialog`, `AdminLogEntryRow`, `AdminFeedStatusStrip`, `AdminTable` |

There is no `templates` or `pages` level. Those assemble whole screens around
real data, which is the client's presentation layer, not a component library.

Every component takes primitives, enums and callbacks — never a domain model
or a Bloc state. Purely presentational local state (hover, focus, expanded) is
fine and uses `StatefulWidget`/`ValueNotifier`.

## Design source

Values come from the "Structured Log Admin UI" design canvas, whose artboards
share one token block. Where a value is derived rather than transcribed, the
code says so:

- **Dark theme** — the canvas is light-only. Dark values keep each role's hue
  and swap figure for ground.
- **Log level badges** — the canvas draws four levels. Their grounds are the
  foreground over the surface at 16%, so the rule is implemented and pinned
  against the canvas hexes in `test/tokens/admin_log_level_test.dart`; that is
  what makes `trace` and `critical`, drawn nowhere, consistent with the rest.
- **Adaptive layouts** — deliberately absent. Every artboard is one desktop
  width, so there is nothing to build against yet; see task 23.9 of the
  `add-structured-log-server` change.

## Running the gallery

```bash
cd example
flutter run -d chrome
```

Every component with several sets of parameters, and a switch for the dark
theme.

---

Russian version: [README.ru.md](README.ru.md)
