## 1. structured_log_http_client

- [x] 1.1 Скаффолдинг пакета `emb/structured_log_http_client/`: `pubspec.yaml` (`http: ^1.5.0`, `structured_log: ^0.2.1`, `sdk: ^3.4.0`), `LICENSE`, barrel-файл
- [x] 1.2 `StructuredLogHttpClient`, `HttpLogLevels`, `describeHttpBody`, наборы маскирования (`lib/src/http_client.dart`); логирование тела ответа без буферизации, сохранение `BaseResponseWithUrl.url` приватным классом (decision 4)
- [x] 1.3 Тесты на каждый сценарий `specs/http-client-logging/spec.md` (`test/http_client_test.dart`, 31 тест, `MockClient`). Тест поймал дефект первой редакции: тело описывалось вне защищённого построителя, и бросающий `describeBody` терял всю запись `http_response`. Мутацией проверены пять мест: маскирование query и заголовков, уровень `cancel`, запись при досрочной отписке, захват тела
- [x] 1.4 `example/main.dart` — настоящий `IOClient` против собственного `HttpServer` на loopback

## 2. Workspace и CI

- [x] 2.1 `melos.yaml`: пакет в `packages:` и в scope `test:dart`
- [x] 2.2 CI-джоба `http-client` (форма `dio-interceptor`)
- [x] 2.3 Порог покрытия в `tool/coverage_floors.json` — 97 при измеренных 100 % (144/144)
- [ ] 2.4 CI зелёный на GitHub Actions

## 3. Документация

- [x] 3.1 `README.md`/`README.ru.md` пакета (установка, быстрый старт, таблица записей, момент записи ответа, маскирование, настройка, API), с предупреждением о различии со `structured_log_http`
- [x] 3.2 Корневые `README.md`/`README.ru.md`, `AGENTS.md`
- [x] 3.3 `docs/guides/embedding-guide.md`/`.ru.md`: раздел 5 стал общим «логировать HTTP-вызовы» с подразделами для `dio` и `package:http`
- [x] 3.4 Сайт: оглавление пакетов, карточка на главной объединена для `dio`/`http` (EN/RU)
