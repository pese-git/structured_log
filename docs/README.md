# Documentation

*Читать на [русском](README.ru.md).*

This directory documents the design of `structured_log_server`,
`structured_log_http`, and `structured_log_admin_client` — the
self-hosted, multi-tenant log-collection service and its client
packages.

**Two kinds of reading are collected here, for two different readers.**
[guides/](guides/) is task-oriented product documentation — a *user*,
*administrator*, and *developer* guide, written for someone using or
integrating the running system. Everything else here —
`architecture/`, `operations/`, `api/` — is reference documentation:
how the system is built and why, for someone who wants to understand
its design rather than just operate or integrate with it. Where the
two overlap on a fact (an endpoint shape, a config flag), they should
agree.

## Contents

- [guides/](guides/) — the [User Guide](guides/user-guide.md),
  [Administrator / DevOps Guide](guides/admin-guide.md),
  [Embedding Guide](guides/embedding-guide.md),
  [Developer Guide](guides/developer-guide.md), and
  [Contributor Guide](guides/contributor-guide.md) — how to use, deploy,
  integrate with, and contribute to the running system, or embed one of
  the `emb/` libraries in your own app with no server involved at all.
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

- Anyone who wants the reasoning behind a design decision, not just the
  end result — how the pieces fit together and why they're shaped this
  way.
- Reviewers checking whether an implementation matches the intended
  design.
