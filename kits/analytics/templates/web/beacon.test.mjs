// Runnable, no-network verification for beacon.js: `node beacon.test.mjs`
// Uses Node's built-in test runner (Node 18+), no install required.
import test from "node:test";
import assert from "node:assert/strict";
import { createBeacon, isValidEventName, sanitizeParams } from "./beacon.js";

test("accepts snake_case event names", () => {
  assert.equal(isValidEventName("page_view"), true);
  assert.equal(isValidEventName("cta_click"), true);
});

test("rejects bad event names", () => {
  assert.equal(isValidEventName("PageView"), false);
  assert.equal(isValidEventName("page view"), false);
  assert.equal(isValidEventName(""), false);
});

test("sanitizeParams drops invalid keys and non-scalar values", () => {
  const cleaned = sanitizeParams({ path: "/home", nested: { a: 1 }, "Bad Key": "x", count: 3 });
  assert.deepEqual(cleaned, { path: "/home", count: 3 });
});

test("createBeacon buffers valid events and rejects invalid ones", () => {
  const beacon = createBeacon({ logToConsole: false });
  assert.equal(beacon.track("cta_click", { label: "signup" }), true);
  assert.equal(beacon.track("Not Valid"), false);
  assert.equal(beacon.events.length, 1);
  assert.equal(beacon.events[0].name, "cta_click");
  assert.equal(beacon.events[0].params.label, "signup");
});

test("createBeacon caps buffered events at maxBufferedEvents", () => {
  const beacon = createBeacon({ logToConsole: false, maxBufferedEvents: 3 });
  for (let i = 0; i < 10; i++) beacon.track("page_view", { i });
  assert.equal(beacon.events.length, 3);
  assert.deepEqual(beacon.events.map((e) => e.params.i), [7, 8, 9]);
});

test("createBeacon calls transport only when an endpoint is configured", () => {
  const calls = [];
  const withEndpoint = createBeacon({
    logToConsole: false,
    endpoint: "/api/analytics",
    transport: (url, body) => calls.push([url, body]),
  });
  withEndpoint.track("page_view");
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], "/api/analytics");

  const withoutEndpoint = createBeacon({ logToConsole: false, transport: (url, body) => calls.push([url, body]) });
  withoutEndpoint.track("page_view");
  assert.equal(calls.length, 1); // unchanged — no transport call without an endpoint
});
