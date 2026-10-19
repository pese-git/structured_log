## Why

Все три скина просмотрщика логов (`structured_log_material`, `structured_log_fluent`, `structured_log_cupertino`)
держат подписи интерфейса английскими литералами в коде, и приложение не может их заменить: экран логов
русскоязычного приложения остаётся наполовину английским. Так это и всплыло — Electro
(`Electro/electro_workspace#188`) просит экран логов по-русски, а пакет этого не позволяет. Там же второй
пробел: после «Copy» виджет молча кладёт текст в буфер обмена, и приложению не на что повесить
подтверждение «Контекст скопирован».

## What Changes

- В `structured_log_flutter` появляется `LogViewerLabels` — неизменяемый набор подписей просмотрщика (поиск,
  пауза/продолжение, очистка, «все» в фильтрах уровня и категории, подписи уровней фильтра, заголовок
  страницы, тексты пустых состояний, сброс фильтров, копирование, закрытие, возврат к списку). Все поля
  необязательны: незаданное поле — прежняя английская подпись **того скина**, где оно показывается.
- `MaterialLogViewer`/`MaterialLogViewerPage`, `FluentLogViewer`/`FluentLogViewerPage`,
  `CupertinoLogViewer`/`CupertinoLogViewerPage` принимают `labels` и передают их всем своим частям, включая
  экран деталей, который Cupertino пушит отдельным маршрутом. Публичные составные виджеты (пустое состояние,
  панели/шторка деталей, фильтр категорий) тоже принимают `labels`.
- Те же виджеты принимают `onContextCopied` — колбэк с записью, вызываемый **после** успешной записи контекста
  в буфер обмена. Встроенного снэкбара/тоста скины не показывают: как подтвердить копирование, решает
  приложение.
- Без `labels` и `onContextCopied` поведение и тексты не меняются — изменение не ломающее (минорные версии
  `structured_log_flutter` и трёх скинов). Уже существующий параметр `allLabel` у фильтров категорий
  остаётся и имеет приоритет над `labels`.
- В `structured_log_flutter` появляется необязательный `LogViewerLocalizations.delegate` с готовыми английским
  (прежние подписи скинов) и русским наборами `LogViewerLabels` — без `flutter_localizations` и `intl`. Скин
  берёт поле из явного `labels`, иначе из делегата, если он зарегистрирован, иначе свой дефолт.

## Capabilities

### New Capabilities

<!-- нет -->

### Modified Capabilities

- `flutter-log-viewer-core`: новый тип `LogViewerLabels` — общий для скинов набор подписей; необязательный
  делегат `LogViewerLocalizations` с en/ru.
- `flutter-log-viewer-material`: подписи из `LogViewerLabels`, колбэк `onContextCopied`.
- `flutter-log-viewer-fluent`: подписи из `LogViewerLabels`, колбэк `onContextCopied`.
- `flutter-log-viewer-cupertino`: подписи из `LogViewerLabels` (в том числе на пушнутом экране деталей),
  колбэк `onContextCopied`.

## Impact

- Код: `emb/structured_log_flutter/lib/src/` (новый файл, экспорт из barrel), `lib/src/` трёх скинов.
- Публичный API: только добавления (новый тип, необязательные именованные параметры).
- Зависимости: скины поднимают нижнюю границу `structured_log_flutter` до версии с `LogViewerLabels`
  (её ставит `melos version`); публикация — ядро первым, скины следом.
- Документация: `README.md`/`README.ru.md` четырёх пакетов, примеры (`example/`) — по желанию, `docs/guides/embedding-guide.md`.
- Потребитель: Electro переходит на новые версии и передаёт русские подписи и снэкбар — в своём репозитории.
