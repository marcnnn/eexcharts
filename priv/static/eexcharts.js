/*
 * EexCharts LiveView hook — the only client-side JS in the library.
 *
 * Every tooltip is rendered server-side into `.eexcharts-tip` divs; this
 * hook just picks which one is visible and positions the tooltip box next
 * to the cursor. Uses event delegation on the container, so it survives
 * LiveView re-renders without rebinding.
 */
const EexCharts = {
  mounted() {
    this.activeIndex = null;

    this.onMove = (e) => {
      const target = e.target.closest("[data-j]");
      if (!target || !this.el.contains(target)) return this.deactivate();
      this.activate(target.dataset.j, target);
      this.positionTip(e);
    };
    this.onLeave = () => this.deactivate();

    this.el.addEventListener("pointermove", this.onMove);
    this.el.addEventListener("pointerleave", this.onLeave);
  },

  destroyed() {
    this.el.removeEventListener("pointermove", this.onMove);
    this.el.removeEventListener("pointerleave", this.onLeave);
  },

  tooltip() {
    return this.el.querySelector(".eexcharts-tooltip");
  },

  activate(j, target) {
    if (this.activeIndex === j) return;
    this.activeIndex = j;

    const tip = this.tooltip();
    if (tip) {
      tip.querySelectorAll(".eexcharts-tip").forEach((t) => {
        t.hidden = t.dataset.j !== j;
      });
      tip.classList.add("eexcharts-tooltip-active");
    }

    // Crosshair follows the hovered category (cartesian charts only).
    const cross = this.el.querySelector(".eexcharts-crosshair");
    if (cross) {
      const { cx, cy } = target.dataset;
      if (cx) {
        cross.setAttribute("x1", cx);
        cross.setAttribute("x2", cx);
        cross.style.opacity = 1;
      } else if (cy) {
        cross.setAttribute("y1", cy);
        cross.setAttribute("y2", cy);
        cross.style.opacity = 1;
      }
    }

    this.el.querySelectorAll(".eexcharts-hover-marker").forEach((m) => {
      m.classList.toggle("active", m.dataset.j === j);
    });

    const pushEvent = this.el.dataset.pushHover;
    if (pushEvent) {
      this.pushEvent(pushEvent, { id: this.el.id, index: parseInt(j, 10) });
    }
  },

  deactivate() {
    if (this.activeIndex === null) return;
    this.activeIndex = null;

    const tip = this.tooltip();
    if (tip) tip.classList.remove("eexcharts-tooltip-active");

    const cross = this.el.querySelector(".eexcharts-crosshair");
    if (cross) cross.style.opacity = 0;

    this.el
      .querySelectorAll(".eexcharts-hover-marker.active")
      .forEach((m) => m.classList.remove("active"));
  },

  positionTip(e) {
    const tip = this.tooltip();
    if (!tip) return;

    const bounds = this.el.getBoundingClientRect();
    let x = e.clientX - bounds.left + 12;
    let y = e.clientY - bounds.top - 10;

    // Keep the tooltip inside the chart container.
    const tw = tip.offsetWidth;
    const th = tip.offsetHeight;
    if (x + tw > bounds.width) x = e.clientX - bounds.left - tw - 12;
    if (y + th > bounds.height) y = bounds.height - th;
    if (y < 0) y = 0;

    tip.style.transform = `translate(${x}px, ${y}px)`;
  },
};

export default EexCharts;
