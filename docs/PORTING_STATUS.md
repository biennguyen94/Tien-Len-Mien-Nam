# Porting status

Last updated: 2026-09-27

| Phase | Name | Status |
|---|---|---|
| 1 | Research | **DONE** (2026-09-27) |
| 2 | Card / Deck | **DONE** (2026-09-27) |
| 3 | Combination engine | **DONE** (2026-09-27) |
| 4 | Rules engine | **DONE** (2026-09-27) |
| 5 | Pure game state | **DONE** (2026-09-27) |
| 6 | GameServer (room process) | NOT STARTED |
| 7 | Lobby / rooms | NOT STARTED. Needs O3 |
| 8 | LiveView UI | NOT STARTED. Needs O4 |
| 9 | Realtime (PubSub, presence) | NOT STARTED |
| 10 | Tests / security / reconnect / deploy | NOT STARTED. Needs O5 |

Phoenix app generated at the repo root (O1, O2). Domain so far: `TienLen.Card`, `TienLen.Deck` (Phase 2), `TienLen.Combination` (Phase 3), `TienLen.Rules` and `TienLen.InstantWin` (Phase 4), `TienLen.Game` (Phase 5). The web layer is still the generator's default page.

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

### Project decisions

| # | Decision |
|---|---|
| O1 | **One Phoenix app at the repo root**, `--app tien_len --module TienLen`. Pure domain in `lib/tien_len/`, web layer in `lib/tien_len_web/`. (Owner accepted the proposal, 2026-09-27.) |
| O2 | **No database** (`--no-ecto`, also `--no-mailer`): rooms and games live in memory; a restart ends running games. Ecto can be added later for accounts or history. (Accepted with O1; the generator needed it.) |

## Open decisions (project-level, not game rules)

| # | Question | Needed by | Proposal (ASSUMPTION until decided) |
|---|---|---|---|
| O3 | Player identity | Phase 7 | Anonymous: a display name plus a signed per-seat token (`Phoenix.Token`) stored in the session. No accounts. |
| O4 | UI language / card selection | Phase 8 | Vietnamese UI (maybe English later). Click-to-select cards with a JS hook only for ordering, or reuse the original's drag-and-drop idea. Card SVGs: the original's are by Adrian Kennard, so check their licence before copying. |
| O5 | Deployment | Phase 10 | Docker on WSL like `open-mu-web` (NOT decided). |

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

## Environment state

- Original repo: `/home/bien_nguyen/tien-len` (unmodified source). It contains one untracked file, `docs/research.md`, added during research. That file is **stale**: it is superseded by this repo's `docs/`. The owner decided to keep it.
- Scratch copy with `node_modules` and the probe tests: the session scratchpad (temporary, not needed).
- Toolchain: `~/.local/beam` (OTP 28, Elixir 1.20.4, `phx_new` 1.8.15), shared with `open-mu-web`.
- Git: local repo on branch `main`, no remote (the `gh` CLI is not installed). No commits yet.
- Owner decision: keep the stale `docs/research.md` in the original repo (do not delete it).
