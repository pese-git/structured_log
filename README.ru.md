# structured_log

Структурированное логирование для Dart, вдохновлённое [Python structlog](https://www.structlog.org/).

Логируйте JSON с привязкой контекста, процессорами и гибкой настройкой вывода.

## Возможности

- **Структурированный JSON** — логи машиночитаемы по умолчанию
- **Привязка контекста** — иммутабельные `bind()` / `unbind()` для добавления метаданных
- **Процессоры** — трансформация записей перед выводом (фильтрация, обогащение, форматирование)
- **Несколько выводов** — stdout, файл, ротируемый файл или кастомный
- **Цветная консоль** — читаемый вывод для разработки
- **Конфигурация** — глобальная настройка через `StructlogConfiguration.configure()`
- **Без зависимостей** — только Dart SDK

## Установка

Добавьте в `pubspec.yaml`:

```yaml
dependencies:
  structured_log:
    # или pub.dev после публикации
```

## Быстрый старт

```dart
import 'package:structured_log/structured_log.dart';

void main() {
  final log = getLogger();
  log.info('user_login', context: {'user_id': 42, 'ip': '127.0.0.1'});
}
```

Вывод:

```json
{
  "user_id": 42,
  "ip": "127.0.0.1",
  "event": "user_login",
  "level": "info",
  "timestamp": "2026-04-27T12:00:00.000000"
}
```

## Справочник API

### Получение логгера

```dart
// Логгер по умолчанию
final log = getLogger();

// Именованный логгер (добавляет ключ 'logger' в контекст)
final log = getLogger('auth');
```

### Уровни логирования

| Метод       | Уровень   | Цвет (консоль) |
|-------------|-----------|----------------|
| `debug()`   | debug     | голубой        |
| `info()`    | info      | зелёный        |
| `warning()` | warning   | жёлтый         |
| `error()`   | error     | красный        |
| `critical()`| critical  | фиолетовый     |

```dart
log.debug('cache miss', context: {'key': 'session:42'});
log.info('request completed', context: {'duration_ms': 150});
log.warning('slow query', context: {'sql': 'SELECT ...', 'ms': 2000});
log.error('payment failed', context: {'error': 'timeout', 'order_id': 123});
log.critical('database down', context: {'host': 'db-primary'});
```

### Привязка контекста

`bind()` возвращает **новый** экземпляр логгера с объединённым контекстом (иммутабельный паттерн):

```dart
final baseLog = getLogger();

// Привязка контекста запроса
final requestLog = baseLog.bind({'request_id': 'abc-123', 'trace_id': 'xyz'});

// Привязка контекста пользователя поверх
final userLog = requestLog.bind({'user_id': 42});

userLog.info('purchase');
// → {"request_id": "abc-123", "trace_id": "xyz", "user_id": 42, "event": "purchase", ...}
```

`unbind()` удаляет ключи:

```dart
final cleanLog = userLog.unbind(['user_id']);
```

### Инлайн-контекст

Передавайте контекст для отдельного вызова:

```dart
log.info('event', context: {'one_off': true});
```

Контекст объединяется в порядке: `initialContext` → `bind()` → инлайн `context`.

## Конфигурация

### Глобальная конфигурация

```dart
StructlogConfiguration.configure(
  processors: [dropNullValues, myCustomProcessor],
  output: fileOutput('logs/app.log'),
  initialContext: {'app': 'my_app', 'version': '1.0.0'},
);
```

| Параметр         | Тип                   | По умолчанию      | Описание                          |
|------------------|-----------------------|-------------------|-----------------------------------|
| `processors`     | `List<Processor>`     | `[dropNullValues]`| Цепочка трансформации записей     |
| `output`         | `OutputFunction`      | `defaultOutput`   | Куда отправлять логи              |
| `initialContext` | `Map<String, dynamic>`| `{}`              | Контекст для всех логгеров        |

Сброс к настройкам по умолчанию:

```dart
StructlogConfiguration.reset();
```

### Вывод (Outputs)

#### Консоль (по умолчанию)

Красивый JSON в stdout:

```dart
StructlogConfiguration.configure(output: defaultOutput);
```

#### Цветная консоль

Читаемый вывод с ANSI-цветами:

```dart
StructlogConfiguration.configure(output: coloredConsoleOutput);
```

Вывод:

```
[2026-04-27T12:00:00.000000] INFO: user_login {"user_id": 42}
```

#### Файл

Добавление JSON-строк (JSONL) в файл. Директории создаются автоматически:

```dart
StructlogConfiguration.configure(
  output: fileOutput('logs/app.log'),
);
```

#### Ротируемый файл

Автоматическая ротация при превышении размера:

```dart
StructlogConfiguration.configure(
  output: rotatingFileOutput(
    'logs/app.log',
    maxSizeBytes: 10 * 1024 * 1024, // 10MB
    maxBackups: 5,                   // хранить 5 ротированных файлов
  ),
);
```

Ротированные файлы: `app.log`, `app.log.0`, `app.log.1`, ... `app.log.4`

#### Кастомный вывод

Реализуйте свой:

```dart
void myOutput(Map<String, dynamic> entry, LogLevel level) {
  // Отправка в Sentry, CloudWatch и т.д.
}

StructlogConfiguration.configure(output: myOutput);
```

## Процессоры

Процессоры — функции, преобразующие записи перед выводом. Верните `null`, чтобы удалить запись.

### Встроенные процессоры

| Процессор        | Описание                          |
|------------------|-----------------------------------|
| `dropNullValues` | Удаляет ключи со значением `null` |
| `addTimestamp`   | Добавляет ISO 8601 timestamp      |
| `addLogLevel`    | Гарантирует наличие ключа уровня  |
| `jsonRenderer`   | Выводит запись как JSON           |
| `logfmtRenderer` | Выводит в формате `key=value`     |

### Кастомный процессор

```dart
Map<String, dynamic>? maskPasswords(Map<String, dynamic> entry) {
  if (entry.containsKey('password')) {
    entry['password'] = '***';
  }
  return entry;
}

StructlogConfiguration.configure(
  processors: [dropNullValues, maskPasswords],
);
```

Порядок процессоров важен — они выполняются последовательно:

```dart
processors: [
  dropNullValues,      // 1. Очистка null
  maskPasswords,       // 2. Маскировка секретов
  addCorrelationId,    // 3. Обогащение
]
```

## Примеры

### Логирование запросов веб-сервера

```dart
import 'package:structured_log/structured_log.dart';

void handleRequest(Request req) {
  final log = getLogger().bind({
    'request_id': req.id,
    'method': req.method,
    'path': req.path,
    'ip': req.remoteAddress,
  });

  log.info('request started');

  try {
    final response = processRequest(req);
    log.info('request completed', context: {
      'status': response.status,
      'duration_ms': response.duration,
    });
  } catch (e, st) {
    log.error('request failed', context: {
      'error': e.toString(),
      'stack_trace': st.toString(),
    });
    rethrow;
  }
}
```

### Несколько логгеров (файл + консоль)

```dart
// Консольный логгер для разработки
final consoleLog = getLogger('console');
consoleLog.info('app started');

// Переключение на файловый вывод
StructlogConfiguration.configure(output: fileOutput('logs/production.log'));
final fileLog = getLogger('production');
fileLog.info('same event, different output');
```

### Асинхронное логирование

Библиотека использует синхронный файловый I/O, что безопасно в любом контексте:

```dart
Future<void> asyncTask() async {
  final log = getLogger().bind({'task': 'background_job'});
  log.info('task started');

  await Future.delayed(Duration(seconds: 1));

  log.info('task completed');
}
```

## Сравнение с Python structlog

| Функция              | Python structlog | Dart structured_log |
|----------------------|------------------|----------------|
| Привязка контекста   | `bind()`         | `bind()`       |
| Процессоры           | Да               | Да             |
| JSON вывод           | Да               | Да             |
| Консоль              | Да               | Да (цветная)   |
| Файловый вывод       | Через stdlib     | Встроенный     |
| Ротация файлов       | Через handlers   | Встроенная     |
| Async поддержка      | Да               | Синхронный I/O |
| Wrapper-классы       | Да               | Нет (простой)  |

## Лицензия

MIT
