import { test } from "node:test"
import assert from "node:assert/strict"
import { loadQmlJs } from "./load.mjs"

const M = loadQmlJs(new URL("../Metrics.js", import.meta.url).pathname)

const STAT = "cpu  100 0 50 800 20 0 0 0 0 0\ncpu0 10 0 5 80 2 0 0 0 0 0\n"
const MEMINFO = "MemTotal:       32000000 kB\nMemFree:         1000000 kB\nMemAvailable:   24000000 kB\n"
const ROUTE = [
  "Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask",
  "wlan0\t0000FEA9\t00000000\t0001\t0\t0\t1000\t0000FFFF",
  "enp5s0\t00000000\t0101A8C0\t0003\t0\t0\t100\t00000000",
].join("\n")

test("parseCpuSample sums every bucket and separates idle", () => {
  assert.deepEqual(M.parseCpuSample(STAT), { busy: 150, total: 970 })
})

test("parseCpuSample rejects text that is not /proc/stat", () => {
  assert.equal(M.parseCpuSample("something else\n"), null)
})

test("cpuPercent is unknown without a baseline", () => {
  assert.equal(M.cpuPercent(null, { busy: 10, total: 100 }), -1)
})

test("cpuPercent is unknown when the counter has not advanced", () => {
  assert.equal(M.cpuPercent({ busy: 10, total: 100 }, { busy: 10, total: 100 }), -1)
})

test("cpuPercent is the busy share of the delta", () => {
  assert.equal(M.cpuPercent({ busy: 10, total: 100 }, { busy: 60, total: 200 }), 50)
})

test("cpuPercent clamps to 0..100", () => {
  assert.equal(M.cpuPercent({ busy: 0, total: 100 }, { busy: 500, total: 200 }), 100)
})

test("parseMem reports used share and absolute kB", () => {
  const mem = M.parseMem(MEMINFO)
  assert.equal(mem.totalKb, 32000000)
  assert.equal(mem.usedKb, 8000000)
  assert.equal(mem.percent, 25)
})

test("parseMem rejects a file missing MemAvailable", () => {
  assert.equal(M.parseMem("MemTotal: 32000000 kB\n"), null)
})

test("parseTempMilli converts millidegrees to celsius", () => {
  assert.equal(M.parseTempMilli("48250\n"), 48)
})

test("parseTempMilli treats a zero or empty reading as unknown", () => {
  assert.equal(M.parseTempMilli("0"), -1)
  assert.equal(M.parseTempMilli(""), -1)
})

test("parseSensorPaths picks cpu and gpu regardless of order", () => {
  const out = "gpu /sys/class/hwmon/hwmon2/temp1_input\ncpu /sys/class/hwmon/hwmon0/temp1_input\n"
  assert.deepEqual(M.parseSensorPaths(out), {
    cpu: "/sys/class/hwmon/hwmon0/temp1_input",
    gpu: "/sys/class/hwmon/hwmon2/temp1_input",
  })
})

test("parseSensorPaths keeps the first match and ignores junk lines", () => {
  const out = "cpu /a\nnonsense\ncpu /b\n"
  assert.deepEqual(M.parseSensorPaths(out), { cpu: "/a", gpu: "" })
})

test("parseDefaultIface finds the 00000000 destination, not the header", () => {
  assert.equal(M.parseDefaultIface(ROUTE), "enp5s0")
})

test("parseDefaultIface returns empty when there is no default route", () => {
  assert.equal(M.parseDefaultIface("Iface\tDestination\n"), "")
})

test("rate is bytes per second", () => {
  assert.equal(M.rate(1000, 3000, 2), 1000)
})

test("rate is unknown without a previous reading", () => {
  assert.equal(M.rate(-1, 3000, 2), -1)
})

test("rate treats a counter reset as unknown, not a spike", () => {
  assert.equal(M.rate(5000, 100, 2), -1)
})

test("rate is unknown when no time has passed", () => {
  assert.equal(M.rate(1000, 3000, 0), -1)
})

test("pushSample appends and drops the oldest past the limit", () => {
  assert.deepEqual(M.pushSample([1, 2, 3], 4, 3), [2, 3, 4])
  assert.deepEqual(M.pushSample([], 1, 3), [1])
})
