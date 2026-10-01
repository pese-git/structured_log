## 1. structured_log_cherrypick

- [x] 1.1 Скаффолдинг пакета `emb/structured_log_cherrypick/`: `pubspec.yaml` (`cherrypick: ">=3.0.0 <5.0.0"`, `structured_log: ^0.2.1`, `sdk: ^3.2.0`), `LICENSE`, barrel-файл
- [x] 1.2 `StructuredLogCherryPickObserver`, `DiLogLevels` (`lib/src/cherrypick_observer.dart`) — имена событий и поля как у копий в сервере и клиенте (decision 1)
- [x] 1.3 Тесты на каждый сценарий `specs/cherrypick-log-observer/spec.md` (`test/cherrypick_observer_test.dart`, 17 тестов, настоящий контейнер). Первая редакция ожидала от контейнера того, чего он не делает (закрытие корневого скоупа, имя вместо id, хуки кеша); ожидания сведены к общему для 3.0.2, 4.0.0-dev.5 и dev.6, на всех трёх тесты зелёные (decision 4). Мутацией проверены: текст ошибки, `details`, per-instance записи по умолчанию, защита от бросающего логгера
- [x] 1.4 `example/main.dart` — корневой и дочерний скоуп, неудачное разрешение; проверен на 3.0.2 и 4.0.0-dev.6

## 2. Workspace и CI

- [x] 2.1 `melos.yaml`: пакет в `packages:` и в scope `test:dart`
- [x] 2.2 CI-джоба `cherrypick-observer` (форма `http-client` + второй прогон на `cherrypick` 4.x, decision 5)
- [x] 2.3 Порог покрытия в `tool/coverage_floors.json` — 97 при измеренных 100 % (53/53)
- [ ] 2.4 CI зелёный на GitHub Actions

## 3. Документация

- [x] 3.1 `README.md`/`README.ru.md` пакета (установка, быстрый старт, таблица записей, что сообщает сам контейнер, секреты, настройка, API)
- [x] 3.2 Корневые `README.md`/`README.ru.md`, `AGENTS.md` (включая то, что копии в сервере и клиенте остаются)
- [x] 3.3 `docs/guides/embedding-guide.md`/`.ru.md`: раздел 7 «логировать DI-контейнер», раздел про сервер стал 8-м
- [x] 3.4 Сайт: оглавление пакетов и карточка на главной (EN/RU)
