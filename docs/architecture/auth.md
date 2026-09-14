# Authentication

*Читать на [русском](auth.ru.md).*

Covers `log-server-auth` and `log-server-password-reset`. For the
normative requirements, see
[specs/log-server-auth/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-auth/spec.md)
and
[specs/log-server-password-reset/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-password-reset/spec.md).

## Two separate authentication paths

The server has two unrelated things to authenticate, with different
threat models, and deliberately different mechanisms (decision 9 vs.
10):

| | Log ingestion | Everything else (management/query/live-stream) |
|---|---|---|
| Credential | Project secret key | Access-token (JWT) |
| Who holds it | An application, not a person | A person, via `structured_log_admin_client` |
| Header | `Authorization: Bearer <project-secret-key>` | `Authorization: Bearer <access-token>` |
| Identifies | A `project_id` directly | A `User`, with claims resolved through RBAC |
| Hashing at rest | SHA-256 (decision 11) | n/a (bcrypt is for the *password*, below) |

A project secret key resolves straight to a `project_id` — an
application sending logs never needs a user account at all.

## The token contract: OAuth2/OIDC-shaped, Keycloak as the reference

By direct user requirement (decision 10), the management/query
authentication contract mirrors Keycloak's
`/protocol/openid-connect/token` shape closely enough that an
off-the-shelf OAuth2 client could talk to it, even though there is no
real Keycloak behind it — only `structured_log_server`'s own users and
RBAC. This is a deliberate, narrow exception: the *protocol shape* is
standard, nothing else about Keycloak is reproduced (see
[technology-stack.md](technology-stack.md) for what's explicitly **not**
implemented, e.g. `.well-known/openid-configuration`, token introspection).

```mermaid
sequenceDiagram
    participant Client as structured_log_admin_client
    participant Srv as structured_log_server

    Client->>Srv: POST /v1/auth/token\ngrant_type=password&username=...&password=...
    Note over Srv: verify password, resolve\neffective roles (RBAC), read token_version
    Srv-->>Client: 200 {access_token, refresh_token,\nexpires_in, token_type: "Bearer"}

    Note over Client: access_token is short-lived (minutes)

    Client->>Srv: any request with\nAuthorization: Bearer <access_token>
    Srv->>Srv: verify JWT signature/exp,\ncompare claim tv to current token_version
    alt tv mismatch
        Srv-->>Client: 401
        Client->>Srv: POST /v1/auth/token\ngrant_type=refresh_token&refresh_token=...
        Note over Srv: also checks is_active;\nrotates: revokes old, issues new pair,\nre-resolves roles/tv fresh
        Srv-->>Client: 200 new {access_token, refresh_token, ...}
        Client->>Srv: retry original request
    else tv matches
        Srv-->>Client: 200 (roles read straight from claims,\nno DB join needed)
    end

    Client->>Srv: DELETE /v1/auth/token\nrefresh_token=...
    Note over Srv: RFC 7009 §2.2 — always 200,\nvalid or not, to avoid enumeration
    Srv-->>Client: 200 (empty body)
```

Key properties, each traced to a decision:

- **One endpoint, dispatched by `grant_type`** (`password` or
  `refresh_token`), form-encoded per RFC 6749 — not a JSON body, and not
  separate paths for "login" vs. "refresh" (decision 10).
- **Revocation is `DELETE /v1/auth/token`**, not a `/logout` path — the
  token is a resource, revocation is its deletion (RFC 7009). It always
  answers `200` with an empty body, valid token or not, so the response
  can't be used to probe whether someone else's token is still live.
- **Roles are a snapshot in the JWT claims** (`roles: [{role, scope_type,
  scope_id}]`), not resolved from the database on every request. This is
  the throughput win over the earlier design revision (full DB
  resolution every request) — but it creates a staleness problem that
  `token_version` exists to solve, below.
- **Error shape on this one endpoint only** follows RFC 6749 §5.2
  (`{"error": "invalid_grant", "error_description": "..."}`) rather than
  the rest of the API's JSON error envelope — an intentional, narrow
  inconsistency, documented so it doesn't read as an oversight.

## `token_version`: how a snapshot in a JWT stays revocable

If roles are baked into the token at issuance, what stops a token from
carrying stale (over-privileged) rights until it expires on its own? The
answer is a single integer counter on `User` (decision 10):

```mermaid
flowchart TD
    A["Admin revokes a RoleAssignment\n(or blocks the user, or they\nchange their password)"] --> B["token_version += 1\n(single UPDATE, or bulk UPDATE\nfor a whole team on team-scoped changes)"]
    B --> C{"Next request with\nthe old access token"}
    C -->|"point-lookup: claim tv\nvs current token_version"| D["Mismatch → 401\n(roles in the token are never trusted\nonce tv is stale)"]
    D --> E["Client calls grant_type=refresh_token"]
    E --> F["Server re-resolves roles + tv fresh\n(never copies from the old token)"]
    F --> G["New token has current rights\n— next request succeeds"]
```

The point-lookup (`SELECT token_version FROM users WHERE id = sub`,
indexed PK) is cheap enough to do on *every* authenticated request,
which is what makes this cheaper than the alternative it replaced (join
`role_assignments`↔`team_members`↔`teams` on every request) while still
giving the same "next request sees current rights" guarantee. Events
that bump it: role grant/revoke on the user directly or on a team they
belong to (bulk `UPDATE` for the whole team in the latter case),
deactivation (block/delete), and password change.

This same mechanism is why the live-streaming endpoint needs its own
periodic re-check — see
[live-streaming.md](live-streaming.md#re-validating-a-long-lived-connection):
a long-lived SSE connection is the one place a stale token could
otherwise keep working past its revocation, since there's no "next
request" to catch it.

## `IdentityProvider`: the seam for swapping in Keycloak later

Everything above is one implementation — `LocalIdentityProvider` —
behind a public interface (decision 17):

```dart
abstract class IdentityProvider {
  Future<VerifiedIdentity?> verifyAccessToken(String bearerToken);
}
class VerifiedIdentity {
  final String subject;
  final String? username;
  final List<EffectiveRole>? roles; // null = resolve from role_assignments
}
```

`roles == null` is the extension point for a provider that only
identifies people (rights still come from this server's own
`role_assignments`); `roles != null` is the extension point for a
provider that supplies its own rights (e.g. via Keycloak group/role
mappers). The `token_version` check above is entirely internal to
`LocalIdentityProvider` — it's not part of the interface, and a future
external provider's own revocation model (e.g. short Keycloak token TTLs)
is its own concern, not something this change guarantees for it. **No
Keycloak adapter is implemented in this change** — only the seam.

## Self-service password recovery

A separate pre-auth flow, not an extension of `/v1/auth/token` (decision
24) — `email` is not a login identifier (that stays `username`), only a
recovery contact, mandatory on self-registration and optional when an
admin creates the account.

```mermaid
sequenceDiagram
    participant User
    participant Client as structured_log_admin_client
    participant Srv as structured_log_server
    participant Mail as EmailSender (SmtpEmailSender)

    User->>Client: "Forgot password?" → enters email
    Client->>Srv: POST /v1/auth/password-reset {email}
    Note over Srv: always 202, same body,\nregardless of whether the email exists\n(anti-enumeration, mirrors DELETE /v1/auth/token)
    alt user with this email exists
        Srv->>Srv: invalidate their prior unused\nreset tokens, create a new one\n(Random.secure(), SHA-256 hash stored)
        Srv->>Mail: send(to: email, ...token + optional link...)
    end
    Srv-->>Client: 202

    User->>Client: enters token (or follows web-build link)\n+ new password
    Client->>Srv: POST /v1/auth/password-reset/confirm {token, new_password}
    alt token valid, unexpired, unused
        Srv->>Srv: update password hash, mark token used,\ninvalidate other unused tokens,\ntoken_version += 1 (same event as any password change)
        Srv-->>Client: 200
    else invalid/expired/already used
        Srv-->>Client: 400 invalid_token
    end
```

`EmailSender` is an interface for the same reason as `IdentityProvider`:
an operator might swap `SmtpEmailSender` for a transactional email API
without touching the reset flow itself.

## Password vs. secret-key hashing: two algorithms for two threats

Decision 11 deliberately does **not** use the same hash for both:

- **User passwords** — `bcrypt`. Low-entropy, human-chosen secrets need
  a slow, adaptive algorithm resistant to offline dictionary attacks.
- **Project secret keys and refresh/reset tokens** — SHA-256 of a
  `Random.secure()`-generated value. These are high-entropy and never
  memorized by a human, so dictionary resistance is irrelevant — a slow
  hash here would just be overhead on every `POST /v1/logs` call (a
  high-frequency path, unlike login).

Both secret types are shown to the caller exactly once, at creation.
