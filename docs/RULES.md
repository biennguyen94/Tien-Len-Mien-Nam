# Rules — Tiến Lên Miền Nam (target ruleset)

Last updated: 2026-09-28

This is the **source of truth** for the game rules of this project. It consolidates every decision in `PORTING_STATUS.md` → Decisions (D1–D9, Q1–Q8, #12–#18, R1–R7, S1–S7, I1–I8).
Rule IDs **T1–T25** are stable (T19–T25: coins, §17); code, tests and docs should cite them.

It deliberately differs from the original implementation and from the original wiki. See `RESEARCH.md` §20 for the comparison and `PORTING_STATUS.md` for why each point differs.

---

## 1. Terms

| Vietnamese | English (used in code/docs) | Meaning |
|---|---|---|
| rác / cóc | single | one card |
| đôi | pair | two cards of the same rank |
| sám (cô) | triple | three cards of the same rank |
| sảnh | straight | 3+ cards of consecutive rank |
| ba đôi thông | three-pair | three pairs of consecutive rank |
| bốn đôi thông | four-pair | four pairs of consecutive rank |
| tứ quý | four-of-a-kind | four cards of the same rank |
| heo | 2 | a card of rank 2 |
| chặt | chop | beating a 2, or a chop, with a special combination |
| hàng | bomb / chop combination | three-pair, four-of-a-kind or four-pair |
| tới trắng | instant win | a dealt hand that wins at once |
| sảnh rồng | dragon | 3 → A plus any card (instant win) |
| ván | game | from deal to ranking |
| vòng | round | from a lead until everyone else passes |
| bỏ lượt | pass | – |
| chủ phòng | host | the player allowed to start games |

"Centre" means the combination currently on the table. The "round owner" is the last player who played to the centre.

---

## 2. Players, deck and deal — T1

- **2, 3 or 4 players.** Never more than 4 (D9).
- **Deck:** standard 52 cards. Each player is dealt **13 cards**. The undealt cards (26 with 2 players, 13 with 3) are out of the game, and nobody sees them (Q1).
- The shuffle uses a server-side seed that is **never sent to clients**. Tests inject a seed so deals are deterministic.

## 3. Card order — T4

- **Ranks**, low → high: `3 4 5 6 7 8 9 10 J Q K A 2`
- **Suits**, low → high: `♠ < ♣ < ♦ < ♥`
- Rank decides first; suit breaks ties. The lowest card is **3♠** and the highest is **2♥**.

## 4. Combinations — T5

| Type | Cards | Constraint |
|---|---|---|
| single | 1 | any card |
| pair | 2 | same rank (2s allowed) |
| triple | 3 | same rank (2s allowed) |
| straight | 3–12 | consecutive ranks, any suits, **no 2**, no wrap-around (A-2-3 and K-A-2 are invalid). Longest: 3 → A. |
| four-of-a-kind | 4 | same rank (four 2s allowed) |
| three-pair | 6 | three pairs of consecutive rank, **no 2s** (D5). Highest: QQ-KK-AA. |
| four-pair | 8 | four pairs of consecutive rank, **no 2s** (D5). Highest: JJ-QQ-KK-AA. |

Anything else is invalid, including **5 or more consecutive pairs** (Q7), two triples, and a straight with a duplicated rank.
The **top card** of a combination is its highest card by T4.

## 5. Beating a combination — T6

### 5.1 Same type

A combination beats the centre if it is **the same type, the same number of cards, and has a higher top card** (T4, suit included).
- Example: pair 7♠7♥ beats pair 7♣7♦, because 7♥ > 7♦ (#16).
- A 5-card straight can only be beaten by a 5-card straight.

### 5.2 Chop context and cross-type chops (D6, D7, Q3, Q4, R2, S3)

The centre is either **normal** or **in chop context**.
- **Chop context starts** when a single 2 or a pair of 2s is chopped.
- **It persists** through every following beat in the same round, same-type or cross-type (S3).
- **It ends** with the round.

A **cross-type** chop never compares ranks: any combination of the stronger type wins. Chop combinations **cannot** be played on ordinary cards (Q4). For example, four 5s may not be played on A♥.

| Centre | Allowed on your turn | Allowed out of turn (four-pair only, §8) |
|---|---|---|
| single 2 | higher single 2; **any** three-pair / four-of-a-kind / four-pair → chop context | any four-pair |
| pair of 2s | higher pair of 2s; **any** four-of-a-kind / four-pair → chop context | any four-pair |
| three-pair, chop context | higher three-pair; **any** four-of-a-kind; **any** four-pair | any four-pair |
| three-pair, normal | higher three-pair only | – |
| four-of-a-kind, chop context | higher four-of-a-kind; **any** four-pair | any four-pair |
| four-of-a-kind, normal | higher four-of-a-kind only | – |
| four-pair, chop context | higher four-pair | higher four-pair (S4) |
| four-pair, normal | higher four-pair only | – |
| anything else (single, pair, triple, straight; incl. a triple of 2s) | same type, same length, higher top card | – |

Things that follow from the table:
- A **triple of 2s** cannot be chopped.
- **Four 2s** is a four-of-a-kind: only a four-pair beats it, and only in chop context.
- A three-pair **cannot** chop a pair of 2s.

---

## 6. Starting a game — T2, T3

### 6.1 Opening leader (R1, R4, I5)

1. The **winner (1st place) of the previous game**, if they are still in the room **and** the previous game did **not** end by instant win.
2. Otherwise the player holding the **lowest dealt card** among the players taking part, searched in order `3♠ → 3♣ → 3♦ → 3♥ → 4♠ → 4♣ → …`.

The mode is known **before** the deal: either *winner-led* or *card-led*. Instant-win detection needs it (§10).

### 6.2 Opening play (R7, S7, D3)

- **Card-led:** the leader may not pass. The first play must **contain the card that selected the leader** (3♠, or 3♣, 3♦, … when lower cards are undealt).
- **Winner-led:** the winner leads with any valid combination and may not pass. The card rule does not apply (R1).

## 7. Turns, leading, passing, rounds — T7, T8, T9, T12

- **Turn order:** seats counter-clockwise, skipping players who have passed this round, finished, or been removed (T12).
- **Leading** (the start of a round, including the opening): the leader **must** play a valid combination and may **not** pass (D3, T7). The centre is empty.
- **Responding:** the current player either plays a combination that beats the centre (§5), or **passes** (T8).
- **A passed player** is skipped until the round ends. They may still make an out-of-turn four-pair chop (§8).
- **Round end** (T9): when every other player who still holds cards has passed since the round owner's last play:
  - the round ends, the **centre is cleared**, and pass marks and chop context are reset (#12, D4);
  - the **round owner leads** the next round;
  - if the owner has finished or been removed, the **next seat that still holds cards** leads (Q2, S5).
- There is **no "Tiến Lên" chaining**: the round owner does not get exclusive extra plays on top of their own combination (D4). The original game had this mechanic; this port removes it.

## 8. Out-of-turn four-pair — T10 (Q8, R3, S2, S4)

- **Who:** any player who still holds cards, **including one who already passed** this round. It need not be their turn.
- **When:** at any moment while the centre is a valid target: a single 2, a pair of 2s, a chop-context three-pair, a chop-context four-of-a-kind, or a lower chop-context four-pair.
- **Effect:** the four-pair becomes the centre (chop context), **all pass marks are reset**, and play **continues from the seat after the chopper** (S2).
- **Concurrency:** commands are processed in arrival order. The first valid one wins, and later ones are re-validated against the new centre.
- No other combination can be played out of turn.
- There is no separate chop timer; the normal turn timer keeps running for the current player (T16).

## 9. Finishing, ranking, game end — T11

- A player who plays their last card takes the **next finishing position** and never plays again in this game. The round continues without them (§7 for the next lead).
- **The game ends when only one player still holds cards** (Q5), including when disconnect removals cause it (S5).
- **Ranking:**
  1. normal finishers, in finishing order;
  2. then the last player holding cards;
  3. then removed players, in order of removal (S5; the position of the last player versus removed players is interpretation §15.2).
- The **winner** is 1st place. They lead the next game unless the game ended by instant win (§6.1).

## 10. Instant win (tới trắng) — T18 (I1–I8)

Checked by the server **automatically, right after the deal**, on each player's 13 dealt cards. Nobody declares it and there is no time window. Undealt cards play no part.

| Hand | Condition | Applies |
|---|---|---|
| **four 2's** | holds 2♠ 2♣ 2♦ 2♥ | always |
| **6 pairs** | the 13 cards split into 6 disjoint pairs + 1 card. Pairs need not be consecutive; pairs of 2s count; **four of a kind counts as two pairs** | always |
| **dragon** (sảnh rồng) | one card of every rank **3 → A** (12 ranks) + any 13th card | always |
| **four 3's** | holds 3♠ 3♣ 3♦ 3♥ | **only in a card-led game** (§6.1): first game of a session, after the previous winner left, or after an instant-win game |
| ~~four triples~~ | – | **not** an instant win, deliberately |

When at least one player qualifies:
- The game **ends immediately**. Nobody plays (I2).
- Every qualifying player's **whole hand is revealed to all players** (I8). All other hands stay hidden.
- **Ranking:** every instant winner is **1st**, with seat order breaking ties where an order is needed. **All other players are tied** after them (I4).
- The **next game is card-led** (§6.1). The instant winner does not lead it (I5).

## 11. Room and sessions — T13

- A room plays **several games in a row** (D8).
- **Only the host can start a game**, and only with **at least 2 players** (host included) (R6).
- **Nobody joins during a game.** Players seated between games take part in the next one.
- **Host leaves or disconnects:** host rights pass to the next remaining player in seat order (S6), after the disconnect timeout (§15.3). The room stays open while at least one player remains.
- **Spectators** may watch without a seat (V1, supersedes #17); they receive only public information (§13).

## 12. Timeouts and disconnects — T15, T16

**Turn timeout** (S1): **20 s** per turn. On expiry the server acts for the player:
- **responding** → pass;
- **leading** (passing forbidden) → play the lowest valid combination (§15.1);
- **card-led opening** → play the lowest combination containing the mandatory card (§15.1).

**Disconnect** (#18, R5, S5):
- The seat is held for **20 s**, and the player can reconnect with their **seat token**.
- If it becomes their turn meanwhile, the turn timer applies as usual.
- After 20 s the player is **removed from the current game**:
  - their cards are discarded;
  - they rank after all normal finishers (§9) and are never treated as a winner;
  - if they were due to lead, the next remaining player leads;
  - if only one player then holds cards, the game ends.
- A removed player plays normally in the **next** game if still in the room.
- To continue on another device, the player logs in there with their account; the same account uses the same seat (Y4).

## 13. Visibility — T14

- Each player sees **only their own hand** and their own card selection.
- **Everyone sees:**
  - the centre and its type/context;
  - whose turn it is and the turn timer;
  - pass marks;
  - finishing order and ranking;
  - **every player's card count** (#15);
  - who is host;
  - connection status.
- **Never sent to any client:** other hands, undealt cards, the seed or PRNG state, other players' selections, and unredacted logs.
- **Exception:** an instant winner's hand is revealed (§10).
- **Spectators** (V1, supersedes #17) receive only what "everyone sees" above; no hand, no room chat.
- **Replays** (V2) show every dealt hand and every play, but only after the game is over and recorded, to its players and admins (V5, V6).

## 14. Authority — T17

- The server validates every command (D1): the seat, the turn (or the out-of-turn four-pair eligibility), card ownership, the combination and the beat rule.
- Invalid commands are rejected with a reason and change nothing.
- Commands for a room are **serialised**.

---

## 15. Interpretations fixed in this spec (confirm or override in PORTING_STATUS)

1. **"Lowest valid combination"** (S1). Any single is a valid lead, so the auto-play is **the single lowest card** in the hand. With a mandatory opening card, it is **that card as a single**.
2. **Last player vs removed players** (S5). The last player still holding cards ranks **above** removed players.
3. **Host transfer on disconnect** (S6). Host rights move **after the 20 s disconnect timeout**, not on the first disconnect. A host who reconnects in time keeps host rights.
4. **Opening leader removed** (S5, T3). If the card-led opening leader is removed before the first play, the next active seat leads **without** a mandatory card: that card was discarded with the hand.
5. **Chopping your own combination** (T10). An out-of-turn four-pair may target any chop target, including the chopper's own combination.

---

## 16. Worked examples (use as test scenarios)

1. **Normal round.** A leads pair 6s. B plays pair 9s. C passes. D passes. A passes. The round ends: the centre is cleared and **B leads**.
2. **No pass on a lead.** B must lead something. "Pass" is rejected, and after 20 s the server plays B's lowest single.
3. **Chop chain.** A plays 2♠. B chops with three-pair 4-5-6 (chop context). C plays three-pair 7-8-9 (same type, higher). D plays four 5s (allowed: chop context persists, S3). A plays a four-pair on their turn, or any player plays it out of turn.
4. **No bombs on ordinary cards.** The centre is A♥. Four 5s is rejected (Q4).
5. **Normal three-pair.** A leads three-pair 3-4-5 (normal). B's four 9s is rejected, and so is C's four-pair (R2). Only a higher three-pair beats it.
6. **Out-of-turn four-pair by a passed player.** The centre is B's single 2. C passes. D (holding a four-pair) chops out of turn: all pass marks are reset, and **A** (the seat after D) is next.
7. **Pair of 2s.** A plays 2♠2♥. B's three-pair is rejected; B's four 7s is accepted.
8. **Finisher.** A plays their last cards (A finishes, 1st). B, C and D all pass. The round ends and **B** (the next seat with cards after A) leads.
9. **Card-led opening, 3♠ undealt** (3 players). The lowest dealt card is 3♦. Its holder leads, may not pass, and the first play must contain 3♦. Four 3's cannot occur, because 3♠ is undealt.
10. **Instant win.** In game 2 (winner-led), C holds four 3's: not an instant win. D holds six pairs including 2♠2♥: instant win. D ranks 1st, the others tie, D's hand is revealed, and game 3 is card-led.

---

## 17. Coins (C1–C10, E1–E9)

Coins are virtual and only exist inside the game (C1). **All amounts are computed and applied by the server** (C10). Stake **S** belongs to the room (C3); with **S = 0** nothing below moves any coin.

| # | Rule |
|---|---|
| T19 | **Balances:** 1,000 on registration; daily bonus 100 (once per Vietnam day); relief 500 when the balance is below 100 (once per Vietnam day). No transfers, deposits or withdrawals (spending: T26). A balance is never negative. |
| T20 | **Eligibility:** only connected players with at least **10×S** are dealt in (C9, E7). |
| T21 | **Place payments** at game over (C4, E1): 4 players: Bét → Nhất S, Ba → Nhì ⌊S/2⌋. 3 players: Bét → Nhất S. 2 players: Bét → Nhất S. |
| T22 | **Instant win** (C5, E2): every non-winner pays 2×S to every instant winner. Nothing else is paid in that game. |
| T23 | **Chặt heo / chặt chồng** (C6, C7, E3): 2♠/2♣ = 1×S, 2♦/2♥ = 2×S, a pair = the sum (V). When the round's chop chain ends, the owner of the last chopped combination pays V × (number of chops in the chain) to the last chopper. |
| T24 | **Thối heo** (C8, E4): at game over, the last player still holding cards pays 1×S per black 2 and 2×S per red 2 in their hand to the player ranked just above them. |
| T25 | **Not enough coins** (C9, E5): a debtor pays at most their balance; several creditors share proportionally; the total is always 0. |

## 17a. Bots (B1–B6)

- Only the host adds or removes bots, while waiting, and **only in rooms with stake 0**. A stake cannot be set while a bot sits.
- Bots play by these rules like any player (same validation, same turn timer as a fallback), see only their own hand, never become host, and do not keep a room open without humans.
- Games with a bot move no coins (stake 0) and are **not recorded** in the leaderboard or history.

## 17b. Missions and seasons (M1–M4, S1–S4)

- **Daily missions** (Vietnam day):
  - play 5 recorded games: +100;
  - finish 1st in 2: +150;
  - chặt heo once: +200.

  Each mission is claimed once per day. A chop is an out-of-turn four-pair, or a bomb played on a 2 or in chop context.
- **Weekly season**: Monday 00:00 to Sunday 24:00 Vietnam time, ranked by 1st places in that week's recorded games (ties as in the leaderboard). The top 3 with at least one win get 1,000 / 500 / 300 coins after the week ends.
- Games with bots are not recorded, so they count for neither. All amounts are admin settings.

## 17c. Spending coins and fun extras (TH1–TH4, BL1–BL3, RC1, SH1–SH3)

| # | Rule |
|---|---|
| T26 | **Spending** (the only way coins leave the game): throwing an item at another seat (🍅 1, 🥚 2, 🩴 3, 🌹 5 coins, 3 s cooldown) and buying a card back or table theme in the shop (once per item, kept forever). The server checks the balance and spends in one transaction; a balance never goes negative. Nothing bought or thrown changes a game. |

- The **commentator** posts lines in the room chat from public events; at game over it may tell how many 2s the thối heo loser held (BL2).
- Leaving during a game still removes the player from it (§12); nobody plays in their place (RC1).

## 18. Rule ↔ decision map

| Rule | Decisions |
|---|---|
| T1 | D9, Q1 |
| T2 | D8, Q6, R1, R4, I5 |
| T3 | D2, Q6, R1, R7, S7 |
| T4 | original, #16 |
| T5 | D5, Q7 |
| T6 | D6, D7, Q3, Q4, R2, S3, #16 |
| T7 | D3 |
| T8 | D3, R3 |
| T9 | D4, #12, Q2, S5 |
| T10 | Q8, R3, S2, S4 |
| T11 | Q5, S5 |
| T12 | original (seat order) |
| T13 | D8, R6, S6, #17, V1 |
| T14 | #15, #17, I8, V1, V2 |
| T15 | #18, R5, S5 |
| T16 | S1 |
| T17 | D1, R3 |
| T18 | I1–I8 |
| T19–T25 | C1–C10, E1–E9 |
| T26 | TH1–TH4, SH1–SH3 |
