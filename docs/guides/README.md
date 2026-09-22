# Guides

*Читать на [русском](README.ru.md).*

Four product guides for the `structured_log` system — the self-hosted
log server, its admin client, and the libraries that ship logs into it.
Each is task-oriented: *how to use it*, for one of the four people who
actually do, rather than *why it's built this way* (that's the rest of
[docs/](../README.md) — the architecture/design record, aimed at
someone reasoning about or reviewing the system's internals):

| Guide | For | Answers |
|---|---|---|
| [User Guide](user-guide.md) | Anyone signed in to the admin client — reading, searching and live-tailing logs, and (for `owner`/`admin`) managing groups, projects and access | "How do I find the log I'm looking for? What can I do with my role?" |
| [Administrator / DevOps Guide](admin-guide.md) | Whoever deploys, configures and operates the server | "How do I get this running, keep it running, and recover when something goes wrong?" |
| [Developer Guide](developer-guide.md) | Whoever writes code *against* this system from outside it — sending logs from an application, calling the HTTP API directly, or embedding a live in-app viewer | "How do I get my application's logs into this system, and how do I read them out programmatically?" |
| [Contributor Guide](contributor-guide.md) | Whoever writes code *in* this repository — any package, not just the server | "How do I get a dev environment running, and land a change the way this codebase expects?" |

Each guide is self-contained — start with the one matching your role,
not this page. Where a guide needs exact wire-level detail (every field,
every error code), it links into the reference documentation instead of
repeating it: [api/http-api.md](../api/http-api.md),
[api/models.md](../api/models.md), [api/errors.md](../api/errors.md),
[operations/configuration.md](../operations/configuration.md).

## What's real and what isn't

Every capability described in these guides exists in the running
system as of this writing — verified against the actual route table and
CLI, not against an earlier design draft. Three flows you'll find
described in [architecture/auth.md](../architecture/auth.md) and
[api/http-api.md](../api/http-api.md) are deliberately **not** covered
here because they aren't implemented: self-service registration,
self-service password reset by email, and email verification. Those
documents describe the full originally-proposed design, including parts
still pending; these guides describe the product as it stands today. An
administrator creates every account and resets a forgotten password
directly — see the Administrator Guide's
[user management](admin-guide.md#managing-users) section.
