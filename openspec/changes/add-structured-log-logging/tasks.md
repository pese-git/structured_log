## 1. structured_log_logging

- [x] 1.1 Скаффолдинг пакета `emb/structured_log_logging/`: `pubspec.yaml` (`logging: ^1.2.0`, `structured_log: ^0.3.0`, версия `0.1.0-dev.0`), `LICENSE`, barrel-файл. `analysis_options.yaml` не заводится — его нет ни у одного пакета `emb/`
- [x] 1.2 `StructuredLogLoggingBridge` (`attach`/`detach`, `source`, `levelOf`, `filter`, `category`, `context`) и `defaultLogLevelOf` (`lib/src/logging_bridge.dart`)
- [x] 1.3 Тесты на каждый сценарий `specs/logging-bridge/spec.md` (`test/logging_bridge_test.dart`, 26 тестов, покрытие 100 % — 39/39). Глобальное состояние `package:logging` (`Logger.root.level`, `recordStackTraceAtLevel`, `hierarchicalLoggingEnabled`) и `StructlogConfiguration` восстанавливаются в `tearDown`, мосты отключаются там же. Поведение `dart:async`, на котором стоит decision 7, проверено пробой до реализации и закреплено тестом: исключение синхронного слушателя уходит в зону подписки, а `log()` возвращается нормально
- [x] 1.4 Проверено мутацией, все красные: `try` вокруг `filter` (decision 7), запасное сопоставление при бросившем `levelOf`, отсев автоматической строки `error` и сравнение её целиком, а не по префиксу (decision 5), идемпотентность `attach()` (decision 9), имя `root` для корня (decision 4). Защита от рекурсии мутацию **пережила**: флаг недостижим, потому что `package:logging` сам отказывает вложенной публикации `StateError`. Флаг удалён, decision 8 и требование спеки переписаны, поведение закреплено тестом
- [x] 1.5 `example/main.dart`: мост, два логгера разных уровней, ошибка со стеком, вывод `jsonLineOutput`

## 2. Workspace и CI

- [x] 2.1 `melos.yaml`: пакет в `packages:` и в скоупе `test:dart`
- [x] 2.2 CI-джоба `logging-bridge` по форме `cherrypick-observer` (свой `pubspec_overrides.yaml` на `emb/structured_log`, format/analyze, прогон примера, тесты с покрытием и порогом) плюс второй прогон тестов с `logging: 1.2.0` в `pubspec_overrides.yaml`, последним шагом (decision 10). Шаги прогнаны локально, второй прогон — 26/26 на 1.2.0
- [x] 2.3 Порог покрытия в `tool/coverage_floors.json` — 97 при измеренных 100 % (39/39), запись `_added_2026_10_05`
- [ ] 2.4 CI зелёный на GitHub Actions, включая новую джобу

## 3. Документация

- [x] 3.1 `README.md`/`README.ru.md` пакета: установка, быстрый старт (с `Logger.root.level = Level.ALL` и объяснением, decision 2), таблица уровней, поля записи, раздел о секретах в тексте сообщений, рекурсия, API, «Related packages»
- [x] 3.2 Строка о `structured_log_logging` в разделе «Related packages»/«Связанные пакеты» (группа «Integrations»/«Интеграции») README всех одиннадцати живых пакетов `emb/` (22 файла; прослойка `structured_log_http` не участвует); заодно «один из пяти адаптеров» → «шести» в README пяти адаптеров
- [x] 3.3 Корневые `README.md`/`README.ru.md` и `AGENTS.md`: пакет в списке `emb/`, в «Структуре», раздел «Внутри `emb/structured_log_logging/`», CI-джоба, число джоб и пакетов
- [x] 3.4 `docs/guides/embedding-guide.md`/`.ru.md`: раздел 8 «принимать записи `package:logging`», раздел про сервер стал 9-м
- [x] 3.5 Сайт: оглавление пакетов, карточка, строка таблицы интеграций, список адаптеров и диаграмма на главной (EN/RU). Страница пакета генерируется `migrate_docs.py` сама (пакеты `emb/` находятся по наличию README), `npm run build` проходит — 69 страниц, включая `/packages/structured_log_logging/`
