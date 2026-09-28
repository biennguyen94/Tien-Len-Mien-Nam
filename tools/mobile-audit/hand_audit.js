// M4: hand layout audit at several window widths
const { chromium } = require("playwright");
const OUT = process.env.OUT;
const widths = (process.env.WIDTHS || "360,390,412,450,640,768,1024,1280").split(",").map(Number);

async function table(b, w) {
  const p = await b.newPage({ viewport: { width: w, height: 820 } });
  await p.goto("http://localhost:4010/");
  await p.fill("#login-form input[name='user[username]']", "ui_ben");
  await p.fill("#login-form input[name='user[password]']", "mat-khau-123");
  await Promise.all([p.waitForNavigation(), p.click("#login-form button[type=submit]")]);
  await p.waitForSelector("[data-phx-main].phx-connected");
  await Promise.all([p.waitForURL(/\/phong\//), p.click("#create-room")]);
  await p.waitForSelector("#add-bot-easy"); await p.click("#add-bot-easy"); await p.waitForTimeout(200);
  for (let i = 0; i < 3; i++) {                     // an instant win ends the game at once: deal again
    await p.click("#start"); await p.waitForTimeout(500);
    if (await p.$("#hand button")) break;
  }
  return p;
}

const state = (p) => p.evaluate(() => {
  const bs = [...document.querySelectorAll("#hand button")];
  const above = document.querySelector("#must-include") || document.querySelector("#table");
  const aboveBottom = above ? above.getBoundingClientRect().bottom : 0;
  return bs.map((btn, i) => {
    const img = btn.querySelector("img").getBoundingClientRect();
    const next = bs[i + 1] && bs[i + 1].querySelector("img").getBoundingClientRect();
    const exposed = next ? next.left - img.left : img.width;
    const hit = document.elementFromPoint(img.left + 6, img.top + 14);
    return { id: btn.id.slice(5), sel: btn.getAttribute("aria-pressed") === "true", exposed: Math.round(exposed),
             visible: hit && hit.closest("#hand button") === btn, top: img.top, clear: img.top - aboveBottom, x: img.left };
  });
});

async function toggle(p, id) {
  const before = await p.getAttribute(`#card-${id}`, "aria-pressed");
  const img = await (await p.$(`#card-${id} img`)).boundingBox();
  const s = await state(p); const me = s.find((c) => c.id === id);
  // click in the middle of the exposed strip, near the corner
  await p.mouse.click(img.x + Math.min(me.exposed / 2, 12), img.y + 30);
  await p.waitForFunction(([id, b]) => document.querySelector(`#card-${id}`)?.getAttribute("aria-pressed") !== b, [id, before], { timeout: 3000 }).catch(() => {});
  await p.waitForTimeout(300);   // let the lift transition finish
  return (await p.getAttribute(`#card-${id}`, "aria-pressed")) !== before;
}

(async () => {
  const b = await chromium.launch();
  let problems = 0;
  for (const w of widths) {
    const p = await table(b, w);
    const ids = (await state(p)).map((c) => c.id);
    const lines = [];
    for (const pick of [[], [4], [4, 5], [3, 4, 5]]) {
      for (const i of pick) await toggle(p, ids[i]);
      const s = await state(p);
      const hidden = s.filter((c) => !c.visible).map((c) => c.id);
      const baseTop = Math.max(...s.filter((c) => !c.sel).map((c) => c.top));
      const lifted = s.filter((c) => c.sel).every((c) => baseTop - c.top >= 10);
      const minExp = Math.min(...s.slice(0, -1).map((c) => c.exposed));
      const clear = Math.min(...s.map((c) => c.clear));
      const ok = hidden.length === 0 && lifted && s.filter((c) => c.sel).length === pick.length && clear >= 0;
      if (!ok) problems++;
      lines.push(`  chọn[${pick.map((i) => ids[i]).join(" ")}] ${ok ? "OK" : "PROBLEM"} minLộ=${minExp}px che=[${hidden}] nhấc=${lifted} khoảngTrên=${Math.round(clear)}px`);
      if (pick.length) await p.locator("#hand").screenshot({ path: `${OUT}/m4-hand-${w}-${pick.length}.png` });
      for (const i of pick) await toggle(p, ids[i]);   // unselect again
    }
    // every card can be picked by its exposed strip
    const fails = [];
    for (const id of ids) { if (!(await toggle(p, id))) fails.push(id); else await toggle(p, id); }
    if (fails.length) problems++;
    console.log(`${w}px: ${ids.length} lá, bấm từng lá: ${fails.length ? "LỖI " + fails : "đúng cả " + ids.length}`);
    lines.forEach((l) => console.log(l));
    await p.click("#leave").catch(() => {});
    await p.close();
  }
  await b.close();
  console.log(problems ? `\n${problems} vấn đề` : "\nKhông có vấn đề");
})().catch((e) => { console.error("ERR", e.message); process.exit(1); });
