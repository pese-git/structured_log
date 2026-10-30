# emb/structured_log_cherrypick — заметки для агентов

Дополняет корневой [AGENTS.md](../../AGENTS.md) (проект, команды, соглашения, версионирование, CI). Подгружается, когда работа идёт в этом каталоге; `CLAUDE.md` рядом — симлинк на этот файл.
- [lib/src/cherrypick_observer.dart](lib/src/cherrypick_observer.dart) —
  `StructuredLogCherryPickObserver`, `DiLogLevels` (уровень на хук, `null` выключает).
- **Имена событий и поля — те же, что у прежних копий в сервере и клиенте** (`di.scope_opened`,
  `di.modules_installed`, …, `scope`/`modules`/`type`/`name`/`chain`/`message`/`error`): копии заменены пакетом без
  изменения журнала и тестов (`test/bin/server_integration_test.dart` наблюдает `di.modules_installed`/
  `di.scope_closed`, `scopes_test.dart` клиента — `di.scope_opened`/`di.scope_closed`/`di.instance_disposed`).
  Добавлено: `category: 'di'`, `stack_trace` у `di.error`, необязательные per-instance записи; `scope: null` больше
  не пишется. **Переименование события — ломающее изменение для обоих потребителей**, а не только для пакета.
- **Docker-образ сервера копирует `emb/structured_log_cherrypick/` до `dart pub get`** — это зависимость по пути, и
  без каталога pub не разрешит ничего. Новая path-зависимость сервера требует того же.
- **Экземпляр не пишется никогда**, ошибка — по типу, `details` предупреждения/диагностики отбрасываются.
  Мутацией проверены: текст ошибки, `details`, per-instance записи по умолчанию, защита от бросающего логгера.
- **Что контейнер сообщает на самом деле — одинаково в 3.0.2, 4.0.0-dev.5 и dev.6** (проверено тестами на всех
  трёх): скоуп называется сгенерированным id, а не именем; `onScopeClosed` — только для `closeSubScope`, не для
  корня; `onInstanceDisposed`/`onCacheHit`/`onCacheMiss` не вызываются никогда (тесты зовут их напрямую);
  неудачное разрешение сообщается дважды. Тесты на контейнер утверждают только это общее.
- **`cherrypick: ">=3.0.0 <5.0.0"`** — интерфейс наблюдателя в 3.0.2 и 4.0.0-dev.5/6 совпадает дословно. pub по
  умолчанию берёт стабильную 3.x, а потребители в репозитории сидят на 4.0-dev, поэтому CI-джоба
  `cherrypick-observer` гоняет тесты второй раз с `cherrypick: ^4.0.0-dev.5` в `pubspec_overrides.yaml`
  (последним шагом — после проверки покрытия, которой нужен `package_config.json` первого прогона).
