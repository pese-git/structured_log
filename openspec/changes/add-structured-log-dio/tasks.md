## 1. structured_log_dio

- [x] 1.1 Скаффолдинг пакета `emb/structured_log_dio/`: `pubspec.yaml` (`dio: ^5.4.0`, `structured_log: ^0.2.1`), `LICENSE`, barrel-файл
- [x] 1.2 `StructuredLogDioInterceptor`, `HttpLogLevels`, `describeHttpBody`, наборы маскирования (`lib/src/dio_interceptor.dart`)
- [x] 1.3 Тесты на каждый сценарий `specs/dio-log-interceptor/spec.md` (`test/dio_interceptor_test.dart`, 22 теста, подставной `HttpClientAdapter`). Мутацией проверены: маскирование query, маскирование заголовков, уровень по статусу в `onError`. Первая редакция тестов бросала из адаптера исключение с чужими `RequestOptions` и отменяла запрос раньше, чем он доходил до перехватчика, — оба поправлены в тестах (decision 2), поведение задокументировано в `AGENTS.md`
- [x] 1.4 `example/main.dart` — против собственного `HttpServer` на loopback, без внешней сети; по его выводу убран шаблонный `error` у `badResponse` (decision 5)

## 2. Workspace и CI

- [x] 2.1 `melos.yaml`: пакет в `packages:` и в scope `test:dart`
- [x] 2.2 CI-джоба `dio-interceptor` (форма `bloc-observer`)
- [x] 2.3 Порог покрытия в `tool/coverage_floors.json` — 97 при измеренных 100 % (97/97)
- [ ] 2.4 CI зелёный на GitHub Actions

## 3. Документация

- [x] 3.1 `README.md`/`README.ru.md` пакета (установка, быстрый старт, таблица записей, маскирование, настройка, API)
- [x] 3.2 Корневые `README.md`/`README.ru.md`, `AGENTS.md`
- [x] 3.3 `docs/guides/embedding-guide.md`/`.ru.md`: раздел 5 «логировать HTTP-вызовы», раздел про сервер стал 6-м
- [x] 3.4 Сайт: оглавление пакетов и карточка на главной (EN/RU)
