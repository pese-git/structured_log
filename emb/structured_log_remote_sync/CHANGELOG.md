## 0.2.0+3

 - **FIX**(structured_log_remote_sync): encode each entry when it is logged, so one value cannot cost the batch.
 - **DOCS**(structured_log_remote_sync): say entries are encoded when they are logged.

## 0.2.0+2

 - **DOCS**(ru): rewrite literal translations across the Russian docs.
 - **DOCS**: cross-link the emb/ packages from each other's READMEs.

## 0.2.0+1

 - **FIX**(structured_log_remote_sync): name ^0.2.0 in the install instructions.

## 0.2.0

> Note: This release has breaking changes.

 - **BREAKING** **REFACTOR**: rename structured_log_http to structured_log_remote_sync (#93).

## 0.1.0

 - Graduate package to a stable release. See pre-releases prior to this version for changelog entries.

## 0.1.0-dev.1

 - **FEAT**(structured_log_http): implement HttpLogOutput.
 - **FEAT**: restructure monorepo into emb/backend/frontend/packages, scaffold structured_log_server and structured_log_http.
 - **DOCS**(ru): smooth over literal-translation calques across all Russian docs (#52).
 - **DOCS**: bring all README.md/AGENTS.md files up to date (#41).
 - **DOCS**: add READMEs for structured_log_server and structured_log_http.

