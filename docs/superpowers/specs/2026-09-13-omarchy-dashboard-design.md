# Omarchy dashboard — design

Date: 2026-09-13
Status: approved, not yet implemented

## Why

The bar is finished as a bar: nine custom widgets, five colour clusters, and
nothing left to add that would not make it noisier. What it cannot do is answer
"what happened while I was away" in one glance, because a bar widget is a slot
for one number.

Omarchy's plugin system supports six surface kinds — `bar-widget`, `panel`,
`overlay`, `menu`, `service`, `bar` — and so far only `bar-widget` has been
used. The dashboard is the first use of `overlay`: a summoned full-screen
surface. Nothing about Omarchy was blocking the richer desktop; the widget slot
was.

## Scope

A read-only "what's up" surface, summoned with `SUPER + D`, that answers: what
is on today, what did I miss, and how is the machine. Read, close, act
elsewhere.

Out of scope for v1, by decision: multi-account calendars, creating events,
notification history beyond the ten entries Omarchy keeps, and any interactive
control. Each can be added later as another block without reworking what is
here.

## Architecture

Two new plugins plus one script.

### `marcos.metrics` — `kind: "service"`

A headless singleton holding every system reader currently duplicated across
bar widgets: `/proc/stat`, `/proc/meminfo`, the hwmon temperature inputs, and
the `rx_bytes`/`tx_bytes` counters of the default-route interface.

This is the load-bearing decision. Today `marcos.sysmon` and `marcos.netspeed`
each run their own timer and their own set of `FileView`s. After this change
there is one timer and one set of readers, and both widgets become views over
the service. The dashboard is therefore not a new cost — it arrives alongside a
net reduction.

The service also keeps a 60-sample ring buffer per metric (~2 minutes at the
existing 2s tick) so the dashboard can draw sparklines. Sixty floats per metric
is not a cost worth optimising.

Cross-plugin access is supported first-class: `shell.ensureService(id)`
instantiates a service lazily and `shell.serviceFor(id)` returns it. An overlay
receives `shell` by injection; a bar widget reaches it through `bar.shell`.

### `marcos.dashboard` — `kind: "overlay"`, `keepLoaded: false`

The card. `keepLoaded: false` is deliberate: closed, the overlay does not exist
— no object, no timer, no memory. Opening costs roughly 30 ms because the
`omarchy-shell` process is already warm.

Contract, matching the stock overlays: an `Item` exposing `open(payloadJson)`,
`close()`, `dismiss()` and `toggle()`, with a `PanelWindow` anchored to all four
edges on `WlrLayer.Overlay` and `WlrKeyboardFocus.Exclusive`.

### `omarchy-agenda` — script

Prints today's events as JSON. Run once when the panel opens; never polled.

`vdirsyncer` syncs Google Calendar into local `.ics` files on a systemd timer;
`khal` queries them. Recurrence is the reason not to parse ICS by hand — RRULE,
EXDATE and timezone handling are where every hand-rolled parser is wrong, and
khal already solves them. Both packages are in Arch's `extra` repository, not
the AUR.

The shell never holds a token and never talks to Google; it runs a local
command that prints JSON, the same shape as `omarchy-qbittorrent`.

## Data sources by cost

| Block | Source | When it costs |
|---|---|---|
| CPU / RAM / temp / network | `marcos.metrics` | already paid today, and less |
| Missed notifications | `~/.local/state/omarchy/notifications/history/*.json` | only while open |
| Reminders | `marcos.reminders` | already paid |
| Snapshots / downloads | existing widget readers | already paid |
| Agenda | `omarchy-agenda` | one process, on open |

Notification history is one JSON file per entry on disk, trimmed to the newest
ten by the notifications service. Reading the directory with `FolderListModel`
plus `FileView` means zero coupling to that plugin's internals — the contract is
the filesystem, which survives upstream refactors.

## Layout

A centred card, roughly 1700x820 on the 2560x1080 ultrawide, over a blurred
desktop. Wide and low rather than narrow and tall: vertical space is the scarce
resource at 1080px, and a narrow card strangles the content while making the
side margins conspicuous.

Header: time, date, uptime, and one overall status dot. The dot is green
unless something needs attention: a temperature in the warn or hot tier, a
pacman transaction without a snapshot, or the root filesystem below 10% free.
It exists so the header answers "is anything wrong" before the eye reaches the
third column. Below it three columns —
HOY (agenda, then reminders), QUÉ ME PERDÍ (notifications, then what is
running), MÁQUINA (sparklines, network, disk, snapshot week).

Column titles carry the bar's cluster colours: HOY in blue (context), QUÉ ME
PERDÍ in peach (tools), MÁQUINA in green (resources); body text neutral. The
point is not decoration — the same colour meaning the same kind of thing in both
surfaces means the new surface needs no learning.

Each sparkline renders the most recent 30 of the 60 buffered samples as a `Row`
of 30 `Rectangle`s with height bound to the sample — three sparklines, 90
rectangles. Not a `Canvas`: a Canvas repaints in software, and 90 rectangles are
a cost the scene graph does not notice. They exist only while the panel is
open.

## Interaction

Read-only. `SUPER + D` toggles (verified free), `ESC` and click-outside close.
The single exception is a discreet "clear" on the notification block, because
reading notifications and finding them still there tomorrow is worse than the
control is worth.

## Empty and failure states

A dashboard with empty boxes reads as broken, so each has a defined state:

| Situation | What shows |
|---|---|
| No events today | "Nada en la agenda" |
| `khal` unconfigured | "Agenda sin configurar · `omarchy-agenda --setup`" |
| No notifications | "Nada que revisar" |
| Service fails to load | MÁQUINA block hides; everything else works |
| `vdirsyncer` offline | Last local `.ics` plus the time of the last sync |

`marcos.sysmon` and `marcos.netspeed` fall back to their current direct reads
when `serviceFor` returns `null`, so a broken service degrades the dashboard
rather than the bar.

## Risk

Thinning `sysmon` and `netspeed` edits code that currently works. The fallback
above is the mitigation, but this is real work on something not broken, and it
is the regression to watch.

## Verification

1. Clean shell start: `journalctl --user -b --since "10 seconds ago" | grep -iE "omarchy-shell.*(error|warn)"` empty.
2. `grim -o DP-3` plus a `magick` crop of the card, read as an image — small screenshots lie about colour, so sample pixels for colour judgements.
3. Disable `marcos.metrics` on purpose and confirm the bar still works.
4. CPU and RSS before and after; expected equal or better, given the timer removed.
