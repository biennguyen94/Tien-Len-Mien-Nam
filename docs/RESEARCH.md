> **Status of this file (2026-09-27):** full reverse-engineering report of the original `nguyenank/tien-len`, copied from `/home/bien_nguyen/tien-len/docs/research.md`.
> §1–20 and §22 describe the **original** project and stay valid as background.
> §21 (decisions) and §23–25 (proposals) are **historical**: the current target rules are in `docs/RULES.md`, the decision log in `docs/PORTING_STATUS.md`, the plan in `docs/PORTING_PLAN.md`. If they disagree, those files win.
> Tags used here: **[code]** / **[lib]** / **[run]** ≈ VERIFIED; **[wiki]** / **[vi-wp]** = documented sources; **[uncertain]** ≈ ASSUMPTION.

# Tiến Lên (`nguyenank/tien-len`) — Reverse-Engineering Report

> Purpose: a specification for porting this game to Elixir/Phoenix.
> Scope: research only. The original source was **not** modified.
> Repo state analysed: `86b2621` (2020-12-18, "Merge pull request #4 from nguyenank/beautifuldnd"), `boardgame.io@0.39.16`.
> Wiki analysed: `tien-len.wiki.git` @ `eb6734f` (Rules page last changed `a629e85`, 2020-11-15).

### How the claims were verified

| Tag | Meaning |
|---|---|
| **[code]** | Read directly from the repository source (file/function cited). |
| **[lib]** | Read from the installed `boardgame.io@0.39.16` dist code. |
| **[run]** | Verified by running it. The repo was copied to a scratch directory, and minimal deps plus the original tests and extra probe tests were run there. The original working tree was not touched. |
| **[wiki]** | GitHub wiki `Rules.md` (cloned verbatim). |
| **[in-app]** | `src/components/Rules.js` (the rules page the app shows). It is *not identical* to the wiki. |
| **[vi-wp]** | Vietnamese Wikipedia, read through a summarising fetch. Treat quotes as approximate and re-check the article before relying on them. |
| **[uncertain]** | Inferred, not proven. |

---

## 1. Executive summary

* This is a **4-player-only** Tiến Lên implementation. The UI is **React 16** (Create React App), and **boardgame.io 0.39** provides the game engine, the socket.io multiplayer server and the lobby. One Node process (`server.js`) serves the built SPA, the lobby REST API and the game socket.
* All game rules live in three pure-ish JS files: `src/TienLen.js`, `src/moves/cardPlayMoves.js` and `src/moves/helper-functions/cardComparison.js`.
* **Most rule validation runs only on the client.** The server-side moves `cardsToCenter` and `tienLenPlay` accept any staged cards, including invalid combinations, plays that do not beat the centre, or nothing at all. `validPlay`, which holds the "must beat centre" and "first play must include 3♠" checks, is called only from the React button component. **[code][run]**
* **The stage restrictions are not active.** `TienLen.js` declares `stages` at the top level of the game object, but boardgame.io 0.39 only reads `turn.stages`. Every player is always "active", so every player can call every move at any time. Some moves act on `ctx.currentPlayer`, so another player can, for example, pass the current player's turn. **[lib][run]**
* **Hidden information leaks in three ways:**
  1. The PRNG seed is sent to every client, and replaying it reconstructs every hand.
  2. The action log broadcasts every player's drag-and-drop payload. That payload contains the card id (`draggableId` = rank+suit).
  3. The `sync` socket event has no credential check, so any socket can subscribe as any seat.

  All three were **[run]/[lib]** verified.
* **Test status: 27 of 39 existing tests pass and 12 fail.** All 12 failures come from tests written for an old `relocateCards(cards, area)` signature that was replaced by a drag-and-drop signature in `b2176a0`. Some turn-order tests "pass" only by accident. **[run]**
* The implemented rules match the wiki's core rules closely. The differences are subtle and are listed in §20–21. Examples: consecutive pairs may include 2s; the Tiến Lên player cannot open a new round with a combination that beats the centre; the 3♠ rule applies to whoever still holds the 3♠. The wiki's "winner starts next game", instant wins and the "Go Fish" house rule are **not implemented**. There is only one game per room.

* **Porting decisions D1–D9 are recorded in §21.** They change the target rules on purpose, most notably by removing the Tiến Lên chaining mechanic (D4). Sections 5–14 still describe the original only. Follow-up decisions (Q1–Q8, R1–R7, S1–S7, I1–I8) are in §21.1–21.8, and **§21.6 consolidates them into one target rulebook (T1–T18)**. §21.7 lists three non-blocking interpretations. Instant wins (tới trắng) are specified in §21.8, and every open point there is now decided.

---

## 2. Repository architecture

### 2.1 Technology inventory **[code]**

| Concern | Actual technology | Evidence |
|---|---|---|
| Frontend framework | React 16.13 (class + function components), CRA `react-scripts` 4 | `package.json`, `src/index.js` |
| Drag & drop | `react-beautiful-dnd` 13 (`react-sortablejs` is a leftover dependency, unused) | `src/TienLenBoard.js`, `src/components/Card.js` |
| Routing | `react-router-dom` 5 (`/` lobby, `/rules`) | `src/components/LobbyView.js` |
| Styling | SCSS via `node-sass` 4 | `src/index.scss`, `src/components/lobby.scss` |
| Game engine | `boardgame.io` ^0.39.16 (`Client`, `Lobby`, `Server`, `PlayerView`, `Stage`) | `src/TienLen.js`, `src/App.js`, `server.js` |
| Server | boardgame.io `Server` (Koa + koa-router + socket.io) plus `koa-static` for the SPA | `server.js` |
| Transport | socket.io via boardgame.io `SocketIO` multiplayer | `src/App.js`, bgio `Lobby` |
| Storage | boardgame.io default **InMemory** DB. No persistence: a restart loses all games. | `server.js` (no `db` option) **[lib]** |
| State management | boardgame.io redux store (`G` + `ctx`). No app-level store. | – |
| Utilities | lodash (`chunk`, `find`, `groupBy`, `cloneDeep`, `uniq`, `isEqual`, `last`) | all move files |
| Package manager | npm (`package-lock.json`) | – |
| Build | `react-scripts build` → `/build`; the server runs through `node -r esm` | `package.json`, `Procfile` |
| Tests | Jest (through react-scripts), boardgame.io headless `Client`; enzyme is configured but unused | `src/tests/*` |
| Lint/format | eslint + prettier-eslint (`.eslintrc.js` has a typo: `"detece"`) | `.eslintrc.js` |
| Deployment | Heroku (`Procfile: web: node -r esm server.js`), README cites `tienlen-en.herokuapp.com` | `Procfile`, `README.md` |

### 2.2 Verified architecture diagram

```text
 Browser (per player)                                        Node process (server.js, PORT or 8000)
 ─────────────────────                                        ───────────────────────────────────────
 index.js ── LOBBY=true ──► LobbyView (react-router)          koa-static(/build) + SPA fallback
                              │                                        │
                              ├─ "/rules" → Rules.js                   │
                              └─ "/"  → bgio <Lobby>  ──HTTP REST──►  bgio Lobby API (koa-router)
                                         │   /games/tien-len/create|join|leave|…   │
                                         │   credentials kept in cookie            ▼
                                         │   "lobbyState"                   InMemory DB
                                         ▼                                 (metadata + state + log)
                                   bgio React Client ◄──socket.io ns "tien-len"──► Master (per event)
                                   (board = TienLenBoard)   'sync' / 'update'         │
                                         │                                             ▼
                                 GameArea / PlayerArea / Buttons          CreateGameReducer(TienLen)
                                         │                                  moves in cardPlayMoves.js
                                 client-side validPlay() only                        cardAreaMoves.js
                                                                            playerView = STRIP_SECRETS
```

`App.js` (used when `LOBBY=false`) is a dev-only single-client setup with the bgio Debug panel. In that mode `numPlayers: 4` and there is no `playerID`.

---

## 3. File / module map

| File | Purpose | Key functions / data | Deps |
|---|---|---|---|
| `server.js` | Starts the bgio `Server({games:[TienLen]})`, serves `/build` and falls back to `index.html` | `Server`, `server.run` | boardgame.io/server, koa-static |
| `src/index.js` | Frontend entry. Renders `LobbyView` if `LOBBY`, else `App` | – | config |
| `src/config.js` | `GAME_SERVER_PORT=8000`, `GAME_SERVER_URL`, `WEB_SERVER_URL`, `APP_PRODUCTION=true`, `LOBBY=true` | constants | – |
| `src/App.js` | Dev client: `Client({game, numPlayers:4, board, multiplayer: SocketIO, debug})` | – | bgio react |
| `src/components/LobbyView.js` | Router with the bgio `<Lobby>` and the Rules page. **Mutates** `GameTienLen.minPlayers = maxPlayers = 4` (browser only) | `LobbyView` | bgio react, react-router |
| `src/TienLen.js` | **Game definition** | `TienLen` object, `setUp(ctx)` | constants, moves |
| `src/constants.js` | `Suits`, `Ranks`, `Combinations` | enums | – |
| `src/moves/cardPlayMoves.js` | **Play/pass/turn logic** | `validPlay` (client-side only), `tienLenPlay`, `cardsToCenter`, `passTurn`, `nextTurn` (private), `findNextPlayer` (private) | cardComparison |
| `src/moves/cardAreaMoves.js` | Hand/staging-area manipulation | `relocateCards`, `clearStagingArea`, `sortStagingArea` | cardComparison |
| `src/moves/helper-functions/cardComparison.js` | **Card and combination rules** | `compareCards`, `compareHighest`, `validCombination`, `validChop`, `consecutive` (private) | constants |
| `src/TienLenBoard.js` | Board root. Wraps everything in `DragDropContext(onDragEnd = moves.relocateCards)` | – | react-beautiful-dnd |
| `src/components/GameArea.js` | Opponent seats and centre pile | seat rotation `(i + pID) % 4` for `[2,3,center,1,0]` | – |
| `src/components/PlayerArea.js` | Own status, staging area, buttons, hand; "Congratulations!" | – | – |
| `src/components/Buttons.js` | Chooses `TienLenButton` or `PlayCardsButton`, and `PassButton` | reads `ctx.activePlayers[currentPlayer] === "tienLen"` | – |
| `src/components/buttons/*.js` | Play / TienLen / Pass / Sort / Clear buttons. **Holds client-side validation.** | `PlayCardsButton` calls `validPlay`, `TienLenButton` re-implements the same logic | – |
| `src/components/Card.js`, `CardArea.js` | Draggable card (`draggableId = rank+suit`), droppable list | – | rbd |
| `src/components/PlayerStatus.js` | Name + medal (🥇🥈🥉) or cards-left count | – | – |
| `src/components/_helperFunctions.js` | `getClassName`: current / passed / normal styling from `turnOrder` | – | – |
| `src/components/Rules.js` | In-app rules text (differs from wiki, see §20) | – | – |
| `src/tests/*.test.js` | Jest tests (see §18) | – | – |

---

## 4. Game engine usage (boardgame.io 0.39)

### 4.1 Game definition — `src/TienLen.js` **[code]**

```js
{
  name: "tien-len",
  setup: setUp,
  moves: { relocateCards, clearStagingArea, cardsToCenter, passTurn, tienLenPlay, sortStagingArea },
  stages: {                                   // ⚠ top-level: IGNORED by bgio 0.39 (see 4.2)
    tienLen: { moves: { tienLenPlay } },
    notTurn: { moves: { relocateCards, clearStagingArea, sortStagingArea } },
  },
  turn: {
    order: { first: G => G.firstPlayer },     // playOrderPos = seat index of 3♠ holder
    activePlayers: { currentPlayer: { stage: Stage.NULL }, others: { stage: "notTurn" } },
  },
  playerView: PlayerView.STRIP_SECRETS,
  endIf: G => G.winners.length === 3 ? { winners: [...G.winners, <remaining seat>] } : undefined,
}
```

* No `phases`, no `turn.order.next` (every turn end supplies an explicit `next`), no `onBegin`/`onEnd` hooks, no `minPlayers`/`maxPlayers` on the server-side object, and no `seed`.
* `ctx.events.endTurn({next})` and `ctx.events.setActivePlayers(...)` are the only events used, plus a redundant `setStage("notTurn")`.

### 4.2 Stages are declared in the wrong place **[lib][run]**

In bgio 0.39, `Flow({ moves, phases, endIf, onEnd, turn, events, plugins, disableUndo })` does not read `game.stages`. `GetMove()` only consults `conf.turn.stages`, which defaults to `{}`, and otherwise falls back to the **global** `moves`.

* The stage **names** still work: `ctx.activePlayers` contains `"tienLen"` / `"notTurn"`, and the UI reads them.
* The stage **move restrictions** do nothing. Every player is always in `activePlayers`, so `isPlayerActive` is true for all four, and every player may call all six moves at any time.
* **Verified [run]:** it was seat 2's turn, seat 3 called `passTurn()`, and the result was seat 2 marked as passed (`turnOrder [0,1,null,3]`), with the turn advanced to 3.

### 4.3 Game lifecycle (verified)

```text
POST /games/tien-len/create {numPlayers:4}   ── bgio Lobby API, InitializeGame → setUp(ctx) runs NOW (deal happens at creation)
      ↓
POST /games/tien-len/:id/join {playerID, playerName} ×4  → credentials per seat (cookie "lobbyState")
      ↓
Lobby shows "Play" once the room is full → React Client mounts, socket 'sync' → Master.onSync → filtered state
      ↓
turn 1: currentPlayer = G.firstPlayer (holder of 3♠); activePlayers = {cur: null, others: "notTurn"}
      ↓
any player: relocateCards / sortStagingArea / clearStagingArea (own cards, any time)
      ↓
current player: cardsToCenter  |  passTurn          (tienLenPlay when in "tienLen")
      ↓                          (server: NO rule validation beyond bgio's credential/active/stateID checks)
state mutation (center, roundType, cardsLeft, winners, turnOrder)
      ↓
nextTurn(): computes next seat, endTurn({next}), maybe setActivePlayers(tienLen)
      ↓
endIf: winners.length === 3 → ctx.gameover = { winners:[1st,2nd,3rd,4th] }
      ↓
UI shows "Game Over!"; no rematch / next game (bgio playAgain endpoint exists but is not used)
```

---

## 5. Game state

### 5.1 `G` (authoritative, server-held) **[code]**

```js
G = {
  turnOrder: [0, 1, 2, 3],        // Array(4) of (seatNumber | null | "W")
  center:    [],                  // Card[] — last combination played, sorted by compareCards
  players: {                      // keys "0".."3" (numeric keys coerced to strings)
    "0": { hand: Card[13], stagingArea: [] }, ...
  },
  roundType: "any",               // Combinations value | "any" | undefined (bug path)
  winners:   [],                  // string seat ids in finishing order
  firstPlayer: 2,                 // number, seat with 3♠ (only used by turn.order.first)
  cardsLeft: { 0: 13, 1: 13, 2: 13, 3: 13 },
}
```

| Field | Type | Purpose | Modified by | When | Visibility | Derived / authoritative |
|---|---|---|---|---|---|---|
| `turnOrder` | `(number\|null\|"W")[4]` | Who is still in the current **round**. Index = seat. `n` = still in, `null` = passed this round or finished, `"W"` = the most recent finisher whose last play is still pending | `passTurn`, `cardsToCenter` (winner), `nextTurn`, `tienLenPlay` | Every pass, finish, round reset | Public | Authoritative. Round-owner is implicit. |
| `center` | `Card[]` | Current combination to beat. Sorted ascending. | `cardsToCenter` (via `tienLenPlay`) | Every play | Public | Authoritative. **Not cleared on round reset**: the old cards stay visible while `roundType` is `"any"`. |
| `players[id].hand` | `Card[]` | Cards not staged. Order is user-controlled (sorted at deal). | `relocateCards`, `clearStagingArea`, `setUp` | Any time by its owner | **Private** (STRIP_SECRETS) | Authoritative |
| `players[id].stagingArea` | `Card[]` | Cards the player intends to play. The play moves read from here, so the move has no card arguments. | `relocateCards`, `clearStagingArea`, `sortStagingArea`, emptied by `cardsToCenter` | Any time by its owner | **Private** | Authoritative |
| `roundType` | `string` | Combination type of the round (`"any"` = free lead) | `cardsToCenter` (always = type of staged cards), `tienLenPlay`, `nextTurn` (reset to `"any"` after a winner) | Every play / reset | Public | Derived from `center` except for `"any"` |
| `winners` | `string[]` | Finishing order | `cardsToCenter` | When `cardsLeft[p]` hits 0 | Public | Authoritative |
| `firstPlayer` | `number` | Seat holding 3♠ at deal | `setUp` | Once | Public | Derived |
| `cardsLeft` | `{[seat]: number}` | Public card count. Used for **win detection**. | `cardsToCenter` (`-= center.length`) | Every play | Public (intentionally, per in-app rules "cards in hand is open information") | Derived (should equal `hand.length + stagingArea.length`) but stored separately, so it can drift |

### 5.2 Relevant `ctx` (boardgame.io-owned)

| Field | Meaning here |
|---|---|
| `ctx.currentPlayer` | Seat whose turn it is (string). **The play moves act on this seat, not on the caller.** |
| `ctx.playerID` | Caller (used only by the staging moves) |
| `ctx.activePlayers` | `{cur: null, others: "notTurn"}`, or `{cur: "tienLen", others: "notTurn"}` |
| `ctx.gameover` | `{ winners: [s1,s2,s3,s4] }` |
| `ctx.turn`, `playOrder` (`["0".."3"]`), `playOrderPos` | Standard |
| `state.plugins.random.data` | `{seed, prngstate}`, **sent to all clients** (see §17) |
| `_stateID` | Optimistic-concurrency counter checked by the server |

Things that are **not** stored: the deck (only the 4 hands exist after the deal), history of plays, round number, who played the centre (the round owner is implicit, see §11), per-round pass flags other than `turnOrder`, scores, and a match of several games.

---

## 6. Card model **[code]**

* A card is a plain object `{ suit, rank }`, both single-character strings.
  * `Suits = ["S","C","D","H"]`, low → high: ♠ < ♣ < ♦ < ♥.
  * `Ranks = ["3","4","5","6","7","8","9","T","J","Q","K","A","2"]`, low → high. Ten is `"T"`.
* **Identity / ID:** the string `rank + suit` (e.g. `"TS"`, `"2H"`). It is used as the React key, the `draggableId` and the SVG filename (`src/assets/cards/TS.svg`). There is no numeric id.
* **Equality:** lodash `find(..., {rank, suit})` or deep equality. Nothing enforces uniqueness. `validCombination([3S,3S])` returns `"pair"` **[run]**.
* **Ordering:** `compareCards(a,b)` compares the rank index first, then the suit index, and returns `1 / 0 / -1`.
  * The overall order is 3♠ < 3♣ < 3♦ < 3♥ < 4♠ < … < 2♦ < 2♥.
  * The lowest card is 3♠ and the highest is 2♥.
* **Serialization:** JSON objects inside `G`.
* **Sorting:** `Array.prototype.sort(compareCards)` (mutating). It is used on hands at deal, on the centre at play, and on the staging area when the user presses "Sort".

---

## 7. Deck creation & dealing — `setUp(ctx)` **[code][lib]**

```text
deck: for suit in [S,C,D,H], for rank in Ranks → 52 cards (suit-major order)
  ↓
n = ctx.random.Die(4)           // 1..4
shuffle (n+1) times             // 2..5 × ctx.random.Shuffle (a correct Fisher–Yates; repeating it adds nothing)
  ↓
_.chunk(deck, 13)               // CONTIGUOUS chunks, not round-robin dealing
  ↓
each chunk .sort(compareCards)  // hands start sorted
  ↓
firstPlayer = index of chunk containing {rank:"3", suit:"S"}
  ↓
turn.order.first = G.firstPlayer
```

* **Randomness:** boardgame.io's `random` plugin (Alea PRNG). The seed is `game.seed`, which is **not set**, so `Random.seed()` is used: `(+new Date()).toString(36).slice(-10)`, a timestamp.
  * The deal is deterministic given the seed. There is no test seeding; tests use random deals and overwrite `G` in place.
  * The seed is created and consumed **at room creation** on the server.
  * **The seed and PRNG state are shipped to every client.** Replaying `setUp` with the leaked seed reproduced another player's hand exactly **[run]**.
* The deal always creates exactly 4 hands, whatever `numPlayers` is.

---

## 8. Combination detection — `validCombination(cards)` **[code][run]**

The algorithm is an ordered cascade:

1. If `length === 1` → **single** (any card, including a 2).
2. If `length === 2` and both cards have the same rank → **pair** (including 2s).
3. If `length === 3` and all three have the same rank → **triple** (`"three-of-a-kind"`, including 2s).
4. If `length >= 3` and **no card is a 2**: sort, map to ranks, and if `consecutive(ranks)` → **straight**. On failure, fall through to step 6.
5. `else if (cards.some(c => c.rank === 2))` is **dead code**: it compares against the number `2`, but ranks are strings. It never returns.
6. If `length === 4` and all four have the same rank → **four-of-a-kind** (including four 2s).
7. Group by rank. If every group has exactly 2 cards and the *unique* sorted ranks are `consecutive`:
   * 6 cards → **three-pair**
   * 8 cards → **four-pair**
8. Otherwise → `undefined` (invalid).

`consecutive(ranks)` is true when `ranks` equals `Ranks.slice(indexOf(ranks[0]), …+len)`. Because `Ranks` ends `…K, A, 2`, **the 2 counts as consecutive after the A** for consecutive pairs. Straights explicitly exclude 2s.

### 8.1 Rules matrix (implemented)

| Combination (`Combinations` key → value) | Cards | Rank constraint | Suit constraint | 2 allowed? | A low? | Notes |
|---|---:|---|---|---|---|---|
| SINGLE `single` | 1 | – | – | yes | – | |
| PAIR `pair` | 2 | same rank | none | yes (pair of 2s) | – | |
| TRIPLE `three-of-a-kind` | 3 | same rank | none | yes | – | |
| STRAIGHT `straight` | 3–12 | strictly consecutive, no duplicates | none (suits may mix) | **no** | **no** (A-2-3, K-A-2 invalid) | Max is 3→A (12 cards) **[run]** |
| FOUROFAKIND `four-of-a-kind` | 4 | same rank | – | yes (four 2s) | – | |
| THREEPAIR `three-pair` | 6 | 3 pairs, consecutive ranks | none | **yes**: `K K A A 2 2` is valid **[run]** | no | Counts as a chop type |
| FOURPAIR `four-pair` | 8 | 4 pairs, consecutive ranks | none | **yes**: `Q Q K K A A 2 2` is valid **[run]** | no | Counts as a chop type |
| – | 10+ pairs | – | – | – | – | 5+ consecutive pairs are **invalid** **[run]** |
| ANY `any` | – | – | – | – | – | Not a combination: marks a free lead |

Also verified invalid **[run]**: `3 4 4 5`, `3 3 4 4` (only 2 pairs), `3 3 3 4 4 4` (two triples), `3 3 5 5 6 6` (gap), `5 5 5 5 6 6`, `A A 2 2`, any 2-card non-pair.

---

## 9. Beat / comparison rules

### 9.1 Algorithm — `validPlay(stagingArea, roundType, center, threeSpadesInHand)` **[code]**

This function is **client-side only**. It is called from `PlayCardsButton`, and `TienLenButton` duplicates the same logic.

```text
if staging empty or validCombination undefined        → "Invalid Combination"
elif threeSpadesInHand (3♠ still in *hand*)            → "First Play Must Include 3♠"
elif roundType == "any" or validChop(center, staging)  → OK
elif roundType != type(staging) or len(staging) != len(center) → "Does Not Match Center"
elif compareHighest(staging, center) != 1              → "Does Not Beat Center"
else                                                   → OK
```

`compareHighest(a, b)` compares the **single highest card** of each set (rank, then suit). Empty `a` → -1, empty `b` → 1.

### 9.2 Normal combination rules (verified examples) **[run]**

| Centre | Attempt | Result |
|---|---|---|
| single 2♠ | single 2♥ | beats (suit decides) |
| pair 7♣7♦ | pair 7♠7♥ | **beats**: same rank, higher top suit (7♥ > 7♦) |
| straight 3♥4♥5♣ | straight 3♣4♣5♠ | does not beat (5♠ < 5♣) |
| 5-card straight | 4-card straight | "Does Not Match Center" |
| 4-card straight | 5-card straight | "Does Not Match Center" (length must be equal) |
| three-pair 3-4-5 | three-pair 4-5-6 | beats |
| four-of-a-kind 5s | four-of-a-kind 9s | beats |
| three-pair | four-of-a-kind | "Does Not Match Center" |
| three-pair | four-pair | "Does Not Match Center" |
| four-of-a-kind | four-pair | "Does Not Match Center" |
| any (`"any"`) | any valid combination | OK |

Type and length must match exactly. The only comparison is the highest card, including its suit. There are **no cross-type beats** except chops of 2s (below).

### 9.3 Special chop rules — `validChop(center, cards)` **[code][run]**

```text
if center.length > 2 or any center card is not a 2 → false
if center is a pair of 2s and cards is four-pair  → true
if center is a single 2 and cards ∈ {three-pair, four-pair, four-of-a-kind} → true
else false
```

A valid chop skips the type and length checks entirely, and the round's `roundType` becomes the chop's type.

---

## 10. The `2` rules (implemented behaviour) **[code][run]**

| Question | Implementation |
|---|---|
| 2 in straights? | **No** (explicit `rank !== "2"` guard) |
| 2 in consecutive pairs? | **Yes**. `KKAA22` is a three-pair and `QQKKAA22` is a four-pair. |
| Single 2 choppable? | Yes, by three-pair, four-of-a-kind or four-pair |
| Pair of 2s choppable? | **Only** by four-pair. Four-of-a-kind and three-pair are rejected. |
| Triple of 2s choppable? | No. `validChop` rejects any centre with more than 2 cards. Only a higher triple of 2s could beat it. |
| Four 2s? | A four-of-a-kind. Only a higher four-of-a-kind could beat it, and none exists. |
| Can a 2 be beaten normally? | Yes, by a higher 2 of the same type (2♥ beats 2♠; a pair of 2s containing 2♥ beats one without it). |
| Can a chop be beaten? | Yes, **only** by the **same type**, higher (normal rule). Chop-over-chop across types (e.g. four-pair over three-pair) is **not** allowed. |
| Multiple chops in a round? | Only as a same-type escalation, e.g. three-pair → higher three-pair. |
| Does the chop depend on the current combination? | Only on `center` being a 1- or 2-card set of 2s. `roundType` is irrelevant once `center` qualifies. |
| Chop out of turn? | No. There is no out-of-turn mechanism; only the current player plays. |
| Chop during Tiến Lên? | Yes. `tienLenPlay` treats a valid chop as a continuation (§11). |
| Chop that itself contains 2s | Allowed: `KKAA22` chops a single 2 **[run]**. |
| Chop as a lead | Allowed, like any combination on `"any"` |
| Penalties (thối 2, etc.) | Not implemented |

---

## 11. Tiến Lên behaviour **[code][run]**

**Meaning in this repository:** when every other player in the round has passed, the one remaining player (always the one who played the current centre) gets an exclusive turn. They may keep playing combinations that beat the centre, including their own last play, **without anyone being able to respond**. Their first play that does *not* beat the centre becomes the lead of a new round.

* **Start:** automatic. At the end of `nextTurn()`, if `turnOrder` has exactly one non-null entry, the server calls `setActivePlayers({currentPlayer:{stage:"tienLen"}, others:{stage:"notTurn"}})`. The "current player" there is the one `endTurn({next})` just selected, i.e. that remaining seat.
* **UI:** `Buttons.js` shows `TienLenButton` instead of `PlayCardsButton` and **hides the Pass button**. The button reads "Tien Len - Tien Len" for a continuing play and "Tien Len - Play Card(s)" for a new-round play.
* **`tienLenPlay(G, ctx)` logic:**

```text
type = validCombination(staging)
if validChop(center, staging):          roundType = type           → continue Tiến Lên
elif type != roundType or !beats or len != len(center):             → END Tiến Lên:
        setStage("notTurn")  (redundant)
        turnOrder = [0,1,2,3] with winners → null     (everyone else is back in)
        roundType = type
(else: beats the centre)                                           → continue Tiến Lên
cardsToCenter(G, ctx)   → center = staging, cardsLeft -=, winner check, nextTurn()
```

  * "Continue" works because `turnOrder` still has one entry, so `nextTurn` picks the same seat and re-applies the `tienLen` stage **[run]**.
  * "End" works because `turnOrder` is refilled, so the next seat gets a normal turn and must beat the new centre.
* **Who may activate it:** nobody chooses it; it is purely automatic.
* **Multiple consecutive plays:** yes, unbounded, as long as each one beats the previous centre.
* **Can others interrupt?** Not through the UI. Server-side, stages are not enforced (§4.2), so another client could technically call moves.
* **Passing in Tiến Lên:** there is no Pass button. If `passTurn` is called anyway (possible because stages are not enforced), `turnOrder` becomes all-null and `findNextPlayer` throws `TypeError: Cannot read properties of undefined (reading 'toString')` **[run]**. On the server this is an exception inside an async socket handler. **[uncertain]** Whether that crashes the process depends on the Node version's unhandled-rejection policy.
* **Important consequence:** the remaining player **cannot** start a new round with a combination that happens to beat the centre. Such a play is always absorbed as a continuation, and they must eventually play something non-beating to hand the turn on. Example **[run]**: centre 6♦6♥, the player plays 8♠8♥ and stays in Tiến Lên (events `endTurn({next:"2"})` + `setActivePlayers(tienLen)`). They then play 3♠ and Tiến Lên ends (`turnOrder` → `[0,1,2,3]`, `roundType` = single, next seat 3).
* **The "free lead" is Tiến Lên:** `roundType` goes back to `"any"` **only** at game start and after a finisher's play goes unanswered (§13). In the ordinary case "everyone passed", there is no `"any"` state. The new round starts with the first non-beating play in Tiến Lên.

### 11.1 State-transition example (confirmed by source and tests)

```text
turnOrder [0,1,2,3], A=0 plays pair 6s              center=66 roundType=pair
B=1 passes → [0,null,2,3]
C=2 passes → [0,null,null,3]
D=3 passes → [0,null,null,null] → next = 0, only one left → A enters "tienLen"
A plays pair 8s  (beats 66)  → stays tienLen         center=88
A plays pair 10s (beats 88)  → stays tienLen         center=TT
A plays single 5 (does not beat) → Tiến Lên ends; turnOrder=[0,1,2,3]; roundType=single; center=5
B's normal turn: must beat single 5 (or pass)
```

---

## 12. Passing **[code]**

* **`passTurn(G, ctx)`** sets `G.turnOrder[currentPlayer] = null` and calls `nextTurn`.
* **Is passing allowed at any time?** The UI shows Pass whenever it is your turn and you are not in Tiến Lên, **including on a free lead** (`roundType "any"`), even the very first play of the game by the 3♠ holder. The server allows it at any time, for any caller, and it acts on `ctx.currentPlayer`.
* **Is it optional?** Yes. Nothing forces a play.
* **Can a passed player play again in the same round?** No. They are skipped by `findNextPlayer` until `turnOrder` is refilled.
* **When are passes cleared?** `turnOrder` is reset to `[0,1,2,3]` minus winners in two places:
  * when a Tiến Lên player makes a non-beating play (`tienLenPlay`)
  * in `nextTurn` when only a `"W"` marker remains (a finisher's play went unanswered).
* **What happens when all others pass?** See §11: the remaining player enters Tiến Lên.

### 12.1 Interaction of the four concepts

| Concept | Representation |
|---|---|
| current combination | `G.center` + `G.roundType` |
| passed players | `null` entries in `G.turnOrder` |
| round owner | **Implicit**: the last seat that played. It remains the only non-null entry once everyone else has passed. When the owner has finished, `"W"` stands in for them. |
| current player | `ctx.currentPlayer` (set via `endTurn({next})`) |

There is no explicit "round owner" field. That the owner is always the last one standing relies on turn cycling. The invariant breaks when `cardsToCenter` is called with an empty staging area, which the server accepts: the player then "plays nothing" and is **not** marked passed **[run]**.

---

## 13. Turn system **[code][run]**

* **Seat order and direction:** 0 → 1 → 2 → 3 → 0. On screen, `GameArea` puts you at the bottom, seat +1 on the right, +2 at the top and +3 on the left. That is **counter-clockwise**, which matches the wiki.
* **`findNextPlayer(turnOrder, cur)`:** takes the first non-null entry of `turnOrder[cur+1..3] ++ turnOrder[0..cur]`. The current seat comes last, so it wraps back to itself. It may return `"W"`.
* **`nextTurn(G, ctx)`:**

```text
next = findNextPlayer(turnOrder, cur)
if next == "W" and >1 non-null entries: clear every "W" to null; next = findNextPlayer again
elif next == "W" and exactly 1 non-null ("W" alone):
      turnOrder = [0..3] minus winners; roundType = "any";
      next = findNextPlayer(turnOrder, lastWinner)      // seat after the latest finisher
endTurn({next})
if exactly 1 non-null entry remains: setActivePlayers(tienLen for current)
```

* **Finished players** are skipped because they are `null`. After finishing, a player is replaced by `"W"` so the round can "come back" to them. The previous `"W"` becomes `null`, so only one exists at a time.
* **Multiple finishers in one move:** impossible, since each move plays one seat's cards.

### 13.1 Examples (from `winners.test.js` + code)

```text
1 finishes:          [0,"W",2,3]      2's turn
2 finishes:          [0,null,"W",3]   (old W cleared) 3's turn
3 passes:            [0,null,"W",null] 0's turn
0 passes:            next = "W", only W left → reset to non-winners → [0,null,null,3]
                     roundType="any", next = seat after last winner (2) → 3 leads freely
```

The test expects `turnOrder [0,null,null,3]` and current player 3.

---

## 14. Winning & ranking **[code]**

* **Finishing:** `cardsLeft[p] === 0` after `cardsToCenter`. The seat is pushed to `G.winners`, and `turnOrder[p] = "W"`.
  * When the finishing play was a **Tiến Lên continuation**, `"W"` is alone, so the next seat after the finisher gets a free lead (`"any"`) **[run, test]**.
  * When the finishing play **ended Tiến Lên** (non-beating), `turnOrder` was just refilled, so the others must beat that last play (`roundType` stays) **[run, test]**.
* **Game end:** `endIf` fires when `winners.length === 3` and sets `ctx.gameover = { winners: [1st, 2nd, 3rd, last] }`. There is no "last player plays out".
* **Ranking:** a complete 1st to 4th ordering. The UI shows 🥇🥈🥉 plus the cards-left count for 4th.
* **Next game / rematch / match scoring:** **not supported.**
  * The Rules.js line "winner of the previous game starts" is commented out.
  * The bgio `/playAgain` endpoint exists but is not wired into the UI.
  * The 3♠ rule applies to every game, because there is only ever one.
* **UI quirk:** at game over, `PlayerArea` shows "Congratulations!" to **every** seated player, including 4th place.

---

## 15. Multiplayer architecture **[lib][code]**

* **Authoritative state:** the server's `Master`, stored in `InMemory` per `gameID`. Clients run moves **optimistically** too (the bgio client reducer), but the server's `update` broadcast overwrites them.
* **Seats and identity:** `playerID` is `"0".."3"`. The lobby `join` endpoint returns a per-seat `playerCredentials`, which the Lobby stores in the `lobbyState` cookie together with `playerName`.
* **Move path (sequence):**

```text
Browser A (seat 2)                         Server (socket.io namespace "tien-len")
  click "Play Cards"
  moves.cardsToCenter()
  ├─ local optimistic reduce
  └─ emit 'update'(action{type, args, playerID:"2", credentials}, stateID, gameID, "2")
                                            │
                                            ├─ Master.onUpdate
                                            │   1. credentials == metadata.players[2].credentials ? (only if lobby-created)
                                            │   2. isPlayerActive(ctx, "2")  → always true (all in activePlayers)
                                            │   3. getMove(ctx, "cardsToCenter", "2") → global move (stages ignored)
                                            │   4. state._stateID === stateID ?  else silently dropped
                                            │   5. reducer: move(G, ctx) → events (endTurn, setActivePlayers) → endIf
                                            │   6. storage.setState
                                            └─ sendAll: for each socket in room:
                                                  G' = STRIP_SECRETS(G, ctx, socket's playerID)
                                                  emit 'update'(gameID, {...state, G:G'}, redactLog(deltalog))
                          ◄──────────────── Browsers A, B, C, D (and spectators) re-render
```

* **Reconnect:** on (re)mount the client emits `'sync'(gameID, playerID, numPlayers)`. `Master.onSync` returns the filtered state, the full (unredacted) log and player metadata **without checking credentials**.
  * `onSync` also **creates the game on demand** if the id is unknown.
  * On page reload the Lobby cookie drops the user back to the room list (`phase PLAY → LIST`), and they rejoin with the stored credentials.
* **Disconnect:** the socket is removed from the room map. There is no presence indicator, no timeout and no seat release, so the game simply waits.
* **Spectators:** a client without `playerID` receives `G.players = {}` (checked **[run]**). It sees the centre, `cardsLeft`, `turnOrder` and winners. `PlayerArea` renders nothing for spectators.
* **Concurrency:** all four players may call `relocateCards` at any time, and each call bumps `_stateID`. If an opponent drags a card while the current player clicks Play, one of the two actions is **silently dropped** as stale ("invalid stateID"). **[lib; not reproduced live]**

---

## 16. Lobby

* It uses the stock `boardgame.io/react` `<Lobby gameServer lobbyServer gameComponents>`. Its phases are ENTER (name) → LIST (create/join/leave/play/spectate) → PLAY.
* REST routes **[lib]**:
  * `GET /games`
  * `POST /games/:name/create`
  * `GET /games/:name`
  * `GET /games/:name/:id`
  * `POST /games/:name/:id/join|leave|playAgain|rename|update`
* The UI forces 4 players only by mutating `GameTienLen.minPlayers/maxPlayers` in the browser bundle. The **server's** `CreateGame` uses the posted `numPlayers` without a min/max check, so a crafted request could create a 2- or 3-seat room. `setUp` still deals four hands, and `turnOrder` is hardcoded `[0,1,2,3]`. **[uncertain: behaviour of such a room not tested]**
* Room listings are public and include `gameID`s (unless `unlisted`).

---

## 17. Client vs server responsibilities & security

### 17.1 Responsibility table (actual)

| Feature | Client | Server | Notes |
|---|---|---|---|
| Card selection (drag hand ↔ staging) | UI (rbd) | `relocateCards` stores the result in `G` | Staging lives in server state |
| Combination validity | `validPlay` / `TienLenButton` | **none** in `cardsToCenter`; `tienLenPlay` uses it only to pick continue/end | Invalid plays are accepted **[run]**: `roundType` becomes `undefined` |
| Beats-centre check | client only | **none** (`cardsToCenter`) | |
| 3♠ first-play rule | client only (`PlayCardsButton`) | none | |
| Turn validation (who may act) | buttons hidden/disabled | bgio: credentials + "is active" (always true) | **Any seat can act for the current seat** **[run]** |
| Card ownership | – | Implicit. Moves only use the actor's own `hand`/`stagingArea` (`relocateCards` uses `ctx.playerID`), so cards cannot be forged. But `cardsToCenter`/`passTurn`/`tienLenPlay` use `ctx.currentPlayer` regardless of the caller. | |
| Turn advancement | – | `nextTurn` | |
| Win detection / ranking | display | `cardsToCenter` + `endIf` | |
| Hidden hands | – | `PlayerView.STRIP_SECRETS` | Leaky, see below |
| Rendering | all | – | |
| Lobby / seats | bgio `<Lobby>` | bgio lobby API | |

### 17.2 Hidden information

| Question | Answer |
|---|---|
| Can A see B's cards through the normal UI? | No. STRIP_SECRETS sends only `players[self]`. |
| Is state filtered? | Only `G`, per recipient, in `Master` (`playerView`). `ctx`, `plugins` and the log are **not** filtered. |
| **Leak 1: seed** | `state.plugins.random.data = {seed, prngstate}` reaches every client. Replaying `setUp` with it reconstructs all four hands **[run]**. |
| **Leak 2: action log** | Each `relocateCards` arg (the full rbd `DropResult`, which includes `draggableId = rank+suit`) is broadcast to all clients in `log`. Opponents can watch which card each player stages **[run]**. |
| **Leak 3: unauthenticated sync** | `socket.on('sync', (gameID, playerID))` registers the socket as that `playerID` without checking credentials. That socket then receives the seat's private `G` on every update **[lib]**. |
| Can a malicious client submit arbitrary moves? | It cannot submit arbitrary *cards*: the plays read server-side staging. It **can**: play invalid or non-beating combinations, play an empty set, pass or play for the current player out of turn, call `tienLenPlay` outside Tiến Lên (which un-passes everyone if the play is non-beating), insert `undefined` into staging with an out-of-range index **[run]**, and throw a server exception with a bad `droppableId` or with `passTurn` in Tiến Lên **[run]**. |
| Does the server validate card ownership? | Implicitly yes, since cards only move between the caller's own areas. There is no explicit check. |

---

## 18. UI reverse-engineering → LiveView candidates

| React component | Responsibility | LiveView candidate (suggestion only) |
|---|---|---|
| `LobbyView` + bgio `<Lobby>` | Name entry, room list, create/join/leave, play/spectate, `/rules` route | `LobbyLive` (index), `RulesLive` or static page |
| `Rules.js` | Rules text | Static template |
| `TienLenBoard` | Root; DnD context → `relocateCards` | `GameLive` (one per seat/viewer) |
| `GameArea` | Opponent seats rotated around the viewer; centre pile + `roundType` label; "Game Over!" | `TableComponent`, `SeatComponent`, `CenterPileComponent` |
| `PlayerArea` | Own status, staging area, buttons, hand; "Congratulations!" | `HandComponent` + `StagingComponent` |
| `PlayerStatus` | Name + medal / cards-left | Function component |
| `CardArea` / `Card` | Droppable list / draggable SVG card | Function component. DnD needs a JS hook (e.g. SortableJS), or a click-to-select UI. |
| `Buttons`, `PlayCardsButton`, `TienLenButton`, `PassButton`, `StagingAreaButtons` | Show validation message as the button label; play/pass/sort/clear | Function components. Labels come from a **server-side** `Rules.validate_play/…` result. |
| `_helperFunctions.getClassName` | current / passed styling | Derived assigns |

**Missing UI states:** there is no loading state beyond the bgio defaults, no error toasts (the server silently rejects), no play history and no disconnect indicator.

---

## 19. Tests

### 19.1 Existing tests (run in a scratch copy: **27 pass / 12 fail**)

| File | Covers | Status |
|---|---|---|
| `compareCards.test.js` | `compareCards`, `compareHighest`, `validCombination` (single, pair, triple, straight, three/four-pair, quad, some invalid cases), `validChop` | 20/20 pass |
| `setUp.test.js` | 13 cards each, sorted hands, 52 cards | 3/3 pass. The "no duplicates" check is **vacuous**: `_.uniqWith(hands)` without a comparator dedupes nothing. |
| `playCards.test.js` | roundType changes, invalid/low plays, higher plays, chop | **0/4**: uses the stale `relocateCards(cards, area)` |
| `turnOrder.test.js` | wrap-around, skipping passed, Tiến Lên start/persist/end | 4/6. The 4 passing ones pass **by accident**: `relocateCards` is a no-op, so `cardsToCenter` plays nothing, but the turn still advances. |
| `winners.test.js` | winners list, finish in Tiến Lên, W-marker turn order, game-over ranking | **0/6** (stale API) |

The tests also mutate the store's state object in place (`G = client.store.getState().G; G.players = …; ctx.currentPlayer = "0"`), which relies on implementation details of bgio.

### 19.2 Missing tests

* Server-side rejection of invalid, non-beating or out-of-turn plays (none exists, and the behaviour itself is missing).
* The 3♠ rule. Passing on a free lead. Passing on the very first play.
* Consecutive pairs containing 2s. 5+ pairs. 12-card straight. A-low straights.
* Chop vs chop across types. Chops inside Tiến Lên. Pair-of-2s vs quad.
* A finisher's last play being beaten, and W-marker clearing across several rounds.
* Tiến Lên with a beating first play (cannot open a new round).
* Multiplayer: hidden info (seed, log, sync), credentials, stale `stateID`, reconnect.
* UI: none (enzyme is configured but unused).

### 19.3 Potential bugs (documented, not fixed)

1. Stages declared at the top level are ignored, so there is no per-stage move restriction (§4.2).
2. `cardsToCenter` / `tienLenPlay` / `passTurn` act on `currentPlayer`, not the caller.
3. No server-side validation of plays or of the 3♠ rule.
4. Empty `cardsToCenter`: `center=[]`, `roundType=undefined`, turn advances, player not marked passed **[run]**.
5. `roundType = undefined` after an invalid play means every normal play is then "Does Not Match Center" until the round resets.
6. `passTurn` while alone throws a `TypeError` **[run]**.
7. `relocateCards` with an out-of-range index inserts `undefined`. An unknown `droppableId` throws.
8. `validCombination` has dead code (`rank === 2`, number vs string).
9. The 3♠ rule is based on "3♠ still in hand", so if its holder passes first, they must include 3♠ in **every** later normal play until they play it. `TienLenButton` does not apply the rule at all.
10. `center` is not cleared when `roundType` resets to `"any"`: the old cards stay on display.
11. The 4th-place player sees "Congratulations!".
12. `cardsLeft` is maintained separately from the actual card arrays.
13. `setUp.test` duplicate check is vacuous.

---

## 20. Rules comparison (source vs wiki vs Vietnamese Wikipedia)

The in-app `Rules.js` is compared separately where it differs from the wiki.

| Rule | Source implementation | Wiki (`Rules.md`) | vi.wikipedia **[vi-wp]** | Conclusion |
|---|---|---|---|---|
| Players | Exactly 4 (hardcoded deal, `turnOrder`) | 4 | 2–4 | Implementation = 4 only |
| Rank order | 3<…<A<2 | same | same | Agree |
| Suit order | ♠<♣<♦<♥ | same | same (♥ highest) | Agree |
| First game starter | 3♠ holder | 3♠ holder, must play 3♠ | 3♠ holder, must include 3♠ (Huế variant: 3♣) | Agree. **Enforcement is client-only and "in hand" based.** |
| Later games | N/A (one game per room) | Winner of previous game starts, no restriction | Previous winner | Not implemented (commented out in `Rules.js`) |
| Direction | Seat 0→1→2→3, shown counter-clockwise | Counter-clockwise | Counter-clockwise | Agree |
| Straight | ≥3, any suits, no 2, no wrap | same | South: any suit. North: same suit. No 2. | Implementation = wiki = southern style |
| Consecutive pairs as a type | Only 3 pairs (6) and 4 pairs (8). 2s allowed. | Defined only as chops. 2s unspecified. | South: 3+ pairs (5 đôi thông mentioned). 2s not stated. | **Differences:** 5+ pairs are invalid here, and 2s are allowed here. The wiki is silent on 2s. |
| Beat rule | Same type, same length, higher top card (incl. suit) | same | Same type and higher. North requires same suit/colour. | Agree with wiki |
| Pass | Out for the rest of the round | same | same (no re-entry that round) | Agree |
| Pass on free lead | Allowed | Not addressed | Not addressed | **Ambiguous** |
| All others pass | Remaining player enters Tiến Lên (exclusive beating plays), then a non-beating play starts a new round | "may tiến lên … Whether the remaining player plays any cards in tiến lên, that player will then start a new round" | The last player simply leads a new round (no "tiến lên" chaining described) | Implementation ≈ wiki. **Difference:** the wiki suggests choosing *not* to chain and leading anything. The implementation cannot lead a new round with a beating combination. |
| Chop single 2 | three-pair, quad, four-pair | same | 3 đôi thông, tứ quý, 4 đôi thông | Agree |
| Chop pair of 2s | four-pair only | four-pair only | **tứ quý and 4 đôi thông** can chop a pair of 2s | Source = wiki, **differs from vi-wp** |
| Chop a chop | Same type, higher only | "Chops can be beaten like any other combination, same type highest card" | 4 đôi thông beats 3 đôi thông and tứ quý. "Chặt chồng" (stacked chops) exists. | Source = wiki, **differs from vi-wp** |
| Chop outside 2s | Only as same-type or lead | "only to beat a 2 … or to start a round" + same-type beating | Varies | Consistent with wiki |
| Out-of-turn chop | No | No | Đà Nẵng: 4 đôi thông "at any time" | Not implemented |
| Finishing | Continue until 3 have finished. Finisher's unanswered play → next seat after finisher leads. | same | First out wins, ranks nhất/nhì/ba/bét | Agree. Edge case in §14 (finishing via a non-beating Tiến Lên play). |
| Instant wins (tới trắng) | No | Commented out ("NOT YET IMPLEMENTED") | Yes (tứ quý heo, 6 pairs, dragon…) | Not implemented |
| Penalties (thối, cóng) | No | No | Yes | Not implemented |
| Go Fish house rule | No | Commented out | No | Not implemented |
| Card count public | Yes (`cardsLeft`) | "players may agree to be honest" | – | In-app `Rules.js` says: "In this implementation, cards in hand is open information." |

**In-app `Rules.js` vs wiki:** the in-app text lacks "For every game after, the winner … starts" (commented out), lacks the hidden Instant-Wins and Go-Fish sections, and adds the sentence about open card counts.

---

## 21. Porting decisions (recorded 2026-09-27)

These decisions define the **target** behaviour of the Elixir port. Where they differ from the original source, the port follows the decision, and §5–14 remain a description of the original only.

| # | Decision | Deviation from original source |
|---|---|---|
| D1 | **The server enforces every play rule.** No rule lives only in the client. | Original validates only in the browser (§17). |
| D2 | **3♠ is required only on the first play of a game with no previous winner.** The 3♠ holder leads and that play must contain 3♠. After that there is no restriction. | Original: client-only check that follows whoever still has 3♠ in hand. |
| D3 | **No passing when leading a new round.** Passing is allowed only when responding to a combination on the table. | Original allows passing on a free lead. |
| D4 | **When all other players have passed, the round ends.** The last player to play leads a new round with any valid combination. | **Removes the original "Tiến Lên" chaining mechanic (§11) entirely.** Also differs from the wiki. |
| D5 | **2s are not allowed in consecutive pairs.** | Original accepts `KKAA22` and `QQKKAA22`. |
| D6 | **Chop hierarchy** (see table below). | Original: single 2 ← 3 pairs/quad/4 pairs; pair of 2s ← 4 pairs only; no cross-type chops. |
| D7 | **Cross-type chops follow D6 and do not compare rank.** Same-type responses must be higher (top card incl. suit). | Original: same type only. |
| D8 | **A room/session plays several games in a row. The winner (1st place) of the previous game leads the next game.** | Original: one game per room. |
| D9 | **2, 3 or 4 players. Never more than 4.** | Original: exactly 4. |

### 21.1 Follow-up decisions (recorded 2026-09-27, second batch)

| # | Decision |
|---|---|
| Q1 | **Deal 13 cards per player; the remaining cards are out of the game** (2 players = 26 cards, 3 players = 39). If the 3♠ is among the undealt cards, nobody holds it: the player at `starting_seat` leads and the 3♠ rule is waived for that game. |
| Q2 | **After a player empties their hand and everyone else passes, the next seat (in turn order) that still holds cards leads the new round.** A finished player never gets another turn. |
| Q3 | **A three-pair can be answered by any four-of-a-kind only when that three-pair was played as a chop on a 2.** A three-pair played normally does not open the door to a four-of-a-kind. |
| Q4 | **Chop combinations (bombs) cannot be played on ordinary cards.** They are only valid against 2s or against a valid chop. Example: four 5s may **not** be played on A♥. |
| Q5 | **A game ends when only one player still holds cards** (N − 1 players finished). |
| Q6 | **The previous game's winner/leader has priority to lead the next game, but the 3♠ rule is reset for every game.** If that player has left the room, the next valid seat is used. Every new game applies the 3♠ rule again, except when Q1 leaves the 3♠ undealt. |
| Q7 | **Five or more consecutive pairs are invalid.** Only three-pair and four-pair exist. |
| Q8 | **Chops are only allowed on your own turn, except four-pair, which may chop out of turn.** All other chops must wait for their turn. |
| #12 | **The centre is cleared when a new round starts.** The new lead is free. |
| #15 | **Every player's remaining card count is public.** |
| #16 | **Pairs of the same rank are compared by the highest suit in the pair** (♠ < ♣ < ♦ < ♥). |
| #17 | **No spectators** in the first release. |
| #18 | **A disconnected player keeps their seat for a timeout period** and can reconnect with a seat token. On timeout the room applies a "disconnect rule" (still to be defined, see R5). A disconnected player is never treated as the winner automatically. |

**D2 is superseded by Q6:** the 3♠ rule now applies to the first play of **every** game, not only the first game of a session.

### 21.2 Beat matrix (D6/D7 as refined by Q3, Q4, Q7, Q8, R2, R3, S3, S4)

**Chop context.** A combination on the table is either *normal* or *in chop context*. It is in chop context when it was played to chop a single 2 or a pair of 2s, or to beat something that was already in chop context. Cross-type chops (three-pair → four-of-a-kind → four-pair) are only allowed in chop context (Q3, R2). Chop context **persists through same-type beats** until the round ends (S3). Example: 2 → three-pair → higher three-pair is still chop context, so a four-of-a-kind may follow.

| Combination on the table | Allowed on your turn | Allowed out of turn (four-pair only, R3) |
|---|---|---|
| single 2 | higher single 2; **any** three-pair, four-of-a-kind or four-pair (starts chop context) | any four-pair |
| pair of 2s | higher pair of 2s; **any** four-of-a-kind or four-pair (starts chop context) | any four-pair |
| three-pair, **chop context** | higher three-pair; **any** four-of-a-kind; **any** four-pair | any four-pair |
| three-pair, **normal** | higher three-pair only | – |
| four-of-a-kind, **chop context** | higher four-of-a-kind; **any** four-pair | any four-pair |
| four-of-a-kind, **normal** | higher four-of-a-kind only | – |
| four-pair, **chop context** | higher four-pair | higher four-pair (S4) |
| four-pair, **normal** | higher four-pair only | – |
| anything else (single, pair, triple, straight, incl. triple of 2s) | same type, same length, higher top card. **No chops** (Q4). | – |

"Higher" means the normal top-card comparison: rank first, then suit (#16). With D5, the highest three-pair is Q-K-A and the highest four-pair is J-Q-K-A. Five or more pairs are invalid (Q7).

### 21.3 Status of all ambiguities

| # | Question | Status |
|---|---|---|
| 1 | Server validation | **Decided: D1** |
| 2 | 3♠ rule scope | **Decided: D2 → Q6 → R1/R4/R7/S7** (see §21.6, rules T2–T3) |
| 3 | Passing on a free lead | **Decided: D3** (not allowed) |
| 4, 5, 10, 19 | Tiến Lên chaining details | **Moot: D4** |
| 6 | 2s in consecutive pairs | **Decided: D5** (not allowed) |
| 7 | 5+ consecutive pairs | **Decided: Q7** (invalid) |
| 8 | Four-of-a-kind chops a pair of 2s | **Decided: D6** (yes) |
| 9 | Cross-type chop over chop | **Decided: D6/D7 + Q3** |
| 11 | Lead after a finisher | **Decided: Q2** |
| 12 | Clear the centre | **Decided** (yes) |
| 13 | Multi-game sessions | **Decided: D8 + Q6** |
| 14 | Player count | **Decided: D9** (2–4) |
| 15 | Public card counts | **Decided** (public) |
| 16 | Same-rank pair by suit | **Decided** (yes) |
| 17 | Spectators | **Decided** (not in the first release) |
| 18 | Disconnect | **Decided: #18 + R5** (20 s, then removed from the game) |
| 20 | Triple of 2s / four 2s | **Decided by D6 + Q4:** a triple of 2s cannot be chopped; four 2s is a four-of-a-kind, beaten only by a four-pair |
| Q1–Q8 | Follow-ups | **Decided** (§21.1) |
| R1–R7 | Conflicts and gaps | **Decided** (§21.4) |
| S1–S7 | Final details | **Decided** (§21.5) |
| I1–I8 | Instant wins (tới trắng) | **Decided** (§21.8, including the final clarifications in §21.8.1) |

### 21.4 Decisions on the remaining questions (recorded 2026-09-27, third batch)

| # | Decision |
|---|---|
| R1 | **The previous game's winner overrides the 3♠ rule.** The winner leads the next game and does not need to hold the 3♠. |
| R2 | **A normally-played three-pair cannot be chopped by a four-pair.** Chops only apply in the context of chopping a 2 or a valid chop. Likewise, **a four-of-a-kind is only choppable by a four-pair when it was played as a chop**; a normally-played four-of-a-kind is not. |
| R3 | **Four-pair is a special interrupt.** It may be played out of turn on any valid chop target, **even by a player who has already passed**. After a successful chop, **the turn goes to the chopper** and the round's pass marks are reset. There is no separate chop timer; the turn timeout applies. Near-simultaneous commands are processed in arrival order by the GameServer, and the first valid one wins. |
| R4 | **Opening-leader order:** previous game's winner → 3♠ → 3♣ → 3♦ → 3♥ → 4♠ → … (rising rank, suits ♠ < ♣ < ♦ < ♥) until a card that some player holds. Replaces `starting_seat` from Q1. |
| R5 | **Disconnect timeout = 20 seconds.** During it the player keeps their seat and may reconnect. On timeout the player is **removed from the current game** and treated as disconnected; if it was their turn, they are auto-passed so the game continues. |
| R6 | **Only the room host can start a game**, with **at least 2 players** (host included); 4 are not required. **No joining mid-game.** |
| R7 | **A player who leads under the 3♠ rule may not pass: their first play must contain the 3♠.** Exception: when R1 applies, the previous winner leads without the 3♠ requirement. |

Supersessions: **R4 replaces the "next valid seat" fallback of Q6** (if the winner has left, the leader is chosen by lowest card). **R1 overrides Q6's "3♠ rule reset every game"** whenever a previous winner is present.

### 21.5 Final decisions (recorded 2026-09-27, fourth batch)

| # | Decision |
|---|---|
| S1 | **Turn timeout = 20 seconds.** On expiry the server acts for the player: when **responding**, it passes. When **leading a new round** (passing forbidden), it plays the **lowest valid combination** the player can play. On a first play that must contain the card that selected the leader, it plays the **lowest combination containing that card**. |
| S2 | **After an out-of-turn four-pair, play continues from the seat after the chopper**, in normal seat order. The four-pair is on the table and must be beaten or passed. |
| S3 | **Chop context persists through same-type beats** (see §21.2). |
| S4 | **In chop context, a higher four-pair may chop a lower four-pair out of turn.** |
| S5 | **A player removed after the disconnect timeout** leaves the game and their cards are discarded. They rank **after every player who finished normally**; several removed players rank in order of removal. If only one player then holds cards, **the game ends immediately**. If the removed player was due to lead, the next remaining player leads. **They play normally in the next game** if still in the room/session. |
| S6 | **When the host leaves or disconnects, host rights pass to the next remaining player in seat order.** The room stays open while at least one player remains. The new host may start the next game. |
| S7 | **The first play must contain the card that selected the leader** (3♠, or 3♣, 3♦, … when the lower cards are undealt). **Supersedes Q1's "3♠ rule waived".** The previous winner (R1) is still exempt. |

### 21.6 Consolidated target rules (the port's rulebook)

This merges every decision: D1–D9, Q1–Q8, #12–#18, R1–R7, S1–S7. **This table is the source of truth for the port.** Where an item still relies on an interpretation, it points to §21.7.

| # | Rule |
|---|---|
| T1 | **Players and deal.** 2–4 players. Each gets 13 cards from a shuffled 52-card deck; the undealt cards are out of the game. The seed stays on the server. |
| T2 | **Opening leader** (R4, I5): the previous game's winner, if still in the room **and the previous game did not end by instant win**; otherwise the holder of the lowest dealt card among the players taking part, searching 3♠, 3♣, 3♦, 3♥, 4♠, … |
| T3 | **Opening play** (R7, S7): a leader chosen by card must include that card in their first play and may not pass. A previous winner leads freely (R1). |
| T4 | **Card order:** ranks 3 < … < A < 2; suits ♠ < ♣ < ♦ < ♥. |
| T5 | **Combinations:** single; pair; triple; straight (3–12 cards, no 2s, no wrap-around); four-of-a-kind; three-pair and four-pair (consecutive, **no 2s**). Five or more pairs are invalid. |
| T6 | **Beating:** per §21.2. Same type needs a higher top card (and the same length); same-rank pairs compare by their highest suit. Cross-type only in chop context, which persists through same-type beats until the round ends. No chops on ordinary cards. |
| T7 | **Leading:** the leader must play; passing is not allowed (D3). |
| T8 | **Passing:** allowed only when responding. A passed player is skipped until the round ends, except that they may still play an out-of-turn four-pair (R3). |
| T9 | **Round end:** when every other player with cards has passed, the round ends, the centre is cleared, pass marks and chop context are reset, and the last player to play leads (D4, #12). If that player has finished or been removed, the next seat with cards leads (Q2, S5). |
| T10 | **Out-of-turn four-pair** (R3, S2, S4): any player with cards, passed or not, may play a four-pair on any chop-context target at any moment (single 2, pair of 2s, chop-context three-pair, four-of-a-kind, or lower four-pair). The first valid command wins. Pass marks are reset, and play continues from the seat after the chopper. |
| T11 | **Finishing and ranking:** a player who empties their hand takes the next finishing position and never plays again this game. The game ends when only one player has cards (Q5, S5). Ranking = normal finishers in order, then the last player holding cards, then removed players in order of removal (§21.7 item 2). |
| T12 | **Turn order:** seats in counter-clockwise order, skipping passed, finished and removed players. |
| T13 | **Room and sessions:** a room plays several games. Only the host starts a game, with at least 2 players. Nobody joins mid-game (R6). When the host leaves or disconnects, host rights pass to the next player in seat order; the room stays open while anyone remains (S6). |
| T14 | **Visibility:** each player sees only their own hand. Everyone sees the centre, turn, pass marks, finishing order and **every player's card count** (#15). No spectators (#17). |
| T15 | **Disconnect:** the seat is held for 20 s and a seat token allows reconnection. After 20 s the player is removed from the current game, their cards are discarded, and they never count as a winner (R5, S5). They play normally in the next game if still in the room. |
| T16 | **Turn timeout (S1):** 20 s per turn. On expiry: responding → auto-pass; leading → auto-play the lowest valid combination; mandatory opening card → auto-play the lowest combination containing that card. There is no separate timer for out-of-turn chops. |
| T17 | **Authority:** the server validates everything (D1). Commands are serialised per room; for near-simultaneous commands, the first valid one wins. |
| T18 | **Instant win (tới trắng)** (§21.8): right after the deal, the server checks every dealt hand for **four 2's**, **6 pairs** or a **dragon** (plus **four 3's** when the leader is chosen by lowest card; four triples are not an instant win). If any player qualifies, the game ends immediately with no play and the qualifying hands are revealed to everyone. Every instant winner ranks 1st (seat order breaks ties); all other players rank tied after them. The next game's leader is chosen by lowest card, not by the instant winner (I5). |

### 21.7 Interpretations to confirm

No blocking questions remain. These three points are fixed in the spec with the interpretation below; the implementation should follow them unless you say otherwise.

1. **"Lowest valid combination" (S1).** Any single card is a valid lead, so the lowest combination is always **the single lowest card** in the hand. When a card is mandatory, it is **that card as a single**. (If you meant something else, e.g. "lowest by type first", it needs a definition.)
2. **Rank of the last player holding cards vs removed players (T11).** The spec ranks the player still holding cards at the end **above** removed players, because S5 says removed players rank after everyone who "về bình thường". Confirm that the last player counts as ranking above removed players.
3. **When host rights pass on disconnect (S6).** The spec transfers host rights **after the 20 s disconnect timeout** (consistent with R5), not the moment the connection drops. A host who reconnects within 20 s keeps host rights.

### 21.8 Instant wins — tới trắng (recorded 2026-09-27)

The original repo does not implement instant wins. The wiki has an "Instant Wins" section, but it is commented out and marked "NOT YET IMPLEMENTED IN GAME" (§20). The decisions below add them to the port.

| # | Decision |
|---|---|
| I1 | **Instant wins exist.** An instant winner ranks **1st** in that game, but **does not lead the next game**. The next game's leader is chosen by the lowest-card rule (3♠ → 3♣ → 3♦ → 3♥ → 4♠ → 4♣ → …). Qualifying hands (first batch, names as in the project wiki): **four 2's**, **6 pairs** (pairs of 2s count), **dragon**. "Five consecutive pairs" is not an instant win (Q7). |
| I2 | **The game ends immediately** when an instant win is detected. The other players do not play that game. |
| I3 | **The server detects instant wins automatically right after the deal.** Players do not declare them, and there is no declaration window. |
| I4 | **Several instant winners all rank 1st.** Seat order breaks the tie when an order among them is needed. **All other players rank tied, after the instant-win group.** |
| I5 | **Instant win is an exception to R1.** The instant winner does not lead the next game automatically. The next game's leader is the holder of the lowest dealt card among the players taking part (3♠ → 3♣ → …). If that card's holder does not take part, the search continues with the next lowest card. |
| I6 | **Instant wins apply in the first game of a session too.** **Four 3's is an instant win only in a game whose leader is chosen by the lowest-card rule**: the first game of a session, a game after the previous winner left, or a game after an instant-win game. It is not an instant win when the previous winner leads (R1). The mode is known before the deal, so detection stays deterministic. *(Widened from "first game of the session only" in the final batch.)* |
| I7 | **2–3 player games also use instant wins**, checked on each player's 13 dealt cards. Undealt cards play no part. |
| I8 | **Once the server confirms an instant win, the qualifying player's whole hand is revealed to every player** so they can check it. Other hands stay hidden. |

*The decisions above replace an earlier batch in which the instant winner led the next game and ties used the previous game's ranking.*

#### Hand definitions used by the spec

These follow the wiki's wording ("all four 2's and nine other cards", "six pairs and one other card", "one card of every single rank") and I1.

| Name | Condition on the 13-card hand | Notes |
|---|---|---|
| four 2's | holds 2♠ 2♣ 2♦ 2♥ | – |
| ~~4 triples~~ | – | **Deliberately excluded**, although the wiki and some rulesets list it. |
| 6 pairs | the hand can be split into 6 disjoint pairs + 1 card | Pairs need not be consecutive; pairs of 2s count (I1); **four of a kind counts as two pairs** (e.g. 7777 + 4 other pairs + 1 card). |
| dragon | one card of each rank **3 → A** (12 ranks) + **any** 13th card | Follows Vietnamese Wikipedia's 3→A, not the wiki's 13-rank version. The 13th card may be a 2 or a duplicate rank. |
| four 3's | holds 3♠ 3♣ 3♦ 3♥ | **Only in games whose leader is chosen by lowest card** (I6) |

#### 21.8.1 Final clarifications (all decided)

| # | Point | Decision |
|---|---|---|
| 1 | Does four of a kind count as two pairs for "6 pairs"? | **Yes.** |
| 2 | Dragon definition | **3 → A (12 ranks) plus any 13th card.** |
| 3 | Hand list | **four 2's; 6 pairs (pairs of 2s allowed); dragon 3 → A; four 3's only when the leader is chosen by lowest card. No 4 triples**, deliberately. |

Earlier open points were resolved by the revised I1, I4, I5 and I6.

## 22. Technical debt

* **boardgame.io coupling:** rules depend on `ctx.currentPlayer`, `ctx.events`, and stage names read by the UI. Round logic is spread across `turnOrder` sentinel values (`null`, `"W"`, numbers).
* **Duplicated logic:** `TienLenButton` re-implements `tienLenPlay`'s branch conditions, and `validPlay` duplicates part of it. The client and server can drift apart.
* **Mixed types:** `turnOrder` holds numbers, `null` and `"W"`. `winners` and player keys are strings. `firstPlayer` is a number. There are constant `parseInt` / `toString` conversions.
* **Derived state stored:** `cardsLeft` is kept separately from the card arrays, and `roundType` separately from `center`.
* **Mutating sorts** (`Array.sort` on state arrays). `_.cloneDeep` is used everywhere as defence.
* **Hard to test:** the moves call `ctx.events` directly, and the tests mutate the redux store in place. The tests are stale.
* **Client-side assumptions:** validation, the 3♠ rule and hiding of Pass in Tiến Lên all live in the UI only.
* **Server-side assumptions:** that only the current player calls play moves, and that stages restrict moves (they do not).
* **Race condition:** off-turn `relocateCards` bumps `_stateID` and can silently drop the current player's play.
* **Security:** seed leak, log leak, unauthenticated sync, no server validation, crash on bad input (§17).
* **Scalability / ops:** InMemory storage (a restart loses games), a single process, no reconnect UX, `node-sass` 4 and CRA 4 are obsolete, no `engines` pin in `package.json`.
* **Config:** `APP_PRODUCTION` / `LOBBY` are compile-time constants that must be edited by hand for development.

---

## 23. Proposed Elixir architecture

The following are suggestions, not implementation.

### 23.1 Mapping

| Original | Elixir/Phoenix candidate |
|---|---|
| `constants.js` + `compareCards` | `TienLen.Card` (struct + ordering), `TienLen.Deck` |
| `validCombination` | `TienLen.Combination` (classify → `{:ok, %Combination{type, cards, top_card, length}}` / `:error`) |
| `compareHighest`, `validChop`, `validPlay` | `TienLen.Rules` (pure: `can_beat?/2`, `chop?/2`, `validate_play/…`) |
| `G` + turn logic (`nextTurn`, `turnOrder`, W marker) | `TienLen.Game` pure struct + command functions (`play/3`, `pass/2`) with explicit fields |
| boardgame.io moves | Commands handled by `Game`, always validated **server-side** with the acting player explicit |
| bgio Master / game instance | `TienLen.GameServer` (GenServer per room) |
| bgio InMemory + gameID registry | `Registry` + `DynamicSupervisor` (optionally ETS/DB snapshot for restart) |
| socket.io broadcast + `playerView` | `Phoenix.PubSub` topic per room, each LiveView projects `Game.view_for(game, seat)` |
| bgio Lobby API + cookie credentials | `TienLen.Lobby` context (rooms, seats) + Phoenix session / signed token per seat |
| React board | `GameLive` + function components |
| React lobby | `LobbyLive` |
| rbd drag & drop | LiveView JS hook, or click-to-select. Staging can stay **client/LiveView-local** rather than in the shared game state. |
| bgio `ctx.random` | `:rand` with a server-only seed (never sent to clients) |

### 23.2 Domain model (responsibilities only)

* **Card:** rank and suit atoms or integers. Total order (rank index × 4 + suit index). Parse and format (`"TS"`).
* **Deck:** build 52 cards, shuffle (injectable seed for tests), deal to 2–4 players (count per Q1), find the opening leader.
* **Combination:** classify a set of cards into a type (single, pair, triple, straight(n), three_pair, four_of_a_kind, four_pair) and its top card. No 2s in straights or consecutive pairs (D5). Enforce uniqueness of the cards.
* **Rules:** `beats?(new, current)` implementing the §21.2 matrix (same-type "higher", the D6/D7 cross-type chops, the Q3 "played as chop" condition, no bombs on ordinary cards per Q4), the 3♠ constraint (Q6), and whether a four-pair may be played out of turn (Q8). Keep the open points R2/R3 isolated so they are easy to change.
* **Player:** seat, name, hand, finished position, connection status.
* **Game (one game of a session):** seats (2–4), hands, the current combination and its owner, explicit `passed` set, explicit `phase` (`:lead | :following | :finished`; no Tiến Lên phase per D4), finishers, the current seat, and an event log (redacted per viewer). The table combination carries a `played_as_chop` flag (Q3). The centre is cleared at each new round (#12). After a finisher, the lead goes to the next seat that still holds cards (Q2).
* **Session / Room:** seats, sequence of games, previous game's ranking (for the next leader, D8/Q6/R1), disconnect timers (20 s) and seat tokens (T15), turn timers (20 s, auto-pass / auto-play per T16), host and host transfer (T13), scores if wanted later. No spectators (#17). Timers belong in the GameServer; the pure `Game` only exposes the "timeout action" (pass or lowest play) as a normal command.
* **Lobby:** rooms, seat claiming, tokens, start with 2–4 seated players (D9), spectators.

---

## 24. Conceptual state machine

Updated for decisions D1–D9 (§21). The original Tiến Lên phase is gone (D4).

```text
 create room
     │
     ▼
 WAITING_FOR_PLAYERS ──(host presses Start, 2–4 seated — R6)──► DEALING
                                                 │
        opening leader (R4): previous winner if present → else holder of lowest dealt card
                                                 ▼
          ┌──────────────────────────────────► LEAD  (must play; no pass — D3;
          │                                     │     card-selected leader must include that card — S7; winner leads freely — R1)
          │                                     │ play(any valid combination)
          │                                     ▼
          │                                 FOLLOWING ◄──────────────┐
          │                                     │ play(beats per §21.2) ─┘  (becomes round owner)
          │                                     │ any seat with cards (even passed): out-of-turn four-pair
          │                                     │   on a chop target → passes reset, next seat after chopper (R3, S2)
          │                                     │ 20 s turn timeout → auto-pass / auto-play lowest (S1)
          │                                     │ pass (marked passed for this round)
          │                                     ▼
          │                      all others passed?
          ├── yes, owner still has cards ── owner leads new round (D4), passes + centre cleared
          └── yes, owner has finished  ──── next seat with cards leads (Q2), passes + centre cleared

 any play that empties a hand ──► record finishing position
 only one player still holds cards (Q5) ──► GAME_FINISHED (ranking)
                                                │
                                                ▼
                                   next game in the same session (D8) ──► DEALING
```

---

## 25. Migration plan

| Phase | Implement | Depends on | Tests required | Acceptance criteria |
|---|---|---|---|---|
| 1 Research | This document. All decisions recorded and consolidated (§21.6). | – | – | **Done.** Only the non-blocking interpretations in §21.7 remain. |
| 2 Card/Deck | `Card`, `Deck` (seeded shuffle, deal 13 × N, opening leader per R4) | 1 | Ordering table (all 52), deal has no duplicates, determinism with a seed, 3♠ undealt → lowest-card leader (R4) | Ordering identical to §6 (T4) |
| 3 Combination engine | `Combination.classify/1` | 2 | Port `compareCards.test.js`, plus every §8 **[run]** case with D5 applied (`KKAA22` and `QQKKAA22` now **invalid**) | Matrix §8.1, with D5 applied, reproduced |
| 4 Rules engine | `beats?`, `validate_play` with reasons ("Invalid Combination", …), the opening-play check (T3), chop context incl. persistence (S3), out-of-turn eligibility (R3, S4) | 3 | One test per row of §21.2, including cross-type chops in chop context, the rejected cases (three-pair on pair of 2s; quad or four-pair on a normal three-pair or quad per R2; quad on single A per Q4; five pairs per Q7), and same-rank pairs by suit (#16) | Verdicts match §21.2 exactly. Instant-win detection (T18): one test per hand type plus near-misses (5 pairs + 3 singles, 12-rank run, three 2s). |
| 5 Pure game state | `Game` commands `play/pass/chop_out_of_turn`, rounds (D3, D4), centre clearing (#12), finishing (Q2), ranking for 2–4 players (Q5), undealt cards (Q1) | 4 | Scenario tests: all-pass ends the round and the owner leads (D4); pass rejected on a lead (D3); finisher lead per Q2; 3♠ undealt in a 2- or 3-player game (R4); out-of-turn four-pair by a passed player, with pass reset and play continuing after the chopper (R3, S2); removal of a disconnected player, incl. immediate game end and ranking (R5, S5); card-selected opening card must be included (S7); instant win at deal ends the game, reveals only the winner's hand, ranks per I4, and the next game's leader is chosen by lowest card (T18, I5); property tests (card conservation, exactly one current seat, N − 1 finishers end the game) | Any seat acting out of turn is rejected, except a valid four-pair chop (Q8). No Tiến Lên chaining exists. |
| 6 GameServer | GenServer per room, Registry, DynamicSupervisor, per-seat projection, sequence of games (D8/Q6), disconnect timers (#18) | 5 | Concurrency (serialised commands, simultaneous out-of-turn chops — first valid wins), crash/restart, next-game leader per R1/R4, 20 s disconnect timeout and removal (R5, S5), 20 s turn timeout with auto-pass / auto-play (S1), host transfer (S6) | No full-state leak. Invalid commands return errors and do not crash. |
| 7 Lobby | Rooms, host, seat claim, signed seat tokens, host-only Start with 2–4 players (R6), no spectators (#17), host transfer (S6) | 6 | Join/leave/full-room (max 4), token auth, reconnect with token, join refused mid-game, non-host cannot start | A seat cannot be impersonated (fixes Leak 3). A fifth player cannot join. Spectating is rejected. |
| 8 LiveView | Lobby, table, hand/staging UI, button labels from server validation | 7 | LiveView tests per component and interaction | Parity with §18 UI, no client-side rule logic |
| 9 Realtime | PubSub broadcast, per-viewer projection, presence (for disconnect detection) | 8 | Multi-session tests, public card counts (#15), out-of-turn chop broadcast | Other players' hands, the seed and other players' staging never reach a socket |
| 10 Tests/security/reconnect | Reconnect by token, disconnect handling, fuzzing, redacted event log | 9 | Fuzz random commands, reconnection, stale-command handling | All §17 leaks closed. §19.3 bugs do not occur in the port. |

---

## Appendix A: Probe results (scratch copy, `boardgame.io@0.39.16`, Node 22)

```text
validCombination KS AS 2S => undefined          validCombination KS KC AS AC 2S 2C => three-pair
validCombination 3..A (12 cards) => straight    validCombination QS QC KS KC AS AC 2S 2C => four-pair
validCombination 3S 3S => pair                  validCombination 10 cards (5 pairs) => undefined
validPlay pair 2 <- quad => Does Not Match Center
validPlay pair 2 <- 3pair => Does Not Match Center
validPlay pair 2 <- 4pair => true
validPlay 3pair <- 4pair => Does Not Match Center
validPlay single 2 <- KKAA22 => true
P1 sees players keys: ["1"]
P1 sees plugins.random.data: {"seed":"…","prngstate":{…}}
seed replay: replayed P0 hand equals real P0 hand: true
current was 2; player 3 called passTurn -> currentPlayer now 3, turnOrder [0,1,null,3]
invalid 2-card play accepted -> roundType undefined
empty cardsToCenter -> roundType undefined, center [], turn advanced, not marked passed
opponent log contains relocateCards args incl. draggableId
relocateCards bad index -> stagingArea [null, …]
passTurn while in tienLen -> TypeError (reading 'toString')
spectator players: {}
```
