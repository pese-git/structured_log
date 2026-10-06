## 1. structured_log_riverpod

- [ ] 1.1 Сверить API Riverpod 3 с исходниками до написания кода (decision 1, риск 1): сигнатуры четырёх хуков `ProviderObserver` и `ProviderObserverContext`, модификатор класса (`base`/`final` у наследника), имя и аргумент провайдера семейства, сообщается ли асинхронная ошибка дважды (decision 6). Расхождения внести в `design.md` до 1.3
- [ ] 1.2 Скаффолдинг пакета `emb/structured_log_riverpod/`: `pubspec.yaml` (`riverpod: ^3.0.0`, `structured_log: ^0.3.0`, версия `0.1.0-dev.0`, без `publish_to`), `LICENSE`, barrel-файл `lib/structured_log_riverpod.dart`. `analysis_options.yaml` не заводится — его нет ни у одного пакета `emb/`
- [ ] 1.3 `StructuredLogRiverpodObserver` и `RiverpodLogLevels` (`lib/src/riverpod_observer.dart`): четыре хука, поле `provider` (decision 4), `provider_argument`, описание значений с обрезкой и заменяемым `describe` (decision 5), пропуск `provider_updated` для `AsyncError` (decision 6), `filter` и `describe` под `try` (decision 8), логгер на каждом хуке (decision 9)
- [ ] 1.4 Тесты на каждый сценарий `specs/riverpod-log-observer/spec.md` (`test/riverpod_observer_test.dart`) на настоящем `ProviderContainer(observers: [...])`. Сценарии с бросающими колбэками — внутри `runZonedGuarded` с проверкой, что обработчик ошибок зоны не вызван. `StructlogConfiguration` восстанавливается в `tearDown`, контейнеры закрываются там же
- [ ] 1.5 Проверить мутацией, что тесты краснеют: без `try` вокруг `filter`, без пропуска `AsyncError` в `provider_updated`, с `toString()` провайдера вместо имени, без обрезки значения, с логгером, взятым один раз в конструкторе
- [ ] 1.6 `example/main.dart`: `ProviderContainer` с наблюдателем, именованный провайдер, провайдер семейства, `FutureProvider` с ошибкой, вывод `jsonLineOutput`

## 2. Workspace и CI

- [ ] 2.1 `melos.yaml`: пакет в `packages:` и в скоупе `test:dart`
- [ ] 2.2 CI-джоба `riverpod-observer` по форме `bloc-observer` (свой `pubspec_overrides.yaml` на `emb/structured_log`, format/analyze, прогон примера, тесты с покрытием и порогом) плюс второй прогон тестов на `riverpod: 3.0.0` последним шагом (decision 10)
- [ ] 2.3 Порог покрытия в `tool/coverage_floors.json` — чуть ниже измеренного, с записью-обоснованием по образцу `_added_2026_10_01`
- [ ] 2.4 CI зелёный на GitHub Actions, включая новую джобу

## 3. Документация

- [ ] 3.1 `README.md`/`README.ru.md` пакета: только Riverpod 3 (decision 1), установка, быстрый старт с `ProviderScope(observers: [...])` и `ProviderContainer`, записи и их поля, уровни, раздел о секретах в значениях и аргументах (`describe`, возвращающий `null`), API, «Related packages»
- [ ] 3.2 Строка о `structured_log_riverpod` в разделе «Related packages»/«Связанные пакеты» (группа «Integrations»/«Интеграции») README всех остальных живых пакетов `emb/`, включая `structured_log_logging`, если тот к этому моменту влит; прослойка `structured_log_http` не участвует. Число адаптеров во фразе «один из N адаптеров» в README адаптеров — увеличить на один
- [ ] 3.3 Корневые `README.md`/`README.ru.md` и `AGENTS.md`: пакет в списке `emb/`, в «Структуре», раздел «Внутри `emb/structured_log_riverpod/`», CI-джоба, число пакетов, джоб и README в правиле «Related packages», список адаптеров в «Соглашениях»
- [ ] 3.4 `docs/guides/embedding-guide.md`/`.ru.md`: раздел о `structured_log_riverpod` рядом с разделом о `structured_log_bloc`, перенумеровать последующие разделы и их якоря
- [ ] 3.5 Сайт: оглавление пакетов, карточка, строка таблицы интеграций, список адаптеров и диаграмма на главной (EN/RU); `npm run build` в `site/` проходит, и страница `/packages/structured_log_riverpod/` создаётся
