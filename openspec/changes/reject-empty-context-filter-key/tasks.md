## 1. Reject the shape that breaks

- [x] 1.1 Measure the boundary before choosing it: run SQLite's `json_extract` over a bound path for every key shape this endpoint can produce. Only an empty segment (`$.`, `$..`, `$..a`) is refused; spaces, quotes, brackets, non-ASCII and a trailing dot are all accepted.
- [x] 1.2 Extract the key out of `parseLogFilter` into a function that throws `ApiError.invalidRequest` with `details.field` for an empty segment, and explains in its doc comment what each backend does with such a key otherwise.
- [x] 1.3 `test/http/log_query_params_test.dart`: the four rejected shapes, the trailing dot that stays accepted, and the list of odd-but-valid keys that must keep working.

## 2. Verification

- [x] 2.1 Reproduce the defect against a running server before the fix: `context.=x` and `context..=x` both answer `500`.
- [x] 2.2 Confirm against a running server built from this branch: the same requests answer `400` with the envelope, while `context.user_id`, `context.a.`, `context.a b` and a Cyrillic key answer `200`.
- [x] 2.3 `dart analyze`, `dart format --set-exit-if-changed`, `dart test --exclude-tags postgres` for `structured_log_server`.
- [ ] 2.4 CI green on every job, including the `postgres` tag — the PostgreSQL half of this (`#>> '{}'` returning the whole document) has no local instance to check against.

## 3. Documentation

- [x] 3.1 `docs/api/http-api.md` / `.ru.md`: the parameter row states that a dotted key is a nested path and that an empty segment is a `400`.
