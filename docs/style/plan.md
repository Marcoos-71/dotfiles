# Visual Language Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the `marcos.*` surfaces one shared vocabulary of motion, depth, spacing and type, and apply it to the dashboard — which today has no animation, an empty lower two thirds, and no separation between columns.

**Architecture:** Values live in one TOML. A renamed `omarchy-style` generates a `Tokens.js` constant file into each plugin that needs one, alongside the cluster-hex rewriting it already does. QML imports its own `Tokens.js`. No runtime service, no null checks, no cross-plugin imports.

**Tech Stack:** QML / Quickshell, plain JS for testable logic, Python 3 (stdlib only) for the generator and `omarchy-agenda`, `deno test` and `pytest` as runners, Hyprland Lua config for blur.

**Spec:** `docs/style/design.md`

> **Estado (14-09-2026): las ocho tareas están hechas, verificadas y commiteadas.**
> Queda una sola decisión de gusto: `decoration:blur:size` está en 8 (se compararon
> 4, 8 y 12 en pantalla). Cambiarlo es una línea en `.config/hypr/looknfeel.lua`.

## Global Constraints

- **Files live in `~/dotfiles/` and are symlinked into `~/.config/`.** Never edit through the symlink; `readlink -f` first.
- **`OMARCHY_PATH` must be the literal string `/usr/share/omarchy`** for any `omarchy` command. `qs ipc` matches instances by the literal `-p` string.
- **A new plugin needs `omarchy restart shell`, not `rescanPlugins`.** A third-party `service` plugin also needs its id in `shell.json`'s `plugins` array (`omarchy plugin enable <id>`).
- **Never touch `/usr/share/omarchy`.** No overriding `Ui/` components. If a task seems to need it, stop and report.
- **Zero subprocesses in polling loops.** A process is allowed once at startup, or once per user-initiated open.
- **Colours are the fixed Catppuccin Mocha cluster values:** identity `#cba6f7`, resources `#a6e3a1`, devices `#94e2d5`, context `#89b4fa`, tools `#fab387`.
- **Code comments in English.** No multi-line docstrings. No comments restating the code.
- **Python via `uv`, never `pip`.**
- **Ask before every `git commit` and `git push`.**
- **`ensureService()` ignores `isEnabled()`.** To prove a fallback, remove the plugin symlink from `~/.config/omarchy/plugins/` — `omarchy plugin disable` is not enough.
- **After every task:** `journalctl --user -b --since "20 seconds ago" | grep -iE "omarchy-shell.*(error|warn)"` must be clean apart from the known `host portal` and MPRIS noise, and the bar must still render.

---

### Task 1: Token source and generator

**Files:**
- Create: `~/dotfiles/.config/omarchy/style-tokens.toml`
- Rename: `~/dotfiles/.local/bin/omarchy-bar-colors` → `~/dotfiles/.local/bin/omarchy-style`
- Create symlink: `~/dotfiles/.local/bin/omarchy-bar-colors` → `omarchy-style`
- Create: `~/dotfiles/docs/style/tokens.md`
- Test: `~/dotfiles/tests/test_style_tokens.py`

**Interfaces:**
- Consumes: nothing.
- Produces: a `Tokens.js` in each plugin listed in `TOKEN_PLUGINS`, exposing these names as top-level `var`s, all numbers:
  - `motionInstant`, `motionFast`, `motionNormal` — milliseconds
  - `motionRise` — pixels; `motionScaleFrom` — 0..1
  - `scrimAlpha` — 0..1
  - `elevPopupY`, `elevPopupBlur`, `elevPopupAlpha`
  - `elevOverlayY`, `elevOverlayBlur`, `elevOverlayAlpha`
  - `ruleAlpha` — 0..1, the separator line against the card background
- Produces: `parse_tokens(text) -> dict` and `render_tokens_js(values) -> str` in `omarchy-style`.

- [x] **Step 1: Write the token file**

```toml
# ~/dotfiles/.config/omarchy/style-tokens.toml
# Source of truth for the visual language. `omarchy-style` generates each
# plugin's Tokens.js from this file; editing a generated Tokens.js by hand
# is pointless because the next sync overwrites it.

[motion]
# Opening a surface. Chosen over a 150ms fade (imperceptible on a full-screen
# card) and a 420ms spring (wearing by the third time in a day).
normal = 260
# Transitions inside a surface that is already open. Also the exit duration:
# leaving is always quicker than arriving.
fast = 150
# Semantic state changes we own, like netspeed turning blue on traffic.
instant = 90
rise = 8
scale-from = 0.965

[depth]
scrim-alpha = 0.30
rule-alpha = 0.16

[elevation.popup]
y = 6
blur = 18
alpha = 0.35

[elevation.overlay]
y = 14
blur = 38
alpha = 0.50
```

- [x] **Step 2: Write the failing tests**

```python
# tests/test_style_tokens.py
import subprocess
import sys
from pathlib import Path

SCRIPT = Path.home() / "dotfiles/.local/bin/omarchy-style"
TOML = Path.home() / "dotfiles/.config/omarchy/style-tokens.toml"


def load():
    """Import omarchy-style as a module despite having no .py extension."""
    import importlib.util
    spec = importlib.util.spec_from_loader(
        "omarchy_style",
        importlib.machinery.SourceFileLoader("omarchy_style", str(SCRIPT)),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_parse_flattens_sections_to_camel_case():
    m = load()
    values = m.parse_tokens(TOML.read_text())
    assert values["motionNormal"] == 260
    assert values["motionScaleFrom"] == 0.965
    assert values["scrimAlpha"] == 0.30
    assert values["elevOverlayBlur"] == 38


def test_render_produces_a_pragma_library_with_every_value():
    m = load()
    js = m.render_tokens_js({"motionNormal": 260, "scrimAlpha": 0.3})
    assert js.startswith(".pragma library")
    assert "var motionNormal = 260" in js
    assert "var scrimAlpha = 0.3" in js
    assert "do not edit" in js.lower()


def test_old_name_still_runs():
    old = Path.home() / "dotfiles/.local/bin/omarchy-bar-colors"
    assert old.is_symlink()
    assert old.resolve().name == "omarchy-style"
```

- [x] **Step 3: Run the tests to verify they fail**

Run: `cd ~/dotfiles && uv run --with pytest pytest tests/test_style_tokens.py -q`
Expected: FAIL — `omarchy-style` does not exist yet.

- [x] **Step 4: Rename the script and leave the compatibility symlink**

```bash
cd ~/dotfiles/.local/bin
git mv omarchy-bar-colors omarchy-style
ln -s omarchy-style omarchy-bar-colors
ln -sfn ~/dotfiles/.local/bin/omarchy-style ~/.local/bin/omarchy-style
ls -la ~/.local/bin/omarchy-bar-colors ~/.local/bin/omarchy-style
```

The symlink in `~/.local/bin/omarchy-bar-colors` already points into dotfiles, so it keeps resolving through the new relative symlink.

- [x] **Step 5: Add the parser and renderer to `omarchy-style`**

Add after the `CLUSTERS` definition. `tomllib` is stdlib from Python 3.11, so nothing to install.

```python
import tomllib

TOKENS_PATH = Path.home() / ".config/omarchy/style-tokens.toml"

# Plugins that animate something and therefore need the constants. Kept
# explicit rather than "every marcos.*" so a plugin that draws nothing
# animated does not carry a file it never imports.
TOKEN_PLUGINS = [
    "marcos.dashboard",
    "marcos.netspeed",
    "marcos.sysmon",
]


def parse_tokens(text: str) -> dict:
    """Flatten the TOML into the flat camelCase names QML imports.

    [motion] normal -> motionNormal; [elevation.popup] y -> elevPopupY.
    """
    raw = tomllib.loads(text)
    out = {}
    for section, body in raw.items():
        if section == "elevation":
            for level, fields in body.items():
                for key, value in fields.items():
                    out[f"elev{level.capitalize()}{_camel(key)}"] = value
            continue
        prefix = "" if section == "depth" else section
        for key, value in body.items():
            name = _camel(key)
            out[(prefix + name) if prefix else (name[0].lower() + name[1:])] = value
    return out


def _camel(key: str) -> str:
    parts = key.split("-")
    return "".join(p.capitalize() for p in parts)


def render_tokens_js(values: dict) -> str:
    lines = [
        ".pragma library",
        "",
        "// Generated by omarchy-style from ~/.config/omarchy/style-tokens.toml.",
        "// Do not edit: the next sync overwrites this file.",
        "",
    ]
    for name in sorted(values):
        lines.append(f"var {name} = {values[name]}")
    return "\n".join(lines) + "\n"


def patch_tokens() -> str:
    if not TOKENS_PATH.is_file():
        return "no token file"
    values = parse_tokens(TOKENS_PATH.read_text())
    js = render_tokens_js(values)
    changed = 0
    for plugin in TOKEN_PLUGINS:
        target = DOTFILES_PLUGINS / plugin / "Tokens.js"
        if not target.parent.is_dir():
            continue
        if target.is_file() and target.read_text() == js:
            continue
        target.write_text(js)
        changed += 1
    return "unchanged" if changed == 0 else f"updated {changed}"
```

Note `parse_tokens`'s `depth` branch: `scrim-alpha` under `[depth]` becomes `scrimAlpha`, with no section prefix, because "depth" adds nothing to the name.

- [x] **Step 6: Call it from `main()`**

Immediately before the existing `report.append(("marcos.dashboard", "surface", patch_dashboard()))` line:

```python
    report.append(("style-tokens", "tokens", patch_tokens()))
```

- [x] **Step 7: Run the tests to verify they pass**

Run: `cd ~/dotfiles && uv run --with pytest pytest tests/test_style_tokens.py -q`
Expected: PASS, 3 tests.

- [x] **Step 8: Run the generator and prove the round trip**

```bash
OMARCHY_PATH=/usr/share/omarchy omarchy-style | grep -E "style-tokens|dashboard"
cat ~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Tokens.js
# deliberately corrupt one value, then prove the sync restores it
sed -i 's/var motionNormal = 260/var motionNormal = 999/' ~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Tokens.js
OMARCHY_PATH=/usr/share/omarchy omarchy-style | grep style-tokens
grep motionNormal ~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Tokens.js
```
Expected: the report line reads `style-tokens tokens updated 3` on the first run, `updated 1` after the corruption, and the final grep shows `260` again.

- [x] **Step 9: Write the reference doc**

Create `~/dotfiles/docs/style/tokens.md` opening with the sentence "The source of truth is `~/.config/omarchy/style-tokens.toml`; every `Tokens.js` is generated and will be overwritten." Then a table of every token name, its value, its unit, and one line on what it is for — the same content as the TOML comments, laid out for reading rather than editing. Close with the two commands: how to change a value (edit the TOML, run `omarchy-style`) and how to see what changed (`git diff`).

- [x] **Step 10: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .local/bin/omarchy-style .local/bin/omarchy-bar-colors .config/omarchy/style-tokens.toml .config/omarchy/plugins/*/Tokens.js tests/test_style_tokens.py docs/style/tokens.md
git commit -m "feat(style): token source of truth and generator"
```

---

### Task 2: Motion on the dashboard

**Files:**
- Modify: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Dashboard.qml`

**Interfaces:**
- Consumes: `Tokens.js` from Task 1.
- Produces: nothing other plugins rely on.

The overlay currently snaps in and out because `PanelWindow.visible` is bound straight to `root.opened`. The window has to outlive the closing animation, which is the same trick Omarchy's own `PopupCard` uses (`visible: open || card.opacity > 0`).

- [x] **Step 1: Import the tokens and keep the window alive during the exit**

```qml
import "Tokens.js" as T
```

Change the `PanelWindow`'s visibility:

```qml
    visible: root.opened || card.opacity > 0
```

- [x] **Step 2: Animate the scrim**

Replace the scrim `Rectangle` with:

```qml
    Rectangle {
      id: scrim
      anchors.fill: parent
      color: Color.menu.scrim
      opacity: root.opened ? 1 : 0
      // Leaving is quicker than arriving: it is what makes the surface feel
      // responsive rather than slow.
      Behavior on opacity {
        NumberAnimation {
          duration: root.opened ? T.motionNormal : T.motionFast
          easing.type: root.opened ? Easing.OutExpo : Easing.OutCubic
        }
      }
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }
```

- [x] **Step 3: Animate the card**

On the `card` Rectangle, add opacity, scale and a vertical offset. `anchors.centerIn: parent` is already there, so the rise is expressed as a centre offset rather than a `y` binding, which would fight the anchor.

```qml
      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : T.motionScaleFrom
      anchors.verticalCenterOffset: root.opened ? 0 : T.motionRise

      Behavior on opacity {
        NumberAnimation {
          duration: root.opened ? T.motionNormal : T.motionFast
          easing.type: root.opened ? Easing.OutExpo : Easing.OutCubic
        }
      }
      Behavior on scale {
        NumberAnimation {
          duration: root.opened ? T.motionNormal : T.motionFast
          easing.type: root.opened ? Easing.OutExpo : Easing.OutCubic
        }
      }
      Behavior on anchors.verticalCenterOffset {
        NumberAnimation {
          duration: root.opened ? T.motionNormal : T.motionFast
          easing.type: root.opened ? Easing.OutExpo : Easing.OutCubic
        }
      }
```

- [x] **Step 4: Verify it opens and closes smoothly**

```bash
OMARCHY_PATH=/usr/share/omarchy omarchy restart shell && sleep 7
OMARCHY_PATH=/usr/share/omarchy omarchy-shell shell summon marcos.dashboard '{}'
sleep 2 && hyprctl layers -j | grep -c marcos-dashboard
OMARCHY_PATH=/usr/share/omarchy omarchy-shell shell hide marcos.dashboard
sleep 2 && hyprctl layers -j | grep -c marcos-dashboard
```
Expected: `1` then `0`. The layer must actually disappear — if `visible` is left true because `card.opacity` never reaches 0, the overlay would keep the keyboard focus and the desktop would appear frozen. This is the failure mode to watch for.

Then capture the midpoint of the animation to prove it is really animating rather than snapping:

```bash
OMARCHY_PATH=/usr/share/omarchy omarchy-shell shell summon marcos.dashboard '{}' & sleep 0.12 && grim -o DP-3 /tmp/mid.png
magick /tmp/mid.png -crop 1700x300+430+130 +repage -resize 70% /tmp/mid-crop.png
```
Read `/tmp/mid-crop.png`. Expected: the card partially faded and slightly offset, not fully drawn and not absent.

- [x] **Step 5: Verify the keyboard still works after the change**

Escape, a click outside, and `SUPER + D` must all still dismiss, and a click inside must not. Use `ydotool` for clicks, remembering its `-a` coordinates are **half** of screen pixels on this display, and `ydotool key 125:1 32:1 32:0 125:0` for `SUPER + D` — `wtype` cannot trigger Hyprland binds.

- [x] **Step 6: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .config/omarchy/plugins/marcos.dashboard/Dashboard.qml
git commit -m "feat(dashboard): animate open and close from the shared tokens"
```

---

### Task 3: Blur and scrim

**Files:**
- Modify: `~/dotfiles/.config/hypr/looknfeel.lua`
- Modify: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Dashboard.qml`

**Interfaces:**
- Consumes: `Tokens.js` (`scrimAlpha`).
- Produces: nothing.

**This task starts with a discovery step, because the Lua syntax for layer rules in this Hyprland is unverified.** Omarchy's own config never writes one. Do not guess it into the file; find out first.

- [x] **Step 1: Discover the layer-rule syntax**

Hyprland here is 0.56.2 with a Lua config layer. Try these in order, checking after each with `hyprctl layerrules` (or `hyprctl -j layers`):

```bash
# candidate A: the hl.config table, same shape as decoration
hyprctl keyword layerrule "blur,marcos-dashboard" && hyprctl layerrules | grep -i marcos
# candidate B: classic keyword through a sourced .conf, since hyprsunset.conf
#              and xdph.conf prove .conf files are still read
grep -rn "source" ~/.config/hypr/*.lua ~/.config/hypr/*.conf | head
```

`hyprctl keyword` applies at runtime without editing anything, so it is the cheap way to learn the accepted spelling before committing to a file. Record which form worked; the remaining steps assume you write it into `looknfeel.lua` in whatever form the Lua layer accepts, matching the `hl.config({ decoration = { ... } })` style already in that file.

If none of the forms work from Lua, fall back to a `~/dotfiles/.config/hypr/blur.conf` sourced from the Lua config, and say so in the commit message.

- [x] **Step 2: Enable blur but exclude windows**

Every window carries `opacity = "0.985 0.96"` from `default/hypr/windows.lua`, so enabling blur globally would start a blur pass behind every one of them for no visible gain. Enable it, then turn it off for windows, leaving only our layer opted in.

```lua
-- Desenfoque: apagado para ventanas a proposito. Omarchy les pone
-- opacity 0.985, asi que blur global costaria una pasada por ventana sin
-- ganancia visible. Solo las superficies propias lo piden por namespace.
hl.config({
  decoration = {
    blur = {
      enabled = true,
      size = 8,
      passes = 2,
      new_optimizations = true,
      ignore_opacity = true,
    },
  },
})

o.window(".*", { no_blur = true })
```

Verify the exact key names before trusting them:
```bash
hyprctl getoption decoration:blur:enabled
hyprctl getoption decoration:blur:size
hyprctl getoption decoration:blur:passes
```
Expected: `int: 1`, `int: 8`, `int: 2`. If a key is rejected, `hyprctl keyword` will say so and the name needs correcting against `hyprctl getoption` rather than guessed.

- [x] **Step 3: Lighten the scrim**

In `Dashboard.qml`, the scrim currently uses `Color.menu.scrim`, whose alpha comes from the theme (0.5 by default). With blur doing the separation, the veil should recede:

```qml
      color: Qt.rgba(Color.menu.scrim.r, Color.menu.scrim.g, Color.menu.scrim.b, T.scrimAlpha)
```

- [x] **Step 4: Calibrate on the real display**

The 9px used in the browser mockup does not map onto Hyprland's `size`/`passes` pair. Judge three candidates on screen with a busy wallpaper and a window behind the card:

```bash
for s in 4 8 12; do
  hyprctl keyword decoration:blur:size $s
  OMARCHY_PATH=/usr/share/omarchy omarchy-shell shell summon marcos.dashboard '{}'
  sleep 1 && grim -o DP-3 /tmp/blur-$s.png
  OMARCHY_PATH=/usr/share/omarchy omarchy-shell shell hide marcos.dashboard
  sleep 1
done
magick /tmp/blur-4.png /tmp/blur-8.png /tmp/blur-12.png -resize 45% -append /tmp/blur-compare.png
```
Read `/tmp/blur-compare.png` and pick the one where the desktop is clearly subordinate but you can still tell what was behind — that is what the user chose. Write the winner into `looknfeel.lua`. Ask the user to confirm the choice rather than deciding alone: this is the one value in the plan that is a matter of taste rather than correctness.

- [x] **Step 5: Confirm windows are not blurred**

```bash
hyprctl clients -j | jq -r '.[0].class'
```
Open the dashboard over a window and read a screenshot: the window behind the card must be blurred (it is under our layer), but with the dashboard closed nothing on the desktop should look softer than before. Compare against a `grim` taken before this task.

- [x] **Step 6: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .config/hypr/looknfeel.lua .config/omarchy/plugins/marcos.dashboard/Dashboard.qml
git commit -m "feat(style): blur the overlay backdrop, not every window"
```

---

### Task 4: Calendar grid logic

**Files:**
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Calendar.js`
- Test: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/test/calendar.test.mjs`
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/test/load.mjs` (copy of the one in `marcos.metrics`)

**Interfaces:**
- Consumes: nothing.
- Produces, as pure functions on the `Calendar` namespace:
  - `monthGrid(year, month) -> Array` of exactly 42 cells `{day: Number, month: -1|0|1}`, Monday first. `month` is 1-12.
  - `monthLabel(year, month) -> String` — `"SEPTIEMBRE 2026"`, Spanish, uppercase.
  - `shiftMonth(year, month, delta) -> {year, month}` — wraps across year boundaries.
  - `isToday(cell, year, month, today) -> Boolean` where `today` is a `Date`.

Headless QML does not run on this machine (`qml` and `qmltestrunner` both exit silently), so this arithmetic lives outside QML to be testable at all — the same reason `Metrics.js` exists.

- [x] **Step 1: Copy the test harness**

```bash
cd ~/dotfiles/.config/omarchy/plugins/marcos.dashboard
mkdir -p test
cp ../marcos.metrics/test/load.mjs test/load.mjs
```

- [x] **Step 2: Write the failing tests**

Six rows of seven is always 42 cells: a fixed grid never reflows as the user pages months, which is what makes the arrows feel solid instead of jumpy.

```javascript
// test/calendar.test.mjs
import { test } from "node:test"
import assert from "node:assert/strict"
import { loadQmlJs } from "./load.mjs"

const C = loadQmlJs(new URL("../Calendar.js", import.meta.url).pathname)

test("the grid is always six rows of seven", () => {
  assert.equal(C.monthGrid(2026, 9).length, 42)
  assert.equal(C.monthGrid(2026, 2).length, 42)
})

test("september 2026 starts on a tuesday, so monday is a filler day", () => {
  const grid = C.monthGrid(2026, 9)
  assert.deepEqual(grid[0], { day: 31, month: -1 })
  assert.deepEqual(grid[1], { day: 1, month: 0 })
})

test("a month starting on monday has no leading filler", () => {
  // June 2026 starts on a Monday.
  const grid = C.monthGrid(2026, 6)
  assert.deepEqual(grid[0], { day: 1, month: 0 })
})

test("a month starting on sunday pushes six filler days first", () => {
  // February 2026 starts on a Sunday.
  const grid = C.monthGrid(2026, 2)
  assert.equal(grid[6].day, 1)
  assert.equal(grid[6].month, 0)
  assert.equal(grid[0].month, -1)
})

test("leap february has twenty-nine days", () => {
  const days = C.monthGrid(2024, 2).filter(c => c.month === 0).map(c => c.day)
  assert.equal(days.length, 29)
  assert.equal(days[28], 29)
})

test("non-leap february has twenty-eight", () => {
  assert.equal(C.monthGrid(2026, 2).filter(c => c.month === 0).length, 28)
})

test("trailing cells belong to the next month", () => {
  const grid = C.monthGrid(2026, 9)
  assert.equal(grid[41].month, 1)
})

test("shiftMonth wraps forward across the year", () => {
  assert.deepEqual(C.shiftMonth(2026, 12, 1), { year: 2027, month: 1 })
})

test("shiftMonth wraps backward across the year", () => {
  assert.deepEqual(C.shiftMonth(2026, 1, -1), { year: 2025, month: 12 })
})

test("monthLabel is spanish and uppercase", () => {
  assert.equal(C.monthLabel(2026, 9), "SEPTIEMBRE 2026")
})

test("isToday only matches a current-month cell on the right date", () => {
  const today = new Date(2026, 8, 13)
  assert.equal(C.isToday({ day: 13, month: 0 }, 2026, 9, today), true)
  assert.equal(C.isToday({ day: 13, month: -1 }, 2026, 9, today), false)
  assert.equal(C.isToday({ day: 13, month: 0 }, 2026, 10, today), false)
})
```

- [x] **Step 3: Run the tests to verify they fail**

Run: `cd ~/dotfiles/.config/omarchy/plugins/marcos.dashboard && deno test --allow-read test/calendar.test.mjs`
Expected: FAIL — `Calendar.js` does not exist, so `loadQmlJs` throws ENOENT.

Before writing the implementation, confirm the weekday assumptions above are real rather than trusted:
```bash
date -d 2026-09-01 +%A   # expect martes / Tuesday
date -d 2026-06-01 +%A   # expect lunes / Monday
date -d 2026-02-01 +%A   # expect domingo / Sunday
```
If any differs, fix the **test**, not the implementation — the calendar is right and the fixture is wrong.

- [x] **Step 4: Write the implementation**

```javascript
// Calendar.js
.pragma library

var MONTHS = ["enero", "febrero", "marzo", "abril", "mayo", "junio",
              "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

function daysInMonth(year, month) {
  // Day 0 of the next month is the last day of this one.
  return new Date(year, month, 0).getDate()
}

// Always 42 cells. A fixed grid never reflows while paging months, which is
// what stops the arrows feeling jumpy.
function monthGrid(year, month) {
  var first = new Date(year, month - 1, 1)
  // getDay() is Sunday-first; the grid starts on Monday.
  var lead = (first.getDay() + 6) % 7
  var total = daysInMonth(year, month)
  var prev = daysInMonth(year, month - 1 === 0 ? 12 : month - 1)
  var cells = []
  for (var i = 0; i < lead; i++)
    cells.push({ day: prev - lead + 1 + i, month: -1 })
  for (var d = 1; d <= total; d++)
    cells.push({ day: d, month: 0 })
  var next = 1
  while (cells.length < 42)
    cells.push({ day: next++, month: 1 })
  return cells
}

function monthLabel(year, month) {
  return (MONTHS[month - 1] + " " + year).toUpperCase()
}

function shiftMonth(year, month, delta) {
  var index = (year * 12) + (month - 1) + delta
  return { year: Math.floor(index / 12), month: (index % 12) + 1 }
}

function isToday(cell, year, month, today) {
  if (!cell || cell.month !== 0 || !today) return false
  return today.getFullYear() === year
    && today.getMonth() + 1 === month
    && today.getDate() === cell.day
}
```

`daysInMonth(year, 0)` is never called because `monthGrid` maps month 0 to 12 before asking, and `new Date(year, 0, 0)` would otherwise return 31 December of the previous year — correct by luck, but not something to rely on.

- [x] **Step 5: Run the tests to verify they pass**

Run: `cd ~/dotfiles/.config/omarchy/plugins/marcos.dashboard && deno test --allow-read test/calendar.test.mjs`
Expected: PASS, 11 tests.

- [x] **Step 6: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .config/omarchy/plugins/marcos.dashboard/Calendar.js .config/omarchy/plugins/marcos.dashboard/test
git commit -m "feat(dashboard): tested month-grid arithmetic"
```

---

### Task 5: `omarchy-agenda --month`

**Files:**
- Modify: `~/dotfiles/.local/bin/omarchy-agenda`
- Modify: `~/dotfiles/tests/test_omarchy_agenda.py`

**Interfaces:**
- Consumes: `khal` on PATH.
- Produces: `omarchy-agenda --month YYYY-MM` prints `{"ok": bool, "reason": str, "days": [Number]}` — the day-of-month numbers holding at least one event, sorted ascending, no duplicates. Always valid JSON, always exit 0, same contract as the default mode.

- [x] **Step 1: Confirm khal's real output for a month range first**

The default mode already taught this lesson: this khal rejects `--color=false` and spells it `--no-color`. Do not assume the month query either.

```bash
khal --no-color list --day-format "" --format "{start-date}" 2026-09-01 2026-09-30
```
Expected: one line per event, each a date in `dd.mm.` form — the `dateformat` from `~/.config/khal/config`. Note the exact shape before writing the parser; if it prints something else, the format string and `parse_days` below change to match.

- [x] **Step 2: Write the failing tests**

Append to `tests/test_omarchy_agenda.py`:

```python
def run_month(path_dir, month="2026-09"):
    env = dict(os.environ, PATH=str(path_dir))
    result = subprocess.run(
        [str(SCRIPT), "--month", month], capture_output=True, text=True, env=env
    )
    return result, json.loads(result.stdout)


def test_month_lists_days_with_events(tmp_path):
    out = "07.09.\n17.09.\n17.09.\n"
    result, data = run_month(fake_khal(tmp_path, out))
    assert result.returncode == 0
    assert data["ok"] is True
    assert data["days"] == [7, 17]


def test_month_with_no_events_is_an_empty_list(tmp_path):
    result, data = run_month(fake_khal(tmp_path, ""))
    assert data["ok"] is True
    assert data["days"] == []


def test_month_without_khal_still_exits_zero(tmp_path):
    result, data = run_month(bin_dir(tmp_path, "nokhal"))
    assert result.returncode == 0
    assert data["ok"] is False
    assert data["days"] == []


def test_month_rejects_a_malformed_argument(tmp_path):
    result, data = run_month(fake_khal(tmp_path, ""), month="septiembre")
    assert result.returncode == 0
    assert data["ok"] is False
    assert "YYYY-MM" in data["reason"]
```

- [x] **Step 3: Run the tests to verify they fail**

Run: `cd ~/dotfiles && uv run --with pytest pytest tests/test_omarchy_agenda.py -q`
Expected: 4 new failures, the original 7 still passing.

- [x] **Step 4: Write the implementation**

Add to `omarchy-agenda`, above `main()`:

```python
import calendar
import re

MONTH_FORMAT = "{start-date}"


def emit_month(ok, days, reason=""):
    payload = {"ok": ok, "reason": reason, "days": days}
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


def parse_days(text, month):
    """Pull day numbers out of khal's dd.mm. dates, keeping only this month."""
    days = set()
    for match in re.finditer(r"\b(\d{1,2})\.(\d{1,2})\.", str(text or "")):
        day, found_month = int(match.group(1)), int(match.group(2))
        if found_month == month and 1 <= day <= 31:
            days.add(day)
    return sorted(days)


def run_month(argument):
    match = re.fullmatch(r"(\d{4})-(\d{2})", argument or "")
    if not match:
        return emit_month(False, [], "expected --month YYYY-MM")
    year, month = int(match.group(1)), int(match.group(2))
    if not 1 <= month <= 12:
        return emit_month(False, [], "expected --month YYYY-MM")

    if shutil.which("khal") is None:
        return emit_month(False, [], "khal is not installed - run omarchy-agenda --setup")

    last = calendar.monthrange(year, month)[1]
    try:
        result = subprocess.run(
            ["khal", "--no-color", "list", "--day-format", "", "--format", MONTH_FORMAT,
             f"{year}-{month:02d}-01", f"{year}-{month:02d}-{last:02d}"],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.SubprocessError) as error:
        return emit_month(False, [], f"khal failed: {error}")

    if result.returncode != 0:
        return emit_month(False, [], (result.stderr or "khal exited non-zero").strip())

    return emit_month(True, parse_days(result.stdout, month))
```

And at the top of `main()`, before the `--setup` check:

```python
    if "--month" in sys.argv:
        index = sys.argv.index("--month")
        return run_month(sys.argv[index + 1] if index + 1 < len(sys.argv) else "")
```

`parse_days` filters on the month because khal prints events from adjacent months when a multi-day event overlaps the range boundary.

- [x] **Step 5: Run the tests to verify they pass**

Run: `cd ~/dotfiles && uv run --with pytest pytest tests/test_omarchy_agenda.py -q`
Expected: PASS, 11 tests.

- [x] **Step 6: Run it against the real calendar**

```bash
omarchy-agenda --month 2026-09 | python3 -m json.tool
```
Expected: `ok: true` and a `days` list that includes `17` — the TFM presentation. Cross-check with `khal --no-color list --day-format "" --format "{start-date} {title}" 2026-09-01 2026-09-30`.

- [x] **Step 7: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .local/bin/omarchy-agenda tests/test_omarchy_agenda.py
git commit -m "feat(agenda): month mode reporting which days hold events"
```

---

### Task 6: The month grid in the HOY column

**Files:**
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/MonthGrid.qml`
- Modify: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Today.qml`

**Interfaces:**
- Consumes: `Calendar.js` (Task 4), `omarchy-agenda --month` (Task 5), `Tokens.js` (Task 1).
- Produces: `MonthGrid.qml` with `property bool active`, `property int year`, `property int month`, `property var eventDays` (array of day numbers).

- [x] **Step 1: Write the component**

```qml
// MonthGrid.qml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Calendar.js" as Calendar
import "Tokens.js" as T

Column {
  id: root

  property bool active: false
  property int year: new Date().getFullYear()
  property int month: new Date().getMonth() + 1
  property var eventDays: []
  property date today: new Date()

  readonly property color accent: "#89b4fa"
  readonly property var cells: Calendar.monthGrid(root.year, root.month)

  spacing: Style.spacing.sm

  function reload() {
    monthProc.command = ["omarchy-agenda", "--month",
                         root.year + "-" + String(root.month).padStart(2, "0")]
    monthProc.running = true
  }

  function page(delta) {
    var next = Calendar.shiftMonth(root.year, root.month, delta)
    root.year = next.year
    root.month = next.month
    root.eventDays = []
    reload()
  }

  onActiveChanged: if (active) reload()

  Process {
    id: monthProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          root.eventDays = (data.ok === true && data.days) ? data.days : []
        } catch (error) {
          root.eventDays = []
        }
      }
    }
  }

  Item {
    width: parent.width
    height: label.implicitHeight

    Text {
      id: label
      text: Calendar.monthLabel(root.year, root.month)
      color: root.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1.2
      font.bold: true
    }

    Row {
      anchors.right: parent.right
      spacing: Style.spacing.md

      Repeater {
        model: [{ glyph: "‹", delta: -1 }, { glyph: "›", delta: 1 }]
        Text {
          text: modelData.glyph
          color: arrow.containsMouse ? root.accent : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          Behavior on color { ColorAnimation { duration: T.motionInstant } }
          MouseArea {
            id: arrow
            anchors.fill: parent
            anchors.margins: -Style.spacing.sm
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.page(modelData.delta)
          }
        }
      }
    }
  }

  Grid {
    width: parent.width
    columns: 7
    spacing: 2

    Repeater {
      model: ["L", "M", "X", "J", "V", "S", "D"]
      Text {
        width: (root.width - 12) / 7
        horizontalAlignment: Text.AlignHCenter
        text: modelData
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    Repeater {
      model: root.cells
      Item {
        width: (root.width - 12) / 7
        height: dayText.implicitHeight + Style.spacing.sm

        readonly property bool current: modelData.month === 0
        readonly property bool isToday: Calendar.isToday(modelData, root.year, root.month, root.today)
        readonly property bool hasEvent: current && root.eventDays.indexOf(modelData.day) !== -1

        Rectangle {
          anchors.fill: parent
          radius: 3
          color: parent.isToday ? root.accent : "transparent"
        }

        Text {
          id: dayText
          anchors.centerIn: parent
          text: modelData.day
          color: parent.isToday ? Color.menu.background
            : (parent.current ? Color.menu.text : Color.muted)
          opacity: parent.current ? 1 : 0.45
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Rectangle {
          visible: parent.hasEvent
          width: 3
          height: 3
          radius: 1.5
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          color: parent.isToday ? Color.menu.background : root.accent
        }
      }
    }
  }
}
```

- [x] **Step 2: Mount it at the foot of the HOY column**

In `Today.qml`, after the reminders `Repeater` and its "Sin recordatorios" text, add:

```qml
  MonthGrid {
    width: parent.width
    active: root.active
  }
```

- [x] **Step 3: Verify against the real calendar**

```bash
OMARCHY_PATH=/usr/share/omarchy omarchy restart shell && sleep 7
OMARCHY_PATH=/usr/share/omarchy omarchy-shell shell summon marcos.dashboard '{}'
sleep 3 && grim -o DP-3 /tmp/cal.png
magick /tmp/cal.png -crop 560x420+430+300 +repage -resize 180% /tmp/cal-crop.png
```
Read `/tmp/cal-crop.png`. Expected: the current month, today filled in blue with dark text, a dot under the 17th, filler days from the neighbouring months dimmed, and exactly six rows.

Then test paging: click `›` twice and confirm the label moves to November, the grid stays six rows, and the dots follow the new month rather than staying on September's.

- [x] **Step 4: Verify the degraded path**

```bash
PATH=/nonexistent omarchy-agenda --month 2026-09
```
Expected: `{"ok": false, ..., "days": []}`. With that, the grid must still render every day correctly and simply show no dots — a calendar that cannot reach khal is still a usable calendar.

- [x] **Step 5: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .config/omarchy/plugins/marcos.dashboard
git commit -m "feat(dashboard): month grid with event dots in the today column"
```

---

### Task 7: Dashboard layout — centred header, separators, density

**Files:**
- Modify: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Dashboard.qml`
- Modify: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Section.qml`
- Modify: `~/dotfiles/.config/omarchy/plugins/marcos.dashboard/Entry.qml`

**Interfaces:**
- Consumes: `Tokens.js`.
- Produces: `Section.qml` gains `property bool divider` — draws a vertical rule on its left edge.

- [x] **Step 1: Centre the header**

In `Dashboard.qml`, the header `Item` currently left-aligns `timeText` and `dateText` and right-anchors the status row. Centre the two texts, leaving the status where it is:

```qml
          Text {
            id: timeText
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, "HH:mm")
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.display * 2
          }
          Text {
            id: dateText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: timeText.bottom
            text: root.spanishDate()
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
```

- [x] **Step 2: Add the rule under the header**

Between the header `Item` and the `Row` of sections, inside the same `Column`:

```qml
        Rectangle {
          width: parent.width
          height: 1
          color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, T.ruleAlpha)
        }
```

- [x] **Step 3: Give `Section.qml` a left divider**

Add to `Section.qml`:

```qml
  property bool divider: false

  Rectangle {
    visible: root.divider
    width: 1
    x: -Style.spacing.lg
    height: parent.height
    color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, T.ruleAlpha)
  }
```

The rule sits in the gutter rather than inside the column, so it separates without stealing width from the text.

Then in `Dashboard.qml`, set `divider: true` on the second and third `Section` only — the first column has nothing to its left.

- [x] **Step 4: Replace the text-dash separators**

In `Today.qml` and `Missed.qml`, the group headings are built from literal dashes (`"── recordatorios ──"`, `"── en marcha ──"`). Replace each with a hairline above a plain label:

```qml
  Rectangle {
    width: parent.width
    height: 1
    color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, T.ruleAlpha)
  }

  Text {
    text: "recordatorios"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.2
    topPadding: Style.spacing.sm
    bottomPadding: Style.spacing.xs
  }
```

Use `"en marcha"` for the corresponding label in `Missed.qml`.

- [x] **Step 5: Verify the whole card**

```bash
OMARCHY_PATH=/usr/share/omarchy omarchy restart shell && sleep 7
OMARCHY_PATH=/usr/share/omarchy omarchy-shell shell summon marcos.dashboard '{}'
sleep 3 && grim -o DP-3 /tmp/card.png
magick /tmp/card.png -crop 1700x820+430+130 +repage -resize 65% /tmp/card-crop.png
```
Read `/tmp/card-crop.png` and compare against the approved mockup. Expected: time and date centred with the status dot still right, a hairline under the header, vertical rules in both gutters, hairlines above the group labels, and the calendar filling the foot of the first column. The empty band that used to occupy the lower two thirds should be gone or much reduced.

Sample the rule colour rather than judging it by eye — at this size a hairline at 16% alpha is easy to mistake for absent:
```bash
magick /tmp/card.png -crop 1x60+1000+400 +repage -format "%[pixel:p{0,30}]" info:
```

- [x] **Step 6: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .config/omarchy/plugins/marcos.dashboard
git commit -m "feat(dashboard): centred header, rules between groups and columns"
```

---

### Task 8: State colour transitions in the bar

**Files:**
- Modify: `~/dotfiles/.config/omarchy/plugins/marcos.netspeed/BarWidget.qml`
- Modify: `~/dotfiles/.config/omarchy/plugins/marcos.sysmon/BarWidget.qml`

**Interfaces:**
- Consumes: `Tokens.js`.
- Produces: nothing.

These two widgets own semantic state colours — `netspeed` turns blue while transferring, `sysmon` turns amber and then red with temperature — and both currently snap between them. Hover and press are not touched: those belong to Omarchy's `WidgetButton`.

- [x] **Step 1: Find where each widget hands a colour to its button**

```bash
grep -n "foreground\|activeColor\|useActiveColor\|transferring\|warm\|hot" \
  ~/dotfiles/.config/omarchy/plugins/marcos.netspeed/BarWidget.qml \
  ~/dotfiles/.config/omarchy/plugins/marcos.sysmon/BarWidget.qml
```

The colour is passed into `WidgetButton`. A `Behavior` cannot be attached from outside that component, so the transition goes on a local property that the binding reads instead.

- [x] **Step 2: Add an animated local colour in `marcos.netspeed`**

```qml
import "Tokens.js" as T
```

```qml
  // WidgetButton is Omarchy's and cannot carry our Behavior, so the animation
  // lives on a local property and the button reads that.
  readonly property color targetColor: root.transferring ? "#89b4fa" : root.bar.barForeground
  property color animatedColor: targetColor
  Behavior on animatedColor {
    ColorAnimation { duration: T.motionInstant; easing.type: Easing.OutCubic }
  }
  onTargetColorChanged: animatedColor = targetColor
```

Then point the `WidgetButton`'s `foreground` at `root.animatedColor`.

- [x] **Step 3: Do the same in `marcos.sysmon`**

Same shape, three states rather than two:

```qml
import "Tokens.js" as T
```

```qml
  readonly property color targetColor: root.hot ? "#f38ba8"
    : (root.warm ? "#f9e2af" : root.bar.barForeground)
  property color animatedColor: targetColor
  Behavior on animatedColor {
    ColorAnimation { duration: T.motionInstant; easing.type: Easing.OutCubic }
  }
  onTargetColorChanged: animatedColor = targetColor
```

- [x] **Step 4: Verify the transition happens**

Force a transfer and capture two frames close together:

```bash
OMARCHY_PATH=/usr/share/omarchy omarchy restart shell && sleep 7
(timeout 20 curl -s -o /dev/null https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso &)
sleep 2 && grim -o DP-3 /tmp/n1.png && sleep 3 && grim -o DP-3 /tmp/n2.png
magick /tmp/n1.png -crop 520x44+2000+0 +repage -resize 250% /tmp/n1-crop.png
magick /tmp/n2.png -crop 520x44+2000+0 +repage -resize 250% /tmp/n2-crop.png
```
Read both. Expected: the rate is blue in the second and the widget is legible in both. A 90ms transition is hard to catch mid-flight in a screenshot, so the real check is that nothing regressed — the colour still ends up right and the number still updates.

- [x] **Step 5: Verify the fallback is intact**

```bash
rm ~/.config/omarchy/plugins/marcos.metrics
OMARCHY_PATH=/usr/share/omarchy omarchy restart shell && sleep 8
grim -o DP-3 /tmp/fb.png
magick /tmp/fb.png -crop 520x44+2000+0 +repage -resize 250% /tmp/fb-crop.png
ln -sfn ~/dotfiles/.config/omarchy/plugins/marcos.metrics ~/.config/omarchy/plugins/marcos.metrics
OMARCHY_PATH=/usr/share/omarchy omarchy restart shell
```
Read `/tmp/fb-crop.png`. Expected: both widgets still show live numbers from their own readers. Removing the symlink is the only way to test this — `omarchy plugin disable` leaves `ensureService()` free to instantiate the service anyway.

- [x] **Step 6: Commit and push** (ask the user first)

```bash
cd ~/dotfiles
git add .config/omarchy/plugins/marcos.netspeed .config/omarchy/plugins/marcos.sysmon
git commit -m "feat(bar): animate the semantic state colours we own"
git push origin main
```

---

## Done when

- `omarchy-style` reports `style-tokens tokens unchanged` on a clean tree, and restores a corrupted token.
- `deno test` passes in `marcos.metrics` (19) and `marcos.dashboard` (11).
- `pytest` passes in `~/dotfiles/tests` (15: 11 agenda, 3 tokens — plus any added).
- The dashboard opens and closes with visible motion, over a blurred backdrop, and the layer disappears on close.
- The card shows a centred header, rules between columns and groups, and a month calendar with today highlighted and event dots.
- With `marcos.metrics` unlinked, the bar still shows live CPU, RAM, temperature and network.
- `journalctl --user` clean of new errors.
