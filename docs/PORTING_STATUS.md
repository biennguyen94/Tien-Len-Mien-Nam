# Porting status

Last updated: 2026-09-28

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
| 11 | Database foundation (Ecto + PostgreSQL) | **DONE** (2026-09-27) |
| 12 | Accounts: register / login / logout | **DONE** (2026-09-28) |
| 13 | Game results, leaderboard, history | **DONE** (2026-09-28) |
| 14 | Deploy with database | **DONE** (2026-09-28): `tien-len` + `tien-len-db` on port 4020 |
| 15 | Coins: ledger and balances | **DONE** (2026-09-28) |
| 16 | Coins: settlement of games (places, instant win, chặt heo, thối heo) | **DONE** (2026-09-28) |
| 17 | Coins: UI | **DONE** (2026-09-28) |
| 18 | Coins: deploy | **DONE** (2026-09-28) |
| 19 | Admin: roles, guard, audit log, set admin | **DONE** (2026-09-28) |
| 20 | Admin: users (search, lock, rename, password, coins) | **DONE** (2026-09-28) |
| 21 | Admin: dashboard, rooms (watch, close, kick), game history | **DONE** (2026-09-28) |
| 22 | Admin: announcements, economy settings, login rate limit | **DONE** (2026-09-28) |
| 23 | Admin: deploy | **DONE** (2026-09-28): first admin `bien` promoted by the server command |
| 24 | Chat: presence, limiter, room chat, quick phrases | **DONE** (2026-09-28) |
| 25 | Chat: lobby chat, private chat | **DONE** (2026-09-28) |
| 26 | Invites: popup, "Chép link", "Không nhận lời mời" | **DONE** (2026-09-28) |
| 27 | Private rooms, admin chat moderation | **DONE** (2026-09-28) |
| 28 | Chat and invites: deploy | **DONE** (2026-09-28) |
| 29 | Hints (Gợi ý) | **DONE** (2026-09-28) |
| 30 | Bots | **DONE** (2026-09-28) |
| 31 | Phone layout, hand order; deploy | **DONE** (2026-09-28) |
| 32 | Profile, avatars, per-player game facts | **DONE** (2026-09-28) |
| 33 | Friends | **DONE** (2026-09-28) |
| 34 | Daily missions | **DONE** (2026-09-28) |
| 35 | Weekly seasons | **DONE** (2026-09-28) |
| 36 | Emoji reactions; deploy | **DONE** (2026-09-28) |
| 37 | Spectators | **DONE** (2026-09-28) |
| 38 | Replays; deploy | **DONE** (2026-09-28) |

Current architecture (modules, processes, database, routes, visibility): `ARCHITECTURE.md` Part 2. What was delivered and verified in each phase: the results sections below.

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
| #17 | No spectators in the first release. **Superseded by V1 (2026-09-28).** | T13, T14 |
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

### Batch 6 — accounts and leaderboard (owner, 2026-09-27)

| # | Decision | Supersedes |
|---|---|---|
| A1 | **Leaderboard = number of 1st places ("về nhất").** Also shown: games played and win rate. | – |
| A2 | **Separate "Đăng ký" and "Đăng nhập".** Register form: "Chào bạn! Bạn tên gì?" (display name), "Tài khoản" (username), "Mật khẩu" (password). Login form: username + password. Logout supported. | – |
| A3 | **Login is required** to use the lobby and rooms; anonymous play is removed. | O3 (anonymous identity) |
| A4 | **PostgreSQL in its own container** (never the OpenMU database). | O2 (no database) |

Interpretations taken to implement A1–A4 (confirm or override):

| # | Interpretation |
|---|---|
| Y1 | Username: 3–20 characters, `a–z 0–9 _ .`, case-insensitive and unique (stored lowercase). Password: 8–72 characters (the bcrypt limit), hashed with bcrypt. The display name follows the existing name rules (1–20 characters). |
| Y2 | **Resume links are removed**: with accounts, continuing on another device means logging in there. A resume link would be a password-less login token. |
| Y3 | Logout ends the session and disconnects the user's open LiveViews. In a room this counts as a disconnect (20 s, then removal, T15). |
| Y4 | The same account on two devices or tabs uses the same seat (like two tabs today). The room player id is the user id. |
| Y5 | Leaderboard details: every finished game is recorded for all its players, including instant-win games (each instant winner gets a win) and removed players (the game counts as played). Order: wins desc, win rate desc, games played asc, username. |
| Y6 | The room process records results at game over. A database failure is logged and never interrupts play. |
| Y7 | No login rate limiting in the first version (residual risk: password guessing; see RISKS). |
| Y8 | The leaderboard and history pages also require login (consistent with A3). (Phase 13) |
| Z1 | The deployed app runs its migrations at **every start** (`bin/migrate && bin/server`). Safe because the database belongs to Tiến Lên alone; open-mu-web does not do this because its database is OpenMU's. PostgreSQL is pinned to major version 18 (`postgres:18`), because a major upgrade needs a data migration. (Phase 14) |

### Batch 7 — coins (owner, 2026-09-28)

| # | Decision |
|---|---|
| C1 | **Virtual coins only.** No real-money deposit or withdrawal, **no transfers between players**. |
| C2 | New account: **1,000** coins. Daily bonus: **100**. Relief ("cứu trợ"): **500**. |
| C3 | Each room has a **stake S**: `0` (for fun, no coins move at all) or any integer **≥ 10**, with no fixed maximum. |
| C4 | **Place payments** (pairs of places): 4 players: Nhất +S from Bét, Nhì +S/2 from Ba. 3 players: Nhất +S from Bét, Nhì 0. 2 players: Nhất +S from Bét. The total is always 0. |
| C5 | **Instant win (tới trắng):** each instant winner receives **2×S from every other player**. |
| C6 | **Chặt heo:** a black 2 (♠ ♣) is worth **1×S**, a red 2 (♦ ♥) **2×S**; a pair of 2s is the sum. The owner of the chopped 2s pays the chopper. |
| C7 | **Chặt chồng:** the **last chopped player pays the whole chain** to the last chopper. |
| C8 | **Thối heo:** at the end of a game, the **Bét** player pays for each 2 still in hand (black 1×S, red 2×S) to the **player ranked just above** them. |
| C9 | **Not enough coins:** a player is dealt in only with a balance of **at least 10×S**. If a debt is still larger than the balance, they pay **all they have** (never negative); several creditors share it proportionally. The total stays 0. |
| C10 | **Server-side and transaction-safe.** The game/room decides the results; an economy layer applies them. The client never sends amounts. |

Interpretations taken to implement C1–C10 — **approved by the owner (2026-09-28)**:

| # | Interpretation |
|---|---|
| E1 | Nhì's amount in a 4-player game is **⌊S/2⌋** (S = 15 → 7). |
| E2 | Several instant winners: **each** receives 2×S from **each** non-winner. An instant-win game has no place payments, no chops and no thối. |
| E3 | **Chop chain** of a round: it starts when a single 2 or a pair of 2s is chopped. Its value **V** = the 2s' value (C6). Every later play on the chop-context centre (a higher same-type chop, a cross-type chop, or an out-of-turn four-pair) is another chop in the chain. When the chain ends (the round ends, or the game ends), **the owner of the last chopped combination pays V × (number of chops) to the last chopper**; nobody else in the chain pays. Example with S = 100, 2♥ (V = 200): B chops A's 2♥ → A would pay 200; C then chops B's three-pair → B pays C 400, and A pays nothing. A 2 beaten by a higher 2 is not a chop. |
| E4 | **Thối heo** is paid by the last player still **holding cards** at the end, to the player ranked just above. Removed players never pay thối (their cards were discarded). No thối in instant-win games. |
| E5 | **Proportional sharing** when a debtor cannot pay everything (C9): each creditor gets ⌊owed × paid / total owed⌋; the few coins left over by rounding go to the creditors in ranking order. |
| E6 | **Settlement timing:** a chop chain is settled when its round ends; place payments, thối and instant-win payments at game over. All are in one database transaction each, recorded once per game (idempotent). |
| E7 | **Eligibility:** a new game is dealt to the connected seated players with a balance ≥ 10×S (C9, together with X6). If fewer than 2 are eligible, the start is refused. The host sets S when opening the room and may change it **between games only**. |
| E8 | **Daily bonus** is claimed with a button, once per Vietnam calendar day (UTC+7). **Relief** is claimed with a button when the balance is **below 100**, at most once per Vietnam day. |
| E9 | Existing accounts receive the 1,000 starting coins when the coin feature is deployed. |

### Batch 8 — admin (owner, 2026-09-28)

| # | Decision | Changes |
|---|---|---|
| AD1 | **Roles** `player` / `admin`. The first admin is created **only by a command on the server**. On the web, an admin can **"set admin"** for another user; nobody else can. | – |
| AD2 | **Audit log** of every admin action (who, what, on whom, when, reason); append-only. | – |
| AD3 | **Dashboard**: accounts, registrations today, open rooms, players online, games today / 7 days, coins in circulation. | – |
| AD4 | **Users**: search; details (coins, games, wins, history, ledger); lock / unlock; rename display name; reset password. | – |
| AD5 | **Admins may add or remove coins** for a user, with a mandatory reason, through the ledger (`admin_adjust`). | Exception to C1 |
| AD6 | **Rooms**: list; close a room; remove a player from a room. **Closing during a game cancels the game and settles no coins.** | – |
| AD7 | **Admins may see players' hands** in running games (admin watch view). | Exception to #17 / T14, for admins only |
| AD8 | **Game history** with each game's coin settlements. | – |
| AD9 | Also now: **lobby announcements**, **economy settings editable on the web** (starting coins, daily bonus, relief, relief threshold, max rooms), **login rate limiting**. | C2 values become defaults, editable by admins (P10 addressed) |

Interpretations taken to implement AD1–AD9 (confirm or override):

| # | Interpretation |
|---|---|
| F1 | An admin can also **remove** admin from another admin, but **never from themselves**, and the **last admin** cannot be removed (no lock-out). Both directions are audited. |
| F2 | **Locking** a user: login is refused ("Tài khoản đã bị khóa"), every open page of that user is sent back to the logged-out lobby at once, and they leave every room they sit in (inside a game: removed, as after a disconnect timeout). Admins cannot lock themselves or another admin. |
| F3 | **Reset password**: the server generates a random temporary password, shown **once** to the admin. So that players can replace it, players get a **"đổi mật khẩu"** form (current + new password). |
| F4 | **Coin adjustments**: +/− any amount with a reason (required, 3–200 characters). A removal larger than the balance is refused (balances stay ≥ 0). Admins may adjust their own balance too; it is audited like any other adjustment. |
| F5 | **Closing a room during a game**: chop chains **already settled** in finished rounds of that game stay (the ledger is append-only). The open chain and all game-over payments are not settled, and the game is not recorded in the leaderboard or history. Players are sent to the lobby with a message. |
| F6 | **Admin watch view** `/quan-tri/phong/:id`: read-only, all hands visible, no seat taken. An admin who is also seated sees the normal table on `/phong/:id`. |
| F7 | **Economy settings** are stored in the database and apply to new actions from the moment they are saved (a registration after the change gets the new starting amount, etc.). Past ledger lines never change. |
| F8 | **Login rate limit**: after **5 failed logins** for the same username or the same IP within 15 minutes, logins from them are refused for 15 minutes ("Thử lại sau"). Counters live in memory (they reset on restart). |

### Batch 9 — chat and invites (owner, 2026-09-28)

| # | Decision | Changes |
|---|---|---|
| CH1 | **Three chats**: room chat, lobby chat, and a **short version of private chat** (only to players online now, no inbox). | – |
| CH2 | **Messages are kept in memory only**, never in the database. | – |
| CH3 | **Quick phrases** (one click), **no profanity filter**. | – |
| CH4 | **Chat is allowed during a game.** The risk of players telling each other their cards is accepted. | Risk accepted (RISKS) |
| IV1 | **Invites** both ways: an **in-app popup** to an online player, and a **"Chép link"** button for the room link. | – |
| IV2 | **Private rooms**: not listed in the lobby, joined only by invite or link. | – |
| IV3 | A player setting **"Không nhận lời mời"**. **No "block this player"** button. | – |

Interpretations taken to implement CH1–IV3 (confirm or override):

| # | Interpretation |
|---|---|
| G1 | **Where messages live**: room chat, the last 50 in the room process (lost when the room closes); lobby chat, the last 100 in one process (lost on restart); private chat, the last 20 lines per pair of players, dropped after 1 hour without messages or on restart (so they survive moving between the lobby and a table). |
| G2 | **Limits for every chat**: 1–200 characters after trimming; **5 messages per 10 s per player** across all chats (server-side); names come from the account; links shown as plain text; HTML escaped. |
| G3 | **Quick phrases**, fixed list: "Nhanh lên!", "Hay quá!", "Chúc may mắn!", "Cảm ơn!", "Xin lỗi, mạng lag", "Ván này căng!", "Chơi lại không?", "Hẹn gặp lại!". Available in room chat and lobby chat. They count towards the rate limit. |
| G4 | **Room chat**: only players seated in the room read and write it; a newcomer sees the last 50 messages; system lines are not mixed in. |
| G5 | **Lobby chat**: every logged-in player on the lobby page; the last 100 shown on open. |
| G6 | **Online list** in the lobby: players with at least one open page, with where they are ("Ở sảnh", "Trong phòng", "Đang chơi"). Uses in-memory presence. The admin dashboard's "online" number uses it too. |
| G7 | **Private chat**: opened by clicking a name in the online list (or on a table); a small panel that follows the player on the lobby and table pages, with an unread badge. Sending to a player who is offline is refused ("Người này không online"). |
| G8 | **Invites**: any seated player may invite, while the room is waiting (a game in progress cannot be joined, as today). Targets: online players not seated in any room. The popup shows the room, the inviter and the stake, with "Vào" / "Từ chối"; it expires after **60 s**. At most **one pending invite per target** and **10 invites per minute per inviter**. "Vào" re-checks everything on the server (seat free, still waiting, enough coins, not kicked from that room). The inviter sees declines and expiries. |
| G9 | **"Không nhận lời mời"**: stored on the account (`users.accept_invites`, the only new database column); such players are shown greyed out in the invite list and invites to them are refused. |
| G10 | **"Chép link"** copies the full room URL (a small clipboard JS hook, no game logic). A logged-out player opening the link logs in and is then **sent back to that room**. |
| G11 | **Private rooms**: chosen by the host at creation and switchable by the host while waiting; hidden from the lobby list but not from admins. The room id (40 random bits) is the secret: anyone with the link can join. |
| G12 | **Admin moderation**: mute a player in all chats for 10 min / 1 h / 24 h (`users.muted_until`, survives restart), delete a room or lobby message (removed live for everyone). Both audited. Admins cannot read private chats (they are not stored). |

### Batch 10 — bots, hints, phone layout (2026-09-28)

The owner asked for #1 bots, #2 phone layout and #3 hints and said not to ask ("ko cần hỏi ý tôi, cứ implement"). The decisions below were **taken by Claude** on that basis. The owner may override any of them.

| # | Decision (Claude, on the owner's instruction) |
|---|---|
| B1 | **Bots** ("máy"): the host adds a bot to a free seat while the room is waiting ("+ Máy (dễ)" / "+ Máy (thường)") and can remove it ("Bỏ máy"). Bots run on the server and play through the same rules as players; they only see their own hand. |
| B2 | **Bots only in rooms without stake** (cược 0). Adding a bot to a stake room, or setting a stake while a bot sits, is refused (`bots_need_free_room`). So no coins are ever created for or paid to a bot. |
| B3 | **Games with a bot are not recorded**: not in the leaderboard, not in the history (no farming 1st places against bots). |
| B4 | A bot **never becomes host**. The room closes when no human is left; bots alone never keep a room open. |
| B5 | A bot acts about **1 s** after its turn starts (config `:bot_delay`). If its command were ever refused, its turn is handled like a timeout. |
| B6 | Two levels:<br>• **dễ** leads its lowest single, answers with the weakest legal play, never chops;<br>• **thường** leads the biggest group holding its lowest card, avoids breaking pairs, keeps 2s and bombs for when they matter, and chops a 2 out of turn with a four-pair. |
| H1 | **"Gợi ý"** button: each click selects the next legal play, weakest first; out of turn it offers four-pair chops. Hints are computed on the server and validated by `TienLen.Game` (CLAUDE.md rule 2). |
| M1 | **Phone layout**: the hand fits one row on a phone (overlapping cards); compact seats; the action bar sticks to the bottom of the screen; the message button moves above it. |
| M2 | **Hand order**: "Xếp theo chất" / "Xếp theo số" (display only, per page). |

### Batch 11 — profile, friends, missions, seasons, reactions (2026-09-28)

The owner asked for #4–#8 "theo cách bạn thấy hợp lý nhất" without being asked. The decisions below were **taken by Claude** and can be overridden.

| # | Decision (Claude, on the owner's instruction) |
|---|---|
| P1 | **Profile page** `/nguoi-choi/<username>` for every logged-in player: avatar, name, join date, online state, coins, numbers, all-time and weekly rank, friend button, "Nhắn tin". |
| P2 | Numbers come from **recorded games** only: games, 1st places, win rate, average place, **chặt heo** count, **tới trắng** count, net coins from games, biggest win in one game. Each recorded player now stores `chops`, `coins`, `instant`. A chop is an out-of-turn four-pair, or a bomb played on a 2 or in chop context. **Games recorded before this change count 0 for these.** |
| P3 | **Avatars**: 20 fixed emoji, chosen on your own profile; no uploads. Shown in the header, seats, online lists, leaderboards. |
| P4 | Profiles of locked accounts are not shown. |
| FR1 | **Friends**: a request, then accepted by the other. Asking someone who already asked you accepts. Decline, cancel, remove (either side). |
| FR2 | Limits: 200 friends, 20 unanswered requests, 10 requests per minute. |
| FR3 | "Bạn bè" page: requests, friends with online state and "Nhắn", pending requests, search by name. The header badge counts incoming requests, live. |
| FR4 | Friends come first (⭐) in the table's invite list and the online tab of the message panel. |
| FR5 | No friends-only features beyond that (no private visibility rules). |
| M1 | **Daily missions**, the same three every Vietnam day:<br>• play 5 games (+100);<br>• finish 1st in 2 games (+150);<br>• chặt heo once (+200). |
| M2 | Progress is counted from that day's recorded games, so games with bots never count (B3). |
| M3 | The reward is claimed with a button, once per mission per day (idempotency key), ledger reason `mission`. |
| M4 | Rewards are admin settings (`mission_*_reward`). |
| S1 | **Weekly season**: Monday 00:00 to Sunday 24:00 Vietnam time; ranked like the leaderboard (1st places) over that week's games. Tabs "Tuần này" / "Tuần trước". |
| S2 | At the end of a week, the **top 3 with at least 1 win** get **1,000 / 500 / 300** coins (settings `season_reward_1..3`). A scheduler checks every hour; the payout is idempotent per week and rank. |
| S3 | Ledger reason `season_reward`, ref "Tuần dd/mm – dd/mm"; "Tuần trước" lists what was paid. |
| S4 | No reset of the all-time leaderboard; the week is a separate view. |
| R1 | **Emoji reactions** at the table (😂 👏 😮 😡 👍 🔥): seated players only, shown on their seat for 3 s, 3 per 5 s, never stored. |

### Batch 12 — spectators and replays (2026-09-28)

| # | Decision | Changes |
|---|---|---|
| V1 | **Spectators are allowed** (owner: "OK"): anyone logged in can watch a room without a seat, at `/phong/<id>/xem` or with "Xem" in the lobby. They see only public information: names, card counts, the centre, whose turn and the timer, results. | **Supersedes #17** (T13, T14) |
| V2 | **Replays show every hand after the game** (owner: "Có"). | Exception to T14, after game over only |
| V3 | (Claude) Spectators do not see or write the room chat and do not react. | – |
| V4 | (Claude) At most **20 spectators** per room. Players see the count (👀). A player seated in the room is sent to the table. Private rooms can be watched by anyone with the link. | – |
| V5 | (Claude) The replay is the dealt hands plus the public events. It is built while the game runs but **stored only with the recorded result at game over**. Games with bots (not recorded) and games recorded before this change have no replay. | – |
| V6 | (Claude) A replay can be opened by the **players of that game and admins**, from "Lịch sử" (and the admin "Ván" page). Controls: first, previous, next, last, auto-play, jump to any step. | – |

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

## Phase 11 results (2026-09-27)

### Delivered

- **Dependencies:** `ecto_sql`, `postgrex`, `phoenix_ecto`, `bcrypt_elixir` (for Phase 12).
- **`TienLen.Repo`**, started in `TienLen.Application` before PubSub.
- **Configuration:**
  - dev and test default to `ecto://tien_len:…@127.0.0.1:5434/tien_len_dev` / `tien_len_test` (override with `DATABASE_URL` / `TEST_DATABASE_URL`);
  - prod requires `DATABASE_URL` (plus optional `POOL_SIZE`).
- **Aliases:** `ecto.setup`, `ecto.reset`; `setup` now includes `ecto.setup`; `test` creates and migrates first.
- **Dev/test PostgreSQL:** `deploy/docker-compose.dev.yml`, container `tien-len-dev-db` (postgres:latest = 18.6), bound to **127.0.0.1:5434** only, with its own volume. Separate from the OpenMU database (5433) and from production.
- **Test sandbox:**
  - `test_helper.exs` sets manual mode;
  - `TienLen.DataCase`;
  - `ConnCase` checks out a sandbox for every test and provides `sandbox_conn/0` (sandbox metadata in the user agent);
  - `Phoenix.Ecto.SQL.Sandbox` plug in the endpoint (test only, via `:sql_sandbox`);
  - the `/live` socket passes `:user_agent`;
  - `TienLenWeb.PlayerHook` lets LiveView processes join the test's sandbox;
  - bcrypt uses 1 log round in tests.
- `config :tien_len, :results_recorder, nil` in test: rooms do not write results unless a test asks (Phase 13).

### VERIFIED

- `mix ecto.create` works for dev and test.
- `mix precommit`: **228 passed** (the 227 previous tests are unchanged, plus a repo test checking that tests run on `tien_len_test`, never `openmu`).

## Phase 12 results (2026-09-28)

### Delivered

- **Migration** `create_users`: `username` (lowercase, unique index), `display_name`, `hashed_password`, timestamps.
- **`TienLen.Accounts`** and **`TienLen.Accounts.User`**:
  - `register_user/1` (Y1 rules, Vietnamese error messages, bcrypt hash; password and hash are redacted from `inspect`);
  - `authenticate/2`: username case ignored; the same timing for unknown users (`Bcrypt.no_user_verify/0`);
  - `get_user/1`, `change_display_name/2`, `change_registration/2`.
- **`TienLenWeb.UserAuth`:**
  - `fetch_current_user` plug (replaces the anonymous `PlayerIdentity` plug);
  - `log_in_user/2`: renews and clears the session (no fixation), stores `user_id` and a random per-browser `live_socket_id`;
  - `log_out_user/1`: broadcasts `disconnect` to this browser's LiveViews, clears the session;
  - `on_mount` hooks: `:mount_current_user` (lobby) and `:require_user` (rooms; assigns `player_id` = user id and `player_name` = display name);
  - the test sandbox hook moved here.
- **`TienLenWeb.UserSessionController`:**
  - `POST /dang-nhap`: one message for a wrong password or an unknown user; the username is kept in the form;
  - `DELETE /dang-xuat`.
- **Router:** `live_session :public` (`/`, lobby) and `live_session :authenticated` (`/phong/:id`). `POST /ten` and `GET /tiep-tuc/:token` are removed.
- **`LobbyLive` when logged out:**
  - a register form with the three fields "Chào bạn! Bạn tên gì?", "Tài khoản", "Mật khẩu", validated live; on success it submits the same credentials to `/dang-nhap` (`phx-trigger-action`), so the user is logged in at once;
  - a login form.
- **`LobbyLive` when logged in:** the lobby plus "đổi tên", which saves the display name in the database.
- **Header:** the display name, `@username` and an "Đăng xuất" link (`DELETE`, CSRF-protected).
- **Removed** (A3, Y2): `TienLenWeb.PlayerIdentity` (anonymous ids, seat tokens, resume links), `PlayerHook`, `PlayerController`, the table's resume link.

### VERIFIED

- `mix precommit`: **240 passed (2 doctests, 238 tests)**, no warnings. The full suite was run 10 more times: 0 failures.
- **Accounts tests:**
  - lowercase storage;
  - bcrypt hash only (not the password, not visible in `inspect`);
  - unique username in any case;
  - format and length rules;
  - password 8 characters to 72 bytes (a 75-byte Vietnamese password is refused);
  - all fields required;
  - authentication with any username case; wrong password, unknown user and junk input all rejected.
- **Web tests:**
  - the lobby shows the 3-field register form and the 2-field login form when logged out;
  - live Vietnamese errors;
  - a taken username (any case) is refused;
  - registering logs the user in (`follow_trigger_action`) and shows the lobby;
  - the session is renewed at login (a value planted before login does not survive);
  - one message for a wrong password or an unknown user;
  - malformed login params do not crash;
  - logout clears the session and broadcasts `disconnect` to this browser's LiveViews; a `GET /dang-xuat` is 404 and leaves the user logged in;
  - a session for a deleted user counts as logged out;
  - rooms require login;
  - two devices of one account share one seat, whose player id is the user id;
  - changing the display name saves it;
  - all earlier game, room, realtime and security tests now run with real accounts.
- **Real dev server over HTTP** (`mix phx.server`, dev database):
  - logged out, `/` shows "Chào bạn! Bạn tên gì?" and `/phong/…` redirects to `/`;
  - a wrong password → "Sai tài khoản hoặc mật khẩu", with the username kept;
  - login with `BINH_SMOKE` (upper case) → "Chào Bình!", name and logout link shown;
  - logout with the link's CSRF token → "Đã đăng xuất", login form shown, rooms redirect again.
  - A dev-database user `binh_smoke` was created for this check.

### NOT VERIFIED

- The registration form in a real browser (the `phx-trigger-action` submit is covered by LiveView tests, not by a browser).

## Phase 13 results (2026-09-28)

### Delivered

- **Migration** `create_games`:
  - `games` (room id, player count, instant win, finished at);
  - `game_players` (game, user, seat, place, won, removed), unique per game and user, deleted with the game or the user.
- **`TienLen.Stats`:**
  - `record/1`: one transaction; only integer (account) player ids; broadcasts `{:stats_updated}`;
  - `leaderboard/1`: wins = 1st places (A1), games and win rate; order wins desc, rate desc, games asc, username asc (Y5);
  - `user_standing/1`;
  - `history/2`: newest first, with every player's place.
- **`TienLen.Room`:**
  - `game_players` snapshot (seat → player id) taken when a game starts, so a player who leaves mid-game is still recorded for the right account;
  - `result/1`: places = ranking groups (instant-win losers share place 2), won = place 1, removed flag.
- **`TienLen.RoomServer`:**
  - records the result whenever the events contain `:game_over` (normal end, instant win at the deal, end by removal or leave);
  - the recorder is `TienLen.Stats` by default, a room option `:recorder`, and off in tests (`config :tien_len, :results_recorder, nil`);
  - a failing recorder is logged and never interrupts play (Y6).
- **Pages** (login required, Y8):
  - `/bang-xep-hang`: my standing plus the top 50, my row highlighted, live updates;
  - `/lich-su`: my last 20 games, Vietnam time (UTC+7), places Nhất/Nhì/Ba/Bét, "Thua (tới trắng)" for instant-win losers, removed players marked, live updates.
- **Header links:** "Bảng xếp hạng", "Lịch sử".

### VERIFIED

- `mix precommit`: **258 passed (2 doctests, 256 tests)**, no warnings. The full suite was run 10 more times: 0 failures.
- **Stats tests:**
  - wins / games / rate;
  - tie-breaks: rate, then fewer games for players without a win, then username;
  - instant win with two winners and a tied loser;
  - a removed player counts as played;
  - non-account ids ignored and `:skipped`;
  - users without games are not listed;
  - the broadcast;
  - deleting a user deletes their results;
  - history order and places.
- **Mutation checks on the ordering:** reversing wins, games or username in the `ORDER BY` each makes a test fail. The first version of the tests missed the games tie-break; a test for players without a win was added.
- **Integration through `RoomServer` with the real recorder:**
  - a 3-player game played to the end is stored with places 1/2/3;
  - two players leaving mid-game are recorded as removed with their places;
  - a raising recorder is logged, and the room still finishes the game.
- **LiveView tests:**
  - both pages require login;
  - the leaderboard shows wins / games / 67% and my highlighted row, and updates without a reload;
  - history shows places and instant wins;
  - the header links are present.
- **Dev environment:**
  - the default recorder is `TienLen.Stats`;
  - a script played real games through `RoomServer` on the dev database;
  - over HTTP, `/bang-xep-hang` redirects when logged out; logged in, it lists "An 2 2 100%" and "Chi 0 2 0%", and `/lich-su` shows "28/09/2026 07:00 · 2 người" with the places.
  - Dev-database users `smoke_an` and `smoke_chi` and their games were created for this check.

## Phase 14 results (2026-09-28)

### Delivered

- `mix phx.gen.release` (with Ecto): `TienLen.Release`, `rel/overlays/bin/migrate` (+ `.bat`).
- **`deploy/docker-compose.yml`:**
  - service `db`: `postgres:18`, volume `tien-len-db`, healthcheck, no host port;
  - service `tien-len`: `DATABASE_URL` built from `POSTGRES_PASSWORD`, `depends_on` a healthy DB, command `bin/migrate && exec bin/server` (Z1).
- `deploy/.env.example` documents `POSTGRES_PASSWORD` and `POOL_SIZE`. `deploy/.env` got a random 48-hex `POSTGRES_PASSWORD` (still gitignored, `chmod 600`).
- `docs/DEPLOY.md` rewritten: topology, variables, operations (including the `down -v` warning), backup/restore, smoke test, verification.

### VERIFIED (on the running containers)

- The build and start sequence works (DB healthy → migrations → server). Later starts log "Migrations already up". The DB port is not published.
- Accounts registered and a game played through the release with the real recorder. Over HTTP: the register form, login, leaderboard ("An @prod_an 1 1 100%") and history.
- **Data survives `docker compose restart` and `down` + `up -d`.** The old session cookie stays valid.
- The backup command works (332-line dump).
- CSRF 403, websocket origin 101/403, login-required redirects, no `.env` in the image.
- `mix precommit`: **258 passed**.
- The test accounts `prod_an` / `prod_chi` and their game were deleted afterwards. The production database is empty.

### NOT VERIFIED

- Registration and a full game in a real browser against the container.

## Phases 15–18 results — coins (2026-09-28)

### Delivered

- **Phase 15 — ledger and balances:**
  - Migration `add_coins`:
    - `users.coins` (bigint, `CHECK coins >= 0`), `daily_bonus_on`, `relief_on`;
    - `coin_transactions` (append-only ledger: amount, balance after, reason, counterparty, ref);
    - `coin_settlements` (unique keys = idempotency);
    - existing accounts get 1,000 (E9).
  - `TienLen.Economy`, the only module that changes balances:
    - `claim_daily_bonus/2`, `claim_relief/2` (E8, Vietnam day);
    - `settle/3`: row locks in id order, each debtor capped at the starting balance, proportional sharing with in-order leftovers (E5), credits never fund debits, idempotent by key;
    - `balance(s)/1`, `claimable/2`, `history/2`, `richest/1`;
    - per-user and global PubSub updates.
  - Registration grants 1,000 coins in the same transaction as the account (`Ecto.Multi`).
  - `.formatter.exs` now imports the Ecto formatter rules; schema macros are written without parentheses.
- **Phase 16 — settlement of games:**
  - `Game` tracks the round's **chop chain** (E3) and emits `{:chop_chain, %{payer, payee, units, chops}}` when the round or the game ends. `Game.twos_units/1` (black 1, red 2).
  - Pure `TienLen.Payout`: `game_over/2` (places T21 or instant win T22, plus thối T24), `places/2`, `instant_win/2`, `thoi/2`, `chop_chain/2`. Debts are between seats; stake 0 gives nothing; chopping your own combination gives nothing.
  - `Room`: `stake` (0 or 10…10¹²), `set_stake/3` (host, between games), eligibility 10×S (`:not_enough_coins`), `game_no` for settlement keys.
  - `RoomServer`:
    - options `:stake` and `:economy` (`TienLen.Economy` by default, off in tests);
    - settles chains and game-over debts through `Economy.settle/3` with keys `room:<id>:game:<n>:chain:<k>` / `:end`;
    - appends `{:coins, transfers}` (seats) to the broadcast events;
    - the view carries `stake`, `min_balance`, `balances` (by seat) and `coin_deltas` (this game);
    - settlement failures are logged and never stop play.
- **Phase 17 — UI:**
  - header balance (live on every page through a `UserAuth` hook);
  - lobby coin panel with "Nhận thưởng ngày (+100)" / "Nhận cứu trợ (+500)";
  - stake field when creating a room; stake in the room list;
  - at the table: stake badge, balance and +/− per seat, the host's "Đổi cược" form between games, the "not enough coins" hint, and a coins section in the results;
  - `/lich-su-coin` ledger page;
  - "Giàu nhất" tab on `/bang-xep-hang`;
  - Vietnamese labels and `1.000` number formatting.
  - Clients never send amounts: the only number a client sends is the host's proposed stake, which the server validates.
- **Phase 18 — deploy:** image rebuilt and redeployed twice (the second time with the fix below). The `add_coins` migration ran on the production database at start.

### VERIFIED

- `mix precommit`: **304 passed (2 doctests, 302 tests)**, no warnings.
- **Economy tests:**
  - the registration grant and its rollback on a failed registration;
  - the daily bonus once per Vietnam day, and **10 concurrent claims pay once**;
  - relief only below 100, once per day; the 17:00 UTC day boundary;
  - `settle` moves coins and writes both ledger lines;
  - idempotency;
  - the balance cap;
  - proportional sharing (100 over three creditors of 200 → 34/33/33);
  - credits cannot fund debits;
  - junk debts are ignored;
  - **300 random settlements keep the total and never go negative, and every ledger sum equals the balance**;
  - the database refuses a negative balance directly.
- **Payout and chain tests:**
  - the E3 example (2♥ chopped, then chopped again → B pays C 4 units);
  - black and red values; a higher 2 is not a chop;
  - an out-of-turn four-pair in a chain;
  - a chain closed at game over;
  - the owner's place examples with stake 500; E1 rounding; zero sums;
  - an instant win with two winners;
  - thối to the player just above; removed players pay no thối;
  - stake 0; chopping your own combination.
- **Rooms with the real Economy** (stake 100, 3 players): chain + place + thối give **1,100 / 400 / 1,500 (total 3,000)**, with ledger reasons and view deltas `%{0 => 100, 1 => -600, 2 => 500}`. Also: the `{:coins, …}` event at round end, stake 0, eligibility, a refused start, stake-change rules, invalid stakes.
- **LiveView:**
  - header and lobby balance; daily bonus once (a replayed event with a forged amount changes nothing); relief;
  - stake validation when creating a room; the room list stake;
  - table stake, seat balances and ± for both players; the header updates live;
  - the host-only stake change; the not-eligible hint; the refused start;
  - the coin history page; the "Giàu nhất" tab; login required.
- **Production** (`bin/tien_len rpc` + HTTP):
  - registrations got 1,000;
  - the same 3-player stake-100 game gave 1,100 / 400 / 1,500 with deltas 100 / −600 / 500 and Bình's ledger `thoi −100, place −100, chop −400`;
  - logged in over HTTP, the header shows 🪙 1.500, the lobby shows the balance, the daily-bonus button and the stake field;
  - `/lich-su-coin` lists "Thối heo (từ Binh) +100", "Chặt heo (từ Binh) +400", "Tặng khi đăng ký +1.000";
  - "Giàu nhất" lists 1.500 / 1.100 / 400.
  - The three test accounts and their game were deleted afterwards.
  - One real account (`bien`, registered after the deploy, 1,000 coins) was left untouched.

### Found and fixed on the way

- **Real bug:** `RoomServer.call/2` only caught `:noproc` and `:normal` exits. A room dying for any other reason (killed, crashed, timed out) during a call **crashed the caller**. For example, the lobby LiveView listing all rooms. It was found by a flaky lobby test (1 in ~20 full runs). Fixed: any exit of the room process becomes `{:error, :room_not_found}`. A regression test was added and confirmed to fail on the old code.
- **Flaky test:** the Phase 9 timeout test used a 40 ms turn timer and could miss the countdown under load. It now uses 500 ms and a longer wait.
- **Flakiness status (accepted by the owner, 2026-09-28):** after both fixes, a background loop of repeated full-suite runs found no further failure before it was stopped at the owner's request. The run count was not recorded exactly: several dozen runs, on top of the earlier 40 clean runs. No known flaky test remains. Any new intermittent failure should be captured with the same loop: repeat `mix test`, log the seed and the first failure.

## Phases 19–23 results — admin (2026-09-28)

### Delivered

- **Phase 19 — roles and audit (AD1, AD2, F1):**
  - migration `add_admin`: `users.role` (`player` / `admin`, check constraint), `users.locked_at`, `admin_actions` (audit), `settings`, `games.ref`;
  - `TienLen.Admin`: `promote/1` (server command, audited as `promote_server`), `set_admin/3` (only admins; cannot demote yourself; cannot remove the last admin);
  - `/quan-tri` `live_session` guarded by `on_mount(:require_admin)`; every admin function re-checks the role in the context (`authorize/1`), so a forged event from a player gets `:forbidden`;
  - a removed admin is sent away live (`{:role_changed, role}` on `user:<id>`); the "Quản trị" header link shows for admins only.
- **Phase 20 — users (AD4, AD5, F2–F4):**
  - search, detail page (coins, games, recent ledger, audit);
  - lock / unlock (F2): the locked user is logged out live (`{:force_logout}`), removed from every room, and refused at login ("Tài khoản đã bị khóa"); admins and yourself cannot be locked;
  - rename; reset password (random temporary password shown once to the admin); the player's own "Đổi mật khẩu" in the lobby (F3);
  - coin adjustments (F4) through `Economy.adjust/4`: ledger reason `admin_adjust`, a required reason of 3–200 characters, never below 0; the player's balance updates live and the coin history shows "Quản trị viên điều chỉnh".
- **Phase 21 — dashboard, rooms, games (AD3, AD6–AD8, F5, F6):**
  - dashboard: accounts, locked, admins, total coins, rooms, players online, games today;
  - room list; watch view with **every hand** (AD7, admins only; players' projections are unchanged);
  - close room (F5): the game is cancelled, no settlement and no stats, players are sent to the lobby with a flash;
  - kick a player (banned from rejoining that room);
  - game history with each game's transfers (ledger lines whose ref starts with the game's `ref`).
- **Phase 22 — announcements, settings, rate limit (AD9, F7, F8):**
  - announcement banner on every page, live; empty text clears it; at most 300 characters;
  - economy settings (`starting_coins`, `daily_bonus`, `relief`, `relief_below`, `max_rooms`) in the `settings` table, cached in `:persistent_term`, loaded at start; new values apply to new actions only (F7);
  - `TienLen.LoginThrottle` (ETS): 5 failures per username or per IP in 15 minutes block further logins ("Đăng nhập sai quá nhiều lần…"); a success clears the username counter.
- **Phase 23 — deploy:** image rebuilt, the `add_admin` migration ran at start, `bien` promoted with `bin/tien_len rpc 'TienLen.Admin.promote("bien")'`.

### VERIFIED

- `mix precommit`: **339 passed (2 doctests, 337 tests)**, no warnings; 10 repeated full runs clean.
- Tests: access for anonymous / players / admins on every page; demote rules and live redirect; lock with live logout and refused login; reset password then log in; adjustments (+250, refused −5000); rename; search; watch view shows all hands; closing a room redirects players; the 6th login refused; password change; settings validation, caching and reload; announcements live.
- **Production** (HTTP + `rpc`, with two temporary accounts `smoke_admin` / `smoke_player`):
  - admin pages: 200 for the admin, 302 for a player and for anonymous users; the header link only for the admin;
  - dashboard numbers and the audit log (the two server promotions) correct;
  - locking `smoke_player` → its login shows "Tài khoản đã bị khóa";
  - an announcement appeared on the lobby and was cleared;
  - 5 wrong passwords for `smoke_admin` → the 6th (correct) login refused.
  - The two smoke accounts were deleted afterwards. Their audit rows stay, with the user ids nulled (by design).
- Production state after the checks: `bien` (admin, 1,100) and `ai_ga` (player, 1,100, a real user) — both untouched apart from the promotion of `bien`.

### Deviations and notes

- **F8 on this deploy:** counting per IP is **off** (`THROTTLE_BY_IP=false` in `deploy/.env`). Behind Docker on WSL every client appears with the gateway IP, so one IP counter would lock out everyone. Counting per username is on. Turn it on when the app runs behind a proxy that passes the real client IP (and `remote_ip` is set from it). Tests also run with it off; the IP logic has its own unit test.
- The throttle lives in ETS: it resets when the container restarts, and it is per node.
- `last_admin` cannot be reached through the web today: removing another admin needs a second admin, and demoting yourself is refused. It stays as a safety check.
- Admins have strong powers (see all hands, change coins); every action is written to `admin_actions` and shown on "Nhật ký".

## Phases 24–28 results — chat and invites (2026-09-28)

### Delivered

- **Phase 24 — presence, limiter, room chat (CH1–CH4, G1–G4, G6):**
  - `TienLen.Presence` (Phoenix.Presence, topic `"online"`): every open page of a logged-in player, with the place (`lobby` / `room` / `playing` / `other`); the admin dashboard shows "Đang online";
  - `TienLen.RateLimit` (ETS sliding window), used for chat (5 / 10 s) and invites (10 / min);
  - `TienLen.Chat`: text rules (1–200 characters, whitespace collapsed), sender re-read from the database (locked → refused, muted → refused), name from the account, 8 quick phrases;
  - room chat in the room process (last 50, `{:room_chat, …}` on the room topic), seated players only, also during a game; panel `#room-chat` on the table.
- **Phase 25 — lobby and private chat (G5, G7):**
  - `TienLen.Chat.Lobby` (last 100) and the `#lobby-chat` panel; online list `#online` with places and "Nhắn";
  - `TienLen.Chat.Private` (last 20 per pair, dropped after 1 h without messages); `TienLenWeb.Social` attaches to every logged-in page: the floating "💬 Tin nhắn" panel (conversations with unread counts, "Đang online" tab), so private chat works on the lobby, table, leaderboard and admin pages.
- **Phase 26 — invites (IV1, IV3, G8–G10):**
  - `TienLen.Invites`: invite from the table ("Mời người chơi"), popup on any page of the target (Vào / Từ chối), 60 s expiry, one pending per target, 10 / min per inviter; accept re-checks the room and the coins (`not_enough_coins_to_join`), the table's join re-checks the rest (kicked, full);
  - `users.accept_invites` + "Không nhận lời mời" checkbox in the lobby; such players are greyed out in the invite list;
  - "Chép link" (clipboard hook, falls back to a prompt); a room link opened logged out goes to `/?next=/phong/<id>` and back to the room after login or registration (`UserAuth.safe_next/1` accepts only `/phong/<id>`).
- **Phase 27 — private rooms and moderation (IV2, G11, G12):**
  - "Riêng tư" checkbox when creating; host toggle while waiting; hidden from the lobby list (`Lobby.public_rooms/0`), shown with a badge to admins;
  - `Admin.mute/4` (10 min / 1 h / 24 h, `users.muted_until`), `Admin.unmute/2`, `Admin.delete_message/2` (lobby: ✕ on the lobby for admins; room: ✕ in the watch view). Audited; the audit row names the author, never the text.
- **Phase 28 — deploy:** migration `add_chat_invites` ran at container start.

### VERIFIED

- `mix precommit`: **374 passed (2 doctests, 372 tests)**, no warnings; 6 full runs clean.
- New tests: `test/tien_len/chat_test.exs`, `test/tien_len/invites_test.exs`, `test/tien_len_web/chat_live_test.exs`. They cover:
  - text rules; the rate limit; the name from the account; muted and locked senders; mute rules;
  - room chat for seated players only, the cap of 50, chat during a game, deletions;
  - lobby chat and deletion; private chat online-only, both sides, unread, 20-line cap, 1 h expiry;
  - presence places;
  - invite / accept / decline / expiry, one pending, every refusal, 10/min, the coin re-check, candidates;
  - private rooms (host only, waiting only, hidden, joinable by id);
  - in the browser: HTML escaped, quick phrases, history for a reopened page, errors shown, admin deletions live, online list moving from "Ở sảnh" to "Trong phòng", the unread badge, the panel on the table page, the popup and accept → room, decline, the greyed-out candidate, the copy-link URL, login back to the room (and unsafe `next` values ignored), the private-room toggle, mute buttons, the online stat.
- **Production** (rpc + HTTP, with temporary accounts `smoke_a` / `smoke_b`, deleted afterwards):
  - private room not in the lobby list;
  - room chat ok, refused for a non-seated player;
  - private message to an online player; invite accepted;
  - a lobby message posted and deleted again;
  - `/phong/abc` logged out → 302 `/?next=%2Fphong%2Fabc`, the login form carries `next`, login → 302 `/phong/abc`;
  - the lobby shows "Chat sảnh", "Đang online", "Không nhận lời mời", "Riêng tư" and the message button.
- Production accounts after the checks: `bien` (admin), `ai_ga`, `ben` (real players, untouched).

### Notes

- Chat, presence, invites and rate limits are in memory: a restart clears them (CH2). Single node only.
- Collusion through chat is accepted (CH4, RISKS P17). There is no profanity filter or block button (CH3, IV3; RISKS P18).
- NOT VERIFIED: the clipboard button and the chat auto-scroll in a real browser (JS hooks; LiveView tests do not run JS).

## Phases 29–31 results — bots, hints, phone layout (2026-09-28)

### Delivered

- **Hints (H1):** `TienLen.Hint` (pure):
  - builds candidates from the hand: sets, straights and runs of pairs, varying only the top card;
  - keeps those that `Game.check_play/3` or `check_chop_out_of_turn/3` accept, sorted weakest first;
  - `RoomServer.hints/2`; a "Gợi ý" button that cycles through them.
- **Bots (B1–B6):**
  - `TienLen.Bot` (pure `decide/3`, `chop/3`);
  - `Room.add_bot/3`, `remove_bot/3`, `humans/1` (bot ids `{:bot, n}`, names "Máy n (dễ|thường)");
  - the room server schedules bot actions after every change (`bot_ref`, `bot_delay`);
  - the host never passes to a bot; the room closes when no human is left;
  - `Room.result/1` is `nil` for games with a bot; stake guards on both sides.
- **Phone layout (M1, M2):**
  - the hand overlaps on small screens (`w-12`, `-ml-6`); compact seats; smaller centre cards;
  - sticky action bar with "Gợi ý" and "Xếp theo chất / số"; the 💬 button sits above the bar on phones.
- Deployed (no migration).

### VERIFIED

- `mix precommit`: **392 passed (2 doctests, 390 tests)**, no warnings; 40 runs of the bot tests and 6 full runs clean.
- `test/tien_len/bot_test.exs`:
  - candidates;
  - hints on 300 random deals are all legal and hold the opening card; the weakest answer comes first; an empty list is correct;
  - chops;
  - easy / normal leads; normal keeps 2s unless pressed, plays out its last cards, does not break a pair, chops a 2; easy never chops;
  - **200 bot-only games (2–4 players, mixed levels) finish with only legal commands**;
  - add / remove rules (host, waiting, stake 0, full) and the stake guard;
  - a human with 3 bots plays to game over and nothing is recorded;
  - room hints are legal; host transfer skips bots; the room closes with bots only.
- `test/tien_len_web/live/bot_live_test.exs`:
  - add / remove bots in the page; a game against a bot starts;
  - no bot buttons with a stake; guests refused;
  - the hint selects a legal play and enables "Đánh"; sorting by suit.
- **Production** (`rpc`): a human plus 3 bots (turn 50 ms, bots 20 ms) played to game over; a 5th seat was refused; the recorded-games count stayed 2; the lobby returns 200.
- Two flaky tests found and fixed while writing: random deals that could be an instant win (fixed deal; the game-over event read from the first update too).

### NOT VERIFIED

- The phone layout on a real phone (LiveView tests check the markup, not the rendering).
- The bots' playing strength is not measured. "Thường" is a simple heuristic, not a strong player.

## Phases 32–36 results — profile, friends, missions, seasons, reactions (2026-09-28)

### Delivered

- Migration `add_social_features`: `users.avatar`; `game_players.chops/coins/instant`; `friendships` (unique pair, not self, status check).
- **P:**
  - `Room.game_chops` counts chops per seat; `Room.result/1` carries `chops` and `instant`;
  - the room server now settles coins **before** recording, so each player's net `coins` is stored;
  - `Stats.profile/1`, `Stats.counts/2`, `Stats.leaderboard/2` with a period;
  - `Accounts.avatars/0`, `set_avatar/2`, `get_by_username/1`, `search/1`;
  - `ProfileLive` (`/nguoi-choi/:username`); avatars in the header, seats, presence, leaderboards, invite list.
- **FR:** `TienLen.Friends` (+ `Friendship` schema), `FriendsLive` (`/ban-be`), a header badge via `TienLenWeb.Social` (`{:friends_changed}` on the user topic), friends first in invite / online lists.
- **M:** `TienLen.Missions`, `Economy.grant/5` (idempotent grant), `Economy.settled?/1`, `Economy.vn_day_bounds/1`, a lobby card with progress and "Nhận".
- **S:** `TienLen.Seasons` (week bounds, standings, `payout/2`, `payout_due/1`, `paid/1`), `TienLen.Seasons.Scheduler` (10 s after start, then hourly; off in tests), leaderboard tabs.
- **R:** `RoomServer.react/3` (`{:reaction, room_id, seat, emoji}`), the emoji bar and the seat bubble on the table.
- 6 new admin settings (mission and season rewards).

### VERIFIED

- `mix precommit`: **406 passed (2 doctests, 404 tests)**, no warnings; 8 full runs clean.
- `test/tien_len/social_features_test.exs`:
  - a three-pair on a 2 is counted as a chop and reaches the result;
  - profile aggregates and daily counts; avatars;
  - friends: the whole flow, notifications, reverse request = accept, decline / cancel / refusals, 10/min;
  - missions: progress only from today; claim refused before done; paid once; ledger line;
  - seasons: weekly standings; not paid before the end; top 3 with a win paid 1,000 / 500 and the 0-win player nothing; a second payout pays nothing; `paid/1`.
- `test/tien_len_web/social_features_live_test.exs`:
  - own profile numbers; avatar pick shown in the header;
  - friend request → badge → accept on `/ban-be` → both pages update; search + request;
  - missions card live after a recorded game, claim → header balance;
  - weekly tabs;
  - reactions seen by the other player; strangers and unknown emoji refused.
- Two older tests updated (seat map now has `avatar`; the reasons list). A latent flaky test (a random deal could be an instant win) was fixed with a fixed deal.
- **Production:**
  - migration ran; with 2 temporary accounts: friend request + accept, avatar, missions listed with rewards 100/150/200;
  - `payout_due` for last week → `{:ok, []}` (no games that week);
  - accounts deleted; no errors in the log; `bien`, `ai_ga`, `ben` untouched.

### Notes

- Games recorded before this deploy have `chops = 0`, `coins = 0`, `instant = false`: profile numbers for chặt heo / coins / tới trắng start from now.
- Missions and seasons pay coins: farming with several accounts is possible (see RISKS P12, P19).

## Phases 37–38 results — spectators and replays (2026-09-28)

### Delivered

- **Spectators (V1, V3, V4):**
  - `RoomServer.watch/1` monitors the watcher (max 20); `spectator_view/1` = `Room.view(room, nil)` plus timer and results, without chat;
  - players' views carry `spectators`; `{:spectators, n}` updates are broadcast;
  - `SpectateLive` (`/phong/:id/xem`), "Xem" in the lobby list, 👀 count on the table;
  - presence place `watching` ("Đang xem"), which can still be invited.
- **Replays (V2, V5, V6):**
  - migration `add_game_replay` (`games.replay` jsonb);
  - the room server builds the replay from `:game_started` (dealt hands, seat names) and the public events (played, chopped, passed, timed_out, removed, round_ended, lead_moved, finished, instant_win, coins, game_over), and passes it to the recorder at game over;
  - `Stats.replay/2` (players + admins), `has_replay` in history;
  - pure `TienLen.Replay.frames/1`; `ReplayLive` (`/van/:id`) with step controls, auto-play and the step list; links in "Lịch sử" and the admin "Ván" page.

### VERIFIED

- `mix precommit`: **413 passed (2 doctests, 411 tests)**, no warnings; 30 runs of the new tests and 5 full runs clean after one fix (a fixed 20 ms sleep for the watcher's `:DOWN` → polling).
- Domain tests:
  - the spectator view has no hand, no chat, no foreign card anywhere in it (`inspect` check);
  - the count follows monitors; the limit of 20;
  - a real 2-player game's replay (hands, names, event types, chop counted) survives JSON; frames rebuild the hands and the centre;
  - access for players / admins / others; `no_replay` for older games; `has_replay`.
- LiveView tests:
  - a spectator page shows the count, the players see 👀, no hand image or chat is rendered, and the page updates live after a play;
  - a seated player is redirected to the table; the lobby has "Xem";
  - replay: history link, deal, next step text and centre, the card leaves the hand, last step, first step, a stranger is refused.
- **Production** (`rpc`, 2 temporary accounts):
  - a watcher got a view without hands; players saw 1 spectator;
  - a fixed-deal game was recorded with a replay of 8 steps.
  - The game row and the accounts were deleted afterwards; no errors in the log.

### NOT VERIFIED

- The spectator and replay pages on a real phone.

## Environment state

- Original repo: `/home/bien_nguyen/tien-len` (unmodified source). It contains one untracked file, `docs/research.md`, added during research. That file is **stale**: it is superseded by this repo's `docs/`. The owner decided to keep it.
- Scratch copy with `node_modules` and the probe tests: the session scratchpad (temporary, not needed).
- Toolchain: `~/.local/beam` (OTP 28, Elixir 1.20.4, `phx_new` 1.8.15), shared with `open-mu-web`.
- Git: local repo on branch `main`, no remote (the `gh` CLI is not installed). One commit per phase.
- Docker: compose project `tien-len` running: `tien-len` (image `tien-len:latest`, host port 4020) and `tien-len-db` (postgres:18, volume `tien-len_tien-len-db`; accounts `bien` (admin), `ai_ga`, `ben`), both `restart: unless-stopped`. Stop with `cd deploy && docker compose down` (never `-v` unless the data should be deleted).
- Dev/test database: container `tien-len-dev-db` on 127.0.0.1:5434 (`docker compose -f deploy/docker-compose.dev.yml up -d`), databases `tien_len_dev` and `tien_len_test`.
- First admin: `bien` (server command). Promote more on the web ("Cấp quyền admin") or with `docker exec tien-len bin/tien_len rpc 'TienLen.Admin.promote("username")'`.
- Owner decision: keep the stale `docs/research.md` in the original repo (do not delete it).
