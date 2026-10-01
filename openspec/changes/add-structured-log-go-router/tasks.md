## 1. structured_log_go_router

- [x] 1.1 Скаффолдинг Flutter-пакета `emb/structured_log_go_router/`: `pubspec.yaml` (`flutter`, `go_router: ">=17.0.0 <19.0.0"`, `structured_log: ^0.2.1`), `LICENSE`, barrel-файл
- [x] 1.2 `StructuredLogGoRouter` (`attach`/`detach`, обёртки `redirect`/`onException`), `RouteLogLevels`, набор маскирования (`lib/src/go_router_logging.dart`)
- [x] 1.3 Виджет-тесты на каждый сценарий `specs/go-router-logging/spec.md` (`test/go_router_logging_test.dart`, 23 теста, настоящий `GoRouter` в `MaterialApp.router`). Тест поймал дефект первой редакции: ошибка маршрута не писалась, потому что пустой список совпадений отсекался раньше проверки на ошибку (decision 4). Тест «бросающий redirect» переписан: первая версия строила `GoRouterState` внутри проверяемого замыкания и могла пройти на чужом `StateError`. Мутацией проверены шесть мест: маскирование query и фрагмента, дедупликация (для неё добавлен тест с прямым `notifyListeners()` — без него мутация выживала), порядок `isError`/`isEmpty`, запись синхронного redirect, пропуск redirect на то же место
- [x] 1.4 `example/main.dart` — три экрана, redirect и страница «не найдено» (одиночный файл, анализируется CI)
- [x] 1.5 Совместимость с `go_router` 18: тесты проходят на 17.5.0 и 18.0.2 (decision 7)

## 2. Workspace и CI

- [x] 2.1 `melos.yaml`: пакет в `packages:` и в scope `test:flutter`
- [x] 2.2 Строка во Flutter-матрице CI с `name` (порог покрытия)
- [x] 2.3 Порог покрытия в `tool/coverage_floors.json` — 97 при измеренных 100 % (84/84)
- [ ] 2.4 CI зелёный на GitHub Actions

## 3. Документация

- [x] 3.1 `README.md`/`README.ru.md` пакета (установка, быстрый старт, таблица записей, режимы ошибок, маскирование, настройка, API)
- [x] 3.2 Корневые `README.md`/`README.ru.md`, `AGENTS.md`
- [x] 3.3 `docs/guides/embedding-guide.md`/`.ru.md`: раздел 6 «логировать навигацию», раздел про сервер стал 7-м
- [x] 3.4 Сайт: оглавление пакетов и карточка на главной (EN/RU)
