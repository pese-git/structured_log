## 1. Make the strict policy possible

- [x] 1.1 Add `--no-web-resources-cdn` to the web build in `deploy/deploy.sh` and `deploy/k8s/build-images.sh`, with a comment saying what it prevents. Without it the bundle boots CanvasKit from `www.gstatic.com` and fetches Roboto from `fonts.gstatic.com`, which no `'self'` policy can allow.
- [x] 1.2 Confirm on a real `flutter build web --release --no-web-resources-cdn` that the engine loads from `/canvaskit/` and nothing is requested off-origin.

## 2. Headers

- [x] 2.1 `frontend/structured_log_admin_client/nginx.conf`: the five headers at server level with `always`, each with the reason it is there and, where a directive is loosened, why.
- [x] 2.2 `deploy/proxy/nginx.conf.template`: `Referrer-Policy` on the `/v1/` location only — the API's responses never pass through the `web` image. Nothing on `/`, so no header is sent twice. `X-Content-Type-Options` is **not** added: `package:shelf` already sends it (found by asking a running server, after a first draft that would have duplicated it).
- [x] 2.3 `site/nginx.conf`: the same set, with a `script-src` that admits Starlight's inline scripts and Google Fonts, and a comment stating plainly what the policy still buys and what tightening it would take.
- [x] 2.4 No `Strict-Transport-Security` anywhere: neither container terminates TLS.

## 3. Verification by observation

- [x] 3.1 Serve the release bundle with the headers **parsed out of the shipped `nginx.conf`** rather than retyped, so the test cannot drift from the config. Result: no console errors, no off-origin requests, `flutter-view` mounted.
- [x] 3.2 Serve a real `npm run build` of the site under its policy: no console errors, six client-rendered Mermaid diagrams become SVG, Pagefind search (WebAssembly in a worker) returns results.
- [x] 3.3 Confirm the failure mode this guards: the same policy over a bundle built *without* the flag leaves a blank page and `Failed to fetch dynamically imported module`.

## 4. Documentation

- [x] 4.1 `docs/guides/admin-guide.md` / `.ru.md`: what ships, why HSTS is the terminator's job, the `connect-src` caveat for a separate-origin API, and that the panel no longer calls Google.

## 5. On the running stand

- [x] 5.1 Reproduce the `deploy/` topology on one origin — release bundle plus `/v1/` proxied to the running server — with both header sets parsed out of the shipped configs. Sign in and walk the screens: zero CSP violations, zero off-origin requests, zero failed requests, and the API calls (`/v1/auth/token`, `/v1/groups`, `/v1/users`) go through under `connect-src 'self'`.
- [x] 5.2 Attribute what the run does report: two `pageerror`s appear identically with the headers removed, so they predate this change.
- [x] 5.3 Exercise the live feed, the one thing `connect-src` governs that an ordinary request does not: a streaming `fetch` of `GET /v1/logs/stream` from inside the page answers `200 text/event-stream` and delivers its first frame, with no violation.
- [x] 5.4 Confirm no header arrives twice on an API response.

## 6. Verification

- [ ] 6.1 CI green on every job.
- [ ] 6.2 `nginx -t` on all three configs. **Not done here** — neither nginx nor Docker is available on this machine, so only a structural check (balanced blocks, terminated directives) was possible. Run it before merging, or let the first image build do it.
