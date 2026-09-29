/// What the browser does with the refresh cookie — the half nothing else sees.
///
/// `flutter test` and `packages/e2e` run where nothing holds cookies.
/// `integration_test/` runs in Chrome but mocks the network below dio, so no
/// `Set-Cookie` reaches the browser. Everything checked here needs a real
/// header, a real cookie jar, a page that can be reloaded and a second tab —
/// and the last two are what `flutter drive` cannot give at all.
///
/// Usage: `npm install && npm test`. Add `--no-build` to reuse `build/web`,
/// `--headful` to watch it.
import puppeteer from 'puppeteer-core';

import { driver, find, settle } from '../screenshots/driver.mjs';
import { build, startProxy, startServer } from './stand.mjs';

const args = process.argv.slice(2);
const shouldBuild = !args.includes('--no-build');
const headless = !args.includes('--headful');
const chromePath =
  process.env.CHROME_PATH ??
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const PROXY_PORT = 8111;
const API_PORT = 8112;
const origin = `http://localhost:${PROXY_PORT}`;
const REFRESH_COOKIE = 'structured_log_refresh';
/// What the operator picks instead of the generated one.
const CHOSEN_PASSWORD = 'chosen-by-the-operator';

const failures = [];
let checks = 0;

function check(name, condition, detail = '') {
  checks++;
  if (condition) {
    process.stdout.write(`  ✓ ${name}\n`);
  } else {
    failures.push(`${name}${detail ? ` — ${detail}` : ''}`);
    process.stdout.write(`  ✗ ${name}${detail ? ` — ${detail}` : ''}\n`);
  }
}

/// Turns on the semantics tree, the way a screen reader does.
///
/// The screenshot harness never needed this: its entry point calls
/// `ensureSemantics()` in Dart. This one drives the **shipped** `main.dart`,
/// which rightly does not — Flutter web builds the tree only when something
/// asks, and nothing had. So the first thing every page here does is press
/// the placeholder button Flutter renders for exactly this purpose, which is
/// also the honest way in: it is the same door a screen-reader user comes
/// through.
async function enableSemantics(page) {
  await page.waitForSelector('flt-semantics-placeholder', { timeout: 30_000 });
  // A DOM click, not a pointer at its coordinates — which is the one thing
  // that cannot work here. Flutter draws this button one pixel wide at
  // (-1, -1), deliberately off-screen so nobody sees it, so `page.mouse`
  // has nothing to land on. Measured: a pointer event near it leaves the
  // tree empty, `element.click()` fills it.
  await page.evaluate(() =>
    document.querySelector('flt-semantics-placeholder')?.click(),
  );
  await page.waitForSelector('flt-semantics', { timeout: 30_000 });
  await settle(page, 4);
}

/// Opens the app on a fresh page, with semantics on and the first frame up.
async function open(browser) {
  const page = await browser.newPage();
  // Before the navigation, so that nothing the boot throws goes unseen.
  page.uncaught = [];
  page.on('pageerror', (error) => page.uncaught.push(error.message));
  await page.setExtraHTTPHeaders({ 'Accept-Language': 'en-US,en' });
  await page.goto(origin, { waitUntil: 'networkidle0' });
  await settle(page, 8);
  await enableSemantics(page);
  return page;
}

/// Writes the language choice once, before any page runs the app in anger.
///
/// Pinning the language matters more than which one it is: the client takes
/// the browser's when nobody has chosen, so a harness reading its own labels
/// would look for "Sign in" on one machine and "Вход в систему" on the next —
/// this one reports `ru-RU`. `--lang=en-US` on Chrome's command line does not
/// settle it; the stored preference does.
///
/// Written straight into `localStorage` rather than by pressing the switcher
/// on the login screen, and that is not a shortcut. Pressing it rebuilds the
/// form, and a rebuilt `TextBox` replaces its input connection: the driver
/// then fills an element the framework has stopped reading, and the sign-in
/// goes out as `username=&password=` with both fields looking correct in the
/// DOM. Found by capturing the request body — from the outside everything
/// looked typed.
async function primeLocale(browser) {
  const page = await browser.newPage();
  await page.goto(origin, { waitUntil: 'domcontentloaded' });
  await page.evaluate(() =>
    localStorage.setItem('structured_log.locale', 'en'),
  );
  await page.close();
}

/// Types with real keystrokes, which is the opposite of what the screenshot
/// harness needs — and the difference is worth knowing before it costs an
/// afternoon.
///
/// There, semantics is on from the first frame (`guide_app.dart` calls
/// `ensureSemantics()`), so Flutter routes text through the semantics
/// element and `driver.type` sets its value directly; synthetic keys go
/// nowhere. Here the shipped `main.dart` starts *without* semantics and this
/// harness turns it on afterwards, so the framework's own input connection is
/// already the one it reads — setting the semantics element's value changes
/// nothing, and the sign-in goes out as `username=&password=` while both
/// fields look filled in the DOM.
///
/// Measured both ways against a real server before choosing: the request
/// body is the only place the difference shows.
async function typeInto(page, label, text) {
  const handle = await find(page, label);
  const input = await handle.evaluateHandle((node) => {
    const all = [...document.querySelectorAll('flt-semantics')];
    for (let i = all.indexOf(node); i < all.length; i++) {
      const field = all[i].querySelector('input, textarea');
      if (field) return field;
    }
    return null;
  });
  const element = input.asElement();
  if (!element) throw new Error(`no field under "${label}"`);
  const box = await element.boundingBox();
  if (!box) throw new Error(`the field under "${label}" is not on screen`);
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await settle(page, 2);
  await page.keyboard.type(text, { delay: 10 });
  await settle(page, 2);
}

/// Signs in on whatever page is given, through the UI.
async function signIn(page, password) {
  const ui = driver(page);
  await ui.waitFor('Sign in', { role: 'button' });
  await typeInto(page, 'Username', 'admin');
  await typeInto(page, 'Password', password);
  await ui.click('Sign in', { role: 'button' });
  await settle(page, 14);
}

/// The gate every first administrator meets: the password an installer
/// generated is temporary, and nothing else opens until it is replaced.
async function completeForcedChange(page, temporary, chosen) {
  const ui = driver(page);
  await ui.waitFor('Change your password');
  await typeInto(page, 'Current (temporary) password', temporary);
  await typeInto(page, 'New password', chosen);
  await typeInto(page, 'Repeat new password', chosen);
  await ui.click('Change password and continue', { role: 'button' });
  await settle(page, 16);
}

/// Everything the page itself can read — which is the question `HttpOnly`
/// exists to answer.
const readableState = (page) =>
  page.evaluate(() => ({
    cookie: document.cookie,
    local: Object.fromEntries(
      Object.keys(localStorage).map((k) => [k, localStorage.getItem(k)]),
    ),
    session: Object.fromEntries(
      Object.keys(sessionStorage).map((k) => [k, sessionStorage.getItem(k)]),
    ),
  }));

const atLogin = async (page) =>
  (await driver(page).labels()).some((l) => l.includes('Sign in'));

async function main() {
  if (shouldBuild) build();

  const server = await startServer({ port: API_PORT, cookieMode: 'on' });
  const proxy = await startProxy({ port: PROXY_PORT, apiPort: API_PORT });
  const browser = await puppeteer.launch({
    executablePath: chromePath,
    headless,
    // The locale is pinned rather than inherited. The client picks its
    // language from the browser when nobody has chosen one, so a harness that
    // took the machine's would look for "Sign in" here and "Вход в систему"
    // on the next developer's laptop. Measured the hard way: this machine
    // reports `ru-RU`.
    args: ['--window-size=1280,900'],
    // A Flutter page under a renderer this busy can take a while to answer a
    // CDP evaluate; the default 30s fires during the two-tab step.
    protocolTimeout: 180_000,
    defaultViewport: { width: 1280, height: 800 },
  });

  try {
    await primeLocale(browser);
    const page = await open(browser);
    // A tab with no session asks the server anyway — the cookie is the only
    // place a session could be — and is told 400. That answer is expected
    // and must end quietly at the login screen. It used to surface as an
    // uncaught error instead: the cross-tab lock handed the failure to a
    // Completer nobody was listening to yet. Checked before any typing,
    // because the engine's text input throws on its own under a driver.
    check(
      'a cold start with no session raises no uncaught error',
      page.uncaught.length === 0,
      page.uncaught.join(' | '),
    );
    await signIn(page, server.password);
    await completeForcedChange(page, server.password, CHOSEN_PASSWORD);

    check('signing in leaves the login screen', !(await atLogin(page)));

    // ---------------------------------------------------------- the cookie
    // Asked for on the path the cookie was set for. `page.cookies(origin)`
    // answers about `/` and a `Path=/v1/auth` cookie does not match it — it
    // is there, it is simply not sent to the page's own URL, which is the
    // narrowing the path attribute is for.
    const cookies = await page.cookies(`${origin}/v1/auth/token`);
    const refresh = cookies.find((c) => c.name === REFRESH_COOKIE);
    check('the browser stored the refresh cookie', Boolean(refresh));
    if (refresh) {
      check('it is HttpOnly', refresh.httpOnly === true);
      check('it is Secure', refresh.secure === true);
      check('it is SameSite=Strict', refresh.sameSite === 'Strict');
      check(
        'its path is /v1/auth, so change-password gets it too',
        refresh.path === '/v1/auth',
        `path=${refresh.path}`,
      );
    }

    const state = await readableState(page);
    check(
      'the page cannot read it — the whole point of HttpOnly',
      !state.cookie.includes(REFRESH_COOKIE),
      `document.cookie=${JSON.stringify(state.cookie)}`,
    );
    check(
      'and it is in neither browser store',
      !Object.keys({ ...state.local, ...state.session }).some((k) =>
        k.includes('refresh_token'),
      ),
      Object.keys({ ...state.local, ...state.session }).join(', '),
    );
    check(
      'the access token is in sessionStorage, where a reload finds it',
      Boolean(state.session['structured_log.access_token']),
    );
    check(
      'and not in localStorage, so another tab renews instead of borrowing',
      !state.local['structured_log.access_token'],
    );

    // ---------------------------------------------------------- the reload
    // One reload first, unmeasured. The forced password change just bumped
    // `token_version`, so the access token this tab is holding is already
    // dead and the next request renews — which is correct, and would be
    // counted against the reload if measured here. The question is what a
    // reload costs in a settled session.
    await page.reload({ waitUntil: 'networkidle0' });
    await settle(page, 8);
    await enableSemantics(page);

    const beforeReload = proxy.tokenGrants().length;
    await page.reload({ waitUntil: 'networkidle0' });
    await settle(page, 8);
    await enableSemantics(page);
    check('a reload stays signed in', !(await atLogin(page)));
    check(
      'and costs no renewal — its own access token is still there',
      proxy.tokenGrants().length === beforeReload,
      `${proxy.tokenGrants().length - beforeReload} extra grant(s)`,
    );

    // --------------------------------------------------------- a new tab
    const beforeNewTab = proxy.tokenGrants().length;
    const second = await open(browser);
    await settle(second, 8);
    check('a new tab restores the session from the cookie alone', !(await atLogin(second)));
    check(
      'by renewing exactly once',
      proxy.tokenGrants().length - beforeNewTab === 1,
      `${proxy.tokenGrants().length - beforeNewTab} grant(s)`,
    );
    await second.close();

    // ------------------------------------------------------- two at once
    // The scenario decision 7 was written for, and the only place it can be
    // performed: two tabs opened together read the same cookie, and without
    // the lock the second presents a token the first has just spent — which
    // the server cannot tell from theft, and answers by revoking the chain.
    // Both boot renewals held until they overlap, so the second really does
    // present a cookie the first has already spent. Without this the two
    // tabs are simply fast enough to take turns by accident — verified by
    // removing the lock and watching this check still pass.
    proxy.holdTokenGrants(2);
    const [tabA, tabB] = await Promise.all([
      browser.newPage(),
      browser.newPage(),
    ]);
    // The race itself: both navigations start before either has answered, so
    // both tabs boot holding the same cookie.
    await Promise.all([
      tabA.goto(origin, { waitUntil: 'networkidle0' }),
      tabB.goto(origin, { waitUntil: 'networkidle0' }),
    ]);
    // Only then, and one at a time in the foreground. A background tab gets
    // no `requestAnimationFrame`, so anything waiting on a frame there waits
    // for as long as you let it — which is what hung this step until the
    // wait was moved in front of the tab rather than the other way round.
    for (const tab of [tabA, tabB]) {
      await tab.bringToFront();
      await settle(tab, 12);
      await enableSemantics(tab);
    }
    check(
      'two tabs opened together: the first stays signed in',
      !(await atLogin(tabA)),
    );
    check(
      'two tabs opened together: the second too',
      !(await atLogin(tabB)),
    );

    // And the tab that was already open is still usable, which is what "the
    // chain was not revoked" looks like from where the reader is sitting.
    await page.bringToFront();
    await page.reload({ waitUntil: 'networkidle0' });
    await settle(page, 8);
    await enableSemantics(page);
    check(
      'and the tab that was already open survives them',
      !(await atLogin(page)),
    );
    await tabA.close();
    await tabB.close();

    // ------------------------------------------------------- signing out
    const ui = driver(page);
    await ui.click('admin');
    await ui.click('Sign out');
    await settle(page, 12);
    check('signing out returns to the login screen', await atLogin(page));
    const after = await page.cookies(`${origin}/v1/auth/token`);
    check(
      'and the browser no longer holds the cookie',
      !after.some((c) => c.name === REFRESH_COOKIE),
      after.map((c) => c.name).join(', '),
    );

    const third = await open(browser);
    await settle(third, 8);
    check('so a fresh tab starts at the login screen', await atLogin(third));
    await third.close();
  } finally {
    await browser.close();
    await proxy.stop();
    await server.stop();
  }

  process.stdout.write(`\n${checks - failures.length}/${checks} checks passed\n`);
  if (failures.length > 0) {
    process.stdout.write(`\n${failures.length} failed:\n`);
    for (const failure of failures) process.stdout.write(`  - ${failure}\n`);
    process.exit(1);
  }
}

main().catch((error) => {
  process.stderr.write(`${error?.stack ?? error}\n`);
  process.exit(1);
});
