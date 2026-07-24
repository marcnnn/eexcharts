// Dev/test-only storybook JS (served straight from source by Dev.Endpoint, no
// bundler). Loaded as an ES module so it can import the published EexCharts
// hook verbatim plus the Phoenix/LiveView ESM builds, then hand them to
// phoenix_storybook via `window.storybook`. This is what lets the catalog's
// LiveSocket connect and drive hover tooltips / legend toggles.
import { Socket } from "/vendor/phoenix/phoenix.mjs";
import { LiveSocket } from "/vendor/live_view/phoenix_live_view.esm.js";
import EexCharts from "/eexcharts/eexcharts.js";

window.storybook = {
  Hooks: { EexCharts },
  Phoenix: { Socket },
  LiveView: { LiveSocket },
};
