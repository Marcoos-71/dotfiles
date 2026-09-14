# Quick capture — design

Date: 2026-09-14
Status: approved, not yet implemented. Implementation plan: `plan.md`.

## Why

Something worth remembering arrives while sitting at the desk — a game to play,
a book, a place to go, a project worth starting. Today that thought either goes
nowhere or costs a context switch into Obsidian. The bar already has a widget
for this (`marcos.vault-capture`) and it works, but it only takes a title and
only knows four categories, so anything with substance — why the place is
interesting, a link, whether the game is a roguelike — has to be added later by
hand, which means it never is.

The goal is that a thought captured from the bar lands as a finished note in the
right folder, with the frontmatter its dashboard queries, and needs no second
pass. Capture it at 23:00 from the bar; find it tomorrow in 🎮 Games List or
📚 Reading List without touching it.

## What exists today

`marcos.vault-capture` is a `Panel` + `KeyboardPanel` with a row of category
chips (Idea, Proyecto, Manual, Viaje), one `TextField`, and a list of the five
newest notes in the selected folder. Saving builds the markdown in QML and
writes it with an inline `sh -c`. The categories are a literal array inside
`BarWidget.qml`.

Everything below is an extension of that widget. No new plugin, no new bar icon.

## Scope

**In scope:** seven capture categories, each with its own short form; the note
shapes they produce; the declarative table that drives both; a writer script.

**Out of scope, each getting its own cycle:** the downloads panel gaining
actions, a cleanup panel replacing the floating terminal, and editing an
existing note's `status` from the bar (marking a game played). Cover art is out
of scope as a lookup — see *Covers*.

## Architecture

Three pieces, each testable on its own.

### 1. The category table — `Capture.js`

One declarative array. Each entry says where the note goes, what `type` it
carries, which fields the form asks for, and what body the note gets:

```javascript
{
  key: "game",
  label: "Juego",
  icon: "󰊗",
  folder: "20-Media/Games",
  fields: [
    { key: "saga",   label: "Saga",    kind: "text" },
    { key: "genre",  label: "Género",  kind: "text" },
    { key: "year",   label: "Año",     kind: "number" },
    { key: "steam",  label: "Steam ID", kind: "text", hint: "para la portada" },
    { key: "status", label: "Estado",  kind: "choice", value: "to-play",
      options: [{ value: "to-play", label: "Por jugar" },
                { value: "playing", label: "Jugando" },
                { value: "played",  label: "Jugado" }] }
  ]
}
```

The panel knows nothing about games. It walks this array and renders controls.
A new category later is an entry here, not new QML.

### 2. Field kinds

| Kind | Control | Used for |
|---|---|---|
| `text` | `TextField` | author, saga, genre, country |
| `number` | `TextField` with numeric validator | year |
| `choice` | `ButtonGroup` — chips, one click, no typing | status, priority, travel kind, movie vs show |
| `multiline` | `MultilineField.qml` (ours, see below) | the notes body, present on every category |

**Anything with a handful of options is a chip, never typed.** `ButtonGroup`
from `qs.Ui` already does mutually-exclusive chips with h/l keyboard walking,
which is what the category row uses today.

`qs.Ui.TextField` extends `TextInput` and is single-line, and Omarchy ships no
multi-line input, so the notes body needs one component of our own — a
`TextEdit` wrapped in the same border treatment. It lives in the plugin, it does
not override anything upstream.

### 3. `buildNote(category, values)` — plain JS

Takes the category entry and the filled form, returns the finished markdown
string. Pure function, no I/O, tested with `deno` the way `Calendar.js` is —
which matters because headless QML does not run on this machine.

It owns three things: the frontmatter (schema fields in the vault's order,
unfilled keys left empty rather than omitted, exactly like the notes Book Search
writes), the title line, and the body template.

### 4. `omarchy-capture` — the writer

Python, stdlib only, reads `{folder, filename, body}` as JSON on stdin and
writes the file, resolving name collisions (`Dune 2.md`) and creating the folder
if needed. Prints `{"ok": bool, "path": str, "reason": str}` and always exits 0,
the same contract as `omarchy-agenda`. Tested with pytest.

This replaces the inline `sh -c` in the QML. With seven categories, optional
fields and accents in filenames, the writing rules deserve tests.

### Where each piece lives

| File | What |
|---|---|
| `.config/omarchy/plugins/marcos.vault-capture/Capture.js` | the category table and `buildNote` |
| `.config/omarchy/plugins/marcos.vault-capture/Panel.qml` | the form renderer, rewritten |
| `.config/omarchy/plugins/marcos.vault-capture/MultilineField.qml` | the notes input |
| `.config/omarchy/plugins/marcos.vault-capture/test/capture.test.mjs` | `deno` tests |
| `.local/bin/omarchy-capture` | the writer |
| `tests/test_omarchy_capture.py` | `pytest` tests |

`BarWidget.qml` keeps the bar button and loses the category array and the
note-building it does today.

## The categories

Every category asks for **Título** (required, focused on open) and **Notas**
(multiline, optional — links, why it is interesting, anything).

| Category | Folder | Own fields | Frontmatter written |
|---|---|---|---|
| 💡 Idea | `00-Inbox` | — | `type: idea`, `tags: [inbox]`, `created` |
| 🚀 Proyecto | `10-Projects` | Prioridad *(chips: baja/media/alta)* | `type: project`, `status: idea`, `priority`, `created`, `tags: [project]` |
| 🔧 Manual | `11-Manual-Projects` | Prioridad | same plus `tags: [project, manual]` |
| ✈️ Viaje | `16-Travel` | País · Región · Tipo *(chips: ciudad/naturaleza/ruta/playa)* · Estado *(chips: idea/planeado/hecho)* | `type: travel`, `country`, `region`, `kind`, `status`, `created`, `tags: [travel]` |
| 📖 Libro | `20-Media/Books` | Autor · Saga · Género · Estado *(chips: por leer/leyendo/leído)* | `type: book`, `title`, `author`, `series`, `cover: ""`, `status`, `rating:`, `category`, `published:`, `started:`, `finished:`, `tags: [book]` |
| 🎬 Peli/Serie | `20-Media/Movies` | Peli o serie *(chips)* · Director · Año · Género · Estado *(chips: por ver/viendo/vista)* | `type: movie\|show`, `title`, `year`, `director`, `genre`, `status`, `rating:`, `runtime:`, `released:`, `poster:`, `watched:`, `tags: [movie]` |
| 🎮 Juego | `20-Media/Games` | Saga · Género · Año · Steam ID · Estado *(chips: por jugar/jugando/jugado)* | `type: game`, `title`, `saga`, `developer: ""`, `publisher: ""`, `genre: [Género]`, `category: Género`, `year`, `status`, `rating:`, `hours:`, `cover`, `finished:`, `tags: [game]` |

**Chips show Spanish, store English.** `Por jugar` writes `status: to-play`.
The vault's own rule (`~/Vault/CLAUDE.md`): never translate frontmatter values,
because every dashboard query matches them literally.

**Travel has no schema in the vault yet** — `16-Travel/` is empty. This design
defines one, and the implementation adds it to `~/Vault/CLAUDE.md` next to the
book, movie and project schemas so a hand-written travel note and a captured one
agree.

**The game Género fills two keys.** `category` is the single bucket the games
grid groups by; `genre` is the array shown on the card. One typed word fills
both, and a second genre can be added later in Obsidian.

## The note that comes out

Each category carries the body template of the folder it writes into, copied
from the notes already there — a captured note must be indistinguishable from
one made by Book Search or Media DB. Games and movies keep the `> [!info] Ficha`
callout and the `📝 Notas` / `💭 Opinión` / `🔗 Relacionado` headings; books keep
the English headings Book Search writes (`📝 Notes & Highlights`, `💭 Review`);
projects follow `90-Templates/Project.md`, including the empty `- [ ]` under
próximos pasos and the `📓 Registro` line.

```markdown
---
type: game
title: "Hollow Knight: Silksong"
saga: "Hollow Knight"
developer: ""
publisher: ""
genre: ["Metroidvania"]
category: "Metroidvania"
year: 2025
status: to-play
rating: 
hours: 
cover: "https://cdn.cloudflare.steamstatic.com/steam/apps/1030300/library_600x900_2x.jpg"
finished: 
tags:
  - game
---

> [!info] Ficha
> **Género:** Metroidvania · **Año:** 2025

## 📝 Notas
Lo que escribiste en el campo de notas.

## 💭 Opinión


## 🔗 Relacionado
- Género: [[Metroidvania]]
```

## Covers

The panel cannot look up cover art: that is what Book Search and Media DB do,
each against its own API, and reimplementing either is a project of its own.
Captured books and movies are born with `cover: ""` / `poster:` empty and show a
blank tile in 📚 Reading List until filled in Obsidian.

Games are the exception, and cheaply: every game note in the vault uses the same
Steam URL shape, so the optional **Steam ID** field builds
`https://cdn.cloudflare.steamstatic.com/steam/apps/<id>/library_600x900_2x.jpg`
and the note is complete on arrival. Left empty, the note is still valid.

## The panel

```
┌─────────────────────────────────────────┐
│ Captura rápida                          │
│ [💡 Idea] [🚀 Proy] [🔧 Manual] [✈️ Viaje] │
│ [📖 Libro] [🎬 Peli] [🎮 Juego]           │
│ ─────────────────────────────────────── │
│ Título  ┃___________________________┃   │
│ Saga    ┃________┃  Género ┃________┃   │
│ Año     ┃____┃     Steam ┃_________┃    │
│ Estado  (Por jugar)(Jugando)(Jugado)    │
│ Notas   ┃                           ┃   │
│         ┃                           ┃   │
│ ─────────────────────────────────────── │
│ En 20-Media/Games · ⏎ guarda · Esc sale │
│ Últimas: Blue Prince · Balatro · …      │
└─────────────────────────────────────────┘
```

- Two rows of category chips; the form below swaps when one is clicked, keeping
  whatever the title field already holds.
- Title has focus on open. Tab walks the fields; chips answer h/l.
- `Enter` saves from any single-line field. Inside Notas, `Enter` is a newline
  and `Ctrl+Enter` saves — a multiline field that swallows Enter would be a trap.
- Saving clears the form, keeps the panel open, and shows the note's name in the
  recents strip below, so a second capture is immediate and the first is visibly
  filed.
- `Esc` closes. Nothing is persisted across closes: a half-typed capture is
  discarded, like it is today.
- Utility first; the visual pass comes after, and inherits the tokens from
  `docs/style/`.

## Errors

| Case | Behaviour |
|---|---|
| Empty title | Save does nothing; the field shows the focus ring. No dialog. |
| Name already taken | The writer appends ` 2`, ` 3`. Never overwrites. |
| Folder missing | Created. A new `16-Travel/` is normal, not an error. |
| Write fails (vault unmounted, no permission) | The panel shows the reason inline and keeps the text, so nothing typed is lost. |
| `omarchy-capture` missing from PATH | Chips and form still render; saving reports it inline. |

## Testing

- `deno` on `Capture.js` and `buildNote`: frontmatter order and quoting, empty
  optional fields left blank, Spanish label to English value, the Steam URL, the
  filename slug (slashes and colons stripped, 80-char cut on a word boundary),
  one golden note per category.
- `pytest` on `omarchy-capture`: collision suffixes, folder creation, accents and
  quotes in filenames, malformed JSON in, always exit 0.
- By hand: capture one of each category, then open 📚/🎬/🎮 in Obsidian and
  confirm the new note appears in the right table with the right status.

## Deferred

- Changing an existing note's `status` from the bar (marking a game played).
- Cover lookup for books and movies.
- The downloads panel gaining actions, and a cleanup panel — separate cycles.
