# Tiến Lên Miền Nam

A real-time multiplayer Tiến Lên (Southern Vietnamese rules) card game for 2–4 players, built with Elixir, Phoenix and LiveView.

It started as a port of [nguyenank/tien-len](https://github.com/nguyenank/tien-len) (React + boardgame.io), with a deliberately different ruleset:
- all rules enforced on the server;
- no "Tiến Lên" chaining;
- cross-type chops in chop context, and an out-of-turn four-pair;
- instant wins (tới trắng);
- several games per room, with turn and disconnect timeouts.

**Status:** complete and deployed with PostgreSQL (Docker, http://localhost:4020): accounts (register / login / logout), leaderboard by 1st places, game history, virtual coins (stakes, chặt heo, thối heo, daily bonus; no real money), bots (dễ / thường), player profiles with avatars, friends, daily missions, weekly seasons, emoji reactions, hints, a phone layout, room / lobby / private chat, invites and private rooms, and an admin area (`/quan-tri`: users, coin adjustments, rooms, game history, announcements, settings). See `docs/PORTING_STATUS.md` and `docs/DEPLOY.md`.

- Rules: [`docs/RULES.md`](docs/RULES.md)
- Plan: [`docs/PORTING_PLAN.md`](docs/PORTING_PLAN.md)
- Architecture: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Background on the original: [`docs/RESEARCH.md`](docs/RESEARCH.md)

## Running

```sh
docker compose -f deploy/docker-compose.dev.yml up -d   # dev/test PostgreSQL on 127.0.0.1:5434
mix setup          # deps + database + assets
mix phx.server     # http://localhost:4010
mix test
```

## Credits

Playing-card images by **Adrian Kennard** (https://www.me.uk/cards/), released under CC0 public domain. They were also used by the original project.
