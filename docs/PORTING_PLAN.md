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

## Phase 5 — Pure game state (T7–T12, T15 effects, T16 actions, T18 flow)

- [ ] `TienLen.Game`: `new(seats, seed, mode)`; commands `play(seat, cards)`, `pass(seat)`, `chop_out_of_turn(seat, cards)`, `timeout(seat)`, `remove(seat)`; each returns `{:ok, game, events}` or `{:error, reason}`.
- [ ] Rounds, centre clearing, chop context, finishing, ranking, game end, instant-win end.
- [ ] `Game.view(game, seat)`: the per-seat projection (T14). No other hands, no seed.
- Tests: the RULES §16 scenarios end to end; property tests (card conservation, exactly one current seat while playing, never a pass on a lead, the game ends with N − 1 finishers or an instant win); timeout actions (X1).
- Acceptance: no command can act for another seat, except a valid out-of-turn four-pair.

## Phase 6 — Room process (T13, T15, T16, T17)

- [ ] `TienLen.Room` (pure): seats, host, sequence of games, leader for the next game (R1, R4, I5).
- [ ] `TienLen.RoomServer` GenServer: serialises commands; turn timer (20 s); disconnect timer (20 s) → `remove`; host transfer (S6, X3); PubSub broadcast of an event only (views are projected per subscriber).
- [ ] Registry + DynamicSupervisor; room lifecycle (the room closes when empty).
- Tests: simultaneous out-of-turn chops (first valid wins); timers with injected clocks; crash isolation; the next-game leader.
- Acceptance: invalid commands never crash the process; no broadcast contains hidden information.

## Phase 7 — Lobby / rooms (T13)

- [ ] Create/list/join/leave rooms; display name; seat tokens (O3); max 4 seats; no mid-game join; host-only start with ≥ 2 players; no spectators.
- Tests: full room, mid-game join refused, a non-host cannot start, token reconnect, forged token rejected.

## Phase 8 — LiveView UI

- [ ] Lobby LiveView, table LiveView (seats around the table, centre, hand, selection, Play/Pass buttons with server-provided reasons, turn timer, card counts, ranking, instant-win reveal).
- [ ] Mapping from the original's components: `RESEARCH.md` §18.
- Tests: LiveView tests per interaction; no rule logic in JS.

## Phase 9 — Realtime

- [ ] PubSub per room; each LiveView re-projects `Game.view/2` for its own seat; Presence for connect/disconnect → RoomServer.
- Tests: multi-session tests; a socket never receives another hand, the seed or the undealt cards.

## Phase 10 — Tests, security, reconnect, deploy

- [ ] Reconnect by token across page reloads; fuzz random commands against `Game`; a review against `RISKS.md` section A (none of R1–R9 reproducible).
- [ ] Deployment (O5).
