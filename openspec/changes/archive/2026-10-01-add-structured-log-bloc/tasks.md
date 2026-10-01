## 1. structured_log_bloc

- [x] 1.1 Скаффолдинг пакета `emb/structured_log_bloc/`: `pubspec.yaml` (`bloc: ^9.0.0`, `structured_log: ^0.2.1`), `LICENSE`, barrel-файл
- [x] 1.2 `StructuredLogBlocObserver`, `BlocLogLevels`, `BlocValueDescriber`, `describeBlocValue` (`lib/src/bloc_observer.dart`)
- [x] 1.3 Тесты на каждый сценарий `specs/bloc-log-observer/spec.md` (`test/bloc_observer_test.dart`, 16 тестов). Первая редакция писала событие блока в `event` и тем затирала имя записи — поймано тестом, поле переименовано в `bloc_event` (decision 2). Отсев `onChange` у блоков проверен мутацией
- [x] 1.4 `example/main.dart` — блок и кубит с выводом в консоль

## 2. Workspace и CI

- [x] 2.1 `melos.yaml`: пакет в `packages:` и в scope `test:dart`
- [x] 2.2 CI-джоба `bloc-observer` (форма `http-sender` + прогон примера)
- [x] 2.3 Порог покрытия в `tool/coverage_floors.json` — 97 при измеренных 100 % (60/60)
- [x] 2.4 CI зелёный на GitHub Actions — все проверки [#87](https://github.com/pese-git/structured_log/pull/87), включая новую джобу `bloc-observer`; влит squash'ем в `1713f3a`

## 3. Документация

- [x] 3.1 `README.md`/`README.ru.md` пакета (установка, быстрый старт, таблица записей, сокрытие секретов, API)
- [x] 3.2 Корневые `README.md`/`README.ru.md`, `AGENTS.md`
- [x] 3.3 `docs/guides/embedding-guide.md`/`.ru.md`: раздел 4 «логировать блоки», раздел про сервер стал 5-м
- [x] 3.4 Сайт: оглавление пакетов и карточка на главной (EN/RU); страница пакета генерируется `migrate_docs.py`, `npm run build` проходит
