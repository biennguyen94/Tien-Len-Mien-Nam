// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/tien_len"
import topbar from "../vendor/topbar"

// SF1: sounds made with Web Audio (no files). The server decides *which* effect happens;
// this only plays it. Muting is a per-device choice (SF2).
const Sound = {
  ctx: null,
  muted() { try { return localStorage.getItem("tl-muted") === "1" } catch (_) { return false } },
  setMuted(m) { try { localStorage.setItem("tl-muted", m ? "1" : "0") } catch (_) {} },
  audio() {
    if (!this.ctx) {
      const AC = window.AudioContext || window.webkitAudioContext
      if (!AC) return null
      this.ctx = new AC()
    }
    if (this.ctx.state === "suspended") this.ctx.resume()
    return this.ctx
  },
  tone(type, freqs, dur, vol = 0.15, at = 0) {
    const c = this.audio(); if (!c) return
    const t = c.currentTime + at, o = c.createOscillator(), g = c.createGain()
    o.type = type
    freqs.forEach(([f, when], i) => i === 0 ? o.frequency.setValueAtTime(f, t) : o.frequency.linearRampToValueAtTime(f, t + when))
    g.gain.setValueAtTime(vol, t)
    g.gain.exponentialRampToValueAtTime(0.001, t + dur)
    o.connect(g).connect(c.destination)
    o.start(t); o.stop(t + dur)
  },
  noise(dur, vol = 0.5) {
    const c = this.audio(); if (!c) return
    const buf = c.createBuffer(1, c.sampleRate * dur, c.sampleRate), d = buf.getChannelData(0)
    for (let i = 0; i < d.length; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / d.length)
    const src = c.createBufferSource(), f = c.createBiquadFilter(), g = c.createGain(), t = c.currentTime
    src.buffer = buf
    f.type = "lowpass"; f.frequency.setValueAtTime(1200, t); f.frequency.exponentialRampToValueAtTime(80, t + dur)
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.001, t + dur)
    src.connect(f).connect(g).connect(c.destination)
    src.start(t)
  },
  play(kind) {
    if (this.muted()) return
    if (kind === "pig") {            // "éc éc"
      for (const at of [0, 0.22]) this.tone("sawtooth", [[700, 0], [1300, 0.06], [900, 0.16]], 0.18, 0.12, at)
    } else if (kind === "chop") {    // bang
      this.noise(0.6)
      this.tone("sine", [[110, 0], [40, 0.4]], 0.5, 0.5)
    } else if (kind === "confetti") { // fanfare
      [523, 659, 784, 1047].forEach((f, i) => this.tone("triangle", [[f, 0]], 0.3, 0.18, i * 0.12))
    } else if (kind === "tick") {
      this.tone("square", [[1500, 0]], 0.04, 0.06)
    }
  },
}

const reduceMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches

function shake() {
  const el = document.querySelector("[data-shake]")
  if (!el || reduceMotion()) return
  el.classList.remove("shake"); void el.offsetWidth; el.classList.add("shake")
}

function confetti() {
  if (reduceMotion()) return
  const colors = ["#ef4444", "#f59e0b", "#10b981", "#3b82f6", "#a855f7", "#ec4899"]
  for (let i = 0; i < 70; i++) {
    const p = document.createElement("span")
    const size = 6 + Math.random() * 6
    Object.assign(p.style, {position: "fixed", top: "-12px", left: `${Math.random() * 100}vw`,
      width: `${size}px`, height: `${size * 0.6}px`, background: colors[i % colors.length],
      zIndex: 60, pointerEvents: "none"})
    document.body.appendChild(p)
    const dx = (Math.random() - 0.5) * 200, rot = Math.random() * 720
    p.animate([{transform: "translate(0, 0) rotate(0deg)"},
               {transform: `translate(${dx}px, 105vh) rotate(${rot}deg)`}],
      {duration: 1800 + Math.random() * 1400, delay: Math.random() * 400, easing: "ease-in"})
      .onfinish = () => p.remove()
  }
}

// Small UI-only hooks (no game logic, CLAUDE.md rule 2)
const Hooks = {
  // SF1/SF2: the 🔊 button plays the effects the server pushes, and remembers muting
  Sfx: {
    mounted() {
      const label = () => { this.el.textContent = Sound.muted() ? "🔇" : "🔊"; this.el.title = Sound.muted() ? "Bật âm thanh" : "Tắt âm thanh" }
      label()
      this.el.addEventListener("click", () => { Sound.setMuted(!Sound.muted()); label(); Sound.audio() })
      // browsers only allow sound after a user gesture
      this.unlock = () => Sound.audio()
      window.addEventListener("pointerdown", this.unlock, {once: true})
      this.handleEvent("sfx", ({kinds}) => {
        for (const k of kinds) {
          Sound.play(k)
          if (k === "chop") shake()
          if (k === "confetti") confetti()
        }
      })
    },
    destroyed() { window.removeEventListener("pointerdown", this.unlock) },
  },
  // keeps a chat list scrolled to the newest message
  ChatScroll: {
    mounted() { this.el.scrollTop = this.el.scrollHeight },
    updated() { this.el.scrollTop = this.el.scrollHeight },
  },
  // TH1: a thrown item flies from one seat to another (looks only; the server already
  // checked and charged the throw and draws the mark on the target seat)
  Throws: {
    mounted() {
      this.handleEvent("throw", ({from, to, emoji}) => {
        const a = document.getElementById(from), b = document.getElementById(to)
        if (!a || !b || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
        const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect()
        const x0 = ra.left + ra.width / 2, y0 = ra.top + ra.height / 2
        const dx = rb.left + rb.width / 2 - x0, dy = rb.top + rb.height / 2 - y0
        const el = document.createElement("span")
        el.textContent = emoji
        el.setAttribute("aria-hidden", "true")
        Object.assign(el.style, {position: "fixed", left: `${x0 - 16}px`, top: `${y0 - 16}px`,
          fontSize: "2rem", lineHeight: "1", zIndex: 60, pointerEvents: "none"})
        document.body.appendChild(el)
        const arc = Math.min(-60, dy / 2 - 60)
        el.animate([
          {transform: "translate(0, 0) rotate(0deg) scale(0.8)"},
          {transform: `translate(${dx / 2}px, ${arc}px) rotate(360deg) scale(1.3)`},
          {transform: `translate(${dx}px, ${dy}px) rotate(720deg) scale(1)`},
        ], {duration: 700, easing: "ease-in-out"}).onfinish = () => el.remove()
      })
    },
  },
  // "Chép link" (G10): copies data-url to the clipboard
  CopyLink: {
    mounted() {
      this.el.addEventListener("click", () => {
        const done = () => {
          const label = this.el.textContent
          this.el.textContent = "Đã chép!"
          setTimeout(() => { this.el.textContent = label }, 1500)
        }
        if (navigator.clipboard) {
          navigator.clipboard.writeText(this.el.dataset.url).then(done, () => window.prompt("Link phòng:", this.el.dataset.url))
        } else {
          window.prompt("Link phòng:", this.el.dataset.url)
        }
      })
    },
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

