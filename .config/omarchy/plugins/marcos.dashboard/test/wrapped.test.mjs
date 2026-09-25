import { test } from "node:test"
import assert from "node:assert/strict"
import { loadQmlJs } from "./load.mjs"

const W = loadQmlJs(new URL("../Wrapped.js", import.meta.url).pathname)

test("fmtMinutes splits hours and minutes", () => {
  assert.equal(W.fmtMinutes(312), "5 h 12 min")
  assert.equal(W.fmtMinutes(44), "44 min")
  assert.equal(W.fmtMinutes(0), "0 min")
  assert.equal(W.fmtMinutes(120), "2 h")
})

test("fmtMinutes rejects what is not a duration", () => {
  assert.equal(W.fmtMinutes(null), "--")
  assert.equal(W.fmtMinutes(-5), "--")
  assert.equal(W.fmtMinutes(NaN), "--")
})

test("fmtCount groups thousands with dots", () => {
  assert.equal(W.fmtCount(8123), "8.123")
  assert.equal(W.fmtCount(1234567), "1.234.567")
  assert.equal(W.fmtCount(999), "999")
  assert.equal(W.fmtCount(undefined), "--")
})

test("tier names and colours cover one to four, nothing else", () => {
  assert.deepEqual([1, 2, 3, 4].map(W.tierName), ["bronce", "plata", "oro", "diamante"])
  assert.equal(W.tierName(0), "")
  assert.equal(W.tierName(5), "")
  assert.equal(W.tierColor(3), "#f9e2af")
  assert.equal(W.tierColor(0), "")
})

test("fmtDay is short spanish", () => {
  assert.equal(W.fmtDay("2026-09-20"), "20 sep")
  assert.equal(W.fmtDay(null), "")
  assert.equal(W.fmtDay("garbage"), "")
})

test("parseToday keeps the top three apps", () => {
  const apps = [1, 2, 3, 4].map(i => ({ name: "a" + i, minutes: 10 * i, icon: "x" }))
  const today = W.parseToday(JSON.stringify({ active_minutes: 312, keys: 8123, top_apps: apps }))
  assert.equal(today.activeMinutes, 312)
  assert.equal(today.keys, 8123)
  assert.equal(today.apps.length, 3)
  assert.equal(today.apps[0].name, "a1")
})

test("parseToday hides on empty, broken or foreign output", () => {
  assert.equal(W.parseToday(""), null)
  assert.equal(W.parseToday("command not found"), null)
  assert.equal(W.parseToday("{}"), null)
})

test("parseDashboard surfaces the first health message only when unhealthy", () => {
  const bad = W.parseDashboard(JSON.stringify({ health: { ok: false, messages: ["uno", "dos"] } }))
  assert.equal(bad.healthOk, false)
  assert.equal(bad.healthMessage, "uno")
  assert.equal(bad.stat, null)
  assert.equal(W.parseDashboard(JSON.stringify({ health: { ok: true, messages: [] } })).healthOk, true)
  assert.equal(W.parseDashboard("nope"), null)
})

test("share is clamped to the unit interval", () => {
  assert.equal(W.share(140, 312), 140 / 312)
  assert.equal(W.share(500, 312), 1)
  assert.equal(W.share(10, 0), 0)
})
