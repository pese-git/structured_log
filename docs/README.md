# Documentation

*Читать на [русском](README.ru.md).*

This directory documents the design of `structured_log_server`,
`structured_log_http`, and `structured_log_admin_client` — the
self-hosted, multi-tenant log-collection service and its client packages
originally proposed by
[openspec/changes/add-structured-log-server/](../openspec/changes/add-structured-log-server/)
and now implemented (see [AGENTS.md](../AGENTS.md) for what's shipped
and what remains, capability by capability).

**Two kinds of reading are collected here, for two different readers.**
[guides/](guides/) is task-oriented product documentation — a *user*,
*administrator*, and *developer* guide, written for someone using or
integrating the running system, and the material intended for a future
project website. Everything else in this directory (`architecture/`,
`operations/`, `api/`) is a narrative reading aid over the OpenSpec
artifacts, written for a contributor, reviewer, or AI coding agent who
wants the reasoning behind a decision before touching the code — it
exists so a reader doesn't have to read every `proposal.md`/`design.md`/
`specs/*.md`/`tasks.md` (several thousand lines across multiple changes)
end to end to get oriented. Where the two overlap on a fact (an endpoint
shape, a config flag), they should agree; if they ever don't, the
`architecture`/`operations`/`api` documents below trace to `design.md`/
`specs/*.md` and win.

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

- [guides/](guides/) — the [User Guide](guides/user-guide.md),
  [Administrator / DevOps Guide](guides/admin-guide.md),
  [Developer Guide](guides/developer-guide.md), and
  [Contributor Guide](guides/contributor-guide.md) — how to use, deploy,
  integrate with, and contribute to the running system.
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
  per-project storage quotas, the administrative audit log, the
  authentication events recorded alongside it, and how long each is kept.
- [architecture/admin-client.md](architecture/admin-client.md) — the
  `structured_log_admin_client` Flutter app's own architecture.
- [architecture/technology-stack.md](architecture/technology-stack.md) —
  every major dependency choice and the alternative it beat.
- [operations/configuration.md](operations/configuration.md) — every
  startup setting: flags, environment variables, precedence, secret
  handling, and what fails the launch.
- [api/http-api.md](api/http-api.md) — every HTTP endpoint: parameters,
  request/response bodies, endpoint-specific errors, and a `curl`
  example.
- [api/models.md](api/models.md) — the JSON object shapes referenced by
  `http-api.md` (`User`, `Project`, `LogEntry`, the token response, ...).
- [api/errors.md](api/errors.md) — the complete error catalog: every
  HTTP status/code pair the server can return, and where.

## Who this is for

**[guides/](guides/):**

- Someone signed in to the admin client, deploying the server, writing
  code against it, or writing code in this repository — see
  [guides/README.md](guides/README.md) to pick the right one.

**`architecture/`, `operations/`, `api/`:**

- Contributors picking up `tasks.md` items, who want the reasoning behind
  a task before writing code against it.
- Reviewers checking whether an implementation matches the agreed design.
- AI coding agents, who benefit from a narrative summary instead of
  re-deriving the design from dozens of decisions and spec files on
  every session.
