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

// Small UI-only hooks (no game logic, CLAUDE.md rule 2)
const Hooks = {
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

