// usage: node audit.js <label>   → measures horizontal overflow on every page at 4 widths
const { chromium } = require("playwright");
const fs = require("fs");
const B = process.env.BASE || "http://localhost:4010";
const OUT = process.env.OUT || "/tmp/shots";
const label = process.argv[2] || "run";
const widths = (process.env.WIDTHS || "360,390,412,1280").split(",").map(Number);
fs.mkdirSync(`${OUT}/${label}`, { recursive: true });

async function login(page, user) {
  await page.goto(B + "/");
  await page.fill("#login-form input[name='user[username]']", user);
  await page.fill("#login-form input[name='user[password]']", "mat-khau-123");
  await Promise.all([page.waitForNavigation(), page.click("#login-form button[type=submit]")]);
}
async function ready(page) {
  await page.waitForSelector("[data-phx-main].phx-connected", { timeout: 10000 }).catch(() => {});
  await page.waitForTimeout(300);
}
async function measure(page) {
  return page.evaluate(() => {
    const vw = document.documentElement.clientWidth;
    const bad = [];
    for (const el of document.querySelectorAll("body *")) {
      const r = el.getBoundingClientRect();
      if (r.width === 0 || r.right <= vw + 1) continue;
      const cs = getComputedStyle(el);
      if (cs.position === "fixed" && r.left >= vw) continue;
      // skip children of an element already reported
      if (bad.some((b) => b.el.contains(el))) continue;
      // skip elements inside a horizontally scrollable container
      let p = el.parentElement, scroll = false;
      while (p) { const s = getComputedStyle(p); if ((s.overflowX === "auto" || s.overflowX === "scroll" || s.overflowX === "hidden") && p.getBoundingClientRect().right <= vw + 1) { scroll = true; break; } p = p.parentElement; }
      if (scroll) continue;
      bad.push({ el, d: `${el.tagName.toLowerCase()}${el.id ? "#" + el.id : ""}${el.className && typeof el.className === "string" ? "." + el.className.trim().split(/\s+/).slice(0, 3).join(".") : ""} right=${Math.round(r.right)}` });
    }
    const inner = [...document.querySelectorAll(".overflow-x-auto")]
      .filter((e) => e.scrollWidth > e.clientWidth + 1)
      .map((e) => `scrollbox(${(e.querySelector("[id]") || e).id}) ${e.scrollWidth}/${e.clientWidth}`);
    return { scroll: document.documentElement.scrollWidth, vw, bad: bad.slice(0, 6).map((b) => b.d), inner };
  });
}

(async () => {
  const browser = await chromium.launch();
  const results = [];
  for (const w of widths) {
    const ctx = await browser.newContext({ viewport: { width: w, height: 800 }, deviceScaleFactor: 1 });
    const page = await ctx.newPage();
    // logged out
    await page.goto(B + "/"); await ready(page);
    results.push(await snap(page, w, "lobby-logged-out"));
    await login(page, "ui_ben");
    const pages = ["/", "/bang-xep-hang", "/bang-xep-hang?tab=tuan", "/bang-xep-hang?tab=giau", "/lich-su", "/lich-su-coin",
      "/nguoi-choi/ui_ben", "/nguoi-choi/ui_an", "/ban-be", "/quan-tri", "/quan-tri/nguoi-choi", "/quan-tri/phong",
      "/quan-tri/van", "/quan-tri/nhat-ky", "/quan-tri/cai-dat"];
    for (const path of pages) { await page.goto(B + path); await ready(page); results.push(await snap(page, w, path)); }
    // admin user page + replay
    await page.goto(B + "/quan-tri/nguoi-choi?q=ui_an"); await ready(page);
    const uhref = await page.getAttribute("#admin-users a[href*='/quan-tri/nguoi-choi/'], a[href*='/quan-tri/nguoi-choi/']", "href").catch(() => null);
    if (uhref) { await page.goto(B + uhref); await ready(page); results.push(await snap(page, w, "/quan-tri/nguoi-choi/:id")); }
    await page.goto(B + "/lich-su"); await ready(page);
    const rhref = await page.getAttribute("a[id^=replay-]", "href").catch(() => null);
    if (rhref) { await page.goto(B + rhref); await ready(page); results.push(await snap(page, w, "/van/:id")); }
    // header menu open (if there is one)
    await page.goto(B + "/"); await ready(page);
    const menu = await page.$("#nav-menu-toggle");
    if (menu && await menu.isVisible()) { await menu.click(); await page.waitForTimeout(200); results.push(await snap(page, w, "menu-open")); }
    // table: create room, add bot, start game
    await page.goto(B + "/"); await ready(page);
    await Promise.all([page.waitForURL(/\/phong\//), page.click("#create-room")]);
    await ready(page);
    const roomUrl = page.url();
    results.push(await snap(page, w, "table-waiting"));
    await page.click("#add-bot-normal"); await page.waitForTimeout(200);
    await page.click("#add-bot-easy"); await page.waitForTimeout(200);
    await page.click("#start"); await page.waitForTimeout(600);
    results.push(await snap(page, w, "table-playing"));
    // spectator (another user)
    const ctx2 = await browser.newContext({ viewport: { width: w, height: 800 } });
    const p2 = await ctx2.newPage(); await login(p2, "ui_chi");
    await p2.goto(roomUrl + "/xem"); await ready(p2);
    results.push(await snap(p2, w, "spectate"));
    await ctx2.close();
    await page.click("#leave").catch(() => {});
    await ctx.close();
  }
  await browser.close();
  let fails = 0;
  for (const r of results) {
    const ok = r.scroll <= r.vw && r.bad.length === 0;
    if (!ok) fails++;
    console.log(`${ok ? "OK  " : "OVER"} ${String(r.w).padEnd(4)} ${r.name.padEnd(28)} scroll=${r.scroll}/${r.vw} ${r.bad.join(" | ")} ${r.inner.join(" ")}`);
  }
  console.log(`\n${results.length - fails}/${results.length} OK`);

  async function snap(page, w, name) {
    const m = await measure(page);
    const file = `${OUT}/${label}/${name.replace(/[\/?:=]+/g, "_").replace(/^_/, "") || "root"}-${w}.png`;
    await page.screenshot({ path: file, fullPage: true });
    return { w, name, ...m };
  }
})().catch((e) => { console.error("ERR", e.message); process.exit(1); });
