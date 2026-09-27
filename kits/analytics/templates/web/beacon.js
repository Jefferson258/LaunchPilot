// Minimal, privacy-friendly first-party pageview/event beacon.
// No cookies, no third-party requests, no fingerprinting. Copy into a site's
// `public/` (or import as a module — both forms are provided below) and load
// on every page.
//
// Default mode is "console" — logs to the browser console and an in-memory
// buffer (`window.__analyticsBeacon.events`) so it's testable with zero
// backend. Set `data-endpoint="/api/analytics"` on the <script> tag (or pass
// `endpoint` to `createBeacon`) to POST events as `navigator.sendBeacon` /
// `fetch(..., {keepalive:true})` JSON instead, once a site actually has an
// endpoint to receive them (not required to test this file).
//
// Naming convention matches LaunchPilot/docs/ANALYTICS.md §4: lowercase
// snake_case event names, flat scalar params, no PII.

const EVENT_NAME_PATTERN = /^[a-z][a-z0-9_]{1,39}$/;
const PARAM_KEY_PATTERN = /^[a-z][a-z0-9_]{0,39}$/;

function isValidEventName(name) {
  return typeof name === "string" && EVENT_NAME_PATTERN.test(name);
}

function sanitizeParams(params) {
  const clean = {};
  if (!params) return clean;
  for (const [key, value] of Object.entries(params)) {
    if (!PARAM_KEY_PATTERN.test(key)) continue;
    if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
      clean[key] = value;
    }
  }
  return clean;
}

/**
 * @param {{ endpoint?: string, logToConsole?: boolean, maxBufferedEvents?: number, transport?: (url: string, body: string) => void }} [options]
 */
function createBeacon(options = {}) {
  const {
    endpoint = null,
    logToConsole = true,
    maxBufferedEvents = 200,
    transport = defaultTransport,
  } = options;

  const events = [];

  function track(name, params = {}) {
    if (!isValidEventName(name)) {
      if (logToConsole) console.warn(`[analytics-beacon] invalid event name: ${name}`);
      return false;
    }
    const event = {
      name,
      params: sanitizeParams(params),
      timestamp: new Date().toISOString(),
      path: typeof location !== "undefined" ? location.pathname : undefined,
    };
    events.push(event);
    if (events.length > maxBufferedEvents) events.shift();

    if (logToConsole) console.log("[analytics-beacon]", event.name, event.params);
    if (endpoint) transport(endpoint, JSON.stringify(event));
    return true;
  }

  function pageview(path) {
    return track("page_view", path ? { path } : {});
  }

  return { track, pageview, events };
}

function defaultTransport(url, body) {
  if (typeof navigator !== "undefined" && navigator.sendBeacon) {
    navigator.sendBeacon(url, body);
    return;
  }
  if (typeof fetch !== "undefined") {
    fetch(url, { method: "POST", body, keepalive: true, headers: { "Content-Type": "application/json" } }).catch(() => {});
  }
}

// Browser <script> tag usage: reads its own data-* attributes and installs
// `window.analytics` + `window.__analyticsBeacon` (buffer, for debugging/QA).
if (typeof window !== "undefined" && typeof document !== "undefined") {
  const currentScript = document.currentScript;
  const endpoint = currentScript?.dataset?.endpoint || null;
  const beacon = createBeacon({ endpoint });
  window.analytics = { track: beacon.track, pageview: beacon.pageview };
  window.__analyticsBeacon = beacon;
  beacon.pageview();
}

export { createBeacon, isValidEventName, sanitizeParams };
