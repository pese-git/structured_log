# Browser end-to-end: the refresh cookie

What a **browser** does with the refresh cookie, which nothing else in this
repository can see.

```bash
npm install
npm test              # builds the client, then drives it
npm test -- --no-build   # reuse an existing build/web
npm test -- --headful    # watch it happen
```

## Why it exists

Three test layers already cover the cookie, and each stops short of the same
thing:

| Layer | Sees | Misses |
| --- | --- | --- |
| `flutter test` | the client's decisions | no browser, no cookies at all |
| `packages/e2e` | the server's real headers | `dio` on the VM stores no cookies |
| `integration_test/` | a real browser | the network is mocked below `dio`, so no `Set-Cookie` arrives |

So "the browser holds it, sends it, and the page cannot read it" had no
evidence anywhere. This harness supplies it: a real server, the shipped
bundle, one origin, and Chrome.

## The stand

`stand.mjs` builds `lib/main.dart` — the shipped entry point, not a test one —
with `STRUCTURED_LOG_BASE_URL=` empty, so the client addresses the API relative
to the page. A fifty-line proxy then serves `build/web` and forwards `/v1/` to
a real `bin/server.dart`, which is what `deploy/` does with nginx.

`http://localhost` is load-bearing: browsers treat it as a secure context, so
a `Secure` cookie is accepted without a certificate. Any other host and Chrome
would drop it in silence — the exact failure the admin guide warns operators
about.

## Four things that cost an afternoon each

**Semantics is off in the shipped build.** `guide_app.dart` (the screenshot
harness) calls `ensureSemantics()`; `main.dart` rightly does not, so there is
no tree to search until something asks. The harness presses the
`flt-semantics-placeholder` button Flutter renders for screen readers — with
`element.click()`, because that button is one pixel wide at (-1, -1) and a
pointer has nothing to land on.

**Typing is the opposite of the screenshot harness.** With semantics on from
the first frame, Flutter reads the semantics element and `driver.type` sets
its value; synthetic keys go nowhere. With semantics turned on *afterwards*,
the framework's own input connection is the live one — so here a real click
plus real keystrokes work and setting the value does not. Get it wrong and the
sign-in goes out as `username=&password=` while both fields look filled in the
DOM. Only the request body shows it.

**The language follows the browser.** This machine reports `ru-RU`, so the app
came up in Russian and every label lookup missed. `--lang=en-US` on Chrome's
command line did not settle it; writing `structured_log.locale` into
`localStorage` before the app boots does. Pressing the switcher instead
rebuilds the form and replaces the input connection — which is one way to
produce the empty sign-in above.

**A background tab gets no `requestAnimationFrame`.** Anything waiting for a
frame in a tab that is not in front waits forever. Tabs are raced by starting
their navigations together, then brought to the front one at a time to be
waited on.

## The race is forced, not hoped for

Two tabs opening together do not collide on their own — whichever asks first is
usually answered before the other asks. The first version of the two-tab check
passed with the cross-tab lock removed, which means it was testing that two
tabs work rather than that they take turns.

`holdTokenGrants(2)` holds token answers until two are in flight, so the second
really does present a cookie the first has spent. The hold has a timeout,
which is what lets the locked build through: there the second request is never
sent while the first is outstanding.

That gate is also what found the defect this harness was written to look for —
the lock was on the 401 renewal but not on the one `restoreSession` performs at
boot, which is precisely the renewal two new tabs both run.
