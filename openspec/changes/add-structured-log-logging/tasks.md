## 1. structured_log_logging

- [ ] 1.1 Скаффолдинг пакета `emb/structured_log_logging/`: `pubspec.yaml` (`logging: ^1.2.0`, `structured_log: ^0.3.0`, версия `0.1.0-dev.0`), `LICENSE`, `analysis_options.yaml`, barrel-файл
- [ ] 1.2 `StructuredLogLoggingBridge` (`attach`/`detach`, `source`, `levelOf`, `filter`, `category`, `context`) и `defaultLogLevelOf` (`lib/src/logging_bridge.dart`)
- [ ] 1.3 Тесты на каждый сценарий `specs/logging-bridge/spec.md` (`test/logging_bridge_test.dart`). Глобальное состояние `package:logging` (`Logger.root.level`, `recordStackTraceAtLevel`, `hierarchicalLoggingEnabled`, слушатели) и `StructlogConfiguration` восстанавливаются в `tearDown`. Отдельно закрепить поведение `dart:async`, на котором стоит decision 7: исключение синхронного слушателя уходит в зону, а не в `log()`
- [ ] 1.4 Проверить мутацией: защиту от рекурсии (decision 8), `try` вокруг `filter` (decision 7), отсев автоматической строки `error` (decision 5) и идемпотентность `attach()` (decision 9)
- [ ] 1.5 `example/main.dart`: мост, два логгера разных уровней, ошибка со стеком, вывод `jsonLineOutput`

## 2. Workspace и CI

- [ ] 2.1 `melos.yaml`: пакет в `packages:` и в скоупе `test:dart`
- [ ] 2.2 CI-джоба `logging-bridge` по форме `bloc-observer` (свой `pubspec_overrides.yaml` на `emb/structured_log`, format/analyze/тесты с покрытием, прогон примера) плюс второй прогон тестов с `logging: 1.2.0` в `pubspec_overrides.yaml`, последним шагом (decision 10)
- [ ] 2.3 Порог покрытия в `tool/coverage_floors.json` — чуть ниже измеренного, с записью `_added_<дата>`
- [ ] 2.4 CI зелёный на GitHub Actions, включая новую джобу

## 3. Документация

- [ ] 3.1 `README.md`/`README.ru.md` пакета: установка, быстрый старт (с `Logger.root.level = Level.ALL` и объяснением, decision 2), таблица уровней, поля записи, раздел о секретах в тексте сообщений, рекурсия, API, «Related packages»
- [ ] 3.2 Строка о `structured_log_logging` в разделе «Related packages»/«Связанные пакеты» (группа «Integrations»/«Интеграции») README всех одиннадцати живых пакетов `emb/` (22 файла; прослойка `structured_log_http` не участвует)
- [ ] 3.3 Корневые `README.md`/`README.ru.md` и `AGENTS.md`: пакет в списке `emb/`, в «Структуре», раздел «Внутри `emb/structured_log_logging/`», CI-джоба, число джоб и пакетов
- [ ] 3.4 `docs/guides/embedding-guide.md`/`.ru.md`: раздел «логировать записи `package:logging`»
- [ ] 3.5 Сайт: оглавление пакетов и карточка на главной (EN/RU). Страница пакета генерируется `migrate_docs.py`, проверить, что `npm run build` проходит
