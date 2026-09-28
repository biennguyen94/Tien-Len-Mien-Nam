# CLAUDE.md

Tiến Lên Miền Nam: a real-time multiplayer card game (2–4 players) in **Elixir/Phoenix LiveView**.
It is a **port with deliberate rule changes** of [nguyenank/tien-len](https://github.com/nguyenank/tien-len) (React + boardgame.io).
Read `docs/` before doing any work. Do not re-analyse the original repo from scratch: it is already reverse-engineered in `docs/RESEARCH.md`.

## Stacks

| | Stack | Status |
|---|---|---|
| **Original** | React 16 + boardgame.io 0.39 + socket.io + Koa (Node), at `/home/bien_nguyen/tien-len` (git `86b2621`) | Background reference only. **Not** the source of truth for rules. Never modify. |
| **Target** | Elixir 1.20.4 / OTP 28 + Phoenix 1.8 + LiveView, OTP processes per room, PubSub, PostgreSQL (Ecto) for accounts and results | This repo, Mix app `:tien_len` (modules `TienLen` / `TienLenWeb`) at the root (O1). A database was added in Phase 11 (A4 supersedes O2). All 18 phases done: the game (1–10), PostgreSQL (11), accounts (12), results + leaderboard + history (13), deploy with the database (14), **virtual coins** with stakes, chặt heo / thối heo settlement, daily bonus / relief (15–18, RULES T19–T25). Deployed as compose project `tien-len` on port 4020 (`docs/DEPLOY.md`). Coins change only through `TienLen.Economy` (ledger, transactions, idempotency keys). Remaining: a manual check in a real browser. See `docs/PORTING_STATUS.md` and `AGENTS.md`. |

Key decisions (full log in `docs/PORTING_STATUS.md` → Decisions):
- Server-authoritative.
- 2–4 players, several games per room.
- **No "Tiến Lên" chaining** (all pass → the round ends).
- Cross-type chop hierarchy with "chop context".
- Out-of-turn four-pair.
- No 2s in consecutive pairs.
- Instant wins (tới trắng).
- 20 s turn timeout and 20 s disconnect timeout.

## Hard rules

1. **`docs/RULES.md` is the only source of truth for game rules.** Do not implement behaviour from the original source, its wiki, or Wikipedia unless `RULES.md` says so. They differ on purpose (see `RESEARCH.md` §20). A rule change is recorded in `docs/PORTING_STATUS.md` → Decisions **first**, then applied to `RULES.md`, then to code.
2. **The server is authoritative.** No rule logic in the browser (no JS validation, no hooks that decide legality). Button labels and error messages come from server-side validation.
3. **Hidden information never leaves the server.** No other player's hand or staging, no shuffle seed or PRNG state, no unredacted event log (the original leaked all three, see `docs/RISKS.md` R1–R3). Every broadcast goes through a per-seat projection. The only exception is an instant-win reveal (RULES §10).
4. **The domain core is pure.** `Card`, `Deck`, `Combination`, `Rules` and `Game` have no processes, timers, PubSub or randomness except an injected seed. Timers (turn, disconnect) live in the room process and call pure "timeout" commands.
5. **Commands carry the acting seat explicitly.** Every command is validated for that seat. Nothing acts on "the current player" implicitly (the original's bug, `RISKS.md` R4).
6. Docs label facts **VERIFIED** (checked by running code/tests), **NOT VERIFIED** or **ASSUMPTION**. Do not rely on NOT VERIFIED or ASSUMPTION items without checking.
7. **Never modify `/home/bien_nguyen/tien-len`.** To run its code, copy it to a scratch directory; this was done for the research.
8. Work phase by phase (`docs/PORTING_PLAN.md`). Do not start a phase unless asked. After each phase, update `docs/PORTING_STATUS.md` (status, results, VERIFIED items).
9. Commit only when asked. Never commit secrets (`.env` is gitignored).

## Docs map

- `docs/RULES.md` — **target rulebook** (T1–T25, incl. coins), beat matrix, instant-win hands, timeouts, Vietnamese terms
- `docs/ARCHITECTURE.md` — original architecture (summary) and target OTP/Phoenix architecture, state model, state machine
- `docs/PORTING_PLAN.md` — phases with checklists and acceptance criteria
- `docs/PORTING_STATUS.md` — current status, **decision log**, interpretations, open questions (update as work progresses)
- `docs/RISKS.md` — original security issues and bugs (not to be ported), porting risks
- `docs/DEPLOY.md` — Docker deployment on WSL (port 4020), environment variables, operations
- `docs/RESEARCH.md` — full reverse-engineering report of the original (background; its §21/§23–25 are historical)

## Commands

Toolchain (user space, shared with `open-mu-web`): `~/.local/beam` (Erlang/OTP 28, Elixir 1.20.4, Hex, `phx_new` 1.8.15). PATH is set in `~/.bashrc`; in a non-login shell prepend:
`export PATH="$HOME/.local/beam/otp/bin:$HOME/.local/beam/elixir/bin:$PATH"`.

Database for dev/test: `docker compose -f deploy/docker-compose.dev.yml up -d` (PostgreSQL on 127.0.0.1:5434), then `mix ecto.setup`. **Never** point any config at the OpenMU database (port 5433).

App: `mix deps.get` · `mix test` · `mix precommit` (compile `--warnings-as-errors`, unlock unused deps, format, test; run it before finishing any change) · `mix assets.setup` (once, downloads the tailwind/esbuild binaries) then `mix phx.server` (default **port 4010**; 4000 is taken by `openmu-web` on this machine).

Phoenix/LiveView coding guidelines from the generator are in `AGENTS.md`. Where they conflict, the hard rules above win.

Original (reference, scratch copy only): `npm install` + `npx jest`. The research results (27 pass / 12 fail) are in `RESEARCH.md` §19.
