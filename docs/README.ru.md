# Документация

*Read in [English](README.md).*

Этот каталог описывает дизайн `structured_log_server`,
`structured_log_http` и `structured_log_admin_client` — self-hosted
мультитенантного сервиса сбора логов и его клиентских пакетов,
спроектированных в
[openspec/changes/add-structured-log-server/](../openspec/changes/add-structured-log-server/).

На момент написания ни один из трёх пакетов ещё не реализован — эта
документация описывает *согласованный дизайн*, а не выпущенный код. Она
нужна, чтобы читатель (человек или AI-агент) мог получить связное
описание системы, не читая все четыре артефакта OpenSpec (`proposal.md`,
`design.md`, `specs/*.md`, `tasks.md` — в сумме несколько тысяч строк) от
начала до конца. Когда пакеты появятся, за описание *реализованного* кода
возьмётся уже существующая в репозитории конвенция `doc/ARCHITECTURE.md`
на пакет — по образцу
[structured_log/doc/ARCHITECTURE.md](../structured_log/doc/ARCHITECTURE.md);
этот же каталог продолжит описывать сквозной дизайн системы, общий для
всех трёх пакетов.

## Как это соотносится с AGENTS.md и OpenSpec

```text
AGENTS.md
    │
    └── обязательные repository-wide инженерные правила

docs/
    │
    └── дизайн системы: компоненты, модель данных, протоколы, почему
        они устроены именно так — этот каталог

openspec/changes/add-structured-log-server/
    │
    ├── proposal.md   — что меняется и зачем, список capabilities
    ├── design.md     — каждое решение, рассмотренные альтернативы и
    │                   почему они отклонены (31 decision на момент
    │                   написания)
    ├── specs/*.md    — нормативные SHALL-требования + блоки Scenario,
    │                   один файл на capability
    └── tasks.md      — чек-лист реализации
```

`design.md` — источник истины про *почему*; документы в этом каталоге —
вспомогательное чтение поверх него, организованное по темам, а не по
номеру decision. Каждое утверждение здесь опирается на конкретный
decision из `design.md` или требование из `specs/`, названные явно — если
они когда-либо разойдутся, приоритет у `design.md`/`specs/`, а этот
каталог нужно поправить, чтобы соответствовать им.

## Содержание

- [architecture/README.md](architecture/README.md) — компоненты, поток
  запроса и принципы, повторяющиеся во всём дизайне.
- [architecture/data-model.md](architecture/data-model.md) —
  мультитенантная модель сущностей (`User`/`Group`/`Team`/`Project`/...)
  и её схема хранения.
- [architecture/auth.md](architecture/auth.md) — OAuth2/OIDC-подобный
  контракт токенов, `IdentityProvider`, отзыв прав через `token_version`
  и ограничитель частоты auth-эндпоинтов (throttling, без блокировки
  учётной записи).
- [architecture/rbac-and-lifecycle.md](architecture/rbac-and-lifecycle.md)
  — роли и области видимости, блокировка и удаление аккаунтов (включая
  защиту основного администратора).
- [architecture/live-streaming.md](architecture/live-streaming.md) —
  дизайн живой доставки логов по SSE (`GET /v1/logs/stream`).
- [architecture/quotas-and-audit.md](architecture/quotas-and-audit.md) —
  квоты на хранение на проект, административный аудит-лог и
  записываемые рядом с ним события аутентификации.
- [architecture/admin-client.md](architecture/admin-client.md) —
  собственная архитектура Flutter-приложения
  `structured_log_admin_client`.
- [architecture/technology-stack.md](architecture/technology-stack.md) —
  каждый значимый выбор зависимости и альтернатива, которую он обошёл.
- [api/http-api.md](api/http-api.md) — каждый HTTP-эндпоинт: параметры,
  тела запроса/ответа, специфичные для него ошибки и пример `curl`.
- [api/models.md](api/models.md) — формы JSON-объектов, на которые
  ссылается `http-api.md` (`User`, `Project`, `LogEntry`, ответ токена, ...).
- [api/errors.md](api/errors.md) — полный каталог ошибок: каждая пара
  HTTP-статус/код, которую может вернуть сервер, и где именно.

## Для кого это

- Контрибьюторы, берущие задачи из `tasks.md`, которым нужно обоснование
  перед тем, как писать код по ним.
- Ревьюеры, проверяющие соответствие реализации согласованному дизайну.
- AI coding agents, которым связное описание экономит повторный разбор
  31 decision и десятка файлов спек в каждой новой сессии.
