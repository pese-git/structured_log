# structured_log_admin_ui

Библиотека компонентов для [`structured_log_admin_client`](../structured_log_admin_client),
организованная по Atomic Design: **tokens**, **atoms**, **molecules**, **organisms**.

На pub.dev не публикуется и для этого не предназначена: пакет несёт эстетику и
словарь конкретного клиента — среди его атомов есть, например, бейдж уровня
лога, — а не является Fluent-китом общего назначения.

## Зачем отдельный пакет

Зависимость односторонняя: клиент зависит от этого пакета, никогда наоборот.
Сам пакет зависит только от Flutter SDK и `fluent_ui` — без `flutter_bloc`,
`cherrypick`, `dio`, `fpdart`, `freezed` и без чего-либо из самого клиента.

Благодаря этому правило «эти виджеты не могут дотянуться до бизнес-логики» —
ошибка сборки, а не соглашение; директория внутри клиента так не умеет.

## Что внутри

| Уровень | Состав |
|---|---|
| `tokens` | `AdminColors`, `AdminTypography`, `AdminSpacing`/`AdminRadius`/`AdminSizes`, `AdminLogLevel` + `AdminLogLevelColors`, `AdminTheme` |
| `atoms` | `AdminLogLevelBadge`, `AdminButton`, `AdminTag`, `AdminLoadingIndicator`, `AdminEmptyState` |
| `molecules` | `AdminSearchField`, `AdminFilterChip`, `AdminKeyValueRow`, `AdminQuotaBar`, `AdminStatusTag`, `AdminLabeledToggle`, `AdminTextField`, `AdminBanner`, `AdminLivePill`, `AdminDateRangeField`, `AdminTimeRangeField` |
| `organisms` | `AdminAppShell`, `AdminResourceRow`, `AdminFilterBar`, `AdminConfirmDialog`, `AdminLogEntryRow`, `AdminFeedStatusStrip`, `AdminTable` |

Уровней `templates` и `pages` нет. Они по определению собирают целый экран
вокруг реальных данных — это presentation-слой клиента, а не библиотека
компонентов.

Каждый компонент принимает только примитивы, enum'ы и колбэки — никаких
доменных моделей и состояний Bloc. Эфемерное презентационное состояние
(hover, фокус, раскрытость) допустимо через `StatefulWidget`/`ValueNotifier`.

## Язык

Кит не знает языков: каждый видимый текст — параметр, а значения по умолчанию у
тех, где они есть (`Cancel`, `From`/`To`/`any`, `Apply`, `Account settings`,
`Sign out`, …), английские. Экран передаёт свои, уже переведённые.

## Источник дизайна

Значения взяты из канваса «Structured Log Admin UI», артборды которого делят
один блок токенов. Там, где значение выведено, а не перенесено, об этом сказано
в коде:

- **Тёмная тема** — канвас светлый. Тёмные значения сохраняют оттенок каждой
  роли и меняют местами фигуру и фон.
- **Бейджи уровней** — в канвасе нарисованы четыре уровня. Их фон — это цвет
  текста поверх поверхности при alpha 0.16, поэтому реализовано правило, а его
  результат закреплён против hex-ов канваса в
  `test/tokens/admin_log_level_test.dart`; именно это делает `trace` и
  `critical`, которых нет ни на одном артборде, согласованными с остальными.
- **Адаптивные раскладки** — намеренно отсутствуют. Все артборды нарисованы в
  одной десктопной ширине, сверяться пока не с чем; см. задачу 23.9 change'а
  `add-structured-log-server`.

## Запуск галереи

```bash
cd example
flutter run -d chrome
```

Каждый компонент с несколькими наборами параметров и переключатель тёмной темы.

---

English version: [README.md](README.md)
