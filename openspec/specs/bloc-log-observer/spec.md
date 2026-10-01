# bloc-log-observer Specification

## Purpose
`StructuredLogBlocObserver` (`emb/structured_log_bloc`) — `BlocObserver`, превращающий жизненный цикл, события, смены состояния и ошибки блоков и кубитов в записи `structured_log`. Введена change `add-structured-log-bloc` (архив `openspec/changes/archive/2026-10-01-add-structured-log-bloc/`).

## Requirements
### Requirement: Каждый хук наблюдателя даёт одну запись structured_log
`StructuredLogBlocObserver`, установленный как `Bloc.observer`, SHALL писать одну запись `structured_log` на каждый вызов хуков `onCreate` (`bloc_created`), `onEvent` (`bloc_event_added`), `onChange` (`bloc_change`), `onTransition` (`bloc_transition`), `onError` (`bloc_error`), `onDone` (`bloc_event_done`) и `onClose` (`bloc_closed`), и SHALL вызывать соответствующий метод `super`.

#### Scenario: Жизненный цикл кубита
- **WHEN** кубит создан, один раз вызывает `emit` и закрыт
- **THEN** записаны `bloc_created`, `bloc_change` и `bloc_closed` в этом порядке

#### Scenario: Падающий обработчик события
- **WHEN** обработчик события блока бросает исключение
- **THEN** записан `bloc_error` уровня `error` с `error`, `error_type` и `stack_trace`, и `bloc_event_done` с `error_type`, но без `stack_trace`

### Requirement: Каждая смена состояния записывается один раз
Для блока (`Bloc`) смена состояния SHALL записываться только как `bloc_transition` (с событием); `onChange` блока SHALL NOT давать записи. Для кубита смена состояния SHALL записываться как `bloc_change`.

#### Scenario: Событие блока меняет состояние
- **WHEN** в блок добавлено событие, обработчик которого вызывает `emit`
- **THEN** записаны `bloc_event_added` и ровно одна запись о смене состояния — `bloc_transition` с `bloc_event`, `current_state`, `next_state` и `state_type`

### Requirement: Запись идентифицирует блок и несёт категорию
Каждая запись SHALL содержать `bloc` (тип блока), `bloc_instance` (идентичность экземпляра) и, если `category` не `null`, поле `category` (по умолчанию `bloc`). Событие блока SHALL лежать в поле `bloc_event`, а не `event`.

#### Scenario: Два экземпляра одного типа
- **WHEN** созданы два кубита одного типа
- **THEN** у их записей одинаковый `bloc` и разный `bloc_instance`, у обеих `category: 'bloc'`

### Requirement: Уровень и включение хуков настраиваются
Уровень каждого хука SHALL задаваться через `BlocLogLevels`; значение `null` SHALL выключать хук. Фильтр `filter`, вернувший `false` для блока, SHALL исключать все записи этого блока.

#### Scenario: Выключенный хук
- **WHEN** `BlocLogLevels(create: null)` и создан блок
- **THEN** записи `bloc_created` нет

### Requirement: Значения описываются заменяемой функцией и не ломают блок
Состояния, события и ошибки SHALL попадать в запись через функцию `describe` (по умолчанию `toString()` с обрезкой до 1000 символов); если она возвращает `null`, поле значения SHALL отсутствовать, а поле типа SHALL оставаться. Исключение из `toString()` или из `describe` SHALL NOT выходить из хука.

#### Scenario: Скрытое значение
- **WHEN** `describe` возвращает `null` для состояния
- **THEN** в записи нет поля значения, но есть `state_type`

#### Scenario: Бросающая функция описания
- **WHEN** `describe` бросает исключение при `emit` кубита
- **THEN** `emit` завершается, состояние обновлено, а запись содержит `describe_failed` с типом исключения

### Requirement: Повторная конфигурация доходит до наблюдателя
Наблюдатель, созданный без явного `logger`, SHALL использовать конфигурацию `structured_log`, действующую в момент хука, а не в момент создания наблюдателя.

#### Scenario: configure после установки наблюдателя
- **WHEN** наблюдатель установлен, затем вызван `StructlogConfiguration.configure` с новым выводом, затем создан блок
- **THEN** запись `bloc_created` получает новый вывод, а старый — нет

