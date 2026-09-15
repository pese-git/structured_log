# Deployment

Self-hosted `structured_log`: the API and the admin client behind one nginx,
on one origin.

```bash
cd deploy
./deploy.sh
```

Then open `http://localhost:8080`. The first administrator's generated
password is printed once, as a warning:

```bash
docker compose logs server | grep -i 'temporary password'
```

It has to be changed at first sign-in — the server answers
`403 must_change_password` to everything else until it is.

## What runs

| Service | Image | What it does |
|---|---|---|
| `server` | built from `backend/structured_log_server/Dockerfile` | The API. Not published to the host — reachable only through the proxy. |
| `web` | built from `frontend/structured_log_admin_client/Dockerfile` | nginx: the client's static files, and `/v1/` proxied to `server`. |

SQLite lives on the named `data` volume. Nothing else is persistent.

## Why one origin

**The server sends no CORS headers.** Not an oversight in this compose file —
there is no CORS anywhere in the server, its specs or its design. A browser
client served from a different host therefore cannot call the API at all: the
preflight goes unanswered and every request fails before it is sent.

So the client is served *beside* the API rather than pointed at it. Its bundle
is built with an empty base URL, every request goes out relative to the page,
and the same image serves any domain without rebuilding.

If the API ever needs to be reachable from elsewhere, that is a server change
(a CORS middleware and a decision about allowed origins), not a proxy setting.

## Configuration

`.env` — copied from `.env.example` on first run, read by compose:

| | |
|---|---|
| `STRUCTURED_LOG_PUBLIC_PORT` | Host port the client answers on. Default 8080. |
| `STRUCTURED_LOG_LOG_LEVEL` | `debug`/`info`/`warning`/`error`. |
| `STRUCTURED_LOG_BOOTSTRAP_ADMIN_*` | Whether to create the first administrator at startup, and under what name. |

Everything else is set in `docker-compose.yml`, where it belongs to the shape
of this deployment rather than to the host: the database path, JSON log
output, and `TRUSTED_PROXY_HOPS=1` for the nginx in front.

That last one matters. The server counts hops from the **right** of
`X-Forwarded-For` to find the caller's address, and buckets rate limits by it.
Set it too high and a caller can spoof the address by sending their own header;
too low and everyone shares one bucket. One proxy in front means `1`.

### The signing secret

`deploy/secrets/jwt_signing_secret`, generated on first run, mounted read-only,
git-ignored.

It is a file rather than an environment variable because every secret this
server takes can come from `<VAR>_FILE`, and a file does not show up in
`docker inspect` or in a process listing. Replacing it invalidates every token
already issued, signing everyone out; leaking it lets whoever has it mint a
token for any account.

## Operating it

```bash
docker compose logs -f server        # JSON lines, one per request
docker compose ps                    # health included
docker compose down                  # stop, keep the data volume
docker compose down -v               # stop and delete the database
```

To re-create an administrator on a database that already has users — the
startup bootstrap never fires there:

```bash
docker compose run --rm \
  -e STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD='...' \
  server create-admin --bootstrap-admin-username=admin
```

## Rebuilding

`./deploy.sh` rebuilds what changed. After a Dart or Flutter SDK bump, or when
an image looks stale, `./deploy.sh --rebuild` builds both from scratch.

The client's web bundle is built **on the host**, by the Flutter SDK this
repository pins, and copied into the nginx image. There is no official Flutter
Docker image, and a community one is not something to add to a deployment path
without examining it; the SDK is already here.

---

Russian version: [README.ru.md](README.ru.md)
