# Architecture

Part 1 summarises the original (details in `RESEARCH.md` §2–4, §15–18). Part 2 is the **proposed** target architecture. It is not implemented yet, and names depend on O1 in `PORTING_STATUS.md`.

## Part 1 — Original (`nguyenank/tien-len@86b2621`)

```text
Browser ── React 16 (CRA) ── boardgame.io React Client ──socket.io──► Node (server.js)
   │         LobbyView (bgio <Lobby>, react-router /rules)            ├─ koa-static: built SPA
   │         TienLenBoard → GameArea / PlayerArea / Buttons           ├─ bgio Lobby REST API (/games/tien-len/…)
   │         client-side validPlay()                                  └─ bgio Master: reducer(TienLen), InMemory DB
   └─ cookie "lobbyState" (seat credentials)                            playerView = STRIP_SECRETS
```

| Concern | Original |
|---|---|
| Rules | `src/moves/helper-functions/cardComparison.js` (cards, combinations, chops), `src/moves/cardPlayMoves.js` (play/pass/turns), `src/TienLen.js` (game config, setup, endIf) |
| State | `G = {turnOrder, center, players{hand, stagingArea}, roundType, winners, firstPlayer, cardsLeft}` + bgio `ctx` |
| Authority | Nominally the server, but moves do not validate rules, stages are ignored, and play moves act on `currentPlayer` |
| Hidden information | `STRIP_SECRETS` on `G` only; the seed, the log and unauthenticated sync all leak (`RISKS.md` A) |
| Players / games | Exactly 4; one game per room; in-memory storage |

What carries over: the card order, the combination shapes, the "staging area" UX idea (select cards, then Play), counter-clockwise seating, and public card counts.
What does not: everything listed in `RISKS.md` A, Tiến Lên chaining, and the original's chop and consecutive-pair rules.

## Part 2 — Target (as built, Phases 1–38)

Status: implemented and deployed (see `PORTING_STATUS.md`). This part describes the code as it is; the decisions behind each piece are referenced by their ids (T = RULES, others = PORTING_STATUS → Decisions).

### 2.1 Layers

```text
┌───────────────────────────── TienLenWeb (Phoenix LiveView) ─────────────────────────────┐
│ LobbyLive · TableLive · SpectateLive · ReplayLive · Leaderboard/History/CoinHistory      │
│ ProfileLive · FriendsLive · Admin.* (/quan-tri) · UserSessionController                   │
│ UserAuth on_mount hooks + TienLenWeb.Social (presence, private chat, invites, badges)    │
│ JS hooks: ChatScroll, CopyLink only (no game logic, CLAUDE.md rule 2)                     │
└────────────▲─────────────────────────────────────────────┬──────────────────────────────┘
             │ PubSub events → each page re-reads its own view │ commands (acting player id)
┌────────────┴──────────── Processes (in memory) ───────────▼──────────────────────────────┐
│ RoomServer per room: commands, timers, bots, spectators, room chat, replay capture       │
│ Chat.Lobby · Chat.Private · Invites · Presence · RateLimit · LoginThrottle · Seasons.Scheduler │
└────────────▲─────────────────────────────────────────────┬──────────────────────────────┘
             │ pure calls                                    │ Ecto (transactions)
┌────────────┴──────── Pure domain ───────────┐   ┌─────────▼──────── Contexts + PostgreSQL ─┐
│ Card · Deck · Combination · Rules ·          │   │ Accounts · Economy · Stats · Admin ·      │
│ InstantWin · Game · Room · Payout · Hint ·   │   │ Settings · Friends · Missions · Seasons    │
│ Bot · Replay                                 │   │                                            │
└──────────────────────────────────────────────┘   └────────────────────────────────────────────┘
```

### 2.2 Supervision

```text
TienLen.Application (one_for_one)
├── TienLenWeb.Telemetry, DNSCluster
├── TienLen.Repo (PostgreSQL)
├── Task: TienLen.Settings.load/0 (admin settings → :persistent_term; off in tests)
├── TienLen.LoginThrottle (ETS, F8)
├── Phoenix.PubSub (TienLen.PubSub)
├── TienLen.Presence (who is online and where, G6)
├── TienLen.RateLimit (ETS sliding windows: chat, invites, friends, reactions)
├── TienLen.Chat.Lobby (last 100 lobby messages)
├── TienLen.Chat.Private (last 20 lines per pair, 1 h expiry)
├── TienLen.Invites (pending invites, 60 s expiry)
├── Registry (TienLen.RoomRegistry, room_id → pid)
├── DynamicSupervisor (TienLen.RoomSupervisor) ── RoomServer per room (restart: :temporary)
├── TienLen.Seasons.Scheduler (hourly weekly-season payout; off in tests)
└── TienLenWeb.Endpoint
```

A crashed room is not restarted: its players return to the lobby. Everything in the process row is **lost on restart by design** (games in progress, chat, invites, presence, rate-limit counters). Accounts, coins, results, replays, friends and settings are in PostgreSQL.

### 2.3 Modules

**Pure domain** (no processes, no DB, no randomness except an injected seed):

| Module | Responsibility | Rules / decisions |
|---|---|---|
| `TienLen.Card` | Rank/suit, total order, key, parse/format | T4 |
| `TienLen.Deck` | Build, seeded shuffle, deal | T1, T2 |
| `TienLen.Combination` | Classify cards → type, top card, length; bombs | T5 |
| `TienLen.Rules` | Beats + chop context, out-of-turn eligibility, opening card, auto-lead | T3, T6, T10 |
| `TienLen.InstantWin` | Tới trắng detection | T18 |
| `TienLen.Game` | One game: turns, rounds, passes, finishing, ranking, removals, timeouts, chop chains, per-seat view, admin view, dry runs | T7–T12, T14–T16, E3 |
| `TienLen.Room` | Seats, host, stake, private flag, bots, banned players, chop counts, sequence of games, result for recording | T13, T15, E7, G11, B1–B4, P2 |
| `TienLen.Payout` | Game result / chop chain → coin debts | T20–T25 |
| `TienLen.Hint` | Legal plays from a hand, validated by `Game` | H1 |
| `TienLen.Bot` | Bot decisions (dễ / thường) | B5, B6 |
| `TienLen.Replay` | Frames of a stored replay | V5 |

**Processes** (in memory):

| Module | Responsibility |
|---|---|
| `TienLen.RoomServer` | Serialises commands; turn timer (20 s); disconnect timer (20 s); monitors players and spectators; bot actions (`bot_delay`); coin settlement (via `Economy`) then result recording (via `Stats`); room chat (last 50); reactions; replay capture; broadcasts events only |
| `TienLen.Lobby` | Thin API over rooms: create/open/join/leave, public and all room lists |
| `TienLen.Presence` | Phoenix.Presence on `"online"`: `%{name, username, avatar, place, room_id}` |
| `TienLen.Chat` (+ `Chat.Lobby`, `Chat.Private`) | Message rules (G2), sender checks (locked / muted), quick phrases, reactions list |
| `TienLen.Invites` | Invite checks, one pending per target, expiry, answers |
| `TienLen.RateLimit`, `TienLen.LoginThrottle` | ETS counters |
| `TienLen.Seasons.Scheduler` | Calls `Seasons.payout_due/0` hourly |

**Contexts** (PostgreSQL):

| Module | Responsibility |
|---|---|
| `TienLen.Accounts` | Registration, login, passwords (bcrypt), display name, avatar, invite setting, search |
| `TienLen.Economy` | **The only module that changes coins**: ledger, row locks, idempotency keys, settlement, daily bonus, relief, admin adjust, `grant/5` (missions, seasons) |
| `TienLen.Stats` | Recording results (with per-player chops / coins / instant and the replay), leaderboards (all-time, by period), history, profile numbers, replay access |
| `TienLen.Admin` | Every admin action, role re-checked and audited |
| `TienLen.Settings` | Admin-editable economy / reward settings and the announcement, cached |
| `TienLen.Friends` | Friend requests and friendships |
| `TienLen.Missions` | Daily missions and their rewards |
| `TienLen.Seasons` | Weekly seasons, standings, payouts |

### 2.4 Database

| Table | Content |
|---|---|
| `users` | `username` (unique, lowercase), `display_name`, `hashed_password`, `coins` (≥ 0 check), `daily_bonus_on`, `relief_on`, `role` (`player`/`admin`), `locked_at`, `accept_invites`, `muted_until`, `avatar` |
| `games` | `room_id`, `ref` (`room:<id>:game:<n>`), `player_count`, `instant_win`, `finished_at`, `replay` (jsonb: seats, dealt hands, public events) |
| `game_players` | `game_id`, `user_id`, `seat`, `place`, `won`, `removed`, `chops`, `coins`, `instant` |
| `coin_transactions` | Append-only ledger: `user_id`, `counterparty_id`, `amount`, `balance_after`, `reason`, `ref` |
| `coin_settlements` | Idempotency keys (game settlements, daily claims, missions, season rewards) |
| `admin_actions` | Audit log: admin, action, target, details, reason |
| `settings` | Key/value admin settings |
| `friendships` | `user_id` → `friend_id`, `status` (`pending`/`accepted`), unique pair, not self |

Only games without bots are recorded (B3). Chat messages are never stored (CH2).

### 2.5 Game state

```text
%Game{
  seats:           [seat]              # seat order = turn order (counter-clockwise)
  hands:           %{seat => [Card]}   # private
  undealt:         [Card]              # private, never projected
  discarded:       [Card]
  mode:            :card_led | :winner_led
  opening_card:    Card | nil          # mandatory card for the first play (T3)
  phase:           :lead | :respond | :finished
  current:         seat | nil
  centre:          nil | %{combo, owner, chop_context}
  passed:          MapSet(seat)        # this round
  finished:        [seat]              # finishing order
  removed:         [seat]              # removal order (disconnect / leave / kick)
  instant_winners: [{seat, hand_type}] # non-empty ⇒ ended at deal
  ranking:         nil | [[seat]]      # groups allow ties (instant win)
  chain:           nil | %{units, chops, payer, payee}   # chop chain of the round (E3)
}
```

`%Room{}` wraps it with seats (`%{player_id, name, connected, avatar, bot?}`), host, status, stake, private flag, banned ids, `game_players` (seat → user id), `game_no` and `game_chops`.

### 2.6 Game state machine

```text
 new(mode) ─ deal ─► instant win? ── yes ─► FINISHED (instant ranking, reveal)
                         │ no
                         ▼
                  LEAD (current = leader; must play; opening card if card-led)
                         │ play
                         ▼
     ┌──────────────► RESPOND (current = next active, not passed) ◄──────────┐
     │  play (beats)     │ pass                     out-of-turn four-pair ────┘
     └───────────────────┤                          (any seat with cards;
                         │                           passes reset; next = seat after chopper)
             all other active players passed?
                         │ yes
                         ▼
        clear centre, reset passes + chop context (chop chain settled)
        leader = owner if active, else next active seat ──► LEAD

 any play that empties a hand → append to finished
 remove(seat)                 → discard hand, append to removed, fix current/leader
 active players ≤ 1           → FINISHED (ranking = finished ++ [last] ++ removed)
 timeout(current)             → RESPOND: pass · LEAD: lowest single (or opening card single)
```

### 2.7 Command and event flow

```text
TableLive (player id = user id from the session)
  └─ RoomServer.play(room, player_id, cards)                 # GenServer.call, serialised
        └─ Room.command → Game.play → {:ok, room', events} | {:error, reason}
              ├─ error → {:error, reason} to the caller only (flash / button label)
              └─ ok    → changed/3:
                         reschedule turn timer → schedule bot action →
                         settle coins (Economy.settle, idempotent keys) → capture replay →
                         at game over: Stats.record(result + coins + replay) →
                         PubSub {:room_updated, id, version, events} on "room:<id>" →
                         each page re-reads its own projection (RoomServer.view / spectator_view)
```

Events carry public facts only. Chat (`{:room_chat, …}`), reactions (`{:reaction, …}`) and spectator counts use the same room topic.

**PubSub topics:**
- `room:<id>`;
- `lobby` (room list), `lobby_chat`, `online` (presence);
- `stats`, `coins` and `coins:<user>` (balances), `settings`;
- `user:<id>`: force logout, role change, private chat, invites, friend changes.

### 2.8 Visibility (T14, AD7, V1–V6)

| Who | Sees |
|---|---|
| Seated player | Own hand and selection; everyone's card counts; centre, turn, timer, passes, ranking; coin results; room chat |
| Spectator (`/phong/:id/xem`) | `Room.view(room, nil)`: no hand at all; no room chat |
| Admin watch (`/quan-tri/phong/:id`) | Every hand, undealt cards, room chat (AD7) |
| Replay (`/van/:id`) | Every dealt hand and every play, only after the game is recorded, for its players and admins |

Never broadcast: hands, undealt cards, seeds, selections. Instant-win hands are revealed (T18).

### 2.9 Web layer

| Path | Page | Access |
|---|---|---|
| `/` | Lobby: register / login, rooms (create, stake, private), missions, lobby chat, online list, settings (password, invites) | public / logged in |
| `/phong/:id` | Table: play, hints, sort, bots, invites, copy link, private toggle, reactions, room chat | logged in (else `/?next=`) |
| `/phong/:id/xem` | Spectator view | logged in |
| `/van/:id` | Replay | players of the game, admins |
| `/bang-xep-hang` | Leaderboards: 1st places, this week, last week, richest | logged in |
| `/lich-su`, `/lich-su-coin` | Game history (replay links), coin ledger | logged in |
| `/nguoi-choi/:username` | Profile, avatar picker, friend button | logged in |
| `/ban-be` | Friends | logged in |
| `/quan-tri/*` | Dashboard, users, rooms (watch / close / kick), games, audit log, settings | admins |
| `POST /dang-nhap`, `DELETE /dang-xuat` | Session controller (login throttle, `next`) | – |

Every logged-in page gets, through `UserAuth` hooks:
- the announcement banner;
- live account events: lock, role change;
- the header balance;
- `TienLenWeb.Social`: presence tracking, the 💬 panel, the invite popup, the friend-request badge.

### 2.10 Configuration switches

| Key | Default | Tests | Purpose |
|---|---|---|---|
| `:economy` | `TienLen.Economy` | `nil` | Rooms settle coins |
| `:results_recorder` | `TienLen.Stats` | `nil` | Rooms record results |
| `:load_settings` | `true` | `false` | Load admin settings at start |
| `:throttle_by_ip` | `true` (`THROTTLE_BY_IP`) | `false` | Count failed logins per IP too |
| `:bot_delay` | 1,000 ms | 0 | Bot thinking time |
| `:season_payouts` | `true` | `false` | Start the season scheduler |
| `:max_rooms` | 500 (`MAX_ROOMS`) | – | Room cap (overridable in admin settings) |

### 2.11 Mapping from the original

| Original | Target |
|---|---|
| `constants.js`, `compareCards` | `TienLen.Card` |
| `setUp` (deal, first player) | `TienLen.Deck`, `Game.new/3` |
| `validCombination` | `TienLen.Combination` |
| `validPlay`, `validChop`, `compareHighest` | `TienLen.Rules` (with new chop rules) |
| `cardsToCenter`, `passTurn`, `nextTurn`, `turnOrder`/`"W"` | `Game.play/3`, `Game.pass/2`, explicit `passed`/`finished` |
| `tienLenPlay` + `tienLen` stage | **removed** (D4); `Game.chop_out_of_turn/3` is new |
| `endIf` | `Game` finishing logic + `ranking` |
| bgio Master + InMemory | `RoomServer` + Registry/DynamicSupervisor |
| socket.io broadcast + `STRIP_SECRETS` | PubSub + `Game.view/2` |
| bgio `<Lobby>` + credentials cookie | `LobbyLive` + `Phoenix.Token` seat tokens |
| `TienLenBoard`, `GameArea`, `PlayerArea`, `Buttons` | `TableLive` + function components (`RESEARCH.md` §18) |
| `relocateCards`/`stagingArea` moves | LiveView-local selection (plus a JS hook for ordering, O4) |
