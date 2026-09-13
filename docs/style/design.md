# Visual Language Design

**Status:** approved 2026-09-13. Implementation plan: `plan.md`. Token reference: `tokens.md` (written during implementation).

## Goal

Close the gap between this shell and the reference dotfiles (caelestia-dots/shell, Odyssey) on the axis the user named: how considered and elegant it looks. The dashboard built earlier today works but reads as unfinished — it has no animation at all, two thirds of its card are empty, and nothing separates one column from the next.

This is the third of four gaps identified against caelestia. The dashboard closed the first. A unified control center and a notification center remain, and each gets its own design cycle. A todolist surface was raised during this discussion and is explicitly deferred to its own cycle too.

The return on this work is mostly forward-looking. It improves the dashboard now, but its real value is that the control center, the notification center and the todolist are born speaking this language instead of being retrofitted into it.

## Scope

**In scope:** the twenty-two `marcos.*` plugins and every surface built from here on.

**Out of scope, and not by choice:** two of the four things the user initially asked for turn out to belong to Omarchy, not to us.

| Surface | Owner | Current behaviour |
|---|---|---|
| Bar widget hover and press | `Ui/WidgetButton.qml` | opacity 140ms, colour 160ms, both OutCubic |
| Popup container enter/exit | `Ui/PopupCard.qml` | opacity 140ms OutCubic |
| Panel *content* | ours | unstyled |
| Overlays we author | ours | unstyled |

The user chose not to override Omarchy's `Ui/` components, because every `omarchy update` could stamp on them. That decision stands, and it means bar hover/press and popup entrance timing stay as Omarchy defines them.

What remains genuinely ours: the dashboard in full, the content inside our five panels, the semantic state colours in `marcos.netspeed` and `marcos.sysmon`, and every future surface.

**Accepted consequence:** the dashboard will open in 260ms while bar popups open in 140ms. This is deliberate, not an inconsistency — a full-screen surface travels further than a small popup, and duration scaling with surface size is normal in design systems. It is recorded here so nobody "fixes" it later.

## Decisions

### Motion

Chosen from three animated alternatives shown side by side. The user picked the middle option: decisive but without overshoot.

| Token | Value | Used for |
|---|---|---|
| `instant` | 90ms | semantic state changes we own: `netspeed` going blue on traffic, `sysmon` going amber on heat |
| `fast` | 150ms | transitions inside a surface that is already open |
| `normal` | 260ms | opening and closing a surface |

- Enter curve: `Easing.OutExpo`. Exit curve: `Easing.OutCubic`.
- **Exit is always faster than enter** (exit runs at `fast`). This is what makes a surface feel responsive rather than slow.
- Enter offset: 8px upward translation, paired with a scale from 0.965 and opacity from 0.

The rejected alternatives, recorded so the question is not reopened blind: a 150ms opacity-only fade (matches Omarchy exactly but is imperceptible on a full-screen card), and a 420ms spring with overshoot (the caelestia look — striking in a demo, wearing by the third time in a day).

### Depth

The user picked medium blur over a flat scrim and over heavy blur.

- Backdrop: `layerrule = blur` on our overlay layers only, with the scrim alpha dropped from the current 0.55 to 0.30. The point of the lighter scrim is that blur already does the separation work, so the veil no longer has to.
- Enabling `decoration:blur:enabled` in Hyprland is safe here: there is currently no translucent window anywhere on this machine (no opacity rules, no terminal transparency, bar `transparent: false`), so the setting changes nothing until a layer opts in by name.
- Three elevation levels: bar (no shadow), popup, overlay. The concrete offsets, blurs and alphas live in `style-tokens.toml`; this design fixes only that there are three and what each is for.

**Must be calibrated on screen.** The 9px used in the browser mockup does not map one-to-one onto Hyprland's blur. The plan carries an explicit calibration step with candidate values judged on the real display.

### Space and separators

This is where the dashboard's empty card gets fixed. Two rules:

1. **A surface either fits its content or justifies why not.** The dashboard justifies its fixed height: a card that resizes daily — tall on a Thursday with six events, short on an empty Sunday — is worse to open every day than one that is occasionally underfull.
2. **Separation is earned in this order: space, then a line, then a background.** Use the cheapest one that works. A vertical rule between columns, a hairline between groups within a column, a filled background only for genuinely independent modules.

The current `── recordatorios ──` built from text dashes is a workaround and goes away.

### Typography and surface colour

- A size and weight hierarchy applied across our panels and the dashboard, replacing the current ad-hoc mix.
- Colour roles beyond the five existing cluster accents: base background, raised background, primary text, secondary text, disabled. The five cluster accents (identity `#cba6f7`, resources `#a6e3a1`, devices `#94e2d5`, context `#89b4fa`, tools `#fab387`) are unchanged — they already work and `omarchy-style` already keeps them in sync.

## Delivery

Tokens reach the plugins as generated constants, not through a runtime service.

1. **`~/.config/omarchy/style-tokens.toml`** holds every value. Data, not code, so a duration can be changed without opening Python or QML — the same role `shell.toml` plays for font size.
2. **`omarchy-style`** (renamed from `omarchy-bar-colors`, with a symlink left at the old name so muscle memory and any hook keep working) reads that TOML and writes a `Tokens.js` into each `marcos.*` plugin, alongside the cluster-hex rewriting it already does.
3. **Each plugin does `import "Tokens.js" as T`**, the pattern `marcos.metrics` already uses for `Metrics.js`.

**Why not a `marcos.style` service.** A service was the alternative. It gives a true single source at runtime, but every animated component would need `duration: style ? style.normal : 260` and a null fallback, exactly the verbosity the metrics fallback already imposes on `sysmon`. Generated constants cost nothing at runtime, need no null checks, and reuse machinery that already exists and is already verified.

**Known limitation:** a QML `.js` library cannot export easing curves, which are QML enums. Tokens therefore carry numbers only — durations, offsets, alphas, blur radii, sizes, spacing — and the curve is written literally in QML as `Easing.OutExpo`. That is a named constant, not a magic number, and `omarchy-style` can rewrite it by regex the same way it rewrites hexes.

**Trade-off accepted:** `Tokens.js` exists in one copy per plugin that animates anything — not all twenty-two need it. Editing one by hand will be overwritten on the next sync. The source of truth is the TOML, and `tokens.md` will say so in its first line.

## The dashboard, redesigned

The user chose the dense three-column layout over a content-fitted card and over a module grid.

**Header.** Time and date centred, not left-aligned as today. The status dot stays at the right edge.

**Columns.** Three, as now, but filled: more rows per column, a full-width sparkline in MÁQUINA, hairlines between groups and vertical rules between columns.

**Calendar.** A month grid anchored to the foot of the HOY column — the time column, next to the events the eye is already reading. Today is highlighted; days holding events carry a dot. `‹ ›` arrows page through months.

The dot is what makes the calendar earn its place: it answers both "what weekday is the 12th" and "when do I have things" in one glance, which was the user's actual question.

Rejected: a dedicated fourth column (squeezes the other three exactly where the sparkline lives) and a full-width three-month band (fills the space best, but three months is more than a daily glance needs).

### Data this requires

`omarchy-agenda` currently answers only "what is on today". Marking days with events needs a month mode: given a year and month, return the set of days holding at least one event. Same JSON-always-valid contract, same fake-khal test approach as the existing seven tests.

The calendar grid arithmetic — which weekday the 1st falls on, how many leading and trailing filler days, leap years, months needing six rows — goes into a `Calendar.js` with real tests, for the same reason `Metrics.js` exists: headless QML does not run on this machine, so pure logic must be separable to be testable.

## Interactivity

The user asked for the surfaces to feel "more interactive". This cycle delivers the part that is presentational: the calendar's `‹ ›` month paging, hover feedback on anything clickable, and the press/hover states of controls we draw ourselves.

It does **not** make dashboard entries actionable — clicking an event to open it, a notification to jump to its app, a metric to open its panel. That is functionality, not visual language, and it belongs to each surface's own cycle. Recorded here so the gap is deliberate rather than forgotten.

## Verification

Three kinds, because a plan built on unchecked assumptions cost eight defects earlier today.

**Pure logic:** `Calendar.js` under `deno test`. Mandatory cases: a month starting on Sunday, one starting on Monday, a leap February, and a month needing six rows.

**Script behaviour:** `omarchy-agenda --month` under pytest with a fake `khal` on PATH. The real khal output format is confirmed empirically *before* the parser is written, not after.

**Visual:** `grim` capture, `magick` crop and zoom, compared against the approved mockups. Two lessons carried forward from today: at true size subtle tones mislead, so colour is judged by sampling pixels rather than by eye on a small screenshot; and the degraded state is checked, not only the good one.

**Non-regression after every task:** the bar still works, the `sysmon` and `netspeed` fallbacks still work — verified by removing the plugin symlink, since `ensureService()` ignores `isEnabled()` and `omarchy plugin disable` is not enough — and `journalctl --user` stays clean.

**Sync correctness:** deliberately corrupt a token, run `omarchy-style`, confirm restoration. This is how the colour propagation was validated today.

## Open items

- Blur radius: calibrate on the real display against three candidates.
- Whether `Easing` enum values can be tokenised is unverified; the design does not depend on it.

## Not in this cycle

Unified control center, notification center, todolist. Each gets its own `docs/<topic>/` with its own design and plan, and each will be built in this language.
