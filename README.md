# Tiến Lên Miền Nam

A real-time multiplayer Tiến Lên (Southern Vietnamese rules) card game for 2–4 players, built with Elixir, Phoenix and LiveView.

It started as a port of [nguyenank/tien-len](https://github.com/nguyenank/tien-len) (React + boardgame.io), with a deliberately different ruleset:
- all rules enforced on the server;
- no "Tiến Lên" chaining;
- cross-type chops in chop context, and an out-of-turn four-pair;
- instant wins (tới trắng);
- several games per room, with turn and disconnect timeouts.

**Status:** research done, implementation not started. See `docs/PORTING_STATUS.md`.

- Rules: [`docs/RULES.md`](docs/RULES.md)
- Plan: [`docs/PORTING_PLAN.md`](docs/PORTING_PLAN.md)
- Architecture: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Background on the original: [`docs/RESEARCH.md`](docs/RESEARCH.md)
