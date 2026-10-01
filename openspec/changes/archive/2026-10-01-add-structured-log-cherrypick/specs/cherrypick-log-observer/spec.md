## ADDED Requirements

### Requirement: Хуки контейнера дают записи di.*
`StructuredLogCherryPickObserver`, установленный глобальным наблюдателем `CherryPick` или переданный `Scope`, SHALL писать запись `di.<событие>` на каждый вызов включённого хука: `di.scope_opened`, `di.scope_closed`, `di.modules_installed`, `di.modules_removed`, `di.binding_registered`, `di.instance_requested`, `di.instance_created`, `di.instance_disposed`, `di.cache_hit`, `di.cache_miss`, `di.cycle_detected`, `di.diagnostic`, `di.warning`, `di.error`. Каждая запись SHALL нести `category` (по умолчанию `di`) и `scope`, если контейнер его назвал.

#### Scenario: Скоуп с модулем
- **WHEN** открыт корневой скоуп, в нём дочерний, в дочерний установлен `AppModule`, затем дочерний закрыт через `closeSubScope`
- **THEN** записаны два `di.scope_opened`, `di.modules_installed` с `modules: [AppModule]` и `di.scope_closed` со `scope` дочернего, все на уровне `debug`

#### Scenario: Цикл зависимостей
- **WHEN** контейнер с включённой детекцией циклов разрешает тип, зависящий от самого себя через другой
- **THEN** записан `di.cycle_detected` уровня `error` с `chain`, содержащей оба типа

### Requirement: Уровни по умолчанию разделяют проводку и ошибки
По умолчанию скоупы, модули и освобождение SHALL писаться на `debug`, цикл и ошибка — на `error`, предупреждение — на `warning`; регистрация, запрос, создание, кеш и диагностика SHALL NOT писаться. Уровень каждого хука SHALL задаваться через `DiLogLevels`; `null` SHALL выключать хук.

#### Scenario: Разрешения по умолчанию молчат
- **WHEN** установлен модуль, затем тип разрешён пять раз
- **THEN** после установки модуля новых записей нет

#### Scenario: Трассировка включена
- **WHEN** в `DiLogLevels` заданы уровни для регистрации, запроса, создания и диагностики, и тип разрешён
- **THEN** записаны `di.binding_registered`, `di.instance_requested`, `di.instance_created` и `di.diagnostic` с `type`, без самого экземпляра

### Requirement: Экземпляр, текст ошибки и details не попадают в лог
Наблюдатель SHALL NOT писать экземпляр ни в одной записи — только `type` и `name`. `di.error` SHALL писать `message`, тип ошибки в `error` и `stack_trace` (если он не пуст), но SHALL NOT писать текст ошибки. `details` предупреждения и диагностики SHALL NOT писаться.

#### Scenario: Экземпляр с секретом
- **WHEN** экземпляр, чей `toString()` содержит токен, создан, освобождён и передан как `details`
- **THEN** токен не встречается ни в одной записи

#### Scenario: Ошибка с секретом в тексте
- **WHEN** контейнер сообщает ошибку `StateError('secret detail')`
- **THEN** `di.error` содержит `error: StateError` и стек, но не `secret detail`

### Requirement: Наблюдатель не меняет работу контейнера
Исключение из логирования SHALL NOT выходить из хука; разрешение SHALL завершаться как без наблюдателя.

#### Scenario: Бросающий процессор
- **WHEN** процессор `structured_log` бросает исключение на каждой записи, и тип разрешён
- **THEN** разрешение возвращает экземпляр
