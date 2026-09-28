# Mobile audit (M3)

Opens every page of a running **dev** server in headless Chromium at 360, 390, 412 and 1280 px,
reports any horizontal overflow (page wider than the screen, and which element causes it), lists
tables that scroll inside their box, and saves full-page screenshots.

It logs in as `ui_ben` (admin) and uses `ui_chi`, password `mat-khau-123`: create them in the
**dev** database first (never production). It creates a room with two bots, and a spectator.

```bash
cd tools/mobile-audit
npm install && npx playwright install chromium       # once (~115 MB in ~/.cache/ms-playwright)
BASE=http://localhost:4010 OUT=/tmp/shots node audit.js after   # screenshots in /tmp/shots/after
#   OK   360  /bang-xep-hang   scroll=360/360
#   ...
#   83/83 OK
```

If Chromium fails with `libnspr4.so: cannot open shared object file` and you have no sudo, fetch
the libraries without installing them:

```bash
mkdir -p /tmp/libs && cd /tmp/libs && apt-get download libnspr4 libnss3 libasound2t64
for f in *.deb; do dpkg-deb -x $f root; done
export LD_LIBRARY_PATH=/tmp/libs/root/usr/lib/x86_64-linux-gnu
```

## Hand audit (M4)

`hand_audit.js` checks the cards in hand at 360–1280 px: with 0, 1, 2 and 3 adjacent cards
selected, every card's corner index is visible (nothing covers it), selected cards are lifted,
the lifted cards stay below the seats, and clicking each card's visible strip selects that card.

```bash
BASE=http://localhost:4010 OUT=/tmp/shots node hand_audit.js     # "Không có vấn đề" = all good
```
