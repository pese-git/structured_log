## ADDED Requirements

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
`LogBuffer` SHALL предоставлять текущее содержимое как `ValueListenable<List<Map<String, dynamic>>>`, обновляющийся при каждом захвате новой записи, чтобы UI мог отрисовывать живой поток логов без ручного опроса.

#### Scenario: UI получает новую запись без пересборки виджета вручную
- **WHEN** захвачена новая запись через `LogBuffer.capture`
- **THEN** значение `ValueListenable`, предоставляемого `LogBuffer`, обновляется и уведомляет своих слушателей

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
