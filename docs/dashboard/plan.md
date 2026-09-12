# Omarchy Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A summoned full-screen overlay that answers "what is on today, what did I miss, how is the machine" in one glance, backed by a shared metrics service that the existing bar widgets also consume.

**Architecture:** Two new Quickshell plugins — `marcos.metrics` (`kind: "service"`, headless, owns every `/proc` and `/sys` reader) and `marcos.dashboard` (`kind: "overlay"`, `keepLoaded: false`, exists only while open). `marcos.sysmon` and `marcos.netspeed` become views over the service, keeping their current readers as a fallback. Calendar data arrives through local `.ics` files synced by `vdirsyncer` and queried by `khal`, never by talking to Google from inside the shell.

**Tech Stack:** QML / Quickshell, plain JS for testable logic, Python 3 (stdlib only) for `omarchy-agenda`, `deno test` as the test runner, systemd user timers, `vdirsyncer` + `khal` from Arch `extra`.

**Spec:** `docs/dashboard/design.md`

## Global Constraints

- **Files live in `~/dotfiles/` and are symlinked into `~/.config/`.** Never edit through the symlink; `readlink -f` first. New plugin directories go in `~/dotfiles/.config/omarchy/plugins/<id>/` with a symlink at `~/.config/omarchy/plugins/<id>`.
- **`OMARCHY_PATH` must be the literal string `/usr/share/omarchy`** for any `omarchy` command. `qs ipc` matches instances by the literal `-p` string, so the symlinked path makes every call fail with "omarchy-shell is not running".
- **A new plugin needs `omarchy restart shell`, not `rescanPlugins`.** Rescan only reloads code for plugins already loaded. Same for editing a `property var` that builds an object.
- **Zero subprocesses in polling loops.** Read `/proc` and `/sys` through `FileView`. A process is allowed once at startup, or once per user-initiated open.
- **Resolve hardware by name or label, never by index.** hwmon numbering is assigned at boot and reorders.
- **Colours are fixed Catppuccin Mocha cluster values:** identity `#cba6f7`, resources `#a6e3a1`, devices `#94e2d5`, context `#89b4fa`, tools `#fab387`.
- **Code comments in English.** No multi-line docstrings. No comments restating what the code says.
- **Python via `uv`, never `pip`.** `omarchy-agenda` uses only the standard library, so it needs neither.
- **Ask before every `git commit` and `git push`.** The commit steps below are written out, but the user approves each one.
- **Never run `omarchy theme set`** from a script — it cycles the background and retriggers the wallpaper watcher. Use `omarchy theme refresh` plus the `applyTheme` IPC.

---

### Task 1: Testable metrics logic

Everything that parses text or does arithmetic lives in a plain `.js` file with no QML dependency, so it can be tested outside the shell. Headless QML does not run in this environment (`qml` and `qmltestrunner` both exit silently), so this separation is the only way any of this gets real tests.

**Files:**
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.metrics/Metrics.js`
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.metrics/test/load.mjs`
- Test: `~/dotfiles/.config/omarchy/plugins/marcos.metrics/test/metrics.test.mjs`

**Interfaces:**
- Consumes: nothing.
- Produces, all pure functions on the `Metrics` namespace:
  - `parseCpuSample(text) -> {busy: Number, total: Number} | null`
  - `cpuPercent(prev, cur) -> Number` (`-1` when unknown)
  - `parseMem(text) -> {percent: Number, usedKb: Number, totalKb: Number} | null`
  - `parseTempMilli(text) -> Number` (celsius, `-1` when unknown)
  - `parseSensorPaths(stdout) -> {cpu: String, gpu: String}`
  - `parseDefaultIface(routeText) -> String` (`""` when none)
  - `rate(prevBytes, curBytes, elapsedSeconds) -> Number` (`-1` when unknown or counter reset)
  - `pushSample(buffer, value, limit) -> Array`

- [ ] **Step 1: Write the test harness**

QML `.js` files are not ES modules, so the harness strips the `.pragma library` directive and evaluates the source, returning every top-level function. This keeps one copy of the logic: QML imports the file natively, the tests read the same bytes.

```javascript
// test/load.mjs
import { readFileSync } from "node:fs"

export function loadQmlJs(path) {
  const src = readFileSync(path, "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "")
  const names = [...src.matchAll(/^function\s+([A-Za-z_$][\w$]*)/gm)].map(m => m[1])
  return new Function(`${src}\nreturn { ${names.join(", ")} }`)()
}
```

- [ ] **Step 2: Write the failing tests**

The cases are the ones that actually bite: a first sample with no baseline, a counter that went backwards because the interface was reinitialised, a `/proc/stat` line that has not advanced, and hwmon output listing sensors in an order that is not ours.

```javascript
// test/metrics.test.mjs
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
  assert.deepEqual(M.parseCpuSample(STAT), { busy: 950, total: 970 })
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd ~/dotfiles/.config/omarchy/plugins/marcos.metrics && deno test --allow-read test/metrics.test.mjs`
Expected: FAIL — `Metrics.js` does not exist yet, so `loadQmlJs` throws ENOENT.

`deno` is used rather than `node` because it ships from `/usr/bin` via pacman, while node here comes from a mise toolchain that may not always be on PATH. `node --test test/metrics.test.mjs` works identically if preferred.

- [ ] **Step 4: Write the implementation**

```javascript
// Metrics.js
.pragma library

// /proc/stat is cumulative since boot, so usage is always a delta between two
// readings. idle + iowait are the two non-busy buckets.
function parseCpuSample(text) {
  var line = String(text || "").split("\n")[0]
  if (line.indexOf("cpu ") !== 0) return null
  var parts = line.trim().split(/\s+/)
  var total = 0
  for (var i = 1; i < parts.length; i++) total += Number(parts[i]) || 0
  var idle = (Number(parts[4]) || 0) + (Number(parts[5]) || 0)
  return { busy: total - idle, total: total }
}

function cpuPercent(prev, cur) {
  if (!prev || !cur || cur.total <= prev.total) return -1
  var value = (cur.busy - prev.busy) / (cur.total - prev.total) * 100
  return Math.max(0, Math.min(100, value))
}

function parseMem(text) {
  var raw = String(text || "")
  var total = raw.match(/MemTotal:\s+(\d+)/)
  var avail = raw.match(/MemAvailable:\s+(\d+)/)
  if (!total || !avail) return null
  var totalKb = Number(total[1])
  var availKb = Number(avail[1])
  if (!(totalKb > 0)) return null
  return {
    percent: (1 - availKb / totalKb) * 100,
    usedKb: totalKb - availKb,
    totalKb: totalKb
  }
}

function parseTempMilli(text) {
  var value = Number(String(text || "").trim())
  return isFinite(value) && value > 0 ? Math.round(value / 1000) : -1
}

// Sensors are resolved by hwmon name + temp label rather than by index, because
// hwmon numbering is assigned at boot and reorders between reboots.
function parseSensorPaths(stdout) {
  var result = { cpu: "", gpu: "" }
  var lines = String(stdout || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].trim().split(/\s+/)
    if (parts.length !== 2) continue
    if (parts[0] === "cpu" && result.cpu === "") result.cpu = parts[1]
    else if (parts[0] === "gpu" && result.gpu === "") result.gpu = parts[1]
  }
  return result
}

function parseDefaultIface(routeText) {
  var lines = String(routeText || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].trim().split(/\s+/)
    // Destination 00000000 is the default route.
    if (parts.length > 1 && parts[1] === "00000000" && parts[0] !== "Iface") return parts[0]
  }
  return ""
}

// Counters reset when an interface is reinitialised; a negative delta is a new
// baseline, not a spike worth reporting.
function rate(prevBytes, curBytes, elapsedSeconds) {
  if (prevBytes < 0 || curBytes < 0 || !(elapsedSeconds > 0)) return -1
  if (curBytes < prevBytes) return -1
  return (curBytes - prevBytes) / elapsedSeconds
}

function pushSample(buffer, value, limit) {
  var next = (buffer || []).concat([value])
  return next.length > limit ? next.slice(next.length - limit) : next
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd ~/dotfiles/.config/omarchy/plugins/marcos.metrics && deno test --allow-read test/metrics.test.mjs`
Expected: PASS, 18 tests.

- [ ] **Step 6: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .config/omarchy/plugins/marcos.metrics
git commit -m "feat(metrics): pure, tested logic for the shared metrics service"
```

---

### Task 2: The `marcos.metrics` service

**Files:**
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.metrics/manifest.json`
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.metrics/Service.qml`
- Create symlink: `~/.config/omarchy/plugins/marcos.metrics`

**Interfaces:**
- Consumes: `Metrics.js` from Task 1.
- Produces, as properties on the service object returned by `shell.serviceFor("marcos.metrics")`:
  - `cpuPercent`, `memPercent` — `real`, `-1` when unknown
  - `memUsedKb`, `memTotalKb` — `real`
  - `cpuTemp`, `gpuTemp` — `int` celsius, `-1` when unknown
  - `hottest` — `int`, the max of the two
  - `iface` — `string`, `""` when no default route
  - `rxRate`, `txRate` — `real` bytes/second, `-1` when unknown
  - `cpuHistory`, `memHistory`, `tempHistory`, `rxHistory`, `txHistory` — arrays of at most 60 numbers, oldest first

- [ ] **Step 1: Write the manifest**

```json
{
  "schemaVersion": 1,
  "id": "marcos.metrics",
  "name": "Metrics",
  "version": "1.0.0",
  "author": "marcos",
  "description": "Shared CPU, memory, temperature and network readings",
  "kinds": ["service"],
  "keepLoaded": true,
  "entryPoints": { "service": "Service.qml" }
}
```

- [ ] **Step 2: Write the service**

Two cadences on purpose: network counters need 2s to produce a readable rate, CPU and memory do not change usefully faster than 5s. Collapsing them into one timer would either over-read `/proc/stat` or make the network graph lumpy.

```qml
// Service.qml
import QtQuick
import Quickshell
import Quickshell.Io
import "Metrics.js" as Metrics

QtObject {
  id: root

  readonly property int historyLimit: 60

  property real cpuPercent: -1
  property real memPercent: -1
  property real memUsedKb: 0
  property real memTotalKb: 0
  property int cpuTemp: -1
  property int gpuTemp: -1
  readonly property int hottest: Math.max(cpuTemp, gpuTemp)

  property string iface: ""
  property real rxRate: -1
  property real txRate: -1

  property var cpuHistory: []
  property var memHistory: []
  property var tempHistory: []
  property var rxHistory: []
  property var txHistory: []

  property string cpuTempPath: ""
  property string gpuTempPath: ""

  property var prevCpu: null
  property real prevRx: -1
  property real prevTx: -1
  property real prevAt: 0
  property real lastResolveAt: 0

  function readSystem() {
    cpuStat.reload()
    var sample = Metrics.parseCpuSample(cpuStat.text())
    if (sample) {
      var percent = Metrics.cpuPercent(root.prevCpu, sample)
      if (percent >= 0) {
        root.cpuPercent = percent
        root.cpuHistory = Metrics.pushSample(root.cpuHistory, percent, root.historyLimit)
      }
      root.prevCpu = sample
    }

    memStat.reload()
    var mem = Metrics.parseMem(memStat.text())
    if (mem) {
      root.memPercent = mem.percent
      root.memUsedKb = mem.usedKb
      root.memTotalKb = mem.totalKb
      root.memHistory = Metrics.pushSample(root.memHistory, mem.percent, root.historyLimit)
    }

    if (root.cpuTempPath !== "") {
      cpuTempFile.reload()
      root.cpuTemp = Metrics.parseTempMilli(cpuTempFile.text())
    }
    if (root.gpuTempPath !== "") {
      gpuTempFile.reload()
      root.gpuTemp = Metrics.parseTempMilli(gpuTempFile.text())
    }
    if (root.hottest >= 0)
      root.tempHistory = Metrics.pushSample(root.tempHistory, root.hottest, root.historyLimit)
  }

  // Interfaces come and go (wifi down, dock plugged in). Re-resolving is cheap
  // but not free, so a failed read triggers at most one retry every 10s.
  function resolveIface() {
    var now = Date.now()
    if (now - root.lastResolveAt < 10000) return
    root.lastResolveAt = now

    routeFile.reload()
    var found = Metrics.parseDefaultIface(routeFile.text())
    if (found !== root.iface) {
      root.iface = found
      root.prevRx = -1
      root.prevTx = -1
    }
    if (found === "") {
      root.rxRate = -1
      root.txRate = -1
    }
  }

  function counter(view) {
    view.reload()
    var value = Number(String(view.text() || "").trim())
    return isFinite(value) ? value : -1
  }

  function readNetwork() {
    if (root.iface === "") {
      resolveIface()
      if (root.iface === "") return
    }

    var rx = counter(rxFile)
    var tx = counter(txFile)
    if (rx < 0 || tx < 0) {
      resolveIface()
      return
    }

    var now = Date.now()
    var elapsed = (now - root.prevAt) / 1000
    var rxValue = Metrics.rate(root.prevRx, rx, elapsed)
    var txValue = Metrics.rate(root.prevTx, tx, elapsed)
    if (rxValue >= 0) {
      root.rxRate = rxValue
      root.rxHistory = Metrics.pushSample(root.rxHistory, rxValue, root.historyLimit)
    }
    if (txValue >= 0) {
      root.txRate = txValue
      root.txHistory = Metrics.pushSample(root.txHistory, txValue, root.historyLimit)
    }
    root.prevRx = rx
    root.prevTx = tx
    root.prevAt = now
  }

  property list<QtObject> children: [
    FileView { id: cpuStat; path: "/proc/stat"; watchChanges: false; printErrors: false },
    FileView { id: memStat; path: "/proc/meminfo"; watchChanges: false; printErrors: false },
    FileView { id: routeFile; path: "/proc/net/route"; watchChanges: false; printErrors: false },
    FileView { id: cpuTempFile; path: root.cpuTempPath; watchChanges: false; printErrors: false },
    FileView { id: gpuTempFile; path: root.gpuTempPath; watchChanges: false; printErrors: false },
    FileView {
      id: rxFile
      path: root.iface === "" ? "" : "/sys/class/net/" + root.iface + "/statistics/rx_bytes"
      watchChanges: false
      printErrors: false
    },
    FileView {
      id: txFile
      path: root.iface === "" ? "" : "/sys/class/net/" + root.iface + "/statistics/tx_bytes"
      watchChanges: false
      printErrors: false
    },

    Process {
      id: resolveSensors
      running: true
      command: ["sh", "-c", "for d in /sys/class/hwmon/hwmon*; do n=$(cat \"$d/name\" 2>/dev/null); for l in \"$d\"/temp*_label; do [ -e \"$l\" ] || continue; lb=$(cat \"$l\" 2>/dev/null); case \"$n/$lb\" in k10temp/Tctl|zenpower/Tdie|'coretemp/Package id 0') echo \"cpu ${l%_label}_input\";; amdgpu/edge) echo \"gpu ${l%_label}_input\";; esac; done; done"]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          var paths = Metrics.parseSensorPaths(text)
          root.cpuTempPath = paths.cpu
          root.gpuTempPath = paths.gpu
          root.readSystem()
        }
      }
    },

    Timer {
      interval: 5000
      running: true
      repeat: true
      triggeredOnStart: true
      onTriggered: root.readSystem()
    },

    Timer {
      interval: 2000
      running: true
      repeat: true
      triggeredOnStart: true
      onTriggered: root.readNetwork()
    }
  ]
}
```

- [ ] **Step 3: Link it and load it**

```bash
ln -s ~/dotfiles/.config/omarchy/plugins/marcos.metrics ~/.config/omarchy/plugins/marcos.metrics
OMARCHY_PATH=/usr/share/omarchy omarchy restart shell
```

- [ ] **Step 4: Verify it loads and produces numbers**

A headless service has no UI to look at, so prove it with one temporary log line. Add to `Service.qml`, inside `readSystem()`, as the last statement:

```qml
console.log("metrics", root.cpuPercent.toFixed(1), root.memPercent.toFixed(1), root.hottest, root.iface, root.rxRate)
```

Run:
```bash
OMARCHY_PATH=/usr/share/omarchy omarchy restart shell
sleep 12
journalctl --user -b --since "20 seconds ago" | grep -E "metrics [0-9]"
journalctl --user -b --since "20 seconds ago" | grep -iE "omarchy-shell.*(error|warn)"
```

Expected: at least two `metrics` lines with a plausible CPU percent, a memory percent near what `free` reports, a temperature in the 30-70 range, the real interface name, and a non-negative rate. The error grep must be empty.

Then **delete the `console.log` line** and restart again. A service that logs every 5s forever is a log spammer.

- [ ] **Step 5: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .config/omarchy/plugins/marcos.metrics
git commit -m "feat(metrics): headless service owning the /proc and /sys readers"
```

---

### Task 3: `marcos.sysmon` becomes a view

The regression risk of the whole plan lives here. The widget keeps every one of its current readers and uses them whenever the service is absent, so a broken service degrades the dashboard, never the bar.

**Files:**
- Modify: `~/dotfiles/.config/omarchy/plugins/marcos.sysmon/BarWidget.qml`

**Interfaces:**
- Consumes: the service properties from Task 2, reached via `root.bar.shell.ensureService("marcos.metrics")`.
- Produces: nothing new.

- [ ] **Step 1: Add the service lookup**

`bar` is injected asynchronously after the widget is created, so the lookup has to be re-run when it changes rather than in `Component.onCompleted`.

Add after the `moduleName` line:

```qml
  // The bar is injected after construction, so resolve on change rather than
  // on completion. A null service is the supported case: the widget's own
  // readers stay and take over, which is what keeps a broken service from
  // taking the bar down with it.
  property var metrics: null

  function resolveMetrics() {
    if (root.bar && root.bar.shell && typeof root.bar.shell.ensureService === "function")
      root.metrics = root.bar.shell.ensureService("marcos.metrics")
  }

  onBarChanged: resolveMetrics()
  Component.onCompleted: resolveMetrics()

  readonly property bool useService: root.metrics !== null
```

- [ ] **Step 2: Point the displayed values at whichever source is live**

Replace the four value properties (currently `property real cpuPercent: -1` and its three neighbours) with:

```qml
  property real ownCpuPercent: -1
  property real ownMemPercent: -1
  property int ownCpuTemp: -1
  property int ownGpuTemp: -1

  readonly property real cpuPercent: useService ? metrics.cpuPercent : ownCpuPercent
  readonly property real memPercent: useService ? metrics.memPercent : ownMemPercent
  readonly property int cpuTemp: useService ? metrics.cpuTemp : ownCpuTemp
  readonly property int gpuTemp: useService ? metrics.gpuTemp : ownGpuTemp
```

Then rename the assignments inside `readCpu()`, `readMem()` and `readTemps()` to write the `own*` properties: `cpuPercent = ...` becomes `ownCpuPercent = ...`, and so on for all four. `hottest`, `warm`, `hot` and `label` already derive from the read-only properties and need no change.

- [ ] **Step 3: Stop the widget's own work when the service is live**

Change the `Timer` and the sensor-resolution `Process`:

```qml
  Process {
    id: resolveSensors
    running: !root.useService
```

```qml
  Timer {
    interval: 5000
    running: !root.useService
```

- [ ] **Step 4: Verify both paths**

```bash
OMARCHY_PATH=/usr/share/omarchy omarchy restart shell
sleep 8
grim -o DP-3 /tmp/bar.png && magick /tmp/bar.png -crop 2560x44+0+0 +repage /tmp/bar-crop.png
```
Read `/tmp/bar-crop.png`. Expected: the sysmon widget shows the same glyphs and plausible numbers as before, in green `#a6e3a1`.

Now the fallback, which is the point of the task:
```bash
OMARCHY_PATH=/usr/share/omarchy omarchy plugin disable marcos.metrics
OMARCHY_PATH=/usr/share/omarchy omarchy restart shell
sleep 8
grim -o DP-3 /tmp/bar2.png && magick /tmp/bar2.png -crop 2560x44+0+0 +repage /tmp/bar2-crop.png
```
Read it. Expected: identical numbers — the widget fell back to its own readers.

```bash
OMARCHY_PATH=/usr/share/omarchy omarchy plugin enable marcos.metrics
OMARCHY_PATH=/usr/share/omarchy omarchy restart shell
```

- [ ] **Step 5: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .config/omarchy/plugins/marcos.sysmon
git commit -m "refactor(sysmon): read from marcos.metrics, keeping own readers as fallback"
```

---

### Task 4: `marcos.netspeed` becomes a view

**Files:**
- Modify: `~/dotfiles/.config/omarchy/plugins/marcos.netspeed/BarWidget.qml`

**Interfaces:**
- Consumes: `iface`, `rxRate`, `txRate` from the service.
- Produces: nothing new.

- [ ] **Step 1: Add the same service lookup**

The code is repeated rather than shared because the two plugins are separate directories with no import path between them, and a third plugin existing only to hold six lines would cost more than it saves.

```qml
  property var metrics: null

  function resolveMetrics() {
    if (root.bar && root.bar.shell && typeof root.bar.shell.ensureService === "function")
      root.metrics = root.bar.shell.ensureService("marcos.metrics")
  }

  onBarChanged: resolveMetrics()
  Component.onCompleted: resolveMetrics()

  readonly property bool useService: root.metrics !== null
```

- [ ] **Step 2: Point the values at whichever source is live**

Replace `property string iface: ""`, `property real rxRate: -1` and `property real txRate: -1` with:

```qml
  property string ownIface: ""
  property real ownRxRate: -1
  property real ownTxRate: -1

  readonly property string iface: useService ? metrics.iface : ownIface
  readonly property real rxRate: useService ? metrics.rxRate : ownRxRate
  readonly property real txRate: useService ? metrics.txRate : ownTxRate
```

In `resolveIface()` and `refresh()`, rewrite every assignment to `iface`, `rxRate` and `txRate` to target `ownIface`, `ownRxRate` and `ownTxRate`. The `FileView` paths that read `root.iface` must change to `root.ownIface`, because when the service is live the widget's own counters must not follow the service's interface — they are the dormant fallback.

- [ ] **Step 3: Stop the widget's own timer when the service is live**

```qml
  Timer {
    interval: 2000
    running: !root.useService
```

- [ ] **Step 4: Verify both paths**

Same procedure as Task 3 Step 4: screenshot with the service enabled, then with `omarchy plugin disable marcos.metrics`, and confirm the rates keep updating in both. To make a rate visible rather than `0K`, start a download first:
```bash
curl -s -o /dev/null https://speed.hetzner.de/100MB.bin &
```

- [ ] **Step 5: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .config/omarchy/plugins/marcos.netspeed
git commit -m "refactor(netspeed): read from marcos.metrics, keeping own readers as fallback"
```

---

### Task 5: Calendar sync and `omarchy-agenda`

**Files:**
- Create: `~/dotfiles/.local/bin/omarchy-agenda`
- Create: `~/dotfiles/.config/vdirsyncer/config`
- Create: `~/dotfiles/.config/khal/config`
- Create: `~/dotfiles/.config/systemd/user/vdirsyncer.service`
- Create: `~/dotfiles/.config/systemd/user/vdirsyncer.timer`
- Test: `~/dotfiles/tests/test_omarchy_agenda.py`

**Interfaces:**
- Consumes: `khal` on `PATH`.
- Produces: `omarchy-agenda` prints one JSON object to stdout and always exits 0:
  `{"ok": bool, "reason": str, "syncedAt": int|null, "events": [{"start": "HH:MM"|"", "end": "HH:MM"|"", "title": str, "location": str, "allDay": bool}]}`
  `syncedAt` is the Unix mtime of `~/.calendars`, or null when it does not exist — it is how the panel can say the data is stale rather than silently showing yesterday's day.
  `ok` is false with a human `reason` when khal is missing or unconfigured. Printing valid JSON even on failure is what lets the QML side have exactly one parse path.

- [ ] **Step 1: Install the tooling and create the accounts**

```bash
sudo pacman -S --needed vdirsyncer khal
```

Google requires an app password with 2FA enabled, or OAuth. The app password path is simpler and does not expire on token rotation. Create one at https://myaccount.google.com/apppasswords, then store it outside the repo, matching how the qBittorrent secret is handled:

```bash
mkdir -p ~/.config/omarchy/secrets
printf '%s\n' 'marcos.mondejar71@gmail.com' 'APP_PASSWORD_HERE' > ~/.config/omarchy/secrets/google-calendar
chmod 600 ~/.config/omarchy/secrets/google-calendar
```

- [ ] **Step 2: Write the vdirsyncer config**

```ini
# ~/.config/vdirsyncer/config
[general]
status_path = "~/.local/state/vdirsyncer/status/"

[pair google]
a = "google_local"
b = "google_remote"
collections = ["from b"]
conflict_resolution = "b wins"
metadata = ["displayname", "color"]

[storage google_local]
type = "filesystem"
path = "~/.calendars/"
fileext = ".ics"

[storage google_remote]
type = "caldav"
url = "https://apidata.googleusercontent.com/caldav/v2/"
username.fetch = ["command", "sh", "-c", "sed -n 1p ~/.config/omarchy/secrets/google-calendar"]
password.fetch = ["command", "sh", "-c", "sed -n 2p ~/.config/omarchy/secrets/google-calendar"]
```

The credentials are fetched by command rather than written inline so the repo never holds them.

```bash
mkdir -p ~/.config/vdirsyncer ~/.calendars ~/.local/state/vdirsyncer/status
ln -sf ~/dotfiles/.config/vdirsyncer/config ~/.config/vdirsyncer/config
vdirsyncer discover google
vdirsyncer sync
ls ~/.calendars/
```
Expected: one directory per Google calendar, containing `.ics` files.

- [ ] **Step 3: Write the khal config**

```ini
# ~/.config/khal/config
[calendars]
[[google]]
path = ~/.calendars/*
type = discover

[locale]
timeformat = %H:%M
dateformat = %d.%m.
longdateformat = %d.%m.%Y
datetimeformat = %d.%m. %H:%M
longdatetimeformat = %d.%m.%Y %H:%M
firstweekday = 0
```

```bash
mkdir -p ~/.config/khal
ln -sf ~/dotfiles/.config/khal/config ~/.config/khal/config
khal list today today
```
Expected: today's events, or "No events".

- [ ] **Step 4: Confirm the exact format output before writing the parser**

khal's `--format` templating is what the script parses, so establish the real output shape first rather than assuming it:

```bash
khal --color=false list --day-format "" --format "{start-time}|{end-time}|{title}|{location}" today today
```

Expected: one line per event, four pipe-separated fields, with `start-time` empty for an all-day event. If this khal version rejects `--day-format` or emits a different shape, adjust the format string and the `SEPARATOR`-based parser in Step 6 to match what it actually prints — the script's contract is the JSON it produces, not khal's template syntax.

- [ ] **Step 5: Write the failing tests**

The tests drive the script with a fake `khal` on `PATH`, so they never touch the real calendar and run anywhere.

```python
# tests/test_omarchy_agenda.py
import json
import os
import stat
import subprocess
from pathlib import Path

SCRIPT = Path.home() / "dotfiles/.local/bin/omarchy-agenda"


def fake_khal(tmp_path, stdout="", returncode=0):
    directory = tmp_path / "bin"
    directory.mkdir(exist_ok=True)
    khal = directory / "khal"
    khal.write_text(f'#!/bin/sh\ncat <<"EOF"\n{stdout}\nEOF\nexit {returncode}\n')
    khal.chmod(khal.stat().st_mode | stat.S_IEXEC)
    return directory


def run(path_dir):
    env = dict(os.environ, PATH=str(path_dir))
    result = subprocess.run([str(SCRIPT)], capture_output=True, text=True, env=env)
    return result, json.loads(result.stdout)


def test_parses_timed_events(tmp_path):
    out = "09:30|10:30|Reunión equipo|Sala 2\n13:00|14:00|Comida|"
    result, data = run(fake_khal(tmp_path, out))
    assert result.returncode == 0
    assert data["ok"] is True
    assert data["events"][0] == {
        "start": "09:30", "end": "10:30",
        "title": "Reunión equipo", "location": "Sala 2", "allDay": False,
    }
    assert data["events"][1]["location"] == ""


def test_all_day_event_has_no_start(tmp_path):
    result, data = run(fake_khal(tmp_path, "||Cumpleaños de Ana|"))
    assert data["events"][0]["allDay"] is True
    assert data["events"][0]["start"] == ""
    assert data["events"][0]["title"] == "Cumpleaños de Ana"


def test_no_events_is_success_with_empty_list(tmp_path):
    result, data = run(fake_khal(tmp_path, ""))
    assert data["ok"] is True
    assert data["events"] == []


def test_titles_containing_a_pipe_survive(tmp_path):
    result, data = run(fake_khal(tmp_path, "09:00|10:00|Repaso | tesis|"))
    assert data["events"][0]["title"] == "Repaso | tesis"


def test_missing_khal_reports_a_reason_and_still_exits_zero(tmp_path):
    empty = tmp_path / "empty"
    empty.mkdir()
    result, data = run(empty)
    assert result.returncode == 0
    assert data["ok"] is False
    assert "khal" in data["reason"]
    assert data["events"] == []


def test_reports_when_the_calendar_last_synced(tmp_path):
    result, data = run(fake_khal(tmp_path, ""))
    calendars = Path.home() / ".calendars"
    if calendars.exists():
        assert data["syncedAt"] == int(calendars.stat().st_mtime)
    else:
        assert data["syncedAt"] is None


def test_khal_failure_reports_a_reason(tmp_path):
    result, data = run(fake_khal(tmp_path, "error", returncode=1))
    assert result.returncode == 0
    assert data["ok"] is False
    assert data["events"] == []
```

Run: `cd ~/dotfiles && pytest tests/test_omarchy_agenda.py -v`
Expected: FAIL — the script does not exist.

- [ ] **Step 6: Write the script**

The pipe-splitting is deliberately right-anchored on the last field and left-anchored on the first two, so a `|` inside an event title does not shift every column — a title is the one field a user can put anything into.

```python
#!/usr/bin/env python3
"""Print today's calendar events as JSON for the Omarchy dashboard."""

import json
import shutil
import subprocess
import sys
from pathlib import Path

SEPARATOR = "|"
FORMAT = "{start-time}|{end-time}|{title}|{location}"

SETUP_HINT = (
    "khal not found. Install it and sync a calendar:\n"
    "  sudo pacman -S --needed vdirsyncer khal\n"
    "  vdirsyncer discover google && vdirsyncer sync\n"
)


CALENDAR_DIR = Path.home() / ".calendars"


def last_sync():
    try:
        return int(CALENDAR_DIR.stat().st_mtime)
    except OSError:
        return None


def emit(ok, events, reason=""):
    payload = {"ok": ok, "reason": reason, "syncedAt": last_sync(), "events": events}
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


def parse_line(line):
    # start and end are fixed-width-ish leading fields and location is the
    # trailing one; everything between belongs to the title, pipes included.
    head = line.split(SEPARATOR, 2)
    if len(head) < 3:
        return None
    start, end, rest = head
    title, _, location = rest.rpartition(SEPARATOR)
    if title == "":
        title, location = location, ""
    start = start.strip()
    return {
        "start": start,
        "end": end.strip(),
        "title": title.strip(),
        "location": location.strip(),
        "allDay": start == "",
    }


def main():
    if "--setup" in sys.argv:
        sys.stderr.write(SETUP_HINT)
        return 0

    if shutil.which("khal") is None:
        return emit(False, [], "khal is not installed - run omarchy-agenda --setup")

    try:
        result = subprocess.run(
            ["khal", "--color=false", "list", "--day-format", "", "--format", FORMAT,
             "today", "today"],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.SubprocessError) as error:
        return emit(False, [], f"khal failed: {error}")

    if result.returncode != 0:
        return emit(False, [], (result.stderr or "khal exited non-zero").strip())

    events = []
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        event = parse_line(line)
        if event and event["title"]:
            events.append(event)
    return emit(True, events)


if __name__ == "__main__":
    sys.exit(main())
```

```bash
chmod +x ~/dotfiles/.local/bin/omarchy-agenda
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd ~/dotfiles && pytest tests/test_omarchy_agenda.py -v`
Expected: PASS, 7 tests.

Then against the real calendar: `omarchy-agenda | python3 -m json.tool`

- [ ] **Step 8: Add the sync timer**

```ini
# ~/dotfiles/.config/systemd/user/vdirsyncer.service
[Unit]
Description=Sync calendars with vdirsyncer
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/vdirsyncer -v WARNING sync
```

```ini
# ~/dotfiles/.config/systemd/user/vdirsyncer.timer
[Unit]
Description=Sync calendars every 15 minutes

[Timer]
OnBootSec=2m
OnUnitActiveSec=15m
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
ln -sf ~/dotfiles/.config/systemd/user/vdirsyncer.service ~/.config/systemd/user/vdirsyncer.service
ln -sf ~/dotfiles/.config/systemd/user/vdirsyncer.timer ~/.config/systemd/user/vdirsyncer.timer
systemctl --user daemon-reload
systemctl --user enable --now vdirsyncer.timer
systemctl --user start vdirsyncer.service
systemctl --user status vdirsyncer.service --no-pager
```
Expected: the service exits 0 and `~/.calendars/` holds current `.ics` files.

- [ ] **Step 9: Commit** (ask the user first)

Confirm the secret is not staged: `git status --short` must not list anything under `secrets/`.

```bash
cd ~/dotfiles
git add .local/bin/omarchy-agenda .config/vdirsyncer .config/khal .config/systemd/user/vdirsyncer.* tests/test_omarchy_agenda.py
git commit -m "feat(agenda): local calendar sync and a JSON query script"
```

---

### Task 6: The dashboard shell — card, header, open and close

Nothing but the surface: it opens, it closes, it has a header, and the three columns are empty labelled boxes. Getting the window, focus and dismissal right before any content exists means the content tasks never have to debug them.

**Files:**
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/manifest.json`
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Dashboard.qml`
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Section.qml`
- Modify: `~/dotfiles/.config/hypr/bindings.lua`
- Create symlink: `~/.config/omarchy/plugins/marcos.dashboard`

**Interfaces:**
- Consumes: `shell` injected by the host; `Color` and `Style` from `qs.Commons`.
- Produces:
  - `Dashboard.qml` exposes `open(payloadJson)`, `close()`, `dismiss()`, `toggle()`, `opened`.
  - `Section.qml` is a titled column: `property string title`, `property color accent`, `default property alias content`.

- [ ] **Step 1: Write the manifest**

`keepLoaded` is false so that nothing exists while the panel is closed.

```json
{
  "schemaVersion": 1,
  "id": "marcos.dashboard",
  "name": "Dashboard",
  "version": "1.0.0",
  "author": "marcos",
  "description": "Glanceable overview: today, what was missed, and the machine",
  "kinds": ["overlay"],
  "keepLoaded": false,
  "entryPoints": { "overlay": "Dashboard.qml" }
}
```

- [ ] **Step 2: Write the column component**

```qml
// Section.qml
import QtQuick
import qs.Commons

Item {
  id: root

  property string title: ""
  property color accent: Color.foreground
  default property alias content: body.data

  implicitHeight: header.height + body.implicitHeight + Style.spacing.md

  Text {
    id: header
    text: root.title
    color: root.accent
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.5
    font.bold: true
  }

  Column {
    id: body
    anchors.top: header.bottom
    anchors.topMargin: Style.spacing.md
    width: parent.width
    spacing: Style.spacing.sm
  }
}
```

- [ ] **Step 3: Write the overlay**

The card is wide and low because the display is 2560x1080: vertical space is the scarce resource, and a narrow card would strangle three columns while making the side margins conspicuous.

```qml
// Dashboard.qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  // The bar's cluster palette, repeated here so the same colour means the same
  // kind of thing on both surfaces. omarchy-bar-colors owns the bar's copy;
  // Task 10 teaches it about this file so they cannot drift.
  readonly property color clusterContext: "#89b4fa"
  readonly property color clusterTools: "#fab387"
  readonly property color clusterResources: "#a6e3a1"

  readonly property int cardWidth: Math.min(Style.space(1700), panel.width - Style.space(160))
  readonly property int cardHeight: Math.min(Style.space(820), panel.height - Style.space(120))

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "marcos.dashboard")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function spanishDate() {
    var days = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]
    var months = ["enero", "febrero", "marzo", "abril", "mayo", "junio",
                  "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
    var now = clock.date
    return days[now.getDay()] + ", " + now.getDate() + " de " + months[now.getMonth()]
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "marcos-dashboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The component emits semantic signals; Escape arrives as closeRequested.
      onCloseRequested: root.dismiss()
    }

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: root.cardWidth
      height: root.cardHeight
      radius: Style.cornerRadius
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: 1

      // Swallows clicks so hitting the card does not dismiss through the scrim.
      MouseArea { anchors.fill: parent }

      Column {
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.spacing.lg

        Item {
          width: parent.width
          height: timeText.height + dateText.height

          Text {
            id: timeText
            text: Qt.formatTime(clock.date, "HH:mm")
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.display * 2
          }
          Text {
            id: dateText
            anchors.top: timeText.bottom
            text: root.spanishDate()
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        Row {
          width: parent.width
          height: parent.height - timeText.height - dateText.height - Style.spacing.lg * 2
          spacing: Style.spacing.lg

          readonly property int columnWidth: (width - spacing * 2) / 3

          Section {
            id: todaySection
            width: parent.columnWidth
            height: parent.height
            title: "HOY"
            accent: root.clusterContext
          }

          Section {
            id: missedSection
            width: parent.columnWidth
            height: parent.height
            title: "QUÉ ME PERDÍ"
            accent: root.clusterTools
          }

          Section {
            id: machineSection
            width: parent.columnWidth
            height: parent.height
            title: "MÁQUINA"
            accent: root.clusterResources
          }
        }
      }
    }
  }

  // Only ticks while the panel is open, which is the whole reason the overlay
  // is not keepLoaded.
  SystemClock {
    id: clock
    enabled: root.opened
    precision: SystemClock.Minutes
  }
}
```

- [ ] **Step 4: Link, load, and bind a key**

Append to `~/dotfiles/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + D", "Dashboard", "omarchy-shell shell toggle marcos.dashboard '{}'")
```

```bash
ln -s ~/dotfiles/.config/omarchy/plugins/marcos.dashboard ~/.config/omarchy/plugins/marcos.dashboard
OMARCHY_PATH=/usr/share/omarchy omarchy restart shell
hyprctl reload
```

- [ ] **Step 5: Verify it opens, closes and looks right**

```bash
OMARCHY_PATH=/usr/share/omarchy omarchy-shell shell toggle marcos.dashboard '{}'
sleep 1
grim -o DP-3 /tmp/dash.png
```
Read `/tmp/dash.png`. Expected: a centred card over the dimmed desktop, the time in large type, the Spanish date beneath it, and three column headings in blue, peach and green.

Then check all three dismissal paths — `ESC`, a click outside the card, and `SUPER + D` again — and confirm a click *inside* the card does not dismiss it.

```bash
journalctl --user -b --since "60 seconds ago" | grep -iE "omarchy-shell.*(error|warn)"
```
Expected: empty.

- [ ] **Step 6: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .config/omarchy/plugins/marcos.dashboard .config/hypr/bindings.lua
git commit -m "feat(dashboard): overlay shell with header and three empty columns"
```

---

### Task 7: The HOY column

**Files:**
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Today.qml`
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Entry.qml`
- Modify: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Dashboard.qml`

**Interfaces:**
- Consumes: `omarchy-agenda` from Task 5; the reminder files that `marcos.reminders` already watches, at `$XDG_RUNTIME_DIR/omarchy-reminders/*.message`.
- Produces: `Today.qml` with `property bool active` (set from `root.opened`) and `Entry.qml`, a two-column row: `property string lead`, `property string title`, `property string detail`, `property color leadColor`.

- [ ] **Step 1: Write the row component**

```qml
// Entry.qml
import QtQuick
import qs.Commons

Item {
  id: root

  property string lead: ""
  property string title: ""
  property string detail: ""
  property color leadColor: Color.muted

  width: parent ? parent.width : 0
  implicitHeight: Math.max(leadText.implicitHeight, titleText.implicitHeight + detailText.implicitHeight)

  Text {
    id: leadText
    width: Style.space(64)
    text: root.lead
    color: root.leadColor
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Text {
    id: titleText
    anchors.left: leadText.right
    anchors.leftMargin: Style.spacing.md
    anchors.right: parent.right
    text: root.title
    color: Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  Text {
    id: detailText
    anchors.left: titleText.left
    anchors.top: titleText.bottom
    anchors.right: parent.right
    visible: root.detail !== ""
    height: visible ? implicitHeight : 0
    text: root.detail
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }
}
```

- [ ] **Step 2: Write the column**

The agenda process runs on `active` becoming true and never on a timer: opening the panel is the only thing that should cost a subprocess.

```qml
// Today.qml
import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import qs.Commons

Column {
  id: root

  property bool active: false
  property var events: []
  property bool agendaOk: true
  property string agendaReason: ""
  property var syncedAt: null

  // Six hours without a sync means vdirsyncer has not run — usually no network.
  // Saying so is the difference between "nothing on today" and "I do not know".
  readonly property bool stale: syncedAt !== null && (Date.now() / 1000 - syncedAt) > 21600

  spacing: Style.spacing.sm

  onActiveChanged: if (active) agendaProc.running = true

  Process {
    id: agendaProc
    command: ["omarchy-agenda"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          root.events = data.events || []
          root.agendaOk = data.ok === true
          root.agendaReason = data.reason || ""
          root.syncedAt = typeof data.syncedAt === "number" ? data.syncedAt : null
        } catch (error) {
          root.events = []
          root.agendaOk = false
          root.agendaReason = "respuesta ilegible de omarchy-agenda"
        }
      }
    }
  }

  Repeater {
    model: root.events
    Entry {
      lead: modelData.allDay ? "todo el día" : modelData.start
      title: modelData.title
      detail: modelData.location
      leadColor: "#89b4fa"
    }
  }

  Text {
    visible: root.agendaOk && root.events.length === 0
    text: "Nada en la agenda"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Text {
    visible: !root.agendaOk
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Agenda sin configurar · omarchy-agenda --setup"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Text {
    visible: root.agendaOk && root.stale
    text: "sin sincronizar desde " + Qt.formatDateTime(new Date(root.syncedAt * 1000), "d MMM HH:mm")
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Text {
    text: "── recordatorios ──"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    topPadding: Style.spacing.md
  }

  FolderListModel {
    id: reminderFiles
    folder: "file://" + Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-reminders"
    nameFilters: ["*.message"]
    showDirs: false
    sortField: FolderListModel.Name
  }

  Repeater {
    model: reminderFiles
    Entry {
      lead: "⏰"
      title: fileBaseName
      leadColor: "#89b4fa"
    }
  }

  Text {
    visible: reminderFiles.count === 0
    text: "Sin recordatorios"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}
```

- [ ] **Step 3: Mount it in the card**

In `Dashboard.qml`, inside the `Section` with `title: "HOY"`, add:

```qml
            Today {
              width: parent.width
              active: root.opened
            }
```

- [ ] **Step 4: Verify against a real event**

Create a known event so the column is not being judged on an empty calendar:

```bash
khal new -a google today 23:45 23:50 "Prueba dashboard"
vdirsyncer sync
omarchy-agenda | python3 -m json.tool
OMARCHY_PATH=/usr/share/omarchy omarchy restart shell
OMARCHY_PATH=/usr/share/omarchy omarchy-shell shell toggle marcos.dashboard '{}'
sleep 1 && grim -o DP-3 /tmp/dash-today.png
```
Read the screenshot. Expected: "23:45  Prueba dashboard" under HOY.

Then check both degraded states render rather than leaving a blank column:
```bash
PATH=/nonexistent omarchy-agenda
touch -d "yesterday" ~/.calendars && omarchy-agenda | python3 -m json.tool
```
Expected: the first prints `{"ok": false, ...}` with the setup hint; the second reports
`ok: true` with a day-old `syncedAt`, and reopening the panel shows the
"sin sincronizar desde ..." line. Run `vdirsyncer sync` afterwards to restore the mtime.

Clean up: `khal delete` the test event, or leave it, it expires.

- [ ] **Step 5: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .config/omarchy/plugins/marcos.dashboard
git commit -m "feat(dashboard): today column with agenda and reminders"
```

---

### Task 8: The QUÉ ME PERDÍ column

**Files:**
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Missed.qml`
- Modify: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Dashboard.qml`

**Interfaces:**
- Consumes: `~/.local/state/omarchy/notifications/history/*.json`, one object per notification; `Entry.qml` from Task 7.
- Produces: `Missed.qml` with `property bool active`.

- [ ] **Step 1: Confirm the on-disk shape before parsing it**

```bash
ls -t ~/.local/state/omarchy/notifications/history/ | head -3
cat ~/.local/state/omarchy/notifications/history/$(ls -t ~/.local/state/omarchy/notifications/history/ | head -1) | python3 -m json.tool
```

Note the exact key names for the application name, summary and body. The code below assumes `appName`, `summary` and `body`; if this shell version uses different keys, use the ones actually on disk.

- [ ] **Step 2: Write the column**

Reading the directory rather than calling into the notifications plugin means the contract is the filesystem, which survives upstream refactors that a QML API would not.

```qml
// Missed.qml
import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import qs.Commons

Column {
  id: root

  property bool active: false
  readonly property string historyDir: Quickshell.env("HOME") + "/.local/state/omarchy/notifications/history"

  spacing: Style.spacing.sm

  function clearAll() {
    clearProc.command = ["sh", "-c", 'rm -f -- "$1"/*.json', "sh", root.historyDir]
    clearProc.running = true
  }

  Process { id: clearProc }

  FolderListModel {
    id: history
    folder: "file://" + root.historyDir
    nameFilters: ["*.json"]
    showDirs: false
    sortField: FolderListModel.Time
    sortReversed: false
  }

  Repeater {
    model: history
    Entry {
      id: entry
      required property string filePath
      lead: "●"
      leadColor: "#fab387"
      title: notification.appName
      detail: notification.summary

      QtObject {
        id: notification
        property string appName: "?"
        property string summary: ""
      }

      FileView {
        path: entry.filePath
        watchChanges: false
        printErrors: false
        onLoaded: {
          try {
            var data = JSON.parse(text())
            notification.appName = data.appName || "?"
            notification.summary = data.summary || data.body || ""
          } catch (error) {
            notification.appName = "?"
          }
        }
      }
    }
  }

  Text {
    visible: history.count === 0
    text: "Nada que revisar"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Text {
    visible: history.count > 0
    text: "limpiar"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    topPadding: Style.spacing.sm

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.clearAll()
    }
  }

  Text {
    text: "── en marcha ──"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    topPadding: Style.spacing.md
  }

  FolderListModel {
    id: downloads
    folder: "file://" + Quickshell.env("HOME") + "/Downloads"
    showDirs: false
    sortField: FolderListModel.Time
    sortReversed: false
  }

  Repeater {
    model: Math.min(downloads.count, 3)
    Entry {
      lead: "⬇"
      leadColor: "#fab387"
      title: downloads.get(index, "fileName")
    }
  }

  Text {
    visible: downloads.count === 0
    text: "Sin descargas recientes"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}
```

- [ ] **Step 3: Mount it in the card**

In `Dashboard.qml`, inside the `Section` with `title: "QUÉ ME PERDÍ"`:

```qml
            Missed {
              width: parent.width
              active: root.opened
            }
```

- [ ] **Step 4: Verify with real notifications**

```bash
notify-send "Zen" "2 mensajes nuevos"
notify-send "Snapper" "snapshot creado"
sleep 12   # let the toasts expire into history
OMARCHY_PATH=/usr/share/omarchy omarchy restart shell
OMARCHY_PATH=/usr/share/omarchy omarchy-shell shell toggle marcos.dashboard '{}'
sleep 1 && grim -o DP-3 /tmp/dash-missed.png
```
Read the screenshot. Expected: both notifications listed with the app name in peach and the summary beneath.

Click "limpiar", reopen, and confirm the column reads "Nada que revisar" and `ls ~/.local/state/omarchy/notifications/history/` is empty.

- [ ] **Step 5: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .config/omarchy/plugins/marcos.dashboard
git commit -m "feat(dashboard): missed column reading notification history from disk"
```

---

### Task 9: The MÁQUINA column

**Files:**
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Sparkline.qml`
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Machine.qml`
- Modify: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Dashboard.qml`

**Interfaces:**
- Consumes: the service from Task 2 via `shell.ensureService("marcos.metrics")`; `df` and `snapper` as one-shot processes on open.
- Produces: `Sparkline.qml` with `property var samples`, `property real maximum`, `property color fill`; `Machine.qml` with `property bool active` and `property var shell`.

- [ ] **Step 1: Write the sparkline**

A `Row` of `Rectangle`s rather than a `Canvas`: a Canvas repaints in software, while thirty rectangles are a cost the scene graph does not notice. They exist only while the panel is open.

```qml
// Sparkline.qml
import QtQuick
import qs.Commons

Row {
  id: root

  property var samples: []
  property real maximum: 100
  property color fill: Color.foreground
  property int barCount: 30

  readonly property var visibleSamples: {
    var all = root.samples || []
    return all.length > root.barCount ? all.slice(all.length - root.barCount) : all
  }

  spacing: 1
  height: Style.space(18)

  Repeater {
    model: root.visibleSamples
    Rectangle {
      width: Math.max(1, (root.width - root.spacing * (root.barCount - 1)) / root.barCount)
      height: Math.max(1, root.height * Math.min(1, Math.max(0, modelData / Math.max(1, root.maximum))))
      anchors.bottom: parent.bottom
      color: root.fill
      opacity: 0.85
      radius: 1
    }
  }
}
```

- [ ] **Step 2: Write the column**

```qml
// Machine.qml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Column {
  id: root

  property bool active: false
  property var shell: null
  property var metrics: null

  property string diskFree: "--"
  property real diskFreePercent: -1
  property var snapshotDays: []

  readonly property color resources: "#a6e3a1"

  // The header dot reads these rather than repeating the thresholds. Snapshot
  // coverage is deliberately not part of it: "a pacman transaction with no
  // snapshot" needs the pacman.log parsing that marcos.snapper owns, and
  // duplicating it here would be a second source of truth.
  readonly property bool diskLow: diskFreePercent >= 0 && diskFreePercent < 10
  readonly property bool tempHigh: metrics !== null && metrics.hottest >= 65
  readonly property bool needsAttention: diskLow || tempHigh
  readonly property string attentionReason: tempHigh ? "temperatura alta" : "disco casi lleno"

  spacing: Style.spacing.sm

  onActiveChanged: {
    if (!active) return
    if (root.shell && typeof root.shell.ensureService === "function")
      root.metrics = root.shell.ensureService("marcos.metrics")
    diskProc.running = true
    snapshotProc.running = true
  }

  function fmtRate(bytesPerSecond) {
    if (bytesPerSecond < 0) return "--"
    if (bytesPerSecond >= 1024 * 1024) return (bytesPerSecond / (1024 * 1024)).toFixed(1) + " MB/s"
    if (bytesPerSecond >= 1024) return Math.round(bytesPerSecond / 1024) + " KB/s"
    return "0 KB/s"
  }

  function fmtGb(kb) {
    return (kb / 1024 / 1024).toFixed(1)
  }

  Process {
    id: diskProc
    command: ["sh", "-c", "df --output=avail,pcent -h / | tail -1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").trim().split(/\s+/)
        root.diskFree = parts[0] || "--"
        // df prints percent USED; free space is the complement.
        var used = Number(String(parts[1] || "").replace("%", ""))
        root.diskFreePercent = isFinite(used) ? 100 - used : -1
      }
    }
  }

  // snapper's own timeline is off; snapshots come from snap-pac on each pacman
  // transaction, so a day with no snapshot only matters if something was
  // installed that day. The week strip shows presence, not health.
  Process {
    id: snapshotProc
    command: ["sh", "-c", "snapper --jsonout list 2>/dev/null || echo '{}'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var days = [false, false, false, false, false, false, false]
        try {
          var data = JSON.parse(String(text || "{}"))
          var list = data.root || []
          var now = new Date()
          for (var i = 0; i < list.length; i++) {
            if (!list[i].date) continue
            var when = new Date(list[i].date.replace(" ", "T"))
            var ago = Math.floor((now - when) / 86400000)
            if (ago >= 0 && ago < 7) days[6 - ago] = true
          }
        } catch (error) {
          // Leave the week empty rather than inventing snapshots.
        }
        root.snapshotDays = days
      }
    }
  }

  Row {
    width: parent.width
    spacing: Style.spacing.md
    Text {
      text: "CPU"
      color: Color.muted
      width: Style.space(40)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    Sparkline {
      width: Style.space(150)
      samples: root.metrics ? root.metrics.cpuHistory : []
      maximum: 100
      fill: root.resources
    }
    Text {
      text: root.metrics && root.metrics.cpuPercent >= 0 ? Math.round(root.metrics.cpuPercent) + "%" : "--"
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  Row {
    width: parent.width
    spacing: Style.spacing.md
    Text {
      text: "RAM"
      color: Color.muted
      width: Style.space(40)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    Sparkline {
      width: Style.space(150)
      samples: root.metrics ? root.metrics.memHistory : []
      maximum: 100
      fill: root.resources
    }
    Text {
      text: root.metrics && root.metrics.memTotalKb > 0
        ? root.fmtGb(root.metrics.memUsedKb) + "/" + root.fmtGb(root.metrics.memTotalKb) + " GB"
        : "--"
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  Row {
    width: parent.width
    spacing: Style.spacing.md
    Text {
      text: "TMP"
      color: Color.muted
      width: Style.space(40)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    Sparkline {
      width: Style.space(150)
      samples: root.metrics ? root.metrics.tempHistory : []
      maximum: 100
      fill: root.resources
    }
    Text {
      text: root.metrics && root.metrics.hottest >= 0 ? root.metrics.hottest + "°" : "--"
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  Text {
    text: "↓ " + root.fmtRate(root.metrics ? root.metrics.rxRate : -1)
      + "     ↑ " + root.fmtRate(root.metrics ? root.metrics.txRate : -1)
    color: Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    topPadding: Style.spacing.md
  }

  Text {
    text: "Disco   " + root.diskFree + " libres"
    color: Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Text {
    visible: !root.metrics
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Servicio de métricas no disponible"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Row {
    spacing: Style.spacing.sm
    topPadding: Style.spacing.md
    Repeater {
      model: ["L", "M", "X", "J", "V", "S", "D"]
      Column {
        spacing: 2
        Text {
          text: modelData
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Rectangle {
          width: Style.space(14)
          height: Style.space(14)
          radius: 3
          color: (root.snapshotDays[index] === true) ? root.resources : Color.muted
          opacity: (root.snapshotDays[index] === true) ? 0.9 : 0.25
        }
      }
    }
  }
}
```

- [ ] **Step 3: Mount it in the card**

In `Dashboard.qml`, inside the `Section` with `title: "MÁQUINA"`:

```qml
            Machine {
              id: machine
              width: parent.width
              active: root.opened
              shell: root.shell
            }
```

- [ ] **Step 4: Verify**

```bash
OMARCHY_PATH=/usr/share/omarchy omarchy restart shell
sleep 90   # let the service accumulate enough samples for a visible sparkline
curl -s -o /dev/null https://speed.hetzner.de/100MB.bin &
OMARCHY_PATH=/usr/share/omarchy omarchy-shell shell toggle marcos.dashboard '{}'
sleep 1 && grim -o DP-3 /tmp/dash-machine.png
```
Read the screenshot. Expected: three sparklines with visible variation, percentages matching `top` and `free -h`, a download rate that is not `0 KB/s`, free space matching `df -h /`, and the week strip with filled cells on days that had a pacman transaction.

Cross-check the numbers rather than trusting the render:
```bash
free -h | head -2; df -h /; snapper list | tail -5
```

Confirm the degraded path too:
```bash
OMARCHY_PATH=/usr/share/omarchy omarchy plugin disable marcos.metrics
OMARCHY_PATH=/usr/share/omarchy omarchy restart shell
```
Expected: the column shows "Servicio de métricas no disponible" and dashes, the other two columns are unaffected, and the bar still works. Re-enable afterwards.

- [ ] **Step 5: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .config/omarchy/plugins/marcos.dashboard
git commit -m "feat(dashboard): machine column with sparklines, disk and snapshot week"
```

---

### Task 10: Status dot, palette upkeep, and cost measurement

**Files:**
- Modify: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Dashboard.qml`
- Modify: `~/dotfiles/.local/bin/omarchy-bar-colors`
- Modify: `~/.claude/projects/-home-marcos/memory/project_omarchy_bar.md`

**Interfaces:**
- Consumes: everything built so far.
- Produces: no new interfaces.

- [ ] **Step 1: Add the header status dot**

It answers "is anything wrong" before the eye reaches the third column. Add to `Dashboard.qml`, inside the header `Item`, anchored to the right:

```qml
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.sm

            // Machine already knows both facts, so the dot asks it rather than
            // duplicating the thresholds here.
            readonly property bool alert: machine.needsAttention

            Rectangle {
              width: Style.space(10)
              height: Style.space(10)
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: parent.alert ? "#f9e2af" : "#a6e3a1"
            }
            Text {
              text: parent.alert ? machine.attentionReason : "todo bien"
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
```

- [ ] **Step 2: Keep the palette from drifting**

The dashboard repeats the cluster hexes that `omarchy-bar-colors` owns for the bar. Teach the script to rewrite them here too, so one edit to `CLUSTERS` moves both surfaces.

In `~/dotfiles/.local/bin/omarchy-bar-colors`, add after the `EXTRA` definition:

```python
# The dashboard is not a bar widget, so the per-widget patching above does not
# reach it, but it repeats the same cluster hexes. Rewriting them here keeps one
# edit to CLUSTERS moving both surfaces.
DASHBOARD_COLORS = {
    "clusterContext": "context",
    "clusterTools": "tools",
    "clusterResources": "resources",
}


def patch_dashboard() -> str:
    path = DOTFILES_PLUGINS / "marcos.dashboard" / "Dashboard.qml"
    if not path.is_file():
        return "not installed"
    text = path.read_text()
    original = text
    for prop, cluster in DASHBOARD_COLORS.items():
        text = re.sub(
            rf'(readonly property color {prop}: )"#[0-9A-Fa-f]{{6}}"',
            rf'\g<1>"{CLUSTERS[cluster]}"',
            text,
        )
    if text == original:
        return "unchanged"
    path.write_text(text)
    return "updated"
```

And in `main()`, immediately before `run(["omarchy-shell", "shell", "rescanPlugins"])`:

```python
    report.append(("marcos.dashboard", "surface", patch_dashboard()))
```

Run it and confirm the report lists `marcos.dashboard  surface  unchanged`:
```bash
omarchy-bar-colors
```

- [ ] **Step 3: Measure the cost**

The claim in the spec is that idle cost is unchanged, since no tick was added or removed. Verify rather than assert:

```bash
pid=$(pgrep -f "quickshell.*omarchy" | head -1)
for i in 1 2 3 4 5; do ps -o %cpu=,rss= -p $pid; sleep 10; done
```
Expected: CPU comparable to the pre-existing baseline of roughly 2.1%, RSS in the same range as before. Open and close the dashboard a few times, then re-measure: RSS should return close to its resting value, because `keepLoaded: false` releases the overlay.

```bash
ls /proc/$pid/task | wc -l
pgrep -P $pid | wc -l
```
Expected: no child processes lingering at idle.

- [ ] **Step 4: Update the system memory**

Append to the "Otras piezas del sistema" section of `~/.claude/projects/-home-marcos/memory/project_omarchy_bar.md`:

```markdown
- **Dashboard** (`marcos.dashboard`, `overlay`, `SUPER + D`): tarjeta central con HOY /
  QUÉ ME PERDÍ / MÁQUINA. `keepLoaded: false`, así que cerrado no existe. Los datos que
  necesitan subproceso (`omarchy-agenda`, `df`, `snapper`) se leen **una vez al abrir**.
- **`marcos.metrics`** (`service`) concentra los lectores de `/proc` y `/sys`. `sysmon` y
  `netspeed` son vistas suyas y **conservan sus lectores propios como fallback**: si el
  servicio falla, la barra sigue. Dos cadencias a propósito: 2s red, 5s sistema.
- **Agenda**: `vdirsyncer` sincroniza Google a `~/.calendars/` con un timer de systemd y
  `khal` la consulta. El shell nunca habla con Google. Credenciales en
  `~/.config/omarchy/secrets/google-calendar` (600, fuera del repo).
- La lógica pura de métricas vive en `Metrics.js` y **tiene tests**:
  `deno test --allow-read test/metrics.test.mjs`. QML headless no arranca aquí
  (`qml` y `qmltestrunner` mueren en silencio), por eso la lógica está separada del QML.
```

- [ ] **Step 5: Commit and push** (ask the user first)

```bash
cd ~/dotfiles
git add .config/omarchy/plugins/marcos.dashboard .local/bin/omarchy-bar-colors
git commit -m "feat(dashboard): status dot, and keep the cluster palette in one place"
git push origin main
```
