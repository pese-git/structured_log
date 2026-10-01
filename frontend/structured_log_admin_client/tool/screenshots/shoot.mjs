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

import { driver, settle } from './driver.mjs';
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
