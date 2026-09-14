# Documentation

*Читать на [русском](README.ru.md).*

This directory documents the design of `structured_log_server`,
`structured_log_http`, and `structured_log_admin_client` — the
self-hosted, multi-tenant log-collection service and its client packages
proposed by
[openspec/changes/add-structured-log-server/](../openspec/changes/add-structured-log-server/).

As of this writing, none of the three packages have been implemented yet
— this documentation describes the *agreed design*, not shipped code.
It exists to give a reader (human or AI agent) a coherent narrative
account of the system without reading all four OpenSpec artifacts
(`proposal.md`, `design.md`, `specs/*.md`, `tasks.md`, together several
thousand lines) end to end. Once the packages exist, the per-package
`doc/ARCHITECTURE.md` convention already used by
[structured_log/doc/ARCHITECTURE.md](../structured_log/doc/ARCHITECTURE.md)
takes over for describing the *implemented* code; this directory keeps
documenting the cross-cutting system design that spans all three
packages.

## How this relates to AGENTS.md and OpenSpec

```text
AGENTS.md
    │
    └── mandatory repository-wide engineering rules

docs/
    │
    └── system design: components, data model, protocols, why they're
        shaped this way — this directory

openspec/changes/add-structured-log-server/
    │
    ├── proposal.md   — what's changing and why, capability list
    ├── design.md     — every decision, its alternatives, and why they
    │                   were rejected (31 decisions as of this writing)
    ├── specs/*.md    — normative SHALL requirements + Scenario blocks,
    │                   one capability per file
    └── tasks.md      — implementation checklist
```

`design.md` is the source of truth for *why*; the documents here are a
reading aid over it, organized by topic instead of by decision number.
Every claim in this directory traces back to a specific decision in
`design.md` or a requirement in `specs/`, cited by name — if the two
ever disagree, `design.md`/`specs/` win, and this directory should be
corrected to match.

## Contents

- [architecture/README.md](architecture/README.md) — components, request
  flow, and the principles that recur across the whole design.
- [architecture/data-model.md](architecture/data-model.md) — the
  multi-tenant entity model (`User`/`Group`/`Team`/`Project`/...) and its
  storage schema.
- [architecture/auth.md](architecture/auth.md) — the OAuth2/OIDC-style
  token contract, `IdentityProvider`, `token_version`-based revocation,
  and the auth-endpoint rate limiter (throttling, no account lockout).
- [architecture/rbac-and-lifecycle.md](architecture/rbac-and-lifecycle.md)
  — roles and scopes, blocking, and account deletion (including the
  primary-administrator protection).
- [architecture/live-streaming.md](architecture/live-streaming.md) — the
  SSE live-tail design (`GET /v1/logs/stream`).
- [architecture/quotas-and-audit.md](architecture/quotas-and-audit.md) —
  per-project storage quotas, the administrative audit log, and the
  authentication events recorded alongside it.
- [architecture/admin-client.md](architecture/admin-client.md) — the
  `structured_log_admin_client` Flutter app's own architecture.
- [architecture/technology-stack.md](architecture/technology-stack.md) —
  every major dependency choice and the alternative it beat.
- [api/http-api.md](api/http-api.md) — every HTTP endpoint: parameters,
  request/response bodies, endpoint-specific errors, and a `curl`
  example.
- [api/models.md](api/models.md) — the JSON object shapes referenced by
  `http-api.md` (`User`, `Project`, `LogEntry`, the token response, ...).
- [api/errors.md](api/errors.md) — the complete error catalog: every
  HTTP status/code pair the server can return, and where.

## Who this is for

- Contributors picking up `tasks.md` items, who want the reasoning behind
  a task before writing code against it.
- Reviewers checking whether an implementation matches the agreed design.
- AI coding agents, who benefit from a narrative summary instead of
  re-deriving the design from 31 decisions and a dozen spec files on
  every session.
