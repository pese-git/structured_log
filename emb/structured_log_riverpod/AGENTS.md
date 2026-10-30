# emb/structured_log_riverpod — заметки для агентов

Дополняет корневой [AGENTS.md](../../AGENTS.md) (проект, команды, соглашения, версионирование, CI). Подгружается, когда работа идёт в этом каталоге; `CLAUDE.md` рядом — симлинк на этот файл.
- [lib/src/riverpod_observer.dart](lib/src/riverpod_observer.dart) —
  `StructuredLogRiverpodObserver` (`final class`: `ProviderObserver` объявлен `abstract base`), `RiverpodLogLevels`,
  `describeRiverpodValue`.
- **API Riverpod 3 сверен по исходникам и пробной программой, а не по документации** (задача 1.1, `riverpod` 3.0.0, 3.2.1,
  3.3.2). Хуки принимают `ProviderObserverContext` (`provider`, `container`, `mutation`); `ProviderBase` в основной
  библиотеке **не экспортируется** — он в `package:riverpod/misc.dart`, оттуда тип нужен для `filter`; `StateProvider`
  в 3.x переехал в `package:riverpod/legacy.dart`; `read` провайдера в ошибочном состоянии бросает `ProviderException`
  (обёртку), а не исходное исключение.
- **Хуков удаления два, и пишется `provider_disposed` из `didUnmountProvider`, а не из `didDisposeProvider`.** Второй
  срабатывает на каждое перестроение (смена зависимости, `refresh`, `invalidate`), иногда дважды подряд, и об удалении
  ничего не говорит. Первый есть с `riverpod` **3.3.2**, в 3.0.0–3.2.1 его нет: там `provider_disposed` не пишется
  вовсе и без предупреждения (решение пользователя 14.10.2026 — граница осталась `^3.0.0`, README говорит об этом прямо).
  Остальные три записи одинаковы на любой 3.x. `didDisposeProvider` не переопределяется.
- **Асинхронная ошибка приходит дважды** — `didUpdateProvider` с `AsyncError`, затем `providerDidFail` (проверено на 3.0.0
  и 3.3.2). Обновление до `AsyncError` пропускается, ошибка пишется одной записью `provider_failed`, которая несёт стек.
  Ошибку и стек пишет `tryLog(error:, stackTrace:)` ядра, мимо `describe`.
- **`getLogger()` сам читает конфигурацию на каждой записи**, поэтому «взять логгер в конструкторе» поведения не меняет
  (мутацией проверено: тесты остались зелёными). Закрепляет конфигурацию только `BoundLogger(StructlogConfiguration.current)`;
  тесты краснеют именно на нём.
- **Значения описываются лениво**: после `filter` и проверки `logger.isEnabled(level)`. Бросивший `filter` или логгер стоит
  записи, бросивший `describe` — её значений (`describe_failed` с типом исключения, без текста).
- **Тест удаления определяет хук пробным наблюдателем, а не по номеру версии**: `riverpodReportsUnmount()` закрывает
  контейнер и смотрит, позвали ли `didUnmountProvider`. Тест `a removed provider is logged as disposed` пропускается без
  хука, парный ему `without didUnmountProvider the other entries are still written` — наоборот, поэтому второй прогон CI
  на `riverpod: 3.0.0` что-то проверяет, а не молча пропускает.
- **Тест не ищет цифры во всей записи**: `isNot(contains('42'))` падал, когда `42` попадало в `timestamp` (`10:42:…`).
  Для проверки утечки аргумента берётся уникальная строка.
- **`riverpod: ^3.0.0`, и нижняя граница проверяется**: CI-джоба `riverpod-observer` гоняет тесты второй раз на
  `riverpod: 3.0.0` (последним шагом, после проверки покрытия). `sdk: ^3.8.0` — нижняя граница самого `riverpod` 3.0.0.
  Покрытие 100 % (41 из 41 строки), порог 97.
- Мутацией проверены восемь мест: `try` вокруг `filter`/логгера, пропуск `AsyncError`, имя провайдера, обрезка значения,
  закрепление логгера, хук удаления, `try` вокруг `describe`, ранний выход по `isEnabled`.
