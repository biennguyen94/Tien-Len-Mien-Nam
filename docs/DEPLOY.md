# Deployment (Docker on WSL, decisions O5 and A4)

Status: deployed 2026-09-28 on the WSL Docker host with its own PostgreSQL (Phase 14). The first deploy without a database was on 2026-09-27 (Phase 10).

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
| `PHX_FORCE_SSL` | off | `true` only behind HTTPS (needs `X-Forwarded-Proto`) |
| `MAX_ROOMS` | `500` | Cap on open rooms (spam guard) |
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
- Behind an HTTPS reverse proxy, also set `PHX_URL_SCHEME=https`, `PHX_URL_PORT=443` and `PHX_FORCE_SSL=true`.
- The proxy must forward websockets (`/live/websocket`).
- Do not publish the database port.

## Verification

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
- HTTPS / reverse proxy setup.
