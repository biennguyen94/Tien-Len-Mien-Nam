# Risks, security issues and known bugs

Labels: **VERIFIED** = reproduced on 2026-09-27 by running the original (`nguyenank/tien-len@86b2621`, boardgame.io 0.39.16) in a scratch copy. **NOT VERIFIED** = source or library analysis only. **ASSUMPTION** = reasoned.
Details and code references: `RESEARCH.md` §15–19.

## A. Security issues in the original (must not be ported)

| ID | Severity | Issue | Status | Port handling |
|---|---|---|---|---|
| R1 | Critical | **PRNG seed sent to every client** (`state.plugins.random.data`). Replaying `setUp` with it reconstructs all hands. | VERIFIED | The seed stays in the room process; `Game.view/2` never includes it (T1, T14) |
| R2 | High | **Action log broadcast unredacted.** `relocateCards` args include `draggableId = rank+suit`, so opponents see which cards a player moves. | VERIFIED | No shared move log. Card selection stays in the player's own LiveView and is never broadcast. |
| R3 | High | **Unauthenticated `sync`.** Any socket can register as any `playerID` and receive that seat's hand. | NOT VERIFIED (library source) | Seat token verified on mount and on reconnect; the view is projected for the verified seat only |
| R4 | Critical | **Any player can act for the current player.** Stages are ignored, and `passTurn`, `cardsToCenter` and `tienLenPlay` act on `ctx.currentPlayer`. | VERIFIED (`passTurn`) | Every command carries its seat and is validated for that seat (T17) |
| R5 | Critical | **No server-side rule validation.** Invalid, non-beating and empty plays are accepted, and the 3♠ rule is client-only. | VERIFIED | Full validation in `Rules`/`Game` (D1) |
| R6 | Medium | **Crash on bad input.** `passTurn` when alone throws; an unknown `droppableId` throws. This may kill the Node process. | VERIFIED (throw); process crash NOT VERIFIED | Commands return `{:error, reason}`; the room process survives bad input |
| R7 | Medium | **Out-of-range index inserts `undefined` into the staging area.** | VERIFIED | Selection is validated against the player's own hand |
| R8 | Low | **Room creation takes `numPlayers` without min/max validation.** | NOT VERIFIED | Seat count enforced at 2–4 (D9) |
| R9 | Low | **`onSync` creates games on demand** for arbitrary ids. | NOT VERIFIED | Rooms are created only through the lobby |

## B. Functional bugs / oddities in the original (for background)

| ID | Issue | Status |
|---|---|---|
| B1 | 12 of 39 tests fail (stale `relocateCards` signature); some passing tests pass by accident; the duplicate-card test is vacuous (`_.uniqWith` without a comparator). | VERIFIED |
| B2 | An empty play advances the turn without marking a pass, and leaves `roundType = undefined`. | VERIFIED |
| B3 | The 3♠ rule follows whoever still has 3♠ in hand, for the whole game. | Source |
| B4 | The centre is not cleared when a new round starts. | Source (decided differently: #12) |
| B5 | The 4th-place player sees "Congratulations!". | Source |
| B6 | `cardsLeft` is stored separately from the hands, so it can drift. | Source |
| B7 | `validCombination` has dead code (`rank === 2`, a number vs a string comparison). | Source |
| B8 | A concurrent drag by an opponent bumps `_stateID` and can silently drop the current player's play. | NOT VERIFIED |

## C. Porting risks

| ID | Risk | Mitigation |
|---|---|---|
| P1 | **Implementing the original's rules instead of the decided ones.** The original has Tiến Lên chaining, 2s in pairs, no cross-type chops and 4 players only. | `RULES.md` is the only source; tests are written from RULES §16, not from the original's tests. |
| P2 | **Chop context bookkeeping.** It must start, persist (S3) and reset with the round. It is easy to get wrong. | An explicit field on the centre; property tests; RULES §16 examples 3, 5, 7. |
| P3 | **Out-of-turn four-pair races** with the current player's command and with the turn timer. | All commands serialised in the RoomServer; re-validate against the current centre; cancel or restart timers on every state change. |
| P4 | **Timer correctness** (20 s turn, 20 s disconnect) and tests that do not sleep. | Inject a clock / send timeout messages directly in tests; timer refs are stored and cancelled. |
| P5 | **Hidden-information leak through LiveView assigns or PubSub payloads.** | Broadcast events only; each LiveView projects its own view; add a test that asserts rendered HTML and messages contain no foreign cards. |
| P6 | **Auto-play on a lead timeout (X1)** might pick an illegal play, e.g. forgetting the mandatory card. | Build auto-play on `Rules` validation; test it with a mandatory card and in a 2-player game. |
| P7 | **Instant-win detection edge cases**: a quad counted as two pairs in 6 pairs; four 3's only in card-led games; several winners. | Table-driven tests (Phase 4). |
| P8 | **In-memory state (O2)**: a deploy or crash ends running games. | Accepted for the first release (ASSUMPTION until O2 is decided). |
| P9 | **Card artwork licence**: the original's SVGs are by Adrian Kennard. | Check the licence or use another card set (O4). |
