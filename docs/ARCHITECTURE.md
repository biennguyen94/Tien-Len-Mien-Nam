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

## Part 2 — Target (proposal)

### 2.1 Layers

```text
┌──────────────── TienLenWeb (Phoenix) ────────────────┐
│ LobbyLive   TableLive   components   JS hook (card order only) │
└───────────────▲──────────────────────────┬───────────┘
                │ view(seat) via PubSub     │ commands {room, seat_token, cmd}
┌───────────────┴──────── TienLen.RoomServer (GenServer per room) ────────┐
│ serialises commands · turn timer 20 s · disconnect timer 20 s · host transfer │
│ holds %Room{} (+ current %Game{}) · broadcasts events, never state           │
└───────────────▲─────────────────────────────────────────────────────────┘
                │ pure function calls
┌───────────────┴──────── Pure domain (no processes) ─────────────────────┐
│ Card · Deck · Combination · Rules · InstantWin · Game · Room             │
└──────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Supervision (proposal)

```text
TienLen.Application
├── Phoenix.PubSub (TienLen.PubSub)
├── Registry (TienLen.RoomRegistry, unique: room_id → pid)
├── DynamicSupervisor (TienLen.RoomSupervisor) ── RoomServer per room (restart: :temporary)
├── TienLenWeb.Presence
└── TienLenWeb.Endpoint
```

With no database (O2), a crashed room process is not restarted with stale state: the room is closed and players return to the lobby.

### 2.3 Domain modules and responsibilities

| Module | Responsibility | Rules |
|---|---|---|
| `TienLen.Card` | Rank/suit, total order, integer key, parse/format | T4 |
| `TienLen.Deck` | Build, seeded shuffle, deal 13 × N, lowest dealt card holder | T1, T2 |
| `TienLen.Combination` | Classify cards → type, top card, length | T5 |
| `TienLen.Rules` | `beats?` + chop context, out-of-turn eligibility, opening-card check, error reasons | T3, T6, T10 |
| `TienLen.InstantWin` | Detect four 2's / 6 pairs / dragon / four 3's (card-led only) | T18 |
| `TienLen.Game` | One game: turns, rounds, passes, finishing, ranking, removals, timeout actions, per-seat view | T7–T12, T14–T16 |
| `TienLen.Room` | Seats, names, host, connection flags, sequence of games, next leader mode | T2, T13, T15 |
| `TienLen.RoomServer` | Process wrapper: serialisation, timers, PubSub, Presence reactions | T15–T17 |

### 2.4 Game state (proposal)

```text
%Game{
  seats:          [seat_id]           # seat order = turn order (counter-clockwise)
  hands:          %{seat => [Card]}   # private
  undealt:        [Card]              # private, never projected
  mode:           :card_led | :winner_led
  opening_card:   Card | nil          # mandatory card for the first play (T3)
  phase:          :lead | :respond | :finished
  current:        seat
  centre:         nil | %{combo: Combination, owner: seat, chop_context?: boolean}
  passed:         MapSet(seat)        # this round
  finished:       [seat]              # finishing order
  removed:        [seat]              # removal order (disconnect)
  instant_winners:[{seat, hand_type}] # non-empty ⇒ game ended at deal
  ranking:        nil | [[seat]]      # groups allow ties (instant win)
}
```

Derived, not stored: card counts (`length(hand)`), the round owner (`centre.owner`), and whether a player is active (has cards, not removed).

### 2.5 Game state machine

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
        clear centre, reset passes + chop context
        leader = owner if active, else next active seat ──► LEAD

 any play that empties a hand → append to finished
 remove(seat) (disconnect)   → discard hand, append to removed, fix current/leader
 active players ≤ 1          → FINISHED (ranking = finished ++ [last] ++ removed)
 timeout(current)            → RESPOND: pass · LEAD: lowest single (or opening card single)
```

### 2.6 Command flow

```text
TableLive (seat verified from token on mount)
  └─ RoomServer.command(room, seat, {:play, cards})         # GenServer.call
        └─ Game.play(game, seat, cards)  → {:ok, game', events} | {:error, reason}
              ├─ error → reply {:error, reason} to the caller only (shown as flash/label)
              └─ ok    → restart turn timer; PubSub.broadcast(room_topic, {:game_event, events})
                         every TableLive: RoomServer.view(room, own_seat) → re-render
```

The alternative is to broadcast nothing but a version number and let each LiveView fetch its own projection. Either way, **no broadcast carries a hand**.

### 2.7 Visibility (T14)

`Game.view(game, seat)` returns:
- the viewer's own hand;
- everyone's card counts;
- the centre (combo, owner, chop context), current seat, deadline, passes, finished/removed/ranking;
- instant-win reveals (the winner's hand only).

It never contains other hands, undealt cards or the seed. Card selection (the original's "staging area") is **LiveView-local state** of the owning player and is not part of `Game`.

### 2.8 Mapping from the original

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
