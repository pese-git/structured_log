## 1. structured_log_drift

- [x] 1.1 Проба поведения drift 2.31.0 на `NativeDatabase.memory()` до design: миграции мимо перехватчика, `batch` внутри своей транзакции со схлопнутыми операторами, вложенные транзакции парами `begin`/`commit`, откат при исключении (Context в `design.md`)
- [ ] 1.2 Скаффолдинг пакета `emb/structured_log_drift/`: `pubspec.yaml` (`drift: ">=2.14.0 <3.0.0"`, `structured_log: ^0.3.0`, версия `0.1.0-dev.0`, без `publish_to`), `LICENSE`, barrel-файл `lib/structured_log_drift.dart`. `analysis_options.yaml` не заводится — его нет ни у одного пакета `emb/`
- [ ] 1.3 `StructuredLogDriftInterceptor` и `DriftLogLevels` (`lib/src/drift_interceptor.dart`): записи и поля (decision 2), дробный `duration_ms` (decision 3), отметка медленных (decision 4), аргументы выключены по умолчанию (decision 5), обрезка текста (decision 6), замер транзакций через `Expando` (decision 8), делегирование вне `try` логирования (decision 9), `filter(kind, statement)` (decision 10), логгер на каждой записи и ленивые поля (decision 11), очистка текста ошибки от аргументов (decision 12)
- [ ] 1.4 Тесты на каждый сценарий `specs/drift-query-logging/spec.md` (`test/drift_interceptor_test.dart`) на `NativeDatabase.memory()`. Сценарии с бросающими колбэками — внутри `runZonedGuarded` с проверкой, что обработчик ошибок зоны не вызван. `StructlogConfiguration` восстанавливается в `tearDown`, базы закрываются там же
- [ ] 1.5 Проверить мутацией, что тесты краснеют: без `try` вокруг логирования, без `rethrow`, с аргументами по умолчанию, без очистки текста ошибки, без отметки медленных, с `Stopwatch` транзакции на перехватчике вместо `Expando`
- [ ] 1.6 `example/main.dart`: база на `NativeDatabase.memory()` с перехватчиком, выборка, пакет, упавший запрос в транзакции, вывод `jsonLineOutput`

## 2. Workspace и CI

- [ ] 2.1 `melos.yaml`: пакет в `packages:` и в скоупе `test:dart`
- [ ] 2.2 CI-джоба `drift-interceptor` по форме `bloc-observer` (свой `pubspec_overrides.yaml` на `emb/structured_log`, format/analyze, прогон примера, тесты с покрытием и порогом) плюс второй прогон тестов на `drift: 2.14.0` последним шагом (decision 13)
- [ ] 2.3 Порог покрытия в `tool/coverage_floors.json` — чуть ниже измеренного, с записью-обоснованием
- [ ] 2.4 CI зелёный на GitHub Actions, включая новую джобу

## 3. Документация

- [ ] 3.1 `README.md`/`README.ru.md` пакета: подключение через `interceptWith`, записи и поля, уровни, медленные запросы, раздел о секретах (аргументы и литералы в SQL), что не видно (миграции), изолят, API, «Related packages»
- [ ] 3.2 Строка о `structured_log_drift` в разделе «Related packages»/«Связанные пакеты» (группа «Integrations»/«Интеграции») README всех остальных живых пакетов `emb/`; прослойка `structured_log_http` не участвует. Число адаптеров во фразе «один из N адаптеров» — увеличить на один
- [ ] 3.3 Корневые `README.md`/`README.ru.md` и `AGENTS.md`: пакет в списке `emb/`, в «Структуре», раздел «Внутри `emb/structured_log_drift/`», CI-джоба, число пакетов, джоб и README в правиле «Related packages», список адаптеров в «Соглашениях»
- [ ] 3.4 `docs/guides/embedding-guide.md`/`.ru.md`: раздел о `structured_log_drift` перед разделом о сервере, перенумеровать последующие разделы и их якоря
- [ ] 3.5 Сайт: оглавление пакетов, карточка, строка таблицы интеграций, список адаптеров и диаграмма на главной (EN/RU); `npm run build` в `site/` проходит, и страница `/packages/structured_log_drift/` создаётся
