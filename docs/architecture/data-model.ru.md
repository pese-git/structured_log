# Модель данных

*Read in [English](data-model.md).*

Схема хранения (`log-server-storage`) лежит в основе всего остального в
системе. Этот документ проходится по сущностям и полям их жизненного
цикла; исчерпывающий список полей и все сценарии — в
[specs/log-server-storage/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-storage/spec.md).

## Связи сущностей

```mermaid
erDiagram
    USER ||--o{ ROLE_ASSIGNMENT : "subject (user)"
    USER ||--o{ TEAM_MEMBER : "состоит в"
    USER ||--o{ REFRESH_TOKEN : владеет
    USER ||--o{ PASSWORD_RESET_TOKEN : владеет
    GROUP ||--o{ PROJECT : владеет
    GROUP ||--o{ TEAM : владеет
    TEAM ||--o{ TEAM_MEMBER : содержит
    TEAM ||--o{ ROLE_ASSIGNMENT : "subject (team)"
    PROJECT ||--o{ PROJECT_SECRET_KEY : имеет
    PROJECT ||--|| PROJECT_USAGE : "счётчик использования"
    PROJECT ||--o{ LOG_ENTRY : содержит
    USER ||--o{ AUDIT_LOG_ENTRY : "actor (nullable)"

    USER {
        int id PK
        string username UK "уникален навсегда (decision 27)"
        string password_hash
        string display_name
        string email UK "nullable, уникален если задан"
        bool is_active "block/unblock, decision 25"
        datetime deleted_at "nullable soft-delete, decision 27"
        bool is_primary_admin "true не более чем у 1 строки, decision 28"
        int token_version "счётчик отзыва, decision 10"
    }
    GROUP {
        int id PK
        string name
    }
    TEAM {
        int id PK
        int group_id FK "ровно одна группа"
        string name
    }
    PROJECT {
        int id PK
        int group_id FK "NOT NULL"
        string name
        int retention_days "обязательно, decision 13"
        int max_entries "nullable"
        int max_bytes "nullable"
        bool is_blocked "decision 25"
    }
    ROLE_ASSIGNMENT {
        int id PK
        string subject_type "user | team"
        int subject_id
        string role "admin | owner | user"
        string scope_type "global | group | project"
        int scope_id "nullable для global"
    }
    LOG_ENTRY {
        int id PK
        int project_id FK
        datetime timestamp "от клиента"
        datetime received_at "часы сервера, не доверяем клиенту"
        string level
        string category
        string logger
        int size_bytes
        json context_json "вся исходная запись"
    }
```

## Почему именно эти сущности, а не другие

- **`Group` владеет `Project`-ами; `Team` — отдельная сущность от
  `Group`.** `group_id` у `Project` — `NOT NULL`, он не может
  существовать вне группы. `Team` существует исключительно для массовой
  выдачи прав подмножеству пользователей группы; это *не* переименование
  «пользователей в группе». Decision 6 отклоняет слияние двух сущностей:
  одна группа может держать несколько команд с разным набором прав, а
  `Group`, одновременно владеющая проектами *и* являющаяся получателем
  гранта, смешала бы два разных понятия.
- **`RoleAssignment` — одна полиморфная таблица, не отдельные колонки на
  каждую область.** `subject_type: user|team` × `scope_type:
  global|group|project` покрывает любую форму гранта, нужную модели RBAC
  (decision 6, 7) — как это трактуется, см.
  [rbac-and-lifecycle.md](rbac-and-lifecycle.ru.md). Грант,
  выданный команде, резолвится через текущее членство на момент проверки
  доступа, а не копируется на каждого участника — добавление человека в
  команду немедленно меняет его эффективные права, без необходимости
  что-либо синхронизировать.
- **`LogEntry` хранит и типизированные колонки, и полный исходный
  JSON.** `project_id`/`timestamp`/`level`/`category`/`logger`/поля
  корреляции получают собственные индексированные колонки, потому что
  это частые цели фильтрации (составной индекс на `(project_id, level,
  timestamp)`); всё остальное — включая произвольные пользовательские
  ключи `context` без фиксированной схемы — живёт в `context_json`,
  запрашиваемом через JSON1 SQLite (`json_extract`) при необходимости.
  Ничего не теряется ради схемы, которая не может заранее знать о
  пользовательских полях вызывающего.
- **`received_at` — не `timestamp`.** `timestamp` — то, что заявляет
  клиент; `received_at` — момент, когда сервер фактически увидел батч.
  Они могут расходиться при задержках доставки (retry/backoff), и оба
  хранятся, чтобы при расследовании инцидента можно было отличить «когда
  это произошло» от «когда мы об этом узнали».
- **Refresh-токены и токены восстановления пароля помечаются
  отозванными/использованными, но никогда не удаляются.** Сохранение
  строки (с установленным `revoked_at`/`used_at`) позволяет серверу
  отличить «этот токен никогда не существовал» от «этот токен
  существовал и уже был использован» — второй случай — сигнал,
  используемый для обнаружения повторного использования refresh-токена и
  отзыва всей цепочки (см. [auth.md](auth.ru.md)).

## Поля жизненного цикла User — кратко

`User` несёт три независимых, но связанных поля состояния — смешение их
в одно было бы реальной дизайн-ловушкой, которую эта схема избегает:

| Поле | Значение | Устанавливается | Обратимо? |
|---|---|---|---|
| `is_active` | Может ли аккаунт сейчас аутентифицироваться? | `block`/`unblock` (decision 25), также меняется при удалении | Да, через `unblock` — с исключением ниже |
| `deleted_at` | Был ли аккаунт когда-либо удалён (сам или админом)? | `DELETE /v1/users/me` / `DELETE /v1/users/:id` (decision 27) | Нет — `unblock` явно отказывает аккаунтам с установленным `deleted_at` |
| `is_primary_admin` | Это тот самый аккаунт, что bootstrap создал первым? | Только первый bootstrap — автосоздание на пустой базе (decision 49) или `create-admin` (decision 28) | Н/Д — ни один API-путь не устанавливает и не снимает его |

Удаление устанавливает `is_active = false` *и* `deleted_at = now()` —
переиспользует механику отзыва прав блокировки (отзыв refresh-токенов,
инкремент `token_version`), а не изобретает вторую, но добавляет поверх
постоянную метку. Полную диаграмму состояний и то, кто может вызвать
какой переход — см. [rbac-and-lifecycle.md](rbac-and-lifecycle.ru.md).

## Значимые индексы

- `log_entries`: `project_id`, `timestamp`, `level`, `category`,
  `session_id`, `request_id`, плюс составной `(project_id, level,
  timestamp)` под самый частый паттерн запроса (область + уровень +
  диапазон времени).
- `users.username`: уникален, **не** ограничен `deleted_at IS NULL` —
  username удалённого аккаунта остаётся зарезервированным, пока строка
  физически не вычищена (decision 27; сама очистка — явный non-goal).
- `users.email`: уникальный частичный индекс (`WHERE email IS NOT
  NULL`), то же неисключение удалённых строк.
- `users.is_primary_admin`: уникальный частичный индекс (`WHERE
  is_primary_admin = true`) — гарантия на уровне схемы, что вторая
  строка никогда не сможет нести этот флаг, даже если бы в любом из двух
  путей bootstrap была ошибка (decisions 28/49).

## Движок хранения

`drift` поверх embedded SQLite (`NativeDatabase`,
`journal_mode=WAL`), один `QueryExecutor` в одном isolate — почему
именно `drift`, см. [technology-stack.md](technology-stack.ru.md), а что
это ограничивает в остальном дизайне — принцип «один isolate» в
[README.md](README.ru.md).
