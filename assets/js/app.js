import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import PetalComponents from "petal_components/assets/js/petal_components"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  ?.getAttribute("content")

const StickyTitle = {
  mounted() {
    this.target = document.getElementById("sticky-page-title")
    if (!this.target) return

    const title =
      this.el.dataset.stickyTitle || this.el.textContent.trim()

    this.observer = new IntersectionObserver(
      ([entry]) => {
        if (!this.target) return
        if (entry.isIntersecting) {
          this.target.textContent = ""
          this.target.hidden = true
          this.target.setAttribute("aria-hidden", "true")
          this.target.classList.remove("isomer-sticky-title--visible")
        } else {
          this.target.textContent = title
          this.target.hidden = false
          this.target.setAttribute("aria-hidden", "false")
          // Next frame so opacity transition runs.
          requestAnimationFrame(() => {
            this.target?.classList.add("isomer-sticky-title--visible")
          })
        }
      },
      {
        // Hide sticky title while the page H1 is still under the app header.
        root: null,
        rootMargin: "-72px 0px 0px 0px",
        threshold: 0,
      }
    )

    this.observer.observe(this.el)
  },

  destroyed() {
    this.observer?.disconnect()
    if (this.target) {
      this.target.textContent = ""
      this.target.hidden = true
      this.target.setAttribute("aria-hidden", "true")
      this.target.classList.remove("isomer-sticky-title--visible")
    }
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { ...PetalComponents, StickyTitle },
})

liveSocket.connect()
window.liveSocket = liveSocket
