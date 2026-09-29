/// The deployment, in miniature: one origin, a real server, a real bundle.
///
/// Everything this file exists for comes down to the cookie being real. The
/// other browser run (`integration_test/`) mocks the network below dio, so no
/// `Set-Cookie` ever reaches Chrome and none is ever sent back — which makes
/// it useless for the half of `add-refresh-token-cookie` that is the
/// browser's behaviour rather than the application's.
///
/// Three things have to hold at once, and each one is a line below:
///
///   * **One origin.** `SameSite=Strict` and a `Path=/v1/auth` cookie only
///     mean anything if the page and the API share an origin, which is what
///     the bundled `deploy/` does with nginx. Here a fifty-line proxy does
///     it: `/v1/` to the server, everything else out of `build/web`.
///   * **An empty base URL** in the bundle, so the client addresses the API
///     relative to the page it was served from — again what `deploy/` builds.
///   * **`http://localhost`**, which browsers count as a secure context, so a
///     `Secure` cookie is accepted without a certificate. Any other host and
///     Chrome would drop it silently — the very failure this change documents
///     for operators.
import { spawn, spawnSync } from 'node:child_process';
import { createServer, request as httpRequest } from 'node:http';
import { createReadStream, existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = fileURLToPath(new URL('.', import.meta.url));
export const clientRoot = resolve(here, '../..');
export const repoRoot = resolve(clientRoot, '../..');
const bundle = join(clientRoot, 'build/web');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.json': 'application/json',
  '.css': 'text/css',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff2': 'font/woff2',
  '.symbols': 'application/octet-stream',
};

/// Builds the **shipped** entry point, not a test one.
///
/// `STRUCTURED_LOG_BASE_URL=` (empty) is what `deploy/deploy.sh` builds with,
/// and it is load-bearing here: an absolute URL would make every request
/// cross-origin and the cookie would never be sent.
export function build() {
  const flutter = join(repoRoot, '.fvm/flutter_sdk/bin/flutter');
  const result = spawnSync(
    existsSync(flutter) ? flutter : 'flutter',
    [
      'build',
      'web',
      '--release',
      '--no-web-resources-cdn',
      '--dart-define=STRUCTURED_LOG_BASE_URL=',
    ],
    { cwd: clientRoot, stdio: 'inherit' },
  );
  if (result.status !== 0) process.exit(result.status ?? 1);
}

/// Starts `bin/server.dart serve` on an empty database and waits for it to
/// announce itself, answering the bootstrap password it printed once.
export async function startServer({ port, cookieMode }) {
  const directory = mkdtempSync(join(tmpdir(), 'structured-log-browser-e2e-'));
  const child = spawn(
    'dart',
    [
      'run',
      'bin/server.dart',
      'serve',
      `--db-path=${directory}/e2e.sqlite`,
      `--http-port=${port}`,
      `--refresh-token-cookie=${cookieMode}`,
      // Sign-ins, renewals and password changes all spend from one bucket
      // keyed on this address, and every tab here is that address.
      '--rate-limit-bucket-capacity=200',
    ],
    {
      cwd: join(repoRoot, 'backend/structured_log_server'),
      env: {
        ...process.env,
        STRUCTURED_LOG_JWT_SECRET: 'browser-e2e-secret-long-enough-for-policy',
        STRUCTURED_LOG_LOG_FORMAT: 'json',
      },
    },
  );

  const transcript = [];
  let password;
  const ready = new Promise((done, fail) => {
    const deadline = setTimeout(
      () => fail(new Error(`server never listened\n${transcript.join('\n')}`)),
      90_000,
    );
    let buffered = '';
    const read = (chunk) => {
      buffered += chunk;
      const lines = buffered.split('\n');
      buffered = lines.pop() ?? '';
      for (const line of lines) {
        transcript.push(line);
        password ??= bootstrapPasswordOf(line);
        if (line.includes('Listening on')) {
          clearTimeout(deadline);
          done();
        }
      }
    };
    child.stdout.setEncoding('utf8').on('data', read);
    child.stderr.setEncoding('utf8').on('data', (chunk) =>
      transcript.push(chunk),
    );
  });

  await ready;
  if (!password) {
    child.kill('SIGKILL');
    throw new Error(
      `the server started without printing a bootstrap password\n${transcript.join('\n')}`,
    );
  }

  return {
    password,
    transcript,
    async stop() {
      child.kill('SIGTERM');
      await new Promise((done) => {
        const give = setTimeout(() => {
          child.kill('SIGKILL');
          done();
        }, 15_000);
        child.on('exit', () => {
          clearTimeout(give);
          done();
        });
      });
      rmSync(directory, { recursive: true, force: true });
    },
  };
}

/// The password the server generated for its first administrator, printed
/// once at `warning` level and available nowhere else.
function bootstrapPasswordOf(line) {
  if (!line.includes('bootstrap.warning')) return null;
  try {
    const entry = JSON.parse(line);
    const message = entry?.message;
    if (typeof message !== 'string') return null;
    return /"admin": (\S+) —/.exec(message)?.[1] ?? null;
  } catch {
    return null;
  }
}

/// One origin over two upstreams, plus a tally of what went to the API.
///
/// The tally is how "a reload costs no renewal" becomes an assertion rather
/// than a claim: count the `POST /v1/auth/token` the page caused.
export async function startProxy({ port, apiPort }) {
  const apiCalls = [];

  /// Holds token-grant answers back until several are in flight at once.
  ///
  /// Two tabs opening together do not reliably race on their own: whichever
  /// asks first is usually answered before the other asks, so the second
  /// presents the rotated cookie and nothing collides. That is what made the
  /// first version of the two-tab check pass with the cross-tab lock removed
  /// — it was testing that two tabs work, not that they take turns.
  ///
  /// Holding the answers makes the overlap certain, and it is not a contrived
  /// one: it is what a slow server looks like, which is exactly when the race
  /// happens in the wild. Released as soon as [count] are waiting, or after
  /// [timeoutMs] — the timeout is what lets the *locked* build through, since
  /// there the second request is never sent while the first is outstanding.
  let gate = null;
  const arm = (count, timeoutMs) => {
    const waiting = [];
    const release = () => {
      if (gate?.timer) clearTimeout(gate.timer);
      gate = null;
      for (const done of waiting) done();
    };
    gate = {
      waiting,
      count,
      timer: setTimeout(release, timeoutMs),
      release,
    };
  };

  const server = createServer((incoming, response) => {
    const url = new URL(incoming.url, 'http://x');
    if (url.pathname.startsWith('/v1/')) {
      apiCalls.push(`${incoming.method} ${url.pathname}`);
      const gated = gate !== null && url.pathname === '/v1/auth/token';
      const upstream = httpRequest(
        {
          host: '127.0.0.1',
          port: apiPort,
          method: incoming.method,
          path: incoming.url,
          headers: { ...incoming.headers, host: `127.0.0.1:${apiPort}` },
        },
        async (upstreamResponse) => {
          if (gated) {
            const chunks = [];
            for await (const chunk of upstreamResponse) chunks.push(chunk);
            const held = new Promise((done) => {
              const open = gate;
              open.waiting.push(done);
              if (open.waiting.length >= open.count) open.release();
            });
            await held;
            response.writeHead(
              upstreamResponse.statusCode ?? 502,
              upstreamResponse.headers,
            );
            response.end(Buffer.concat(chunks));
            return;
          }
          response.writeHead(
            upstreamResponse.statusCode ?? 502,
            upstreamResponse.headers,
          );
          upstreamResponse.pipe(response);
        },
      );
      upstream.on('error', () => response.writeHead(502).end('upstream'));
      incoming.pipe(upstream);
      return;
    }

    const path = decodeURIComponent(url.pathname);
    const file = join(bundle, path === '/' ? 'index.html' : path);
    // A single-page app: an unknown path is a route, not a missing file.
    const target = existsSync(file) && file.startsWith(bundle)
      ? file
      : join(bundle, 'index.html');
    response.writeHead(200, {
      'content-type': MIME[extname(target)] ?? 'application/octet-stream',
    });
    createReadStream(target).pipe(response);
  });

  await new Promise((done) => server.listen(port, '127.0.0.1', done));
  return {
    apiCalls,
    tokenGrants: () => apiCalls.filter((c) => c === 'POST /v1/auth/token'),
    /// Makes the next [count] token grants overlap, or gives up after
    /// [timeoutMs] — see the note on the gate above.
    holdTokenGrants: (count, timeoutMs = 6000) => arm(count, timeoutMs),
    stop: () => new Promise((done) => server.close(done)),
  };
}
