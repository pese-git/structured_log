## 0.1.0-dev.6

 - **FEAT**(structured_log_logging): add a bridge from package:logging (#108).

## 0.1.0-dev.5

 - **FIX**(structured_log_go_router): apply filter to both ends of a redirect.
 - **FIX**(structured_log_go_router): keep a filtered location out of previous_location.
 - **FIX**(structured_log_go_router): redact the locations quoted in route_error.
 - **FEAT**(structured_log_drift): add a drift QueryInterceptor (#110).
 - **DOCS**(ru): rewrite literal translations across package READMEs and docs (#104).

## 0.1.0-dev.4

 - **DOCS**: lead every package README with its purpose and features (#102).

## 0.1.0-dev.3

 - **DOCS**: ask for structured_log ^0.3.0 in the bloc, go_router and cherrypick install snippets.

## 0.1.0-dev.2

 - **DOCS**(ru): rewrite literal translations across the Russian docs.
 - **DOCS**: describe the adapters as published pre-releases.
 - **DOCS**: cross-link the emb/ packages from each other's READMEs.

## 0.1.0-dev.1

> Note: This release has breaking changes.

 - **FEAT**(structured_log_go_router): log go_router navigation through structured_log (#90).
 - **BREAKING** **REFACTOR**: rename structured_log_http to structured_log_remote_sync (#93).

