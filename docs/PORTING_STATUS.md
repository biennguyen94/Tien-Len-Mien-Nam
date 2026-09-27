# Porting status

Last updated: 2026-09-27

| Phase | Name | Status |
|---|---|---|
| 1 | Research | **DONE** (2026-09-27) |
| 2 | Card / Deck | **DONE** (2026-09-27) |
| 3 | Combination engine | **DONE** (2026-09-27) |
| 4 | Rules engine | **DONE** (2026-09-27) |
| 5 | Pure game state | **DONE** (2026-09-27) |
| 6 | GameServer (room process) | **DONE** (2026-09-27) |
| 7 | Lobby / rooms | **DONE** (2026-09-27) |
| 8 | LiveView UI | **DONE** (2026-09-27); real-browser check still NOT VERIFIED, see results |
| 9 | Realtime (PubSub, presence) | **DONE** (2026-09-27): PubSub + process monitors; no `Phoenix.Presence` (see results) |
| 10 | Tests / security / reconnect / deploy | **DONE** (2026-09-27): deployed on Docker (WSL), port 4020 |

Phoenix app generated at the repo root (O1, O2). Domain so far: `TienLen.Card`, `TienLen.Deck` (Phase 2), `TienLen.Combination` (Phase 3), `TienLen.Rules` and `TienLen.InstantWin` (Phase 4), `TienLen.Game` (Phase 5), `TienLen.Room` and `TienLen.RoomServer` (Phase 6), `TienLen.Lobby` + `TienLenWeb.PlayerIdentity` (Phase 7), LiveView UI: `LobbyLive` (`/`) and `TableLive` (`/phong/:id`) (Phase 8). The web layer is still the generator's default page.

## Decisions

All game-rule decisions below were made by the owner on 2026-09-27. The consolidated rules are in `RULES.md`; this is the log.
When a decision is replaced, the old row stays and the new one says what it supersedes.

### Batch 1 — core

| # | Decision | Rule |
|---|---|---|
| D1 | The server enforces every play rule. | T17 |
| D2 | 3♠ required only on the first play of a game with no previous winner. *Superseded by Q6, then R1/R7/S7.* | T3 |
| D3 | No passing when leading a new round; passing only when responding. | T7, T8 |
| D4 | When all others pass, the round ends and the last player leads a new round freely. **Removes the original Tiến Lên chaining.** | T9 |
| D5 | No 2s in consecutive pairs. | T5 |
| D6 | Chop hierarchy: single 2 ← three-pair / quad / four-pair; pair of 2s ← quad / four-pair; three-pair ← higher three-pair / quad / four-pair; quad ← higher quad / four-pair; four-pair ← higher four-pair. *Refined by Q3, R2, S3.* | T6 |
| D7 | Cross-type chops follow D6 and do not compare rank; same type must be higher. | T6 |
| D8 | A room plays several games; the previous winner leads the next game. *Refined by R1, I5.* | T2, T13 |
| D9 | 2, 3 or 4 players; never more than 4. | T1 |

### Batch 2 — follow-ups

| # | Decision | Rule |
|---|---|---|
| Q1 | Deal 13 cards per player; undealt cards leave the game. *"3♠ rule waived / `starting_seat`" superseded by R4 and S7.* | T1 |
| Q2 | After a finisher's play is passed by everyone, the next seat with cards leads. | T9 |
| Q3 | A three-pair is answerable by a quad only when it was played as a chop. *Generalised by R2 and S3 ("chop context").* | T6 |
| Q4 | Chop combinations cannot be played on ordinary cards. | T6 |
| Q5 | The game ends when only one player holds cards. | T11 |
| Q6 | The previous winner has lead priority; the 3♠ rule is reset each game. *Winner part refined by R1/I5; fallback superseded by R4.* | T2, T3 |
| Q7 | Five or more consecutive pairs are invalid. | T5 |
| Q8 | Chops only on your own turn, except the four-pair, which may chop out of turn. | T10 |
| #12 | Clear the centre when a new round starts. | T9 |
| #15 | Remaining card counts are public. | T14 |
| #16 | Same-rank pairs compare by the highest suit. | T6 |
| #17 | No spectators in the first release. | T13, T14 |
| #18 | A disconnected player keeps the seat for a timeout and reconnects with a seat token; they are never auto-winners. | T15 |

### Batch 3 — conflicts and gaps

| # | Decision | Rule |
|---|---|---|
| R1 | The previous winner overrides the 3♠ rule: they lead the next game with no card requirement. | T2, T3 |
| R2 | A normally-played three-pair is not choppable by a four-pair; a quad is choppable by a four-pair only when played as a chop. | T6 |
| R3 | The four-pair is a special interrupt: out of turn, even by a passed player. Pass marks reset. No chop timer. First valid command wins. *"Turn goes to the chopper" clarified by S2.* | T10 |
| R4 | Opening-leader order: previous winner → 3♠ → 3♣ → 3♦ → 3♥ → 4♠ → … | T2 |
| R5 | Disconnect timeout 20 s. After it, the player is removed from the current game (auto-pass if it was their turn). | T15 |
| R6 | Only the host starts a game, with ≥ 2 players. No joining mid-game. | T13 |
| R7 | A card-led leader may not pass; their first play must contain the card. The previous winner is exempt. | T3 |

### Batch 4 — final details

| # | Decision | Rule |
|---|---|---|
| S1 | Turn timeout 20 s. On expiry: responding → pass; leading → lowest valid combination; mandatory card → lowest combination containing it. | T16 |
| S2 | After an out-of-turn four-pair, play continues from the seat after the chopper. | T10 |
| S3 | Chop context persists through same-type beats (until the round ends). | T6 |
| S4 | In chop context, a higher four-pair may chop a lower four-pair out of turn. | T10 |
| S5 | A removed player's cards are discarded. They rank after all normal finishers (in removal order). The game ends if one player is left. The next remaining player leads if needed. They play normally in the next game. | T11, T15 |
| S6 | When the host leaves or disconnects, host rights pass to the next player in seat order; the room stays open while anyone remains. | T13 |
| S7 | The first play must contain the card that selected the leader (3♠, 3♣, …). Supersedes Q1's waiver. | T3 |

### Batch 5 — instant wins (tới trắng)

| # | Decision | Rule |
|---|---|---|
| I1 | Instant wins exist. The winner ranks 1st but does **not** lead the next game. Hands: four 2's; 6 pairs (2s allowed, a quad counts as two pairs); dragon 3 → A + any card. **No four triples.** | T18 |
| I2 | The game ends immediately; nobody plays. | T18 |
| I3 | The server detects automatically after the deal; no declaration. | T18 |
| I4 | Several instant winners are all 1st (seat order breaks ties); the others are tied after them. | T18 |
| I5 | Exception to R1: the next game is card-led; skip holders who do not take part. | T2 |
| I6 | Applies in the first game too. Four 3's counts **only in card-led games**. | T18 |
| I7 | Applies with 2–3 players, on the 13 dealt cards only. | T18 |
| I8 | Reveal the instant winner's whole hand to everyone. | T14, T18 |

An earlier version of I1/I4/I5/I6 (the instant winner leads the next game; ties by the previous ranking; four 3's in the first session game only) was replaced on the same day.

## Interpretations (fixed in `RULES.md` §15; confirm or override)

| # | Interpretation |
|---|---|
| X1 | The auto-play when leading is the single lowest card; with a mandatory card, that card as a single. |
| X2 | The last player holding cards ranks above removed players. |
| X3 | Host rights transfer after the 20 s disconnect timeout, not on the first disconnect. |
| X4 | If the leader of a card-led opening is removed before the first play, the lead moves to the next active seat **without** an opening-card requirement (the mandatory card was discarded with their hand). (Phase 5) |
| X5 | An out-of-turn four-pair is allowed on **any** chop target, including a combination the chopper played themselves; nothing in T10 excludes it. (Phase 5) |
| X6 | A new game is dealt only to **connected** seated players. A disconnected player keeps their seat and joins the next game after reconnecting. (Phase 6) |
| X7 | Host transfer (S6) goes to the next seat in seat order **that is connected**, if any; otherwise to the next seated player. (Phase 6) |
| X8 | **Leaving** the room (as opposed to disconnecting) during a game removes the player from the game at once (like a disconnect timeout), frees the seat, and passes host rights at once. (Phase 6) |
| X9 | A room closes when its last player leaves, or when a disconnect timeout expires and nobody in the room is connected. (Phase 6) |

### Project decisions

| # | Decision |
|---|---|
| O1 | **One Phoenix app at the repo root**, `--app tien_len --module TienLen`. Pure domain in `lib/tien_len/`, web layer in `lib/tien_len_web/`. (Owner accepted the proposal, 2026-09-27.) |
| O2 | **No database** (`--no-ecto`, also `--no-mailer`): rooms and games live in memory; a restart ends running games. Ecto can be added later for accounts or history. (Accepted with O1; the generator needed it.) |
| O5 | **Docker on WSL**, like open-mu-web: release image `tien-len:latest`, compose project `tien-len`, host port 4020 (`docs/DEPLOY.md`). (Owner asked to proceed with Phase 10 on the proposal, 2026-09-27.) |
| O4 | **Vietnamese UI; click to select cards; the original's card SVGs** (Adrian Kennard, **CC0 public domain**: "You can do what you like with these designs", "No attribution required"; credit kept in README anyway). (Owner, 2026-09-27.) |
| O3 | **Anonymous identity**: a random player id in the signed Phoenix session, a display name, and a signed seat token (`Phoenix.Token`) for reconnecting without a session. No accounts. (Owner asked to proceed with Phase 7 on the proposal, 2026-09-27.) |

## Open decisions (project-level, not game rules)

| # | Question | Needed by | Proposal (ASSUMPTION until decided) |
|---|---|---|---|

## Phase 1 results (2026-09-27)

### Delivered

- `docs/RESEARCH.md`: a full reverse-engineering report of `nguyenank/tien-len@86b2621` (boardgame.io 0.39.16). It covers the architecture, state, card model, combinations, beat and chop rules, the Tiến Lên mechanic, turns, winning, multiplayer, security, tests, and the source vs wiki vs Wikipedia comparison.
- The decision log above (5 batches) and the consolidated `RULES.md` (T1–T18).
- This repo's `CLAUDE.md` and docs structure.

### VERIFIED (by running the original in a scratch copy with boardgame.io 0.39.16, Node 22)

- Original test suite: **27 pass / 12 fail**. The failures come from stale tests using the old `relocateCards(cards, area)` signature.
- The game-level `stages` config is ignored by boardgame.io 0.39. Any player can call any move, and `passTurn` from another seat passes the current player.
- The server accepts invalid, non-beating and empty plays (`roundType` becomes `undefined`).
- Hidden information leaks:
  - the PRNG seed reaches every client, and replaying it reconstructs every hand;
  - the action log exposes drag payloads, i.e. card ids.
- `passTurn` while alone in the Tiến Lên stage throws a `TypeError`.
- An out-of-range `relocateCards` index inserts `undefined` into the staging area.
- Combination edge cases, e.g. `KKAA22` is accepted as a three-pair and 5 pairs are rejected (RESEARCH §8, Appendix A).

### NOT VERIFIED

- Unauthenticated `sync` letting a socket read any seat's hand. This comes from the library source only; it was not reproduced over a real socket.
- A server crash on unhandled rejection from a throwing move. It depends on the Node version.
- Silent dropping of a play when an opponent's drag bumps `_stateID` at the same moment (a race).
- The Vietnamese Wikipedia content, which was read through a summarising fetch. Re-check it before quoting.

### ASSUMPTIONS

- The live deployment (`tienlen-en.herokuapp.com`) ran the analysed commit.

## Phase 2 results (2026-09-27)

### Delivered

- **Phoenix 1.8.15 app at the repo root.** Generated with `mix phx.new tien_len --app tien_len --module TienLen --no-ecto --no-mailer` in a scratch directory, then copied in without overwriting `README.md`. The generator's `.gitignore` was merged with ours. The generator's `AGENTS.md` (Phoenix/LiveView guidelines) is kept, with a project header pointing to `CLAUDE.md`.
- **`TienLen.Card`** (`lib/tien_len/card.ex`):
  - struct `%Card{rank: 3..15, suit: :spades | :clubs | :diamonds | :hearts}`, with J=11, Q=12, K=13, A=14, 2=15;
  - `all/0`, `key/1` (0 = 3♠ … 51 = 2♥), `compare/2` (usable as an `Enum.sort/2` module), `sort/1`, `highest/1`, `lowest/1`;
  - codes `to_code/1` / `parse/1` / `parse!/1` / `parse_many!/1` (`"3S"`, `"10H"`, `T` accepted), `display/1` / `String.Chars` (`"10♥"`).
- **`TienLen.Deck`** (`lib/tien_len/deck.ex`):
  - `new/0`;
  - `new_seed/0` (`:crypto.strong_rand_bytes`);
  - `shuffle/2`: Fisher–Yates with a local `:exsss` state; it never touches the global `:rand` state;
  - `deal/2`: 2–4 players, round-robin, 13 each, sorted hands and sorted `undealt`;
  - `lowest_holder/1`: map or list of hands → `{seat, card}` for card-led openings (T2).
- **Tests:** `test/tien_len/card_test.exs`, `test/tien_len/deck_test.exs`.

### VERIFIED

- `mix precommit` (compile `--warnings-as-errors`, `deps.unlock --unused`, format, test): **41 passed (1 doctest, 40 tests)**, run twice including once from a clean `_build/test`.
- Order of all 52 cards matches T4. `key/1` is a bijection onto 0..51. Codes round-trip for all 52 cards.
- Deal sizes are 13 each with 26/13/0 undealt for 2/3/4 players. No duplicates. The same seed gives the same deal.
- The shuffle is a permutation and does not change the process's global `:rand` state. Coarse uniformity holds over 5200 fixed seeds: every card appears first 50–150 times (expected about 100).
- `lowest_holder/1` over 600 real deals (2–4 players × 200 seeds) returns the lowest dealt card, and every lower card is undealt. With 4 players it is always 3♠.

### Notes

- The deal is round-robin from a Fisher–Yates shuffle. The original used contiguous chunks of a shuffled deck. Both are uniform; this is not a rule difference.
- `mix phx.server` and the assets (tailwind/esbuild binaries) were not exercised; they are not needed until Phase 8.

## Phase 3 results (2026-09-27)

### Delivered

- **`TienLen.Combination`** (`lib/tien_len/combination.ex`):
  - `classify/1` → `{:ok, %Combination{type, cards (sorted), top, length}}` or `{:error, :empty | :duplicate_cards | :invalid_combination}`;
  - `classify!/1`, `types/0`, `bomb?/1` (three-pair, four-of-a-kind, four-pair).
- Types and constraints exactly as RULES §4:
  - no 2 in straights or consecutive pairs (D5);
  - 5 or more pairs invalid (Q7);
  - straights of 3–12 cards with no wrap-around.
- Comparison between combinations is left to Phase 4 (`TienLen.Rules`).
- **Tests** (`test/tien_len/combination_test.exs`):
  - table cases per type;
  - the original repo's `validCombination` cases with D5 applied;
  - an **exhaustive** check of every 1-, 2- and 3-card set (52 + 1,326 + 22,100);
  - 3,000 random 1–13-card sets and 2,000 generated near-valid runs, cross-checked against an independent reference classifier in the test.

### VERIFIED

- `mix precommit`: **66 passed (2 doctests, 64 tests)**.
- Cases that changed from the original (RESEARCH §8): `KKAA22`, `QQKKAA22` and `AA22` are **invalid** (the original accepted the first two). `3S 3S` gives `:duplicate_cards` (the original accepted it as a pair).
- The near-valid generator covers every long type: 483 straights, 133 three-pairs, 122 four-pairs and 918 invalid sets (e.g. 5–6 pairs, runs with a 2) over 2,000 seeds.

## Phase 4 results (2026-09-27)

### Delivered

- **`TienLen.Rules`** (`lib/tien_len/rules.ex`), all pure. The centre is `nil` (a lead) or `%{combo, chop_context}`.
  - `play(cards, centre, opening_card \\ nil)` → `{:ok, combo, chop_context}`: a lead (with the mandatory opening card, T3) or a beat on your turn.
  - `play_out_of_turn(cards, centre)`: four-pair only, on a chop target (T10, S4).
  - `pass(centre)`: rejected on a lead (D3).
  - `beats/2`: the RULES §5.2 matrix, with chop context starting on a 2 and persisting (S3).
  - `chop_target?/1`.
  - `auto_lead/2`: the timeout lead play per interpretation X1. It lives here because it is pure; Phase 5/6 calls it.
- **Error reasons** (for UI labels later):
  - `:empty`, `:duplicate_cards`, `:invalid_combination` (from Combination);
  - `:does_not_match`, `:too_low`;
  - `:cannot_chop` (a bomb where chopping is not allowed: Q4, R2, pair of 2s ← three-pair, triple of 2s);
  - `:must_include_card`, `:cannot_pass_on_lead`, `:not_four_pair`, `:no_chop_target`.
- **`TienLen.InstantWin`** (`lib/tien_len/instant_win.ex`):
  - `detect(hand, mode)` → `:four_twos | :dragon | :six_pairs | :four_threes | nil`;
  - `matches/2` (all types, in priority order);
  - `winners(hands, mode)` → `[{seat, type}]` in seat order (the I4 tie-break).
  - Four 3's only when `mode == :card_led`. A quad counts as two pairs, and so does "five pairs + a triple". The dragon is 3 → A plus any card. No four triples.
- Card ownership, turn order and seats are **not** checked here; that is Phase 5 (`Game`).

### VERIFIED

- `mix precommit`: **115 passed (2 doctests, 113 tests)**, no warnings.
- Every row of RULES §5.2, including the rejected cases:
  - three-pair on a pair of 2s;
  - quad or four-pair on a normal three-pair or quad (R2);
  - bombs on ordinary cards (Q4);
  - triple of 2s unchoppable;
  - four 2s beaten only by a four-pair in chop context.
- RULES §16 legality examples 3, 4, 5 and 7, plus the S3 chain 2 → three-pair → higher three-pair → quad → four-pair.
- Invariants over random combinations (from 400 seeds × 7 sizes, plus every bomb and 2 shape):
  - same shape: the higher top wins; **equal tops beat neither way** (e.g. two straights ending in 5♥);
  - cross-type wins are only bombs over 2s, or over chop-context bombs;
  - a beat never clears chop context.
- Instant wins: table cases and near misses (five pairs + 3 singles, three 2s, a 3 → K run, four triples), and a cross-check against a brute-force reference on 20,000 dealt hands × 2 modes.

## Phase 5 results (2026-09-27)

### Delivered

- **`TienLen.Game`** (`lib/tien_len/game.ex`), a pure state machine for one game.
  - `new(seats, seed, leader: seat | nil)` deals from a seed. The **seed is not stored**.
  - `start(seats, hands, undealt, opts)` takes given hands (tests and replays).
  - Instant wins are checked at the start (T18). An instant win gives phase `:finished`, ranking `[[winners…], [others…]]`, and the winners' hands revealed in `view/2`.
  - Commands take the acting seat and return `{:ok, game, events}` or `{:error, reason}`, never raising on bad input:
    - `play/3`, `pass/2`;
    - `chop_out_of_turn/3` (resets passes; next is the seat after the chopper);
    - `timeout/2` (respond → pass; lead → `Rules.auto_lead`);
    - `remove/2` (discard the hand; a current responder counts as a pass; a current leader moves the lead, X4).
  - Dry runs: `check_play/3`, `check_pass/2`, `check_chop_out_of_turn/3` (for UI labels later).
  - Rounds end when no responder is left (active, not passed, not the owner). The owner leads, or the next active seat after the owner (Q2, S5). The centre is cleared (#12).
  - The game ends when ≤ 1 player is active. Ranking = finishers, then the last player, then removed players (T11, X2).
  - Queries: `active_seats/1`, `finished?/1`, `instant_win?/1`, `winner/1`.
  - `view/2` (T14): own hand, all card counts, the public centre and state. The mandatory opening card goes to the leader only. It never includes other hands, undealt or discarded cards.
- **Events** are public facts only: `:played`, `:chopped`, `:passed`, `:timed_out`, `:finished`, `:removed`, `:round_ended`, `:lead_moved`, `:game_over`.
- Error reasons added: `:game_over`, `:not_in_game`, `:not_active`, `:not_your_turn`, `:not_your_cards`.

### VERIFIED

- `mix precommit`: **143 passed (2 doctests, 141 tests)**, no warnings.
- **Scenario tests:**
  - RULES §16 examples 1, 2, 3, 6, 8, 9, 10;
  - card-led and winner-led openings;
  - 2 and 3 players;
  - passed players skipped;
  - response and lead timeouts;
  - finisher's play beaten or passed;
  - full game to game over with ranking;
  - removal of a responder, the current leader, the round owner, and down to one player;
  - instant win with several winners in seat order;
  - authority checks (other seat, foreign cards, garbage input, unknown seat);
  - `view/2` contents.
- **Random simulations: 600 full games** (2–4 players, card- and winner-led). In 2/3 of them the deal is rigged by card swaps: a four-pair, two 2s and a three-pair are placed so chops happen.
  - A bot mixes plays, passes, out-of-turn chops, timeouts and removals (including of the current seat).
  - At **every step** the test checks:
    - 52 distinct cards across hands, played, undealt and discarded;
    - the current seat is active and has not passed;
    - `:lead` exactly when the centre is empty;
    - finished and removed players have empty hands;
    - no `view/2` shows another player's card, except instant-win reveals.
  - Every game terminates with a complete ranking.
  - Event totals today: about 7,200 plays, 6,400 passes, 4,100 round ends, **160 out-of-turn chops**, 430 timeouts, 430 removals, 19 lead moves, 480 game overs. The test enforces minimums so the bot cannot silently stop covering a command.

### Notes

- The first version of the simulation never produced `:chopped` or `:lead_moved` (random deals almost never hold a four-pair when a 2 is on the table, and the bot never removed the current seat). That was fixed by rigging deals, keeping four-pairs intact in the bot, and allowing removal of any active seat. It was a test-coverage gap, not a code bug.
- X4 and X5 are new interpretations taken while implementing; see Interpretations.

## Phase 6 results (2026-09-27)

### Delivered

- **`TienLen.Room`** (`lib/tien_len/room.ex`), pure.
  - Seats `0..3` (ascending seat order = turn order). The first player is host.
  - `join/3`: a new player takes the first free seat, or the same player id reconnects. Refused when full or mid-game (R6).
  - `leave/2`, `disconnect/2`, `disconnect_timeout/2` (S5, S6, X3, X7, X8).
  - `start_game/3`: host only, ≥ 2 connected players (X6). The deal is a seed or `{:hands, …}` for tests.
  - `command/3`: `{:play, cards}`, `:pass`, `{:chop, cards}`.
  - `turn_timeout/1`, `view/2`.
  - Next-game leader: `last_winner` (player id) leads if taking part (R1). `nil` after an instant win (I5) or if the winner left (R4).
- **`TienLen.RoomServer`** (`lib/tien_len/room_server.ex`), a GenServer per room under a `DynamicSupervisor` (`TienLen.RoomSupervisor`) and a `Registry` (`TienLen.RoomRegistry`), both added to `TienLen.Application`. `restart: :temporary`, since there is no DB (O2).
  - **API:** `start_room/1` (random id or `:id`), `join/3`, `leave/2`, `start_game/2`, `play/3`, `pass/2`, `chop/3`, `view/2` (adds `turn_ms_left`), `subscribe/1`, `topic/1`, `whereis/1`.
  - **Commands are serialised** by the process.
  - **Turn timer:** 20 s, configurable. It restarts when the turn changes hands or the current player acts; stale timer messages are ignored by ref.
  - **Disconnect timer:** 20 s, configurable. Connections are tracked by **monitoring the joining process** (the LiveView later). A player with several tabs is disconnected only when all of them are gone. Joining again cancels the timer.
  - **Broadcast** `{:room_updated, id, version, events}`: events only. Subscribers fetch their own `view/2`.
- Connection tracking uses process monitors, not `Phoenix.Presence`. Presence is not needed for the rules; Phase 9 can still add it for a "who is online" display.

### VERIFIED

- `mix precommit`: **172 passed (2 doctests, 170 tests)**, no warnings.
- **Room (18 tests):**
  - seat filling and fifth player refused;
  - reconnect to the same seat;
  - no new join mid-game;
  - host-only start with ≥ 2 players;
  - disconnected players not dealt;
  - command routing and errors;
  - a scripted full game → ranking `[[0], [3], [1], [2]]`, and the winner leads the next game;
  - instant win → next game card-led;
  - winner left → card-led;
  - leave / disconnect-timeout removal with host transfer;
  - removal down to one player ends the game;
  - `view/2`.
- **RoomServer (11 tests):**
  - lifecycle, duplicate ids, unknown room, room stops after the last leave;
  - bad input (junk cards, wrong types, strangers) never crashes the process;
  - **concurrent out-of-turn four-pairs**: whichever arrives first, the higher one ends on top and play continues after its owner;
  - a turn timeout auto-plays the mandatory 3♠, then auto-passes;
  - **a whole 4-player game finished purely by 2 ms turn timeouts, with every broadcast scanned: no card appears that was not played**;
  - a killed player process → disconnected → removed after the timeout, host moved;
  - reconnect before the timeout cancels removal;
  - two tabs;
  - the room stops when nobody is connected.
- **Flakiness check:** the RoomServer tests were run 30 times and the full suite 10 times after the fix below, with 0 failures.

### Notes

- A flaky test ("room stops when the last player leaves") exposed a real issue: the `Registry` unregisters a dead process asynchronously, so `whereis/1` could briefly return a dead pid. `whereis/1` now treats a pid that is not alive as absent. Before the fix, the test failed 5 times in 20 runs.
- New interpretations X6–X9, taken while implementing; see Interpretations.

## Phase 7 results (2026-09-27)

### Delivered

- **`TienLen.Lobby`** (`lib/tien_len/lobby.ex`):
  - `create_room/3` (the creator is seated as host);
  - `join_room/3` (join or reconnect), `leave_room/2`, `start_game/2`;
  - `room_view/2` (seated players only);
  - `list_rooms/0`: public summaries `%{id, players, max_players, status, host_name, joinable}`, joinable rooms first;
  - `normalize_name/1`: trim, collapse whitespace, 1–20 characters, Unicode allowed, no control characters, invalid UTF-8 rejected;
  - `subscribe/0` to lobby updates.
- **`TienLen.RoomServer` additions:**
  - `summary/1`;
  - `{:lobby_updated, id}` on joins, leaves, host changes, game start and game over, and `{:room_closed, id}` on termination;
  - a room nobody joins closes after the disconnect timeout (X9);
  - `view/2` refuses non-seated players (**no spectators**, #17).
- **`TienLen.Room`:** a game ended by instant win at the deal now also emits `{:instant_win, winners}` and `{:game_over, ranking}`, so clients learn it from events.
- **`TienLenWeb.PlayerIdentity`** (`lib/tien_len_web/player_identity.ex`, O3):
  - a plug in the `:browser` pipeline that gives each session a random `player_id` (stored in the signed session cookie) and assigns `player_id` / `player_name`;
  - `sign/1` / `verify/2` seat tokens (`Phoenix.Token`, 30-day max age).
- The session cookie stays **signed** (not encrypted): the player id is not secret, only tamper-proof.

### VERIFIED

- `mix precommit`: **191 passed (2 doctests, 189 tests)**, no warnings; the full suite was run 10 times without failure.
- **Lobby (13 tests):**
  - name rules;
  - the creator is host and the room is listed as joinable;
  - a full room is not joinable and refuses a fifth player;
  - mid-game join refused, reconnect allowed, non-host start refused;
  - a single player cannot start;
  - unknown room;
  - listing order;
  - summaries carry no player ids or cards;
  - **no spectators**;
  - lobby broadcasts for create, join, leave and close;
  - an empty room closes by itself.
- **PlayerIdentity (6 tests):**
  - a new session gets a player id that persists across requests;
  - sessions get distinct ids;
  - a tampered session cookie does not keep the id;
  - token round-trip;
  - forged, garbage, missing, expired and other-salt tokens rejected;
  - a verified token reconnects the player to their seat.

### Notes

- A test exposed a **real crash**: `normalize_name/1` raised `ArgumentError` on invalid UTF-8 input, because `String.trim/1` and the regex ran before the validity check. It is fixed: UTF-8 is checked first. Display names are user input, so this mattered.
- Rooms are identified by a short random id. There are no room names yet; the lobby shows the host's name.

## Phase 8 results (2026-09-27)

### Delivered

- **Routes** (`:browser` pipeline, `live_session :player` with `TienLenWeb.PlayerHook`):
  - `/` → `LobbyLive`;
  - `/phong/:id` → `TableLive`;
  - `POST /ten` → `PlayerController.set_name` (stores the name in the session; `return_to` accepts local paths only).
- The generator's page controller was removed; the layout is simplified to a game header plus the theme toggle; `<html lang="vi">`.
- **`LobbyLive`**:
  - name form;
  - live room list (lobby PubSub), with room id, host, x/4, status and a join link;
  - "Tạo phòng" opens an empty room (`Lobby.open_room/1`) and navigates there, so the creator joins from the table's own process.
- **`TableLive`**:
  - joins from its own process (monitored for disconnects), subscribes to the room, re-fetches its own `view/2` on every broadcast;
  - seats relative to the viewer (me at the bottom, next seat right, top, left);
  - host crown, connection badge, card count, pass / removed badges, place medals, turn countdown (1 s tick from `turn_ms_left`);
  - centre pile with combination name, owner and a "chặt" badge in chop context;
  - own hand as clickable card buttons; the selection lives only in this LiveView;
  - "Đánh" button whose disabled label is the server's dry-run reason (`RoomServer.check/3`);
  - "Bỏ lượt" only when passing is legal;
  - "Chặt ngoài lượt!" only when an out-of-turn four-pair is legal;
  - host "Bắt đầu ván" / "Ván mới";
  - results panel with ranking and instant-win reveal;
  - "Rời phòng".
  - No spectators: anyone who cannot be seated is sent back to the lobby with a message.
- **`TienLenWeb.Text`**: Vietnamese messages for every domain error reason, combination names, instant-win names, and place names (Nhất/Nhì/Ba/Bét).
- **`TienLenWeb.CardComponents`**: card faces from `priv/static/images/cards/` (52 faces + back, copied from the original; CC0).
- **Domain additions:** `Room.check/3` and `RoomServer.check/3` (dry runs for labels); `Lobby.open_room/1`.
- The **default HTTP port is 4010** (`config/runtime.exs`), because 4000 is used by the `openmu-web` container on this machine.

### VERIFIED

- `mix precommit`: **204 passed (2 doctests, 202 tests)**, no warnings. The full suite was run 10 more times: 0 failures.
- **LiveView tests** (real LiveView processes, two players with separate sessions):
  - each player's HTML contains only their own card ids and images;
  - the mandatory-card hint is shown only to the leader;
  - disabled-button labels come from server reasons (`Hãy chọn lá bài`, `Nước đầu phải có lá bắt buộc`);
  - a play updates both tables through PubSub;
  - pass visibility (not on a lead);
  - round end;
  - game over with ranking, and "Ván mới" only for the host;
  - instant-win reveal (the winner's hand only);
  - leaving frees the seat for others;
  - no name → lobby; unknown room → lobby with a message; a fifth player is refused;
  - every domain reason has a message.
- **Lobby LiveView tests:**
  - the name is stored in the session;
  - an invalid name gets a message;
  - `return_to` refuses `https://…`, `//…` and `javascript:` (no open redirect);
  - creating a room navigates to it;
  - the list updates live.
- **Real server over HTTP** (`PORT=4010 mix phx.server`, after `mix assets.setup && mix assets.build`):
  - `GET /` → 200 with a Vietnamese title;
  - `POST /ten` with the page's CSRF token → 302, and the name is shown;
  - `POST /ten` **without** a token → **403**;
  - card SVGs are served as `image/svg+xml`; CSS → 200.
- The CSRF token rendered inside the LiveView form is valid: LiveView loads the session's CSRF state on mount (`deps/phoenix_live_view/lib/phoenix_live_view/channel.ex`, `load_csrf_token/2`).

### NOT VERIFIED

- **Visual layout and interaction in a real browser**, including mobile widths, the countdown ticking, and reconnect after a real network drop. No browser was available in this environment. LiveView tests exercise the server side of every interaction, but not CSS or client JS.

## Phase 9 results (2026-09-27)

### Delivered

- Most of the realtime design was already in place from Phases 6–8:
  - PubSub per room, carrying events only;
  - each `TableLive` re-fetches its **own** projection on every broadcast, so message order does not matter;
  - connection tracking by `RoomServer` process monitors.
- Phase 9 adds `test/tien_len_web/live/realtime_test.exs`: multi-session checks on real LiveView processes.
- **Design decision:** `Phoenix.Presence` is **not** used. The room process already monitors every player's LiveView and ties connections to seats: that is the authoritative source for "connected", disconnect timers and host transfer. Presence would duplicate it. It can still be added later for a site-wide "who is online" count.

### VERIFIED

- `mix precommit`: **213 passed (2 doctests, 211 tests)**; the full suite was run 10 more times: 0 failures.
- **No hidden card ever reaches another player's page:**
  - whole games with 2, 3, 4 and 4 players (seeds 11, 22, 33, 44) are driven one command at a time;
  - after **every** command, every player's rendered HTML is compared with the server's actual hands;
  - no card of another hand, the undealt cards or discarded cards may appear (as image or card id), except instant-win reveals;
  - the player's own hand must be shown in full while they play.
- **Mutation check of that test:** a leak was injected on purpose (`Game.view/2` returning all hands as the player's hand). All 4 whole-game tests failed and named the leaked cards. The change was then reverted (git diff clean) and the suite passed again.
- **Connections seen by others:**
  - closing a tab (killing its LiveView) shows "mất kết nối" on the other player's table;
  - reopening removes the badge and shows the same hand;
  - two tabs of one player share the seat, and closing one keeps the player connected.
- **Out-of-turn chop through the UI:**
  - a player who already passed selects a four-pair while a 2 is on the table and sees "Chặt ngoài lượt!";
  - chopping updates all three tables (combination name plus the chop-context badge);
  - play continues from the seat after the chopper;
  - the current player sees a normal "Đánh" button for the same cards, not the chop button.
- **Server action on timeout:** with a 40 ms turn timeout, the other player sees the countdown badge and then the auto-played 3♠ in the centre.

### NOT VERIFIED

- A real browser over a real network (websocket reconnect after a network drop, mobile layout). Same as Phase 8.

## Phase 10 results (2026-09-27)

### Delivered

- **Hardening:**
  - catch-all `handle_call` / `handle_info` in `RoomServer` (unknown requests → `{:error, :unknown_request}`, stray messages ignored);
  - catch-all `handle_event` / `handle_info` in `TableLive` and `LobbyLive`;
  - **room cap**: `RoomServer.start_room/1` refuses when `max_rooms` rooms are open (`MAX_ROOMS`, default 500) → "Máy chủ đang quá nhiều phòng".
- **Resume links (reconnect on another device, T15):**
  - `PlayerIdentity.sign_resume/3` / `verify_resume/2`: a signed token with player id, name and room, valid 24 h;
  - `GET /tiep-tuc/:token` renews the session with that identity and redirects to the room;
  - `TableLive` shows the link only to its own player ("Chơi tiếp trên máy khác", with a warning not to share it).
  - Page reloads on the same device already reconnect through the session (Phases 7–9).
- **Deploy (O5):**
  - `mix phx.gen.release --docker` (`Dockerfile`, `.dockerignore`, `rel/`);
  - `deploy/docker-compose.yml`, `deploy/.env.example`, `deploy/.env` (gitignored, `chmod 600`, excluded from the build context);
  - prod config: `PHX_URL_SCHEME` / `PHX_URL_PORT` / `check_origin: :conn` / optional `PHX_FORCE_SSL` / `MAX_ROOMS`;
  - deployed as container `tien-len` on host port **4020**; see `docs/DEPLOY.md`.
- **Tests added:**
  - `test/tien_len/fuzz_test.exs`;
  - `test/tien_len/room_cap_test.exs` (not async: it changes global config);
  - `test/tien_len_web/security_test.exs`.

### Security review (RISKS.md section A)

| Risk | Status in the port | Evidence |
|---|---|---|
| R1 seed leak | Not reproducible: the seed is never stored (`Game`), `RoomServer.deals` is empty after the deal, and views/broadcasts carry no seed | `security_test` R1, `game_test` "does not keep the seed", `room_server_test` broadcast scan |
| R2 action-log leak | Not reproducible: no shared move log, selection is LiveView-local, broadcasts carry played cards only | `room_server_test` "whole game by timeouts" scan, `realtime_test` whole-game HTML checks (mutation-checked) |
| R3 unauthenticated sync | Not reproducible: identity only from the signed session (URL params ignored), a forged cookie loses the id, no spectators | `security_test` R3/R4, `player_identity_test`, `table_live_test` no spectators |
| R4 acting for another player | Not reproducible: every command carries the session's seat | `security_test` R3/R4, `game_test` authority, `room_test` |
| R5 no server validation | Not reproducible: all rules validated in `Rules` / `Game` | `rules_test`, `game_test`, `combination_test` |
| R6 crash on bad input | Not reproducible: bad input returns errors; catch-alls in processes | `fuzz_test` (200 games × 400 random commands; garbage calls and messages), `security_test` R6/R7 |
| R7 `undefined` in staging | Not reproducible: selection is limited to cards in the player's own hand | `security_test` R6/R7 (foreign and junk card codes) |
| R8 unvalidated player count | Not reproducible: 2–4 seats enforced | `room_test`, `lobby_test` |
| R9 rooms created on demand | Not reproducible: rooms only via the lobby; visiting an unknown id does not create it | `security_test` R9 |
| Extra: XSS through names | Escaped by HEEx | `security_test` XSS |
| Extra: open redirect | `return_to` local paths only | `lobby_live_test` |
| Extra: CSRF | Enforced (403 without a token), verified on the dev server and the container | `DEPLOY.md` verification |
| Extra: cross-site websocket | Refused (403 for a foreign `Origin`) | `DEPLOY.md` verification |

### VERIFIED

- `mix precommit`: **227 passed (2 doctests, 225 tests)**, no warnings. The full suite was run 10 more times: 0 failures.
- The Docker image builds. The container runs. The smoke tests in `DEPLOY.md` pass (HTTP, CSRF, SVG, websocket origin check, resume-link base URL). The image contains no `.env`.

### NOT VERIFIED

- A full game played in a real browser (dev server or container), including mobile layout and real network drops. This is the main remaining manual check.
- HTTPS behind a reverse proxy.

### Residual risks (accepted or open)

- **Resume links grant the identity** to whoever holds them, for 24 hours. The UI warns the player not to share them.
- **In-memory state**: a redeploy or crash ends running games (O2).
- No per-IP rate limiting beyond the room cap. Name length and LiveView frame limits bound payload sizes.

## Environment state

- Original repo: `/home/bien_nguyen/tien-len` (unmodified source). It contains one untracked file, `docs/research.md`, added during research. That file is **stale**: it is superseded by this repo's `docs/`. The owner decided to keep it.
- Scratch copy with `node_modules` and the probe tests: the session scratchpad (temporary, not needed).
- Toolchain: `~/.local/beam` (OTP 28, Elixir 1.20.4, `phx_new` 1.8.15), shared with `open-mu-web`.
- Git: local repo on branch `main`, no remote (the `gh` CLI is not installed). One commit per phase.
- Docker: container `tien-len` (image `tien-len:latest`) running on host port 4020, `restart: unless-stopped`; stop with `cd deploy && docker compose down`.
- Owner decision: keep the stale `docs/research.md` in the original repo (do not delete it).
