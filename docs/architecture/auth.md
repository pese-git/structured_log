# Authentication

*Читать на [русском](auth.ru.md).*

Covers `log-server-auth` and `log-server-password-reset`. For the
normative requirements, see
[specs/log-server-auth/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-auth/spec.md)
and
[specs/log-server-password-reset/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-password-reset/spec.md).

## Two separate authentication paths

The server has two unrelated things to authenticate: log ingestion
(from applications) and everything else (people using the admin
client). They're authenticated differently because they have different
threat models, and deliberately different mechanisms (decision 9 vs.
10). "RBAC" — role-based access control, detailed in
[rbac-and-lifecycle.md](rbac-and-lifecycle.md) — governs what an
authenticated person can then do.

| | Log ingestion | Everything else (management/query/live-stream) |
|---|---|---|
| Credential | Project secret key | Access-token (JWT) |
| Who holds it | An application, not a person | A person, via `structured_log_admin_client` |
| Header | `Authorization: Bearer slk_<project-secret-key>` | `Authorization: Bearer <access-token>` |
| Identifies | A `project_id` directly | A `User`, with claims resolved through RBAC |
| Hashing at rest | SHA-256 (decision 11) | n/a (bcrypt is for the *password*, below) |

A project secret key resolves straight to a `project_id` — an
application sending logs never needs a user account at all.

### One entry point, two credentials

Only the credentials differ — the header is the same one, and exactly
one place reads it: `principalMiddleware`, the single authenticating
stage of the shared `Pipeline` (change `unify-server-auth`). It
resolves the presented value into a `Principal` — `UserPrincipal`,
`ProjectPrincipal` or `AnonymousPrincipal` — and **always** passes the
request on, never answering by itself.

Rejecting inside the middleware is not an option: several endpoints are
public by construction (`GET /healthz`, `POST`/`DELETE /v1/auth/token`,
registration, password reset, email verification), so a rejecting
middleware would immediately grow a list of paths inside itself — that
is, put routing knowledge back into the auth layer. The handler states
its own requirement instead, on its very first line:

- `request.requireUser()` → `VerifiedIdentity`, otherwise 401;
- `request.requireProject()` → `project_id`, otherwise 401.

Hence the behaviour `log-server-auth` relies on: a project secret key
presented to a management endpoint, and an access token presented to
`POST /v1/logs`, both answer 401 — exactly as a missing credential
does. It is also what lets `GET` and `POST` on `/v1/logs` share one
path with different schemes: the scheme is chosen by the handler, not
by the route.

Telling the two credentials apart inside the shared header is the job
of the `slk_` prefix every project secret key carries. A JWT is
base64url of a JSON object and so always starts with `eyJ`, which rules
out a collision by construction; a prefixed value is looked up by hash
in `project_secret_keys` and never reaches signature verification,
while an unprefixed one never reaches the key lookup. A side benefit,
not the reason for it: a leaked key is recognizable on sight and to
secret scanners, the way `ghp_`/`sk-`/`AKIA` are.

The forced-password-change gate lives there too — inside
`requireUser()`, which answers 403 `must_change_password` by default
for an account holding a temporary password. The endpoints the spec
exempts (`POST /v1/auth/change-password`, and later `DELETE
/v1/users/me`) say so explicitly:
`requireUser(allowTemporaryPassword: true)` — the exception is written
in the handler that *is* the exception, not in a list of paths in
another file.

The price of this layout is that the route table no longer shows what
guards what. In exchange there is a mechanical check:
`test/http/route_auth_matrix_test.dart` enumerates every `buildHandler`
route with the principal it requires and, for each non-public one,
asserts 401 both with no credential and with a credential of the other
kind; a route added around the table fails it.

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
        Note over Srv: also checks is_active,\nrotates: revokes old, issues new pair,\nre-resolves roles/tv fresh
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

- **What triggers a bump:** role grant/revoke on the user directly or
  on a team they belong to (bulk `UPDATE` for the whole team in the
  latter case), deactivation (block/delete), and password change.
- **Why a point-lookup, not a join:** `SELECT token_version FROM users
  WHERE id = sub` (indexed PK) is cheap enough to do on *every*
  authenticated request — cheaper than the alternative it replaced
  (joining `role_assignments`↔`team_members`↔`teams` on every request)
  while still giving the same "next request sees current rights"
  guarantee.
- **What happens on mismatch:** the client is forced through
  `grant_type=refresh_token`, which re-resolves roles fresh rather than
  copying them from the old token.

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

**One naming trap that adapter will have to respect:** a Keycloak
`group` and this system's `Group` are not the same thing. In Keycloak,
LDAP and OIDC a "group" is a set of *users* — which here is called a
`Team`. A `Group` here is the container that owns projects and teams,
carries ownership and receives role grants
([rbac-and-lifecycle.md](rbac-and-lifecycle.md)). So Keycloak group
membership maps onto `TeamMember` — or straight onto `RoleAssignment`
when the adapter supplies rights itself (`roles != null`) — and **never**
onto `Group`. The word matching is a false friend. The name `Group` is
kept deliberately (it carries the same meaning as GitLab's `Group`,
which likewise owns projects); renaming it was considered and rejected,
which is exactly why the mapping rule is written down here instead of
being left to whoever writes the adapter to guess.

## Self-service password recovery

> **Planned, not implemented** — no `POST /v1/auth/password-reset`(`/confirm`)
> route exists in the running server; this section documents the design
> as originally specified. An admin resets a forgotten password directly
> via `PATCH /v1/users/:id` instead — see the
> [Administrator Guide](../guides/admin-guide.md#managing-users).

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

## Email verification: mandatory before login, not optional

> **Planned, not implemented** — no `POST /v1/auth/verify-email`(`/resend`)
> route exists in the running server, and `grant_type=password` does not
> gate on `email_verified_at`; this section documents the design as
> originally specified. Self-registration (`POST /v1/auth/register`,
> referenced throughout this section) is likewise not implemented — see
> the [Developer Guide](../guides/developer-guide.md#what-isnt-implemented).

By direct, explicit user requirement (decision 40): any account with an
`email` set — whether through self-registration (where it's mandatory)
or an admin setting one via `POST /v1/users` (where it's optional) —
must verify that address before `grant_type=password` will issue it
tokens. Accounts with no `email` at all are simply exempt — there's nothing to
verify. That covers both bootstrap paths (decision 49): the account
`create-admin` creates, and the one the server creates by itself on a
first start against an empty database
([rbac-and-lifecycle.md](rbac-and-lifecycle.md#bootstrap-two-paths-to-the-first-admin))
— neither collects an address, which is exactly what keeps the very
first login from depending on SMTP being configured. The trade-off is
named rather than hidden: until an admin sets an email on that account,
password recovery isn't available to it either.

```mermaid
sequenceDiagram
    participant User
    participant Client as structured_log_admin_client
    participant Srv as structured_log_server
    participant Mail as EmailSender (SmtpEmailSender)

    Note over Srv: account created with an email\n(POST /v1/auth/register, or POST /v1/users)
    Srv->>Srv: create email_verification_tokens row\n(Random.secure(), SHA-256 hash stored)
    Srv->>Mail: send(to: email, ...token + optional link...)

    User->>Client: attempts grant_type=password
    Client->>Srv: POST /v1/auth/token
    Note over Srv: password correct, but\nemail_verified_at IS NULL
    Srv-->>Client: invalid_grant\n+ reason: "email_not_verified"
    Note over Client: shown as a distinct message,\nnot a generic "wrong credentials" error

    User->>Client: enters token (or follows web-build link)
    Client->>Srv: POST /v1/auth/verify-email {token}
    alt token valid, unexpired, unused
        Srv->>Srv: email_verified_at = now(), mark token used,\ninvalidate other unused verification tokens
        Srv-->>Client: 200
    else invalid/expired/already used
        Srv-->>Client: 400 invalid_token
    end

    User->>Client: retries grant_type=password
    Client->>Srv: POST /v1/auth/token
    Srv-->>Client: 200 {access_token, refresh_token, ...}
```

A few choices worth calling out:

- **One uniform rule, not two paths to track.** The gate is simply "is
  `email` set and unverified" — it doesn't matter whether the account
  was self-registered or admin-created. The alternative (gate only
  self-registered accounts) was rejected specifically because it would
  need a way to remember *how* an account was created just to answer
  one question, where "is `email` set" already answers it directly. The
  practical cost: an admin who sets an `email` at creation time and
  hands out credentials immediately should tell that person to check
  their inbox first — a small, accepted trade-off (see `design.md`'s
  Risks).
- **`grant_type=refresh_token` isn't re-checked.** A refresh token can
  only exist for an account that already passed the `grant_type=password`
  gate once — there's no path to a refresh token for a still-unverified
  account, so re-checking on every refresh would be redundant. Contrast
  this with `is_active` (decision 25), which genuinely can change *after*
  tokens were issued and so *is* re-checked on refresh.
- **The `reason` field is a deliberate, additive extension to the RFC
  6749 error envelope.** RFC 6749 doesn't define this case, and its
  closed `error` set (`invalid_grant`/`invalid_request`/
  `unsupported_grant_type`) has no better fit than reusing `invalid_grant`
  — but a generic `invalid_grant` alone would make "wrong password" and
  "right password, unverified email" indistinguishable to a client. The
  extra `reason` field rides on top of the standard envelope; any
  conformant OAuth2 client ignores fields it doesn't recognize, so this
  doesn't break the compatibility decision 10 introduced RFC-shaped
  errors for in the first place — `structured_log_admin_client` is just
  the one client that reads it.
- **Verification links are `POST`-driven, never a bare `GET`.**
  Confirming by simply clicking a link (`GET`) is tempting — it needs no
  screen at all — but `GET` is supposed to be side-effect-free, and an
  email scanner or link-preview bot following the link would silently
  burn the token before the real recipient ever sees it. Instead, the
  web build's page reads `?token=...` from the URL and issues the
  `POST` itself — the same pattern already used for password-reset
  links (decision 24), not a new one.
- **No separate email-sending interface.** Verification reuses
  `EmailSender` and its `SmtpEmailSender` reference implementation
  as-is — this flow needed a new token table
  (`email_verification_tokens`, structurally identical to
  `password_reset_tokens`) and two new endpoints, not a new way to send
  mail.

## `PATCH /v1/users/:id` and the mandatory temporary password

By direct user requirement (decisions 41/42): admins can edit an
existing user's `email`/`display_name`/`password` — closing a gap
where an admin could create, block, or delete an account but never
correct it. `username`/`is_active`/`deleted_at`/`is_primary_admin`/roles
stay out of reach of this endpoint on purpose — each already has its
own, more narrowly authorized path, and decision 25 already rejected
folding differently-authorized fields into one generic `PATCH` once
before.

Whenever an admin sets a password — at creation (`POST /v1/users`) or
later (`PATCH /v1/users/:id`) — it's unconditionally temporary. There's
no flag to turn this off:

```mermaid
sequenceDiagram
    participant Admin
    participant Srv as structured_log_server
    participant User as Target user

    Admin->>Srv: POST /v1/users {password: "..."} or PATCH /v1/users/:id {password: "..."}
    Note over Srv: must_change_password = true\n(unconditional)\nrevoke all of the target's refresh tokens\ntoken_version += 1
    Srv-->>Admin: 200/201

    Note over Admin,User: admin communicates the temporary password out-of-band

    User->>Srv: POST /v1/auth/token grant_type=password
    Note over Srv: login itself is NOT blocked —\nthe user is expected to know this password
    Srv-->>User: 200 {access_token, refresh_token, ...}

    User->>Srv: any other request, e.g. GET /v1/logs
    Srv-->>User: 403 must_change_password

    User->>Srv: POST /v1/auth/change-password {current_password, new_password}
    Note over Srv: verify current_password,\nupdate hash, token_version += 1,\nmust_change_password = false
    Srv-->>User: 200

    User->>Srv: GET /v1/logs (retried)
    Srv-->>User: 200 (works normally now)
```

A few choices worth calling out:

- **Login succeeds; everything else doesn't.** This is the opposite
  gate shape from [email verification](#email-verification-mandatory-before-login-not-optional),
  which blocks token issuance itself. Here the user is *expected* to
  know the temporary password (the admin told them out-of-band), so
  refusing to issue a token at all would leave no API path to comply
  with the requirement in the first place. Instead, a small middleware
  step — sitting right after auth, before authorization — blocks every
  JWT-authenticated request except an explicit allowlist:
  `POST /v1/auth/change-password` (obviously — without it the flag
  could never be cleared), `DELETE /v1/users/me` (someone who'd rather
  delete the account than deal with it shouldn't be trapped — this
  endpoint already requires the current password, which doubles as
  proof they know the temporary one), and the session-maintenance pair
  `POST /v1/auth/token` (`grant_type=refresh_token`) / `DELETE /v1/auth/token`.
- **Refresh tokens are explicitly revoked, not just `token_version`-bumped.**
  A `token_version` bump alone only invalidates the *current* access
  token — the still-valid refresh token would happily mint a new one,
  and the user could keep working under the password they already knew,
  never noticing (or needing) the reset. Revoking refresh tokens (the
  same call already used for blocking, decision 25) forces a fresh
  `grant_type=password` login with the *new* password — which only
  succeeds if they actually received it.
- **`POST /v1/auth/change-password` is a general capability, not a
  forced-flow-only one.** It works identically whether
  `must_change_password` is set or not — this happens to close a
  separate, previously-identified gap (there was no way to change your
  own password while already logged in; only the unauthenticated
  password-reset flow existed, and that needs an `email`).
- **Changing `email` through `PATCH` resets verification.** A new
  address hasn't proven anyone owns it yet — even if the old one was
  verified — so `email_verified_at` resets to `null` and a fresh
  verification email goes out through the same shared function
  `POST /v1/auth/register` already uses.
- **No extra work for the live-stream heartbeat.** If an admin resets
  someone's password while their `GET /v1/logs/stream` connection is
  open, the `token_version` bump this already triggers is exactly what
  the heartbeat's existing re-validation ([live-streaming.md](live-streaming.md#re-validating-a-long-lived-connection))
  already watches for — the stream closes on its own, no new code
  needed specifically for this case.

## Rate limiting: throttling without lockout

Six unauthenticated auth endpoints plus two password-confirming ones
(`POST /v1/auth/change-password`, `DELETE /v1/users/me`) share a
property no other path in this API has: a single request is cheap for
the caller and expensive for everyone else — it either guesses at a
password, guesses at a one-time token, or sends an email at the
server's expense. Decision 43 throttles exactly those, and deliberately
does **nothing else**.

**There is no account lockout.** Not a failure counter on `User`, not a
`locked_until` column, not an administrative `unlock`. That option was
weighed and rejected: `username` is not a secret in this system
(`POST /v1/auth/register` answers `409 username_taken`, so names are
enumerable by design), which means lockout would hand anyone a way to
freeze anyone else's account on purpose and leave the victim waiting on
an admin. Throttling can't be weaponized that way — it slows the
attacker exactly as much as it slows a legitimate user on the same key,
and it undoes itself as time passes.

```mermaid
flowchart TD
    Req["Request to a rate-limited path"] --> IP["IP bucket:\nspend a token (EVERY request)"]
    IP -->|empty| Deny["429 + Retry-After\naction never runs:\nno password checked,\nno token issued, no email sent"]
    IP -->|ok| SubCheck{"Subject bucket\nalready empty?"}
    SubCheck -->|yes| Deny
    SubCheck -->|no| Handle["Verify credentials /\nsend the email"]
    Handle --> Ok{"Succeeded?"}
    Ok -->|yes| Refill["Subject bucket refilled to full\n(a legitimate user never meets the limiter)"]
    Ok -->|no| Spend["Subject bucket spends a token"]
    Spend --> Fail["Normal error response\n(401/400/…)"]
```

- **Two keys, both must pass.** The *IP* bucket spends a token on every
  request, which is what stops one host from spraying attempts across
  many usernames. The *subject* bucket — keyed by `username`, submitted
  `email`, or the caller's own id, depending on the endpoint — spends a
  token only on a *failed* attempt, and a success refills it completely.
  A user who simply logs in often never meets the limiter at all; a
  password guesser meets it within a handful of tries.
- **One number configures both capacities** (`rateLimitBucketCapacity`),
  which has a non-obvious consequence: from a single address the IP bucket
  always empties first, since it spends on every request while the subject
  bucket spends only on failures. So the IP bucket is what stops an
  attacker working from one address, and the subject bucket is what covers
  the **distributed** guess, where every attempt arrives from a fresh
  address and therefore a fresh, full IP bucket. That is exactly the
  division of labour two keys exist for — but making the subject limit
  stricter than the address limit would need more than one number.

- **The subject key is the string that was submitted**, not a row that
  was found. Keying on a located user would make the limiter itself an
  existence oracle — non-existent addresses would never throttle and
  would answer faster — which is exactly the leak the uniform `202`
  responses on `password-reset`/`verify-email/resend` exist to prevent.
  The cost is that callers control how many keys get created, so the
  bucket map is size-capped with LRU eviction and swept of full buckets
  periodically.
- **Token bucket, not a fixed window.** A fixed window (N per calendar
  minute) permits a 2N burst across a window boundary; a token bucket
  states the sustained rate (refill) and the tolerated burst (capacity)
  as two separate numbers. Refill is computed lazily on access — no
  per-key timer.
- **State lives only in memory.** The server is single-isolate by design
  (decision 4), so there is no shared counter store to coordinate with,
  and a restart simply clears every counter. That's an accepted
  weakness, not an oversight: whoever can restart the process already
  has operator-level access.
- **`X-Forwarded-For` is ignored unless trust is configured.**
  `trustedProxyHops` defaults to `0` (use the socket address). Without
  that distinction the limiter is either useless (everything behind a
  proxy shares one address) or trivially bypassed (a spoofed header from
  a direct client).
- **The whole thing switches off** (`rateLimitEnabled`) for development,
  for tests that would otherwise have to count attempts, and for
  deployments already fronted by the operator's own gateway.

What the limiter does *not* cover is as deliberate: `POST /v1/logs` is
governed by project quotas ([quotas-and-audit.md](quotas-and-audit.md))
and a high-entropy secret key, and management endpoints are governed by
RBAC — in neither case does request frequency buy an attacker anything
that access alone doesn't already give.

Throttling also can't stop a patient, widely distributed attacker who
stays under every limit. That's why decision 44 pairs it with audit:
`auth.login_failed` and `auth.throttled` let an admin *see* such an
attack even when the limiter isn't stopping it
([quotas-and-audit.md](quotas-and-audit.md#audit-log-log-server-audit)).

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
