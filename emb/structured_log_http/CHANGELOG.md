## 0.2.0+4

 - Update a dependency to the latest release.

## 0.2.0+3

 - Update a dependency to the latest release.

## 0.2.0+2

 - Update a dependency to the latest release.

## 0.2.0+1

 - **FIX**(structured_log_http): point the migration at structured_log_remote_sync ^0.2.0.

## 0.2.0

> Note: This release has breaking changes.

 - **FIX**(http): refuse a serverUrl this sender can never send to (#74).
 - **FIX**(http): obey Retry-After, and refuse a duration that cannot mean anything (#69).
 - **BREAKING** **REFACTOR**: rename structured_log_http to structured_log_remote_sync (#93).

## 0.1.0

 - Graduate package to a stable release. See pre-releases prior to this version for changelog entries.

## 0.1.0-dev.1

 - **FEAT**(structured_log_http): implement HttpLogOutput.
 - **FEAT**: restructure monorepo into emb/backend/frontend/packages, scaffold structured_log_server and structured_log_http.
 - **DOCS**(ru): smooth over literal-translation calques across all Russian docs (#52).
 - **DOCS**: bring all README.md/AGENTS.md files up to date (#41).
 - **DOCS**: add READMEs for structured_log_server and structured_log_http.

