// Regenerates the user guide's screenshots.
//
//   npm install && npm run shoot -- --build
//
// What it drives is `test_driver/guide_app.dart`: the shipped application on
// a mocked network, seeded by `test_driver/guide_fixture.dart`. No server, no
// database, no CORS — the reason the previous version of this script never
// reached the repository is that it needed a stand, and a script that needs a
// stand is a script nobody runs.
//
// It aims at the semantics tree rather than at coordinates. Flutter paints
// into a canvas, so a coordinate-driven script is guessing at where a widget
// settled — the failure written up at length in `test_driver/live_app.dart`.
// `guide_app.dart` switches semantics on, which puts a `<flt-semantics>`
// element with an `aria-label` behind every control, and everything below
// names what it wants.

import { spawnSync } from 'node:child_process';
import { createServer } from 'node:http';
import { createReadStream, existsSync } from 'node:fs';
import { mkdir } from 'node:fs/promises';
import { extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const here = fileURLToPath(new URL('.', import.meta.url));
const clientRoot = resolve(here, '../..');
const repoRoot = resolve(clientRoot, '../..');
const bundle = join(clientRoot, 'build/web');

const args = process.argv.slice(2);
const shouldBuild = args.includes('--build');
const outDir = resolve(
  valueOf('--out') ?? join(repoRoot, 'docs/guides/assets/user-guide'),
);
const only = valueOf('--only');
const port = Number(valueOf('--port') ?? 8099);
const chromePath =
  process.env.CHROME_PATH ??
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const VIEWPORT = { width: 1280, height: 800 };

function valueOf(flag) {
  const i = args.indexOf(flag);
  return i === -1 ? undefined : args[i + 1];
}

/** Builds the guide entry point into `build/web`. */
function build() {
  // `--no-web-resources-cdn` for the reason the deployment scripts carry it:
  // a release bundle otherwise fetches CanvasKit and Roboto from Google, and
  // a screenshot run should not depend on the network — or render different
  // glyphs depending on whether it reached it.
  const flutter = join(repoRoot, '.fvm/flutter_sdk/bin/flutter');
  const result = spawnSync(
    existsSync(flutter) ? flutter : 'flutter',
    [
      'build',
      'web',
      '--release',
      '--no-web-resources-cdn',
      '--target=test_driver/guide_app.dart',
    ],
    { cwd: clientRoot, stdio: 'inherit' },
  );
  if (result.status !== 0) process.exit(result.status ?? 1);
}

const MIME = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.css': 'text/css',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff2': 'font/woff2',
  '.symbols': 'application/octet-stream',
};

function serve() {
  const server = createServer((request, response) => {
    const path = decodeURIComponent(new URL(request.url, 'http://x').pathname);
    const file = join(bundle, path === '/' ? 'index.html' : path);
    if (!existsSync(file) || !file.startsWith(bundle)) {
      response.writeHead(404).end('not found');
      return;
    }
    response.writeHead(200, {
      'content-type': MIME[extname(file)] ?? 'application/octet-stream',
    });
    createReadStream(file).pipe(response);
  });
  return new Promise((done) => server.listen(port, () => done(server)));
}

/** The application's own semantics tree, as the browser exposes it.
 *
 * Flutter labels a control two different ways depending on what it is: an
 * `aria-label` on some, the text itself as the element's content on others
 * (a button reads `<flt-semantics role="button">Sign in</flt-semantics>`).
 * Matching reads whichever is there, which is why nothing below has to know
 * which kind a given control happens to be.
 */
const MATCH = `(node) => (node.getAttribute('aria-label') || node.textContent || '').trim()`;

const driver = (page) => ({
  async click(label, options = {}) {
    const handle = await find(page, label, options);
    await handle.click();
    await settle(page);
  },

  /// Types into the field that belongs to the visible label [label].
  ///
  /// Not `find(label)` then click: the input carries **no accessible name**
  /// of its own — `AdminTextField` draws the label as a separate line of
  /// text above it — so the label matches a caption, and clicking a caption
  /// focuses nothing. What the tree does give is order: a field's own node
  /// is the next one after its label, and it is the one holding an `input`.
  ///
  /// (That the inputs are nameless is worth fixing in the widget rather than
  /// worked around here — a screen reader announces nothing for them either.
  /// Until then, this is the honest way to reach them.)
  async type(label, text, options = {}) {
    const handle = await find(page, label, options);
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
    // Set the value and announce it, which is how a screen reader enters
    // text and the only way that works here. Synthetic key events do not:
    // with semantics on, Flutter routes typing through this element rather
    // than a hidden one of its own, and DOM focus goes straight back to
    // `<flutter-view>` — so `keyboard.type` lands nowhere. Measured, not
    // assumed: a click on the field shows the framework's focus ring while
    // both the element's value and the rendered text stay empty.
    // Focus first, with a real pointer event at the field's own box: the
    // framework only takes text from the element it considers active, so
    // setting a second field without focusing it silently changes nothing —
    // which is how a sign-in with the right password still failed.
    const box = await element.boundingBox();
    if (box) {
      await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
      await settle(page, 1);
    }
    await element.evaluate((node, value) => {
      node.value = value;
      node.dispatchEvent(new Event('input', { bubbles: true }));
    }, text);
    await settle(page);
  },

  /// Delivers [count] entries into the open live subscription, through the
  /// hook `guide_app.dart` installs. The only thing in this file that asks
  /// the application to do something no reader could do by clicking.
  async deliver(count) {
    await page.evaluate((howMany) => window.guideDeliverEntries(howMany), count);
    await settle(page, 5);
  },

  async press(key) {
    await page.keyboard.press(key);
    await settle(page);
  },

  async waitFor(label, options = {}) {
    await find(page, label, options);
  },

  /** Every label the tree currently carries — for writing a new scene. */
  async labels() {
    return page.evaluate(
      (matcher) =>
        [...document.querySelectorAll('flt-semantics')]
          .filter((node) => !node.querySelector('flt-semantics'))
          .map(eval(matcher))
          .filter((text) => text.length > 0),
      MATCH,
    );
  },
});

/// Waits for a control whose label contains [label] and answers its handle.
///
/// `exact` for the times a short name is a substring of a longer one, `nth`
/// for a list where the same label repeats, `role` for a button that sits
/// inside a row carrying the same words.
async function find(page, label, { exact = false, nth = 0, role } = {}) {
  const criteria = { label, exact, nth, role: role ?? null };
  await page.waitForFunction(
    (matcher, want) =>
      [...document.querySelectorAll('flt-semantics')].filter((node) => {
        if (node.querySelector('flt-semantics')) return false;
        if (want.role && node.getAttribute('role') !== want.role) return false;
        const own = eval(matcher)(node);
        return want.exact ? own === want.label : own.includes(want.label);
      }).length > want.nth,
    { timeout: 20000 },
    MATCH,
    criteria,
  );
  const handles = await page.$$('flt-semantics');
  const matching = [];
  for (const handle of handles) {
    const keep = await handle.evaluate(
      (node, matcher, want) => {
        // A parent in this tree carries all of its children's text, so a
        // match on an ancestor would click the middle of the screen.
        if (node.querySelector('flt-semantics')) return false;
        if (want.role && node.getAttribute('role') !== want.role) return false;
        const own = eval(matcher)(node);
        return want.exact ? own === want.label : own.includes(want.label);
      },
      MATCH,
      criteria,
    );
    if (keep) matching.push(handle);
  }
  if (matching.length <= nth) throw new Error(`no control labelled "${label}"`);
  return matching[nth];
}

/** Lets the frame after an interaction paint before anything is measured. */
async function settle(page, frames = 3) {
  for (let i = 0; i < frames; i++) {
    await page.evaluate(() => new Promise(requestAnimationFrame));
  }
  await new Promise((done) => setTimeout(done, 150));
}

async function shoot(page, name) {
  if (only && !name.startsWith(only)) return;
  await mkdir(outDir, { recursive: true });
  await page.screenshot({ path: join(outDir, `${name}.png`) });
  process.stdout.write(`  ${name}.png\n`);
}

async function main() {
  if (shouldBuild) build();
  if (!existsSync(join(bundle, 'index.html'))) {
    console.error(
      'No build at build/web — run with --build, or build the guide target first.',
    );
    process.exit(1);
  }

  const server = await serve();
  const browser = await puppeteer.launch({
    executablePath: chromePath,
    headless: true,
    defaultViewport: VIEWPORT,
    args: [`--window-size=${VIEWPORT.width},${VIEWPORT.height}`],
  });

  try {
    const page = await browser.newPage();
    await page.setViewport(VIEWPORT);
    // The guide is illustrated light. Without this the theme follows
    // whatever the machine running the script prefers, and the pictures
    // change colour depending on whose laptop regenerated them.
    // The application reports its own failures through the browser console,
    // and a scene that waits for a screen the mock never answered otherwise
    // looks like a missing label rather than a broken request.
    page.on('pageerror', (error) =>
      process.stderr.write(
        `page error: ${error.message}\n${(error.stack ?? '').slice(0, 1200)}\n`,
      ),
    );
    page.on('console', (message) => {
      if (message.type() === 'error' || message.text().includes('error')) {
        process.stderr.write(`console: ${message.text().slice(0, 300)}\n`);
      }
    });
    await page.emulateMediaFeatures([
      { name: 'prefers-color-scheme', value: 'light' },
    ]);
    const { scenes } = await import('./scenes.mjs');
    const ui = driver(page);
    for (const scene of scenes) {
      process.stdout.write(`${scene.name}\n`);
      await page.goto(`http://localhost:${port}/${scene.query ?? ''}`, {
        waitUntil: 'networkidle0',
      });
      await settle(page, 10);
      try {
        await scene.play(ui, (name) => shoot(page, name), page);
      } catch (error) {
        // A failing step is almost always "that control is not called that
        // any more", and the two things needed to fix it are what the screen
        // looks like and what it is offering. Leave both behind rather than a
        // stack trace into puppeteer.
        await page.screenshot({ path: join(outDir, '_failed.png') });
        process.stderr.write(
          `\n${scene.name}: ${error.message}\n` +
            `left ${join(outDir, '_failed.png')} behind; the screen offers:\n` +
            (await ui.labels()).map((l) => `  ${l}`).join('\n') +
            '\n',
        );
        throw error;
      }
    }
  } finally {
    await browser.close();
    server.close();
  }
}

await main();
