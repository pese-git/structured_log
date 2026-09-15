## ADDED Requirements

### Requirement: Репозиторий организован как multi-package workspace на Melos с плоской раскладкой
Корневой `melos.yaml` SHALL объявлять пакеты явным списком по имени (`packages: [structured_log, structured_log_flutter, structured_log_material]`, по образцу [cherrypick](https://github.com/pese-git/cherrypick)), и каждый пакет репозитория SHALL располагаться в собственной директории прямо в корне репозитория (не вложенной под `packages/`), со своим `pubspec.yaml`.

#### Scenario: Melos видит все пакеты репозитория
- **WHEN** выполняется `melos bootstrap` из корня репозитория
- **THEN** Melos обнаруживает и линкует `structured_log`, `structured_log_flutter` и `structured_log_material`

### Requirement: Перенос structured_log не меняет его поведение и версию
Перенос существующего пакета в `structured_log/` (плоско, в корень репозитория) SHALL не изменять его публичный API, текущую версию в `pubspec.yaml` или содержимое `CHANGELOG.md`.

#### Scenario: Тесты structured_log проходят без изменений после переноса
- **WHEN** выполняется `dart test` внутри `structured_log/` после переноса
- **THEN** все тесты, ранее проходившие в плоской структуре репозитория, проходят без изменений в самих тестах

### Requirement: Каждый пакет версионируется независимо
Каждый пакет репозитория SHALL иметь собственную линию git-тегов вида `<package>-v<version>` и собственный `CHANGELOG.md` в формате Keep a Changelog, независимые от версий и changelog других пакетов репозитория.

#### Scenario: Релиз одного пакета не требует бампа версии другого
- **WHEN** выходит новая версия `structured_log_material`
- **THEN** версия `structured_log` и `structured_log_flutter` в их `pubspec.yaml` остаётся неизменной, если в них не было содержательных изменений

### Requirement: Общие скрипты качества кода работают на все пакеты через Melos
Скрипты `melos run analyze`, `melos run format:check` и `melos run test` (и их агрегат `melos run lint`) SHALL выполняться на все пакеты workspace через один вызов из корня репозитория, независимо от того, является пакет чистым Dart-пакетом или Flutter-пакетом.

#### Scenario: Один вызов lint проверяет все пакеты
- **WHEN** из корня репозитория выполняется `melos run lint`
- **THEN** `dart analyze`/`dart format --set-exit-if-changed` (или их Flutter-эквиваленты) выполняются для `structured_log`, `structured_log_flutter` и `structured_log_material`, и команда завершается ошибкой, если хотя бы один пакет не проходит проверку
