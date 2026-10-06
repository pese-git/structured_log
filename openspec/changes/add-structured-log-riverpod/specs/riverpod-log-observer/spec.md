## ADDED Requirements

### Requirement: Жизненный цикл провайдера даёт записи structured_log
`StructuredLogRiverpodObserver`, переданный контейнеру Riverpod, SHALL писать запись `structured_log` на каждое событие провайдера:
- `provider_added` — при создании;
- `provider_updated` — при смене значения;
- `provider_failed` — при ошибке;
- `provider_disposed` — при удалении.

Каждая запись SHALL нести `category: 'riverpod'` и поле `provider`. Поле `provider` SHALL равняться `name` провайдера, если имя задано, и типу провайдера, если нет.

#### Scenario: Создание и обновление именованного провайдера
- **WHEN** провайдер `StateProvider<int>((ref) => 0, name: 'counter')` прочитан, а затем его значение изменено на `1`
- **THEN** записаны `provider_added` с `provider: 'counter'` и `value: '0'`, затем `provider_updated` с `previous_value: '0'` и `value: '1'`

#### Scenario: Провайдер без имени
- **WHEN** прочитан провайдер, созданный без `name`
- **THEN** поле `provider` содержит тип провайдера, а не результат его `toString()`

#### Scenario: Удаление
- **WHEN** провайдер `autoDispose` теряет последнего слушателя
- **THEN** записан `provider_disposed` с его `provider`

### Requirement: Аргумент семейства пишется отдельным полем
Для провайдера семейства (`family`) запись SHALL содержать поле `provider_argument`, полученное той же функцией описания, что и значения.

#### Scenario: Провайдер семейства
- **WHEN** прочитан `userProvider('42')` семейства с именем `user`
- **THEN** запись содержит `provider: 'user'` и `provider_argument: '42'`

### Requirement: Значения описываются заменяемой функцией
По умолчанию значение SHALL писаться как его `toString()`, обрезанный до 1000 символов. Если `toString()` бросил, SHALL писаться заглушка с типом значения. Функция `describe` SHALL заменять описание. Если она вернула `null`, поле значения SHALL NOT писаться, а поле `value_type` SHALL сохраняться.

#### Scenario: Длинное значение
- **WHEN** значение провайдера — строка из 5000 символов
- **THEN** поле `value` содержит первые 1000 символов и многоточие

#### Scenario: Скрытое значение
- **WHEN** `describe` возвращает `null` для значения типа `Session`
- **THEN** запись содержит `value_type: 'Session'` и не содержит `value`

### Requirement: Ошибка провайдера пишется один раз
Ошибка провайдера, синхронная или асинхронная, SHALL давать ровно одну запись `provider_failed` с полями `error`, `error_type` и `stack_trace` в форме ядра. Обновление до `AsyncError` SHALL NOT давать записи `provider_updated`.

#### Scenario: Асинхронная ошибка
- **WHEN** `FutureProvider` завершается исключением `StateError('offline')`
- **THEN** записана одна запись `provider_failed` с `error_type: 'StateError'` и `stack_trace`, и записи `provider_updated` со значением `AsyncError` нет

#### Scenario: Ошибка при построении
- **WHEN** синхронный провайдер бросает при построении
- **THEN** записана запись `provider_failed` уровня `error`

### Requirement: Уровни настраиваются на каждый хук
Уровни по умолчанию SHALL быть: `provider_added` — `debug`, `provider_updated` — `debug`, `provider_failed` — `error`, `provider_disposed` — `debug`. `RiverpodLogLevels` SHALL позволять задать уровень каждого хука, а `null` SHALL выключать хук.

#### Scenario: Обновления выключены
- **WHEN** наблюдатель создан с `RiverpodLogLevels(updated: null)`, и значение провайдера изменено
- **THEN** записи `provider_updated` нет, а `provider_added` записан

### Requirement: Фильтр отсекает провайдеры
Функция `filter`, вернувшая `false` для провайдера, SHALL исключать все его записи. Бросивший `filter` SHALL исключать запись, к которой относился вызов.

#### Scenario: Отфильтрованный провайдер
- **WHEN** `filter` возвращает `false` для провайдера с именем `noisy`
- **THEN** записей с `provider: 'noisy'` нет, а записи других провайдеров есть

#### Scenario: Бросающий фильтр
- **WHEN** `filter` бросает `FormatException('secret=1')`, и значение провайдера изменено
- **THEN** записи об этом событии нет, обработчик ошибок зоны не вызван, и состояние провайдера изменено

### Requirement: Наблюдатель никогда не бросает в Riverpod
Исключение из `filter`, `describe`, `toString()` значения или логгера SHALL NOT выходить из хука наблюдателя. Бросившая `describe` SHALL давать запись с полем `describe_failed`, равным типу исключения, без текста исключения.

#### Scenario: Бросающая функция описания
- **WHEN** `describe` бросает `StateError('token=abc')`, и провайдер создан
- **THEN** записан `provider_added` с `describe_failed: 'StateError'`, текста `token=abc` в записи нет, и обработчик ошибок зоны не вызван

### Requirement: Повторная конфигурация доходит до наблюдателя
Если `BoundLogger` не передан явно, наблюдатель SHALL использовать конфигурацию `structured_log`, действующую в момент события, а не в момент создания наблюдателя.

#### Scenario: configure после создания
- **WHEN** наблюдатель создан, затем вызван `StructlogConfiguration.configure` с новым выводом, затем провайдер прочитан
- **THEN** запись `provider_added` получает новый вывод
