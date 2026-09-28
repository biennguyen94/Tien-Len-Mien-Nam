# Porting plan: boardgame.io (React) → Elixir/Phoenix LiveView

Principle: implement the rules in `RULES.md` idiomatically in Elixir. **Do not** copy behaviour from the original source where `RULES.md` differs. The server is authoritative, and hidden information stays on the server.
References: `RULES.md` (rules), `ARCHITECTURE.md` (target structure), `RISKS.md` (what must not be ported), `RESEARCH.md` (original behaviour).

Each phase ends with its tests green and `PORTING_STATUS.md` updated (status, results, VERIFIED items).

## Repository layout (decision O1)

```text
Tien-Len-Mien-Nam/
├── CLAUDE.md
├── docs/
├── lib/tien_len/          pure domain + room processes (TienLen.*)
│   ├── card.ex  deck.ex  combination.ex  rules.ex  instant_win.ex
│   ├── game.ex            pure game state machine (one game)
│   ├── room.ex            session: seats, host, sequence of games (pure)
│   └── room_server.ex     GenServer per room (timers, PubSub), Registry, DynamicSupervisor
├── lib/tien_len_web/      router, LiveViews (lobby, table), components, JS hooks
└── test/tien_len/ …       ExUnit (domain), test/tien_len_web/ … (LiveView)
```

## Phase 1 — Research — DONE (2026-09-27)

- [x] Reverse-engineer the original: architecture, state, rules, multiplayer, security, tests → `RESEARCH.md`.
- [x] Run the original's tests and probes in a scratch copy (27/39 pass; leaks and rule edge cases VERIFIED).
- [x] Compare the source, the wiki and Vietnamese Wikipedia.
- [x] Record rule decisions D, Q, R, S, I → `PORTING_STATUS.md`; consolidate into `RULES.md` (T1–T18).
- [ ] Owner confirms interpretations X1–X3 (not blocking).

## Phase 2 — Card / Deck (T1, T2, T4) — DONE (2026-09-27)

- [x] Decide O1 (+ O2); generate the Phoenix project (`--no-ecto --no-mailer`); `mix precommit` alias (from the generator).
- [x] `TienLen.Card`: struct, rank/suit order, `compare/2`, a sortable integer key (rank × 4 + suit), parse/format (`"3S"`, `"10H"`), and a display name.
- [x] `TienLen.Deck`: 52 cards, `shuffle(seed)`, `deal(n_players, seed)` → 13 cards each plus undealt cards, `lowest_holder(hands)` for card-led openings.
- [x] Tests: 41 passing (see PORTING_STATUS → Phase 2 results).
- Tests: ordering of all 52 cards; the deal has no duplicates and correct sizes for 2/3/4 players; the same seed gives the same deal; lowest holder when 3♠ (or 3♠ and 3♣) is undealt.
- Acceptance: the card order matches T4 exactly.

## Phase 3 — Combination engine (T5) — DONE (2026-09-27)

- [x] `TienLen.Combination.classify/1` → `{:ok, %Combination{type, cards, top, length}}` or `{:error, :empty | :duplicate_cards | :invalid_combination}`; `bomb?/1`.
- [x] Reject duplicate cards.
- [x] Tests: 66 passing overall, including an exhaustive check of all 1–3-card sets and a cross-check against a reference classifier (see PORTING_STATUS → Phase 3 results).
- Tests: every type at its min/max length; straights with 2 or wrap-around rejected; `KKAA22` and `QQKKAA22` **rejected** (D5); 5 pairs rejected (Q7); two triples rejected; duplicate ranks in a straight rejected.
- Acceptance: RULES §4 reproduced.

## Phase 4 — Rules engine (T3, T6, T10, T18) — DONE (2026-09-27)

- [x] `TienLen.Rules.beats/2` implementing the RULES §5.2 matrix, returning the new chop context; `play/3` (lead with the opening card, or beat).
- [x] `play_out_of_turn/2` (four-pair only, on a chop target).
- [x] Opening card check (T3) inside `play/3`; `pass/1`; `auto_lead/2` (X1).
- [x] `TienLen.InstantWin.detect(hand, mode)` → `nil` or the hand type (four 3's only when `mode == :card_led`); `winners/2`.
- [x] Error reasons usable as UI labels (see PORTING_STATUS → Phase 4 results).
- [x] Tests: 115 passing overall.
- Tests: one per matrix row, including the rejected cases (three-pair on a pair of 2s; quad or four-pair on a normal three-pair/quad; quad on A♥; triple of 2s unchoppable); same-rank pairs by suit; each instant-win hand plus near misses (5 pairs + 3 singles; a 3→K run; three 2s; four 3's in a winner-led game).
- Acceptance: every example in RULES §16 that concerns legality passes.

## Phase 5 — Pure game state (T7–T12, T15 effects, T16 actions, T18 flow) — DONE (2026-09-27)

- [x] `TienLen.Game`: `new(seats, seed, leader: …)` / `start/4`; commands `play(seat, cards)`, `pass(seat)`, `chop_out_of_turn(seat, cards)`, `timeout(seat)`, `remove(seat)`; each returns `{:ok, game, events}` or `{:error, reason}`; `check_*` dry runs.
- [x] Rounds, centre clearing, chop context, finishing, ranking, game end, instant-win end.
- [x] `Game.view(game, seat)`: the per-seat projection (T14). No other hands, no seed (the seed is not stored at all).
- [x] Tests: 143 passing overall, including 600 simulated games (see PORTING_STATUS → Phase 5 results).
- Tests: the RULES §16 scenarios end to end; property tests (card conservation, exactly one current seat while playing, never a pass on a lead, the game ends with N − 1 finishers or an instant win); timeout actions (X1).
- Acceptance: no command can act for another seat, except a valid out-of-turn four-pair.

## Phase 6 — Room process (T13, T15, T16, T17) — DONE (2026-09-27)

- [x] `TienLen.Room` (pure): seats, host, sequence of games, leader for the next game (R1, R4, I5).
- [x] `TienLen.RoomServer` GenServer: serialises commands; turn timer (20 s); disconnect timer (20 s) → `remove`; host transfer (S6, X3, X7); PubSub broadcast of events only (views are projected per subscriber). Connections via process monitors.
- [x] Registry + DynamicSupervisor; room lifecycle (the room closes when empty, X9).
- [x] Tests: 172 passing overall; timing tests repeated 30× without failure (see PORTING_STATUS → Phase 6 results).
- Tests: simultaneous out-of-turn chops (first valid wins); timers with injected clocks; crash isolation; the next-game leader.
- Acceptance: invalid commands never crash the process; no broadcast contains hidden information.

## Phase 7 — Lobby / rooms (T13) — DONE (2026-09-27)

- [x] Create/list/join/leave rooms; display name; seat tokens (O3); max 4 seats; no mid-game join; host-only start with ≥ 2 players; no spectators.
- [x] Identity plug (random player id in the signed session); lobby PubSub updates; empty rooms close.
- [x] Tests: 191 passing overall (see PORTING_STATUS → Phase 7 results).
- Tests: full room, mid-game join refused, a non-host cannot start, token reconnect, forged token rejected.

## Phase 8 — LiveView UI — DONE (2026-09-27)

- [x] Lobby LiveView, table LiveView (seats around the table, centre, hand, selection, Play/Pass buttons with server-provided reasons, turn timer, card counts, ranking, instant-win reveal).
- [x] Mapping from the original's components: `RESEARCH.md` §18. Vietnamese UI, click-to-select, original CC0 card SVGs (O4).
- [x] Tests: 204 passing overall; smoke test of the real server over HTTP.
- [ ] Manual check in a real browser (desktop + mobile), NOT VERIFIED yet.
- Tests: LiveView tests per interaction; no rule logic in JS.

## Phase 9 — Realtime — DONE (2026-09-27)

- [x] PubSub per room; each LiveView re-projects its own view on every broadcast. Connections: RoomServer process monitors (decided instead of Presence, see PORTING_STATUS).
- [x] Tests: multi-session tests; a page never shows another hand or the undealt cards, checked after every command of whole 2–4 player games (and mutation-checked).

## Phase 10 — Tests, security, reconnect, deploy — DONE (2026-09-27)

- [x] Reconnect: page reloads via the session; another device via a signed resume link (`/tiep-tuc/:token`, 24 h).
- [x] Fuzz random commands against `Game`, `Room` and `RoomServer`; catch-alls in processes and LiveViews; room cap.
- [x] Review against `RISKS.md` section A: none of R1–R9 reproducible (table in PORTING_STATUS → Phase 10 results).
- [x] Deployment (O5): Docker on WSL, port 4020, `docs/DEPLOY.md`.
- [ ] Manual check in a real browser (NOT VERIFIED yet).

## Phase 11 — Database foundation (A4) — DONE (2026-09-27)

- [x] Add `ecto_sql`, `postgrex`, `phoenix_ecto`; `TienLen.Repo`; config for dev / test / prod (`DATABASE_URL`).
- [x] Dev/test PostgreSQL container on `127.0.0.1:5434` (`deploy/docker-compose.dev.yml`); never the OpenMU database.
- [x] Test sandbox for plain tests, controllers and LiveViews; `DataCase`.
- Acceptance: the existing suite passes with the database in place; `mix ecto.setup` works.

## Phase 12 — Accounts (A2, A3, Y1–Y4, Y7) — DONE (2026-09-28)

- [x] `users` table; `TienLen.Accounts` (register, authenticate, change display name); bcrypt.
- [x] Register (3 fields) and login (2 fields) forms, logout; the session stores the user id (renewed on login); LiveViews require a user; resume links removed (Y2).
- [x] Tests: 240 passing; HTTP check of login/logout on the dev server.
- Tests: validation, unique username (case-insensitive), wrong password, session fixation (renewed session), logout disconnects LiveViews, pages require login, the room player id is the user id.

## Phase 13 — Results, leaderboard, history (A1, Y5, Y6, Y8) — DONE (2026-09-28)

- [x] `games` and `game_players` tables; the room records every finished game.
- [x] `/bang-xep-hang` leaderboard; `/lich-su` personal history of recent games (both live, login required).
- [x] Tests: 258 passing; ordering mutation-checked; dev-database check over HTTP.
- Tests: normal game, instant win (several winners), removed players, ordering, a DB failure does not stop play.

## Phase 14 — Deploy with database — DONE (2026-09-28)

- [x] Compose service `db` (PostgreSQL 18, volume, healthcheck); migrations with `bin/migrate` at every start (Z1); `DATABASE_URL` from `POSTGRES_PASSWORD` in `.env`; backup/restore notes in `DEPLOY.md`.
- [x] Verified on the containers: migrations, login, leaderboard, history over HTTP; data survives restart and down/up.
- [ ] Manual check in a real browser (NOT VERIFIED yet).
- Acceptance: the container stack runs, registration/login/leaderboard work over HTTP, data survives a restart.

## Phase 15 — Coins: ledger and balances (C1, C2, C10, E8, E9) — DONE (2026-09-28)

- [x] `users.coins` (CHECK ≥ 0) and an append-only `coin_transactions` ledger (user, amount, reason, reference, unique idempotency key).
- [x] `TienLen.Economy`: starting coins at registration, daily bonus, relief, and `apply/1` for a list of transfers in one transaction (row locks, caps at the balance, proportional sharing E5), idempotent by key.
- Tests: balances never negative, ledger sums equal balances, concurrent claims pay once, idempotency, proportional sharing and rounding.

## Phase 16 — Coins: settlement of games (C3–C9, E1–E7) — DONE (2026-09-28)

- [x] Pure `TienLen.Payout`: from a finished game (ranking, instant winners, final hands) and the round's chop chains → transfers (T21–T24).
- [x] `Game` records chop chains (start, every chop, owner, value) and emits them when a round or the game ends.
- [x] Room stake (0 or ≥ 10, changeable between games), eligibility 10×S, `RoomServer` applies chain settlements at round end and the rest at game over through `Economy`.
- Tests: every example in RULES T21–T24, chains of 1–4 chops, out-of-turn four-pair in a chain, removed players, instant win with several winners, insufficient balances, stake 0, idempotency across retries.

## Phase 17 — Coins: UI — DONE (2026-09-28)

- [x] Stake when opening a room (and between games); stake in the lobby list; balance in the header and at each seat; +/− coins in the results; daily bonus and relief buttons; coin history page; "Giàu nhất" leaderboard tab.
- Tests: LiveView tests; no page or event lets a client set an amount.

## Phase 18 — Coins: deploy — DONE (2026-09-28)

- [x] Migrations on the containers (existing accounts get 1,000, E9); smoke test; DEPLOY.md.

## Phase 19 — Admin: roles, guard, audit log, set admin (AD1, AD2, F1) — DONE (2026-09-28)

- [x] `users.role`; `admin_actions` audit table; `TienLen.Admin` context; release command `TienLen.Admin.promote/1`.
- [x] `/quan-tri` live_session guarded by `:require_admin` (every mount and event); set / remove admin on the web (F1).
- Tests: non-admins cannot reach any admin page or event; promote / demote rules; audit rows.

## Phase 20 — Admin: users (AD4, AD5, F2–F4) — DONE (2026-09-28)

- [x] Search and user detail page; lock / unlock (session kill, room removal); rename; reset password (temporary, shown once) and the player's "đổi mật khẩu"; coin adjustments through `Economy`.
- Tests: locked users cannot log in and are kicked live; password reset + change; adjustments in the ledger, no negative balances; everything audited.

## Phase 21 — Admin: dashboard, rooms, game history (AD3, AD6–AD8, F5, F6) — DONE (2026-09-28)

- [x] Dashboard numbers; room list; watch view with all hands; close room (cancel game, F5); remove a player; game history with settlements.
- Tests: counts; watch view only for admins; closing a room mid-game settles nothing and records nothing; kick.

## Phase 22 — Admin: announcements, settings, rate limit (AD9, F7, F8) — DONE (2026-09-28)

- [x] Lobby announcement banner (live); economy settings table + admin form used by `Economy`; login rate limiting.
- Tests: announcements appear live; new values apply; old ledger unchanged; the 6th failed login is refused.

## Phase 23 — Admin: deploy — DONE (2026-09-28)

- [x] Migrations on the containers; promote the first admin with the server command; smoke test; DEPLOY.md.

## Phase 24 — Chat: presence, limiter, room chat, quick phrases (CH1–CH4, G1–G4, G6) — DONE (2026-09-28)

- [x] In-memory presence (online players and where they are); dashboard "online" from it.
- [x] `TienLen.Chat`: validation (G2), shared rate limiter, quick phrases (G3).
- [x] Room chat in the room process (last 50), panel on the table page, usable during a game.
- Tests: only seated players read/write; limits and rate limit; history for newcomers; nothing in the database.

## Phase 25 — Chat: lobby chat, private chat (G5, G7) — DONE (2026-09-28)

- [x] Lobby chat process (last 100) and panel; online list in the lobby.
- [x] Private chat (last 20 per pair, 1 h expiry), floating panel on lobby and table, unread badge; offline targets refused.
- Tests: live delivery; only the two players see a private line; expiry; offline refusal.

## Phase 26 — Invites (IV1, IV3, G8–G10) — DONE (2026-09-28)

- [x] Invite list and popup (60 s, one pending per target, 10/min per inviter), accept re-checks on the server, decline/expiry shown to the inviter.
- [x] `users.accept_invites` + lobby toggle; "Chép link" hook; return to the room after login.
- Tests: accept joins; every refusal case; toggle respected; login redirect back.

## Phase 27 — Private rooms, admin chat moderation (IV2, G11, G12) — DONE (2026-09-28)

- [x] Private flag at creation + host toggle while waiting; hidden from the lobby, visible to admins.
- [x] Admin mute (`users.muted_until`) and message deletion, audited.
- Tests: private rooms not listed but joinable by link/invite; muted players refused everywhere; deletions live.

## Phase 28 — Chat and invites: deploy — DONE (2026-09-28)

- [x] Migrations on the containers; smoke test; DEPLOY.md.

## Phase 29 — Hints (H1) — DONE (2026-09-28)

- [x] `TienLen.Hint` (candidates validated by `Game`), `RoomServer.hints/2`, "Gợi ý" button.

## Phase 30 — Bots (B1–B6) — DONE (2026-09-28)

- [x] `TienLen.Bot` (dễ / thường), add / remove in rooms without stake, scheduled bot actions, no host, no records.

## Phase 31 — Phone layout, hand order; deploy (M1, M2) — DONE (2026-09-28)

- [x] Overlapping hand, compact seats, sticky actions, sort toggle; deployed.

## Phase 32 — Profile, avatars, per-player facts (P1–P4) — DONE (2026-09-28)

- [x] `game_players.chops/coins/instant`, `Stats.profile/1`, `/nguoi-choi/:username`, avatar picker.

## Phase 33 — Friends (FR1–FR5) — DONE (2026-09-28)

- [x] `TienLen.Friends`, `/ban-be`, header badge, friends first in invite / online lists.

## Phase 34 — Daily missions (M1–M4) — DONE (2026-09-28)

- [x] `TienLen.Missions`, `Economy.grant/5`, lobby card.

## Phase 35 — Weekly seasons (S1–S4) — DONE (2026-09-28)

- [x] `TienLen.Seasons` + hourly scheduler, "Tuần này" / "Tuần trước" tabs.

## Phase 36 — Emoji reactions; deploy (R1) — DONE (2026-09-28)

- [x] `RoomServer.react/3`, emoji bar; migration deployed.

## Phase 37 — Spectators (V1, V3, V4) — DONE (2026-09-28)

- [x] `RoomServer.watch/1`, `spectator_view/1`, `/phong/:id/xem`, lobby "Xem", 👀 count.

## Phase 38 — Replays; deploy (V2, V5, V6) — DONE (2026-09-28)

- [x] `games.replay`, replay capture in the room server, `TienLen.Replay`, `/van/:id`, links from history / admin.
