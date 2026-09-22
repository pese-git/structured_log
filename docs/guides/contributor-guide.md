# Contributor Guide

*Читать на [русском](contributor-guide.ru.md).*

For whoever writes code *in* this repository — any of its packages, not
just `structured_log_server`. If you're integrating your own
application with the running system instead, see the
[Developer Guide](developer-guide.md); that one is for consumers of the
system, this one is for people changing the system itself.

This guide gets you from a clean checkout to your first green PR. It
does not replace [AGENTS.md](../../AGENTS.md) — the root instructions
file is the exhaustive, continuously-updated reference for this
workspace's conventions, every non-obvious gotcha found so far, and the
full per-package deep-dive; read the section for the package you're
touching before a non-trivial change. This guide is the on-ramp to it.

## The workspace, in one picture

A [Melos](https://melos.invertase.dev/) + [FVM](https://fvm.app/)
monorepo, packages grouped by what they are, each listed by its full
path in [melos.yaml](../../melos.yaml):

| Category | What lives there |
|---|---|
| `emb/` | Libraries meant to be **embedded** in someone else's app: `structured_log` (the core logging library), its Flutter log-viewer skins (`structured_log_flutter`/`_material`/`_fluent`/`_cupertino`), and `structured_log_http` (ships logs to the server) |
| `backend/` | Standalone server processes: `structured_log_server` |
| `frontend/` | Standalone client apps with a UI: `structured_log_admin_client`, and its presentation-only component library `structured_log_admin_ui` |
| `packages/` | Anything that doesn't fit the three categories above: `structured_log_e2e`, cross-system end-to-end tests |

Each package has its own `README.md`/`README.ru.md`; several also have a
`doc/ARCHITECTURE.md` for internal design aimed at contributors
(`emb/structured_log/doc/ARCHITECTURE.md` is the reference example).
[docs/architecture/](../architecture/) covers the design that spans
`structured_log_server`/`structured_log_http`/`structured_log_admin_client`
together, since no single package's own doc is the right place for a
cross-package protocol decision.

## Getting set up

```bash
# 1. Pin the Flutter SDK this workspace uses (see .fvmrc) — not "stable",
#    an exact version, so it doesn't drift under you between sessions.
fvm install
fvm use

# 2. Install melos itself (the root pubspec.yaml exists only for this —
#    it isn't a package in melos.yaml's own package list).
dart pub get

# 3. Link every package to every other package it depends on inside
#    this workspace (writes pubspec_overrides.yaml per package; those
#    are gitignored, regenerate them any time with this command).
dart run melos bootstrap
```

Requires the Dart/Flutter SDK (via FVM — don't use a system-wide
install, the pin exists precisely so everyone's toolchain matches) and,
for `structured_log_server`'s PostgreSQL-backed tests and the bundled
`deploy/` setup, Docker.

**The CI pin and the local pin are independent, and that's a known trap.**
[.github/workflows/ci.yml](../../.github/workflows/ci.yml) uses
`dart-lang/setup-dart`/`subosito/flutter-action` on the `stable` channel
directly, not FVM — so CI always runs the SDK that was current when the
job started, while your local `.fvmrc` pin can quietly fall behind.
`dart format` changes its output between SDK versions, so a stale local
pin manifests as `dart format --set-exit-if-changed` disagreeing between
your machine and CI on code neither side actually reformatted wrong.
If you hit that, `fvm use <version-from-ci>` and re-run `melos bootstrap`
before assuming your code is the problem.

Verify the setup:

```bash
dart run melos run analyze
dart run melos run test
```

If `melos` is on your `PATH` globally and working, plain `melos <cmd>`
(without `dart run`) works the same way — but if that binary was built
against a different Dart SDK than this workspace pins, prefer `dart run
melos` (the root `pubspec.yaml`'s `dev_dependencies` exist for exactly
this fallback).

## Everyday commands

Run from the repository root; Melos fans each one out per package:

```bash
dart run melos run analyze        # dart analyze, every package
dart run melos run format:check   # dart format --set-exit-if-changed, every package
dart run melos run format         # dart format (writes), every package
dart run melos run lint           # analyze + format:check together
dart run melos run test           # test:dart + test:flutter (below)
dart run melos run test:e2e       # packages/e2e — NOT part of `test`, see below
dart run melos run generate       # build_runner for structured_log_server + structured_log_admin_client
```

`test` is actually two steps under the hood
(`test:dart` — plain `dart test` for the Dart-only packages;
`test:flutter` — `flutter test` for everything Flutter-based), split
because they use different test runners, not because either is
optional. `test:e2e` is separate on purpose: every case in
`structured_log_e2e` starts `bin/server.dart` as a real OS process
(a `dart run` compile per test file) and needs the server's and the
admin client's generated code to already exist — run `generate` first.

For one package at a time, `cd` into it and use the tool directly —
Melos is a fan-out convenience, not a requirement:

```bash
cd backend/structured_log_server
dart pub get
dart test                                    # everything except tagged suites
dart test --exclude-tags integration --exclude-tags postgres   # fast inner loop
dart test --tags integration                 # spawns a real server process
dart test --tags postgres --concurrency=1    # needs a real PostgreSQL — see below
```

```bash
cd frontend/structured_log_admin_client
flutter test
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/user_flow_test.dart -d web-server --browser-name=chrome
```

### Code generation

`structured_log_server` and `structured_log_admin_client` are the two
packages that use `build_runner` (`drift`/`freezed`/`json_serializable`,
plus `shelf_router_generator`/`retrofit_generator` respectively) — a
deliberate, narrow exception to this workspace's otherwise no-magic,
no-codegen convention (see
[architecture/README.md](../architecture/README.md#principles-that-recur-across-the-design)).
Generated files (`*.g.dart`, `*.freezed.dart`) are **not committed** —
nothing in either package compiles from a fresh checkout until you run:

```bash
dart run melos run generate
# or, inside one of the two packages:
dart run build_runner build --delete-conflicting-outputs
```

Run this again any time you change a `drift` table, a `freezed` model,
an `@Route` annotation, or a `retrofit` `@RestApi` interface — a stale
generated file fails loudly (a missing symbol), not silently.

### Tests that need a real PostgreSQL

`structured_log_server` has a `postgres` test tag
(`dart_test.yaml`) for the dialect-sensitive code path
(`--db-backend=postgres`) — excluded from the default run, and it needs
a live instance plus `--concurrency=1` (files in this tag share one
physical database with no per-file isolation the way SQLite's
`NativeDatabase.memory()` gives every other test, and corrupt each
other's fixtures run together at default concurrency):

```bash
docker run -d --name pg-dev -p 5432:5432 \
  -e POSTGRES_PASSWORD=dev -e POSTGRES_DB=structured_log_test postgres:16-alpine

STRUCTURED_LOG_TEST_POSTGRES_PASSWORD=dev \
  dart test --tags postgres --concurrency=1
```

CI runs this same tag against a GitHub Actions service container — see
[operations/configuration.md](../operations/configuration.md) and
[admin-guide.md](admin-guide.md#kubernetes) for the same backend from
the *operating* side, if that's what brought you here instead.

## Making a change: OpenSpec-first for behavior, plain commits for the rest

This repository tracks non-trivial design decisions as **OpenSpec
changes** under [openspec/changes/](../../openspec/changes/) — four
documents: a `proposal.md` (what and why), a `design.md` (every
alternative considered and why it lost), `specs/*.md` (normative
requirements), and a `tasks.md` (the implementation checklist). All
four are written **in Russian** (identifiers, flags, and code stay
as-is). Whether your change needs this artifact set or not is the
first thing to work out, not an afterthought:

- **New capability, or a change to an existing contract** (a new
  endpoint, a new config setting, a storage-backend choice, an RBAC
  (role-based access control) rule) — start an OpenSpec change first.
  The `openspec-new-change` skill scaffolds it; `openspec-apply-change`
  walks `tasks.md` section by section as you implement;
  `openspec-archive-change` closes it out once merged.
  [add-postgres-backend](../../openspec/changes/add-postgres-backend/)
  is a complete, recent example worth reading end to end — proposal
  through a fully checked-off `tasks.md`, including places the original
  plan turned out to be wrong and was revised against real evidence.
- **A bug fix, a docs correction, a dependency bump, a refactor with no
  behavior change** — a plain commit is enough; no proposal/design/specs
  needed. These three product guides (this one included) and the
  Kubernetes deployment section were both added this way.

When in doubt, `openspec-onboard` (a skill in this repo) explains the
workflow from scratch; `openspec-explore` is the read-only way to browse
what's active or already archived without starting anything.

## Git conventions

- **Branch before committing — never commit directly to `master` or
  `develop`.** Open a PR against `develop` (the integration branch);
  `master` is releases.
- **[Conventional Commits](https://www.conventionalcommits.org/)**:
  `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `perf:`, `test:`,
  `build:`, `ci:`, `revert:` — a breaking change gets `!` after the type
  or a `BREAKING CHANGE:` footer. This isn't just style: `melos version`
  reads this history to pick each package's next semver bump
  automatically, working from the last `<package>-v<version>` tag.
- **Never hand-edit `CHANGELOG.md`.** Only `melos version` writes it —
  not to add an entry, and not to "clean up" after a run that reformatted
  it. This is a deliberate maintainer decision, not a gap.
- Every package versions independently — its own tag line, its own
  changelog.

## Before opening a PR

The same four checks, every time, mirroring
[AGENTS.md](../../AGENTS.md)'s own closing checklist:

1. `dart analyze` (or `flutter analyze`) — clean, no warnings.
2. Tests green — the package's own suite at minimum; run the workspace
   `melos run test` if the change could plausibly affect another
   package.
3. `dart format --set-exit-if-changed .` — formatted.
4. If the change touches public behavior, the package's own
   `README.md`/`README.ru.md` is updated to match — **except**
   `CHANGELOG.md`, which you never touch by hand (above).

CI ([.github/workflows/ci.yml](../../.github/workflows/ci.yml)) has to
be green on every job before a PR merges — one job per
package-with-tests, plus `server` (SQLite + integration + PostgreSQL
suites, three separate steps so the log shows which failed),
`admin-client-flow` (a real-browser drive of the operator's path, not
`flutter test` — it catches defects the fake-input test binding
structurally can't reproduce), and `e2e` (the whole system, one process
tree, `packages/e2e`). Reproduce any of them locally with the commands
in ["Everyday commands"](#everyday-commands) above before pushing —
cheaper than a round trip through Actions.

## Testing discipline worth adopting

Two habits this codebase leans on hard, worth internalizing rather than
picking up by osmosis:

- **Mutation-test a new regression test before trusting it.** Having
  written a test that's supposed to catch a specific bug, temporarily
  revert the fix and confirm the test actually goes red — then restore
  the fix. A test that stays green either way isn't exercising what you
  think it is. This is how almost every regression test added across
  this codebase's history was verified, not an occasional extra step.
- **Reach for a real instance before a large refactor, not after.** More
  than one plan in this repository's `design.md` history started from a
  documentation claim that turned out to be wrong once checked against
  actual running code — caught by verifying early, before hundreds of
  call sites were touched on a false premise, not by getting partway
  through and backing out. When a plan is about to touch many places,
  spend five minutes confirming its premise against the real system
  first.

## Where to go deeper

- **[AGENTS.md](../../AGENTS.md)** — the authoritative, continuously
  maintained reference: every package's non-obvious behavior, every
  toolchain trap already hit once, the full command list, CI in detail.
  Read the section for the package you're changing before anything
  beyond a trivial fix.
- **[docs/architecture/](../architecture/)** — why the
  `structured_log_server` system's design is shaped the way it is,
  topic by topic, tracing back to specific decisions.
- **[openspec/changes/](../../openspec/changes/)** — the full decision
  record for every non-trivial change, active and archived; the best
  place to see *how* a decision got made, not just what it landed on.
- Each package's own `README.md` and (where it exists) `doc/ARCHITECTURE.md`.
