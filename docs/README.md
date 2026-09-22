# Documentation

*Читать на [русском](README.ru.md).*

**Two ways to use this project.** `structured_log` — and, optionally,
an in-app log viewer — works entirely on its own, inside your app, with
no server involved at all: see the [Embedding
Guide](guides/embedding-guide.md). Add the self-hosted, multi-tenant
`structured_log_server` (plus `structured_log_http`, its client-side
sender, and `structured_log_admin_client`, its web UI) only once you
want those logs collected centrally, searchable, and shared across a
team — that system is what the rest of this directory documents the
design of.

**Two kinds of reading are collected here, for two different readers.**
[guides/](guides/) is task-oriented product documentation — one guide
per audience, from embedding the packages standalone to running,
extending, and contributing to the self-hosted system. Everything else
here — `architecture/`, `operations/`, `api/` — is reference
documentation: how the system is built and why, for someone who wants
to understand its design rather than just operate or integrate with
it. Where the two overlap on a fact (an endpoint shape, a config
flag), they should agree.

## Contents

- [guides/](guides/) — five guides, grouped by how you're using the
  project: the [Embedding Guide](guides/embedding-guide.md) (standalone,
  no server); the [User Guide](guides/user-guide.md),
  [Administrator / DevOps Guide](guides/admin-guide.md), and
  [Developer Guide](guides/developer-guide.md) (with the self-hosted
  server); and the [Contributor Guide](guides/contributor-guide.md)
  (contributing to this repository).
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

- Whoever wants `structured_log` — and, optionally, an in-app viewer —
  in their own app, with no server involved.
- Someone signed in to the admin client, deploying the server, or
  writing code against the self-hosted system.
- Whoever writes code in this repository, in any package.

See [guides/README.md](guides/README.md) to pick the right one.

**`architecture/`, `operations/`, `api/`:**

- Anyone who wants the reasoning behind a design decision, not just the
  end result — how the pieces fit together and why they're shaped this
  way.
- Reviewers checking whether an implementation matches the intended
  design.
