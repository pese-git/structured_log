# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

## 2026-10-01

### Changes

---

Packages with breaking changes:

 - [`structured_log_bloc` - `v0.1.0-dev.1`](#structured_log_bloc---v010-dev1)
 - [`structured_log_cherrypick` - `v0.1.0-dev.1`](#structured_log_cherrypick---v010-dev1)
 - [`structured_log_dio` - `v0.1.0-dev.1`](#structured_log_dio---v010-dev1)
 - [`structured_log_go_router` - `v0.1.0-dev.1`](#structured_log_go_router---v010-dev1)
 - [`structured_log_http` - `v0.2.0`](#structured_log_http---v020)
 - [`structured_log_http_client` - `v0.1.0-dev.1`](#structured_log_http_client---v010-dev1)
 - [`structured_log_remote_sync` - `v0.2.0`](#structured_log_remote_sync---v020)

Packages with other changes:

 - [`structured_log` - `v0.2.2`](#structured_log---v022)
 - [`structured_log_cupertino` - `v0.1.1+1`](#structured_log_cupertino---v0111)
 - [`structured_log_flutter` - `v0.1.1+1`](#structured_log_flutter---v0111)
 - [`structured_log_material` - `v0.1.1+1`](#structured_log_material---v0111)
 - [`structured_log_fluent` - `v0.1.1+1`](#structured_log_fluent---v0111)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `structured_log_flutter` - `v0.1.1+1`
 - `structured_log_material` - `v0.1.1+1`
 - `structured_log_fluent` - `v0.1.1+1`

---

#### `structured_log_bloc` - `v0.1.0-dev.1`

 - **FEAT**(structured_log_bloc): add a BlocObserver that logs through structured_log (#87).
 - **BREAKING** **REFACTOR**: rename structured_log_http to structured_log_remote_sync (#93).

#### `structured_log_cherrypick` - `v0.1.0-dev.1`

 - **FEAT**(structured_log_cherrypick): log the cherrypick DI container through structured_log (#91).
 - **BREAKING** **REFACTOR**: rename structured_log_http to structured_log_remote_sync (#93).

#### `structured_log_dio` - `v0.1.0-dev.1`

 - **FEAT**(structured_log_dio): add a dio interceptor that logs through structured_log (#88).
 - **BREAKING** **REFACTOR**: rename structured_log_http to structured_log_remote_sync (#93).

#### `structured_log_go_router` - `v0.1.0-dev.1`

 - **FEAT**(structured_log_go_router): log go_router navigation through structured_log (#90).
 - **BREAKING** **REFACTOR**: rename structured_log_http to structured_log_remote_sync (#93).

#### `structured_log_http` - `v0.2.0`

 - **FIX**(http): refuse a serverUrl this sender can never send to (#74).
 - **FIX**(http): obey Retry-After, and refuse a duration that cannot mean anything (#69).
 - **BREAKING** **REFACTOR**: rename structured_log_http to structured_log_remote_sync (#93).

#### `structured_log_http_client` - `v0.1.0-dev.1`

 - **FEAT**(structured_log_http_client): add a package:http client that logs through structured_log (#89).
 - **BREAKING** **REFACTOR**: rename structured_log_http to structured_log_remote_sync (#93).

#### `structured_log_remote_sync` - `v0.2.0`

 - **BREAKING** **REFACTOR**: rename structured_log_http to structured_log_remote_sync (#93).

#### `structured_log` - `v0.2.2`

 - **FEAT**(structured_log): redact sensitive values, at any depth (#70).

#### `structured_log_cupertino` - `v0.1.1+1`

 - **DOCS**(openspec): archive eight finished changes.


## 2026-09-23

### Changes

---

Packages with breaking changes:

 - [`structured_log` - `v0.2.1`](#structured_log---v021)
 - [`structured_log_cupertino` - `v0.1.1`](#structured_log_cupertino---v011)
 - [`structured_log_fluent` - `v0.1.1`](#structured_log_fluent---v011)
 - [`structured_log_flutter` - `v0.1.1`](#structured_log_flutter---v011)
 - [`structured_log_material` - `v0.1.1`](#structured_log_material---v011)

Packages with other changes:

 - [`structured_log_http` - `v0.1.0`](#structured_log_http---v010)

Packages graduated to a stable release (see pre-releases prior to the stable version for changelog entries):

 - `structured_log` - `v0.2.1`
 - `structured_log_cupertino` - `v0.1.1`
 - `structured_log_fluent` - `v0.1.1`
 - `structured_log_flutter` - `v0.1.1`
 - `structured_log_http` - `v0.1.0`
 - `structured_log_material` - `v0.1.1`

---

#### `structured_log` - `v0.2.1`

#### `structured_log_cupertino` - `v0.1.1`

#### `structured_log_fluent` - `v0.1.1`

#### `structured_log_flutter` - `v0.1.1`

#### `structured_log_material` - `v0.1.1`

#### `structured_log_http` - `v0.1.0`


## 2026-09-23

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`structured_log` - `v0.2.1-dev.0`](#structured_log---v021-dev0)
 - [`structured_log_cupertino` - `v0.1.1-dev.0`](#structured_log_cupertino---v011-dev0)
 - [`structured_log_fluent` - `v0.1.1-dev.0`](#structured_log_fluent---v011-dev0)
 - [`structured_log_flutter` - `v0.1.1-dev.0`](#structured_log_flutter---v011-dev0)
 - [`structured_log_http` - `v0.1.0-dev.1`](#structured_log_http---v010-dev1)
 - [`structured_log_material` - `v0.1.1-dev.0`](#structured_log_material---v011-dev0)

---

#### `structured_log` - `v0.2.1-dev.0`

 - **FEAT**: restructure monorepo into emb/backend/frontend/packages, scaffold structured_log_server and structured_log_http.
 - **DOCS**(ru): smooth over literal-translation calques across all Russian docs (#52).

#### `structured_log_cupertino` - `v0.1.1-dev.0`

 - **FEAT**: restructure monorepo into emb/backend/frontend/packages, scaffold structured_log_server and structured_log_http.
 - **DOCS**(site): add a Packages section covering the emb/ libraries (#44).
 - **DOCS**: bring all README.md/AGENTS.md files up to date (#41).

#### `structured_log_fluent` - `v0.1.1-dev.0`

 - **FEAT**: restructure monorepo into emb/backend/frontend/packages, scaffold structured_log_server and structured_log_http.
 - **DOCS**(site): add a Packages section covering the emb/ libraries (#44).
 - **DOCS**: bring all README.md/AGENTS.md files up to date (#41).

#### `structured_log_flutter` - `v0.1.1-dev.0`

 - **FEAT**: restructure monorepo into emb/backend/frontend/packages, scaffold structured_log_server and structured_log_http.
 - **DOCS**: bring all README.md/AGENTS.md files up to date (#41).

#### `structured_log_http` - `v0.1.0-dev.1`

 - **FEAT**(structured_log_http): implement HttpLogOutput.
 - **FEAT**: restructure monorepo into emb/backend/frontend/packages, scaffold structured_log_server and structured_log_http.
 - **DOCS**(ru): smooth over literal-translation calques across all Russian docs (#52).
 - **DOCS**: bring all README.md/AGENTS.md files up to date (#41).
 - **DOCS**: add READMEs for structured_log_server and structured_log_http.

#### `structured_log_material` - `v0.1.1-dev.0`

 - **FEAT**: restructure monorepo into emb/backend/frontend/packages, scaffold structured_log_server and structured_log_http.
 - **DOCS**(site): add a Packages section covering the emb/ libraries (#44).
 - **DOCS**: bring all README.md/AGENTS.md files up to date (#41).


## 2026-09-16

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`structured_log` - `v0.2.0+1`](#structured_log---v0201)
 - [`structured_log_cupertino` - `v0.1.0`](#structured_log_cupertino---v010)
 - [`structured_log_fluent` - `v0.1.0`](#structured_log_fluent---v010)
 - [`structured_log_flutter` - `v0.1.0`](#structured_log_flutter---v010)
 - [`structured_log_material` - `v0.1.0`](#structured_log_material---v010)

Packages graduated to a stable release (see pre-releases prior to the stable version for changelog entries):

 - `structured_log` - `v0.2.0+1`
 - `structured_log_cupertino` - `v0.1.0`
 - `structured_log_fluent` - `v0.1.0`
 - `structured_log_flutter` - `v0.1.0`
 - `structured_log_material` - `v0.1.0`

---

#### `structured_log` - `v0.2.0+1`

#### `structured_log_cupertino` - `v0.1.0`

#### `structured_log_fluent` - `v0.1.0`

#### `structured_log_flutter` - `v0.1.0`

#### `structured_log_material` - `v0.1.0`


## 2026-09-11

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`structured_log_fluent` - `v0.1.0-dev.4`](#structured_log_fluent---v010-dev4)

---

#### `structured_log_fluent` - `v0.1.0-dev.4`

 - **DOCS**(structured_log_fluent): record that fluent_ui 4.16.1 is still incompatible.


## 2026-09-11

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`structured_log_cupertino` - `v0.1.0-dev.2`](#structured_log_cupertino---v010-dev2)
 - [`structured_log_fluent` - `v0.1.0-dev.3`](#structured_log_fluent---v010-dev3)
 - [`structured_log_flutter` - `v0.1.0-dev.3`](#structured_log_flutter---v010-dev3)
 - [`structured_log_material` - `v0.1.0-dev.3`](#structured_log_material---v010-dev3)

---

#### `structured_log_cupertino` - `v0.1.0-dev.2`

 - **FEAT**: add structured_log_cupertino Cupertino (iOS-style) log viewer.

#### `structured_log_fluent` - `v0.1.0-dev.3`

 - **REFACTOR**(structured_log_flutter): extract shared logLevelColor from material/fluent.
 - **REFACTOR**(structured_log_fluent): extract FluentLogViewer as an embeddable widget.
 - **FIX**(structured_log_fluent,structured_log_material): fix stale example app_test.dart assertions.
 - **FIX**(structured_log_fluent): give the example's embedded panel a flexible width.
 - **FEAT**(structured_log_fluent): make FluentLogViewer's layout responsive.
 - **FEAT**(structured_log_fluent): add category filter selector.

#### `structured_log_flutter` - `v0.1.0-dev.3`

 - **REFACTOR**(structured_log_flutter): extract shared logLevelColor from material/fluent.

#### `structured_log_material` - `v0.1.0-dev.3`

 - **REFACTOR**(structured_log_flutter): extract shared logLevelColor from material/fluent.
 - **FIX**(structured_log_fluent,structured_log_material): fix stale example app_test.dart assertions.
 - **FEAT**(structured_log_material): category filter, embeddable widget, and adaptive master-detail.


## 2026-09-10

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`structured_log_fluent` - `v0.1.0-dev.2`](#structured_log_fluent---v010-dev2)
 - [`structured_log_material` - `v0.1.0-dev.2`](#structured_log_material---v010-dev2)

---

#### `structured_log_fluent` - `v0.1.0-dev.2`

 - **FIX**: ComboBox placeholder and back button in FluentLogViewerPage.
 - **FEAT**: add a runnable web example for structured_log_fluent.
 - **FEAT**: add structured_log_fluent Fluent UI (WinUI-style) log viewer.
 - **DOCS**: add structured_log_fluent README, update workspace docs.

#### `structured_log_material` - `v0.1.0-dev.2`

 - **FEAT**: turn structured_log_material's example into a runnable web app.
 - **FEAT**: add structured_log_material Material 3 log viewer.
 - **DOCS**: add README.md/README.ru.md for the new Flutter packages.


## 2026-09-10

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`structured_log` - `v0.2.0-dev.0+1`](#structured_log---v020-dev01)
 - [`structured_log_flutter` - `v0.1.0-dev.2`](#structured_log_flutter---v010-dev2)

---

#### `structured_log` - `v0.2.0-dev.0+1`

 - **DOCS**: add README.md/README.ru.md for the new Flutter packages.

#### `structured_log_flutter` - `v0.1.0-dev.2`

 - **FEAT**: add structured_log_material Material 3 log viewer.
 - **FEAT**: add structured_log_flutter headless log-viewer core.
 - **DOCS**: add README.md/README.ru.md for the new Flutter packages.

