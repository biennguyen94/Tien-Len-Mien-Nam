# Deployment (Docker on WSL, decisions O5 and A4)

Status: deployed 2026-09-28 on the WSL Docker host with its own PostgreSQL (Phase 14). The first deploy without a database was on 2026-09-27 (Phase 10). Public deploy on 2026-09-29: VM `openmu-server` (34.177.90.124) at **https://tienlenmn.duckdns.org**, behind Caddy (see [Public VPS](#public-vps-tienlenmnduckdnsorg)).

## Topology

```text
Docker host (WSL2)
├── openmu-web      (other project)                    host 4000
├── tien-len-dev-db (dev/test only, docker-compose.dev.yml)  127.0.0.1:5434
└── compose project `tien-len` (deploy/docker-compose.yml)
    ├── tien-len     image tien-len:latest   host 4020 → 4000, restart unless-stopped
    │                runs `bin/migrate && bin/server` at every start (Z1)
    └── tien-len-db  postgres:18, volume `tien-len_tien-len-db`, healthcheck,
                     NOT published on the host (reachable only as `db` inside the network)
```

- **Kept in PostgreSQL:** accounts, game results (leaderboard, history) and coins (balances, ledger). They survive restarts and redeploys; verified with `restart` and `down`/`up`.
- **In memory:** rooms and running games (O2). A restart or redeploy ends running games; finished games are already recorded.
- Open **http://localhost:4020** (WSL forwards localhost to Windows).
- The dev server (`mix phx.server`) uses port 4010 and the dev database `tien-len-dev-db`, so it can run next to the deploy.

## Files

| File | Purpose |
|---|---|
| `Dockerfile`, `.dockerignore`, `rel/` | Release image (`mix phx.gen.release --docker`). `rel/overlays/bin/migrate` + `TienLen.Release` run the migrations. Builder `hexpm/elixir:1.20.4-erlang-28.5.0.7-debian-trixie-20260918-slim`, runner `debian:trixie-20260918-slim`. |
| `deploy/docker-compose.yml` | Services `db` and `tien-len` |
| `deploy/.env.example` | All variables (copy to `.env`) |
| `deploy/.env` | Real values: **gitignored**, `chmod 600`, excluded from the Docker build context. It holds the generated `SECRET_KEY_BASE` and `POSTGRES_PASSWORD`. |
| `deploy/docker-compose.dev.yml` | Dev/test PostgreSQL only (not used by the deploy) |

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `SECRET_KEY_BASE` | — (required) | Signs the session cookie. Changing it logs everyone out; accounts and results are not affected. Generate with `mix phx.gen.secret`. |
| `POSTGRES_PASSWORD` | — (required) | Password of the `tien_len` database user. Compose builds `DATABASE_URL=ecto://tien_len:…@db/tien_len` from it. The volume keeps the password it was **created** with: to change it later, run `ALTER USER tien_len PASSWORD '…'` in the database as well. |
| `POOL_SIZE` | `10` | Database connections |
| `PHX_HOST` | `localhost` | Public host name / IP (absolute URLs) |
| `PHX_URL_SCHEME` | `http` | `https` behind a TLS proxy |
| `PHX_URL_PORT` | `4020` | Public port in absolute URLs (`443` behind a TLS proxy) |
| `PHX_FORCE_SSL` | off | Not needed: `force_ssl` is compiled in from `prod.exs`. It only repeats the value at runtime and crashes the boot if the two differ (see [HTTPS / VPS](#https--vps)). |
| `MAX_ROOMS` | `500` | Cap on open rooms (spam guard). Admins can override it on "Cài đặt" (stored in the database). |
| `THROTTLE_BY_IP` | `true` | Also count failed logins per client IP (F8). Set to `false` on this WSL deploy: behind Docker every client has the gateway IP, so one counter would lock out everyone. Counting per username is always on. |
| `WEB_PORT` | `4020` | Host port (compose variable) |

LiveView websockets use `check_origin: :conn`: they accept the origin the page was served from.

## Operations

```bash
cd deploy
docker compose up -d --build          # first deploy / update after `git pull` (migrates automatically)
docker compose logs -f tien-len       # app logs (migrations are logged at start)
docker compose restart tien-len       # ends running games; accounts and results are kept
docker compose down                   # stop both (the data volume is kept)
docker compose down -v                # ⚠ also DELETES the database volume (all accounts and results)

docker exec tien-len bin/tien_len rpc 'IO.inspect(TienLen.Lobby.list_rooms())'   # open rooms
docker exec tien-len bin/migrate                                                  # migrations by hand
docker compose exec db psql -U tien_len -d tien_len                               # SQL shell
```

## Admins

The first admin is created on the server (there is no sign-up for admins):

```bash
docker exec tien-len bin/tien_len rpc 'IO.inspect(TienLen.Admin.promote("username"))'   # {:ok, user}; audited as promote_server
```

After that, admins give or remove the role on the web (`/quan-tri/nguoi-choi/<id>`, "Cấp quyền admin"). Every admin action is in `/quan-tri/nhat-ky` (table `admin_actions`). Economy settings and the announcement live in the `settings` table and are loaded at start.

Current admin: `bien`.

## Backup and restore

```bash
cd deploy
# backup (plain SQL; includes DROP … IF EXISTS so it can be restored over an existing DB)
docker compose exec -T db pg_dump -U tien_len -d tien_len --clean --if-exists > tien_len_$(date +%F).sql

# restore (stop the app first so nothing writes meanwhile)
docker compose stop tien-len
docker compose exec -T db psql -U tien_len -d tien_len < tien_len_YYYY-MM-DD.sql
docker compose start tien-len
```

Keep backups outside the repository: they contain password hashes.

## Smoke test after a deploy

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:4020/                        # 200 (register/login forms)
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://localhost:4020/dang-nhap -d x=1 # 403 (no CSRF token)
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:4020/bang-xep-hang           # 302 (login required)
docker compose ps                                                                      # db (healthy), tien-len Up
```

## HTTPS / VPS

- On a VPS, set `PHX_HOST` (and `WEB_PORT`).
- Behind an HTTPS reverse proxy, also set `PHX_URL_SCHEME=https` and `PHX_URL_PORT=443`.
- The proxy must forward websockets (`/live/websocket`) and send `X-Forwarded-Proto`.
- Do not publish the database port.

**`force_ssl` is compile-time.** `config/prod.exs` turns it on when the image is built: HTTP → HTTPS redirect and HSTS, except for `localhost`/`127.0.0.1`. So a public prod deploy **needs** a TLS proxy; plain `http://<ip>:4020` redirects to an HTTPS address without a certificate.

- Do not edit or comment out `force_ssl` in `prod.exs`.
- `PHX_FORCE_SSL=true` only sets the same value again at runtime. If it differs from the compiled value, the release refuses to boot and restarts in a loop:
  `the application :tien_len has a different value set for path [:force_ssl] inside key TienLenWeb.Endpoint during runtime compared to compile time`.
  Fix: `git checkout config/prod.exs`, then `docker compose up -d --build`.

## Public VPS (tienlenmn.duckdns.org)

Set up 2026-09-29 and confirmed working.

```text
VM openmu-server (34.177.90.124), firewall: tcp 80 + 443 only
└── compose project `tien-len` (docker-compose.yml + docker-compose.caddy.yml)
    ├── tien-len-caddy  caddy:2, host 80/443 (+443/udp), Let's Encrypt certificate
    │                   in volume `caddy-data` → reverse_proxy tien-len:4000
    ├── tien-len        NOT published on the host (only Caddy reaches it)
    └── tien-len-db     not published
```

### 1. DNS

```bash
curl "https://www.duckdns.org/update?domains=tienlenmn&token=<TOKEN>&ip=34.177.90.124"
dig +short tienlenmn.duckdns.org      # 34.177.90.124
```

Keep the VM IP static (reserve it on the cloud provider), otherwise it changes on stop/start and DuckDNS must be updated.

### 2. `deploy/.env` on the VM

```ini
SECRET_KEY_BASE=<mix phx.gen.secret>
POSTGRES_PASSWORD=<openssl rand -hex 24>
PHX_HOST=tienlenmn.duckdns.org
PHX_URL_SCHEME=https
PHX_URL_PORT=443
THROTTLE_BY_IP=false
MAX_ROOMS=500
# compose merges both files, no -f needed
COMPOSE_FILE=docker-compose.yml:docker-compose.caddy.yml
```

`THROTTLE_BY_IP` stays `false`: the app reads `conn.remote_ip` and does not parse `X-Forwarded-For`, so every player has Caddy's IP.

### 3. Caddy files (only on the VM, next to `docker-compose.yml`)

`deploy/Caddyfile` (indent with a tab):

```
tienlenmn.duckdns.org {
	encode zstd gzip
	reverse_proxy tien-len:4000
}
```

The port is **4000** (inside the Docker network), not 4020 (host port). With 4020, Caddy logs `connect: connection refused` and serves 502.

`deploy/docker-compose.caddy.yml`:

```yaml
services:
  tien-len:
    ports: !reset []          # compose >= 2.24

  caddy:
    image: caddy:2
    container_name: tien-len-caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data        # keeps the certificate across redeploys
      - caddy-config:/config
    depends_on:
      - tien-len

volumes:
  caddy-data:
  caddy-config:
```

Caddy redirects HTTP → HTTPS, forwards websockets and sends `X-Forwarded-Proto`, which `force_ssl` needs (`rewrite_on: [:x_forwarded_proto]`).

### 4. Deploy and check

```bash
cd ~/Tien-Len-Mien-Nam
git status --short config/            # must be empty (see force_ssl above)
cd deploy
docker compose up -d --build
docker compose logs -f caddy          # wait for "certificate obtained successfully"
docker compose ps                     # tien-len Up (not Restarting), db healthy, caddy Up

curl -s -o /dev/null -w '%{http_code}\n' https://tienlenmn.duckdns.org/   # 200
curl -sI https://tienlenmn.duckdns.org/ | grep -i strict                 # HSTS header
```

### Troubleshooting

| Caddy log / symptom | Cause |
|---|---|
| `dial tcp …:4020: connect: connection refused` | Caddyfile points to 4020; use `tien-len:4000` |
| `lookup tien-len on 127.0.0.11:53: server misbehaving` | the `tien-len` container is not running; see `docker compose logs --tail=80 tien-len` |
| `tien-len` in `Restarting (1)`, log mentions `[:force_ssl]` | `prod.exs` changed on the VM; see `force_ssl` above |

The other commands (logs, backup, admin `promote`) are the same as on WSL. The VM database is separate from the WSL one: accounts and the admin must be created there again.

## Verification

### Public VPS (2026-09-29), tienlenmn.duckdns.org

- Caddy got the Let's Encrypt certificate (http-01) on the first start.
- Two problems fixed on the way:
  - the Caddyfile pointed to port 4020 → 502;
  - `force_ssl` was commented out in the VM's `prod.exs`, so the release crash-looped. Restored with `git checkout config/prod.exs` and rebuilt.
- After the fix, the owner confirmed the site works at https://tienlenmn.duckdns.org.

### Phase 40 (2026-09-28), cards in hand

- Redeployed (no migration). `hand_audit.js` on the dev server is clean at 360–1280 px.

### Phase 39 (2026-09-28), phone layout

- Redeployed (no migration). The logged-out lobby had no horizontal overflow at 360/390/412 px. The full audit (every page, logged in) was run on the dev server with `tools/mobile-audit`: 83/83 OK.

### Phases 37–38 (2026-09-28), spectators and replays

- The `add_game_replay` migration ran at start. Via `rpc`: a spectator got no hands; a fixed 2-player game was recorded with a replay (8 steps). The test game and accounts were deleted.

### Phases 32–36 (2026-09-28), profile, friends, missions, seasons, reactions

- The `add_social_features` migration ran at start. The season scheduler pays last week's top 3 within an hour of any start (idempotent).
- Via `rpc` with 2 temporary accounts: friend request + accept, avatar, missions; last week's payout `{:ok, []}`. Accounts deleted.

### Phases 29–31 (2026-09-28), bots, hints, phone layout

- Redeployed (no migration). Via `rpc`: a human plus 3 bots played a game to the end; a 5th seat was refused; no game was recorded.

### Phases 24–28 (2026-09-28), chat and invites

- The `add_chat_invites` migration ran at start (`users.accept_invites`, `users.muted_until`).
- Through `rpc` with two temporary accounts: private room hidden from the lobby list; room chat (refused when not seated); private message; invite accepted; a lobby message posted and deleted.
- Over HTTP: a room link opened logged out → `/?next=/phong/…`, login → back to the room; the lobby shows the chat, the online list, "Không nhận lời mời" and "Riêng tư".
- Temporary accounts deleted. Chat and invites live in memory: `docker compose restart tien-len` clears them.

### Phases 19–23 (2026-09-28), admin

- The `add_admin` migration ran at container start; `THROTTLE_BY_IP=false` active.
- `TienLen.Admin.promote("bien")` over `rpc`.
- With two temporary accounts (`smoke_admin`, `smoke_player`), over HTTP:
  - admin pages 200 for the admin, 302 for a player and anonymous; "Quản trị" link only for the admin;
  - dashboard and audit log correct;
  - a locked account's login shows "Tài khoản đã bị khóa";
  - an announcement appeared on the lobby, then was cleared;
  - after 5 wrong passwords the 6th login was refused.
- Smoke accounts deleted afterwards; `bien` (admin) and `ai_ga` (a real player) kept.

### Phases 15–18 (2026-09-28), coins

- The `add_coins` migration ran at container start (coins column + `coins_not_negative` check, ledger and settlement tables).
- Through `bin/tien_len rpc`: 3 registrations got 1,000 each. A stake-100 game with a chop chain, a place payment and thối gave 1,100 / 400 / 1,500 (total 3,000), with matching ledger lines.
- Over HTTP (logged in):
  - the header shows `🪙 1.500`;
  - the lobby shows the balance, the daily-bonus button and the stake field;
  - `/lich-su-coin` lists the ledger lines;
  - `/bang-xep-hang?tab=giau` ranks by coins.
- Test accounts removed afterwards. A real account `bien` (registered after the deploy) was left untouched.

### Phase 14 (2026-09-28), with the database

- `docker compose up -d --build`: `db` became healthy first, then the app ran both migrations (`create_users`, `create_games`) and started. Later starts log "Migrations already up".
- The database port is not published on the host (`5432/tcp` internal only).
- Through the release (`bin/tien_len rpc`): 2 accounts were registered and a game was played through `RoomServer` with the real recorder; the leaderboard held the result.
- Over HTTP:
  - `/` shows the register form;
  - login with CSRF → 302;
  - `/bang-xep-hang` lists "An @prod_an 1 1 100%" and "Chi @prod_chi 0 1 0%";
  - `/lich-su` shows the game in Vietnam time.
- **Persistence:** after `docker compose restart` and after `docker compose down` + `up -d`, the same leaderboard is served, and the old session cookie is still valid.
- **Backup:** the `pg_dump` command above produced a 332-line dump containing both accounts.
- **Security:**
  - login without CSRF → 403;
  - websocket same origin → 101, foreign origin → 403;
  - `/phong/…` logged out → 302;
  - the image contains no `.env`.
- **Cleanup:** the two test accounts and their game were deleted afterwards. The production database was left empty (0 users, 0 games).

### Phase 10 (2026-09-27), before the database

- HTTP 200 / CSRF 403 / SVG / websocket origin 101 and 403 / `Endpoint.url()` = `http://localhost:4020` / no `.env` in the image.

### NOT VERIFIED

- Registration through the browser form against the container (LiveView over a real websocket). It is covered by LiveView tests and by `rpc`, not by a browser.
- HTTPS behind Caddy: confirmed working by the owner, but not every step of the smoke test above was recorded (HSTS header, websocket over `wss://`, `Endpoint.url()`).
