# flutter-log-viewer-core Specification

## Purpose
Headless-ядро in-app просмотрщика логов (`emb/structured_log_flutter`): `LogBuffer` — кольцевой буфер, подключаемый к `structured_log` как `OutputFunction`/`LogSink.output`, `LogViewerController` — фильтры по уровню/категории/поиску, пауза и очистка, и `logLevelColor()` — общая для всех скинов палитра уровней. Не зависит ни от одной дизайн-системы, чтобы поверх него строились скины Material, Fluent и Cupertino.
## Requirements
### Requirement: LogBuffer захватывает записи лога как OutputFunction
`LogBuffer` SHALL предоставлять метод `capture`, сигнатура которого совпадает с `OutputFunction` из `structured_log`, чтобы его можно было подключить напрямую как `output` существующего `LogSink`, без изменений в core-пакете.

#### Scenario: LogBuffer подключается как обычный синк
- **WHEN** `LogBuffer.capture` передан как `output` в `LogSink` внутри `StructlogConfiguration.configure(sinks: [...])`
- **THEN** каждая запись, доставленная этому синку через `BoundLogger`, добавляется в `LogBuffer`

### Requirement: LogBuffer — кольцевой буфер ограниченной ёмкости
`LogBuffer` SHALL хранить не более `capacity` последних записей (значение по умолчанию задокументировано явно); при превышении ёмкости самая старая запись SHALL вытесняться при добавлении новой.

#### Scenario: Вытеснение старейшей записи при переполнении
- **WHEN** в `LogBuffer` с `capacity: N` захвачено более `N` записей
- **THEN** буфер продолжает хранить ровно `N` последних записей, а самая старая из них более недоступна

### Requirement: LogBuffer уведомляет о новых записях в реальном времени
`LogBuffer` SHALL предоставлять текущее содержимое как `ValueListenable<List<Map<String, dynamic>>>`, чтобы UI мог отрисовывать живой поток логов без ручного опроса. Значение SHALL быть актуальным сразу после захвата и SHALL быть неизменяемым списком, который не меняется после чтения; повторное чтение без нового захвата SHALL возвращать тот же список. Записи, захваченные за один синхронный участок, SHALL давать одно уведомление слушателей не позднее следующей микрозадачи; `clear()` SHALL уведомлять синхронно, и ожидавшее уведомление пачки после него SHALL NOT приходить.

#### Scenario: UI получает новую запись без пересборки виджета вручную
- **WHEN** захвачена новая запись через `LogBuffer.capture`
- **THEN** после следующей микрозадачи значение `ValueListenable`, предоставляемого `LogBuffer`, содержит запись, и слушатели уведомлены

#### Scenario: Всплеск записей
- **WHEN** за один синхронный участок захвачено 100 записей
- **THEN** до следующей микрозадачи слушатель не уведомлён, после — уведомлён один раз, и список содержит все 100 записей в порядке захвата

### Requirement: LogViewerController фильтрует по минимальному уровню
`LogViewerController` SHALL предоставлять свойство минимального уровня (`LogLevel?`), ограничивающее видимые записи теми, чей уровень не ниже заданного; `null` SHALL означать отсутствие ограничения по уровню.

#### Scenario: Фильтр по уровню скрывает записи ниже порога
- **WHEN** `levelFilter` установлен в `LogLevel.warning` и в буфере есть записи уровней `info` и `error`
- **THEN** `visibleEntries` контроллера содержит запись уровня `error`, но не содержит запись уровня `info`

### Requirement: LogViewerController фильтрует по категории
`LogViewerController` SHALL предоставлять свойство фильтра по категории (`String?`), ограничивающее видимые записи теми, чей контекстный ключ `category` совпадает со значением фильтра; `null` SHALL означать отсутствие ограничения по категории.

#### Scenario: Фильтр по категории показывает только совпадающие записи
- **WHEN** `categoryFilter` установлен в `"network"` и в буфере есть записи с категориями `"network"` и `"database"`
- **THEN** `visibleEntries` контроллера содержит только записи с категорией `"network"`

### Requirement: LogViewerController фильтрует по тексту поиска
`LogViewerController` SHALL предоставлять текстовое свойство поиска, ограничивающее видимые записи теми, у которых `event` или значения контекста содержат текст поиска (регистронезависимо); пустая строка поиска SHALL означать отсутствие ограничения.

#### Scenario: Поиск по подстроке в event
- **WHEN** `searchQuery` установлен в `"payment"` и в буфере есть запись с `event: "payment_failed"` и запись с `event: "user_login"`
- **THEN** `visibleEntries` контроллера содержит запись `"payment_failed"`, но не содержит запись `"user_login"`

### Requirement: LogViewerController поддерживает паузу живого потока
`LogViewerController` SHALL предоставлять булево свойство `paused`; когда `paused` равно `true`, набор `visibleEntries`, видимый UI, SHALL оставаться зафиксированным на состоянии на момент постановки на паузу, несмотря на продолжающийся захват новых записей в `LogBuffer`.

#### Scenario: Новые записи не появляются в списке во время паузы
- **WHEN** `paused` установлен в `true`, а затем в `LogBuffer` захвачена новая запись
- **THEN** `visibleEntries` контроллера не включает эту новую запись, пока `paused` не станет `false`

### Requirement: LogViewerController очищает буфер
`LogViewerController` SHALL предоставлять метод `clear()`, который очищает связанный `LogBuffer` и уведомляет слушателей контроллера об изменении состояния.

#### Scenario: Очистка убирает все записи из списка
- **WHEN** вызван `controller.clear()` при непустом `LogBuffer`
- **THEN** `visibleEntries` контроллера становится пустым списком

### Requirement: structured_log_flutter не импортирует конкретную дизайн-систему
Пакет `structured_log_flutter` SHALL не иметь зависимостей и импортов на `package:flutter/material.dart`, `package:flutter/cupertino.dart` или сторонние UI-киты (например, `fluent_ui`); он SHALL зависеть только от `package:flutter/foundation.dart` (для `ChangeNotifier`/`ValueListenable`) и `structured_log`.

#### Scenario: Пакет собирается без Material/Cupertino в зависимостях
- **WHEN** анализируется граф импортов `packages/structured_log_flutter/lib/`
- **THEN** ни один файл не импортирует `package:flutter/material.dart`, `package:flutter/cupertino.dart` или `package:fluent_ui/fluent_ui.dart`

### Requirement: Однострочный выход для мобильных консолей
`structured_log_flutter` SHALL предоставлять `debugPrintOutput` — `OutputFunction`, выводящий запись одной строкой через `debugPrint` без ANSI-последовательностей, с временем, уровнем, `event` и остальными полями в экранированном виде `key=value`.

#### Scenario: Запись с переводом строки в значении
- **WHEN** `debugPrintOutput` получает запись с `message: 'a\nb'`
- **THEN** `debugPrint` вызван со строкой без перевода строки и без `\x1B`

### Requirement: LogViewerLabels — общий для скинов набор подписей просмотрщика
`structured_log_flutter` SHALL экспортировать неизменяемый класс `LogViewerLabels` с `const`-конструктором, в
котором каждое поле необязательно (`null` по умолчанию): `searchHint`, `pause`, `resume`, `clear`,
`levelFilterLabel` (функция `String Function(LogLevel? minLevel)`, `null`-аргумент — «все уровни»),
`allCategories`, `pageTitle`, `emptyTitle`, `emptyMessage`, `noMatchesTitle`, `noMatchesMessage`,
`clearFilters`, `contextHeading`, `copyContext`, `close`, `backToList`. Поле со значением `null` SHALL означать «подпись скина по
умолчанию». Класс SHALL предоставлять `copyWith`. Класс SHALL NOT содержать встроенных переводов и SHALL NOT
импортировать ни одну дизайн-систему (Material/Cupertino/Fluent) и `flutter_localizations`.

#### Scenario: Пустой набор не задаёт ни одной подписи
- **WHEN** создаётся `const LogViewerLabels()`
- **THEN** все его поля равны `null`

#### Scenario: copyWith меняет только указанное поле
- **WHEN** у набора с заданными `searchHint` и `pause` вызывается `copyWith(pause: 'Стоп')`
- **THEN** результат имеет `pause == 'Стоп'` и прежний `searchHint`, а исходный набор не изменён

#### Scenario: Набор доступен из барреля ядра
- **WHEN** код импортирует только `package:structured_log_flutter/structured_log_flutter.dart`
- **THEN** тип `LogViewerLabels` доступен

### Requirement: Необязательный делегат локализации с английским и русским
`structured_log_flutter` SHALL экспортировать `LogViewerLocalizations` со свойством `labels` типа
`LogViewerLabels`, статическим `delegate` (`LocalizationsDelegate<LogViewerLocalizations>`) и статическим
`of(BuildContext)`, возвращающим `null`, если делегат не зарегистрирован. Делегат SHALL поддерживать языки `en` и
`ru` (по `languageCode`) и SHALL загружаться синхронно. Для `en` `labels` SHALL быть пустым набором (все поля
`null`), для `ru` — набором, в котором задано каждое поле. Пакет SHALL NOT зависеть от `flutter_localizations` и
`intl`.

`LogViewerLocalizations.resolve(BuildContext, LogViewerLabels)` SHALL возвращать набор, в котором каждое поле
берётся из переданного набора, если оно не `null`, иначе из `labels` зарегистрированного делегата, иначе
остаётся `null`.

#### Scenario: Русский набор задаёт все подписи
- **WHEN** делегат загружается для `Locale('ru')`
- **THEN** у `labels` результата не `null` ни одно поле, и `levelFilterLabel(null)` возвращает `Все`

#### Scenario: Английский набор оставляет подписи скинам
- **WHEN** делегат загружается для `Locale('en')`
- **THEN** у `labels` результата все поля `null`

#### Scenario: Неподдерживаемый язык
- **WHEN** у делегата спрашивают `isSupported(Locale('de'))`
- **THEN** ответ `false`

#### Scenario: Явная подпись важнее делегата
- **WHEN** делегат `ru` зарегистрирован и `resolve` вызывается с набором, где задан только `pause: 'Стоп'`
- **THEN** у результата `pause == 'Стоп'`, а остальные поля — из русского набора делегата

#### Scenario: Без делегата resolve возвращает переданный набор
- **WHEN** делегат не зарегистрирован и `resolve` вызывается с набором, где задан только `pause`
- **THEN** у результата задан только `pause`

