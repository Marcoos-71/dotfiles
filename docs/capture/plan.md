# Quick Capture Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grow `marcos.vault-capture`'s single-field popup into a seven-category form — Idea, Proyecto, Manual, Viaje, Libro, Peli/Serie, Juego — where anything with a handful of options is a clickable chip, and the note that lands in the vault is shaped exactly like one Book Search or Media DB would write.

**Architecture:** A declarative category table (`Capture.js`) the panel walks blindly — it renders `text`/`number`/`choice` controls per category and knows no category by name. Pure builder functions turn a filled form into the final markdown, testable with `deno` since headless QML does not run on this machine. A new `omarchy-capture` script does the actual file write (folder creation, name-collision handling), replacing the inline `sh -c` the widget uses today, testable with `pytest`.

**Tech Stack:** QML / Quickshell (`qs.Ui` — `Button`, `ButtonGroup`, `TextField`, `KeyboardPanel`, `PanelKeyCatcher`), plain JS (`.pragma library`) for testable logic, Python 3 (stdlib only) for the writer, `deno test` and `pytest` as runners.

**Spec:** `docs/capture/design.md`

## Global Constraints

- **Files live in `~/dotfiles/` and are symlinked into `~/.config/`.** Never edit through the symlink; `readlink -f` first.
- **`OMARCHY_PATH` must be the literal string `/usr/share/omarchy`** for any `omarchy` command.
- **A new plugin needs `omarchy restart shell`, not `rescanPlugins`** — this plan only touches an existing plugin's files, so `omarchy restart shell` is still the way to pick up QML changes (Quickshell does not hot-reload plugin QML).
- **Never touch `/usr/share/omarchy`.**
- **Zero subprocesses in polling loops.** A process runs once at startup or once per user action (a save).
- **Code comments in English, prose to the user in Spanish.** No multi-line docstrings. No comments restating the code.
- **Chips show Spanish, store English.** A chip labeled "Por jugar" writes `status: to-play` — never translate a frontmatter *value*, because every dashboard query in `~/Vault/CLAUDE.md` matches it literally.
- **Body content passed as argv, not stdin.** Quickshell's `Process` type (`quickshell-io.qmltypes`, checked on this machine) exposes a `write()` method and a `stdinEnabled` property but no confirmed way to signal EOF on the pipe — a script blocking on `sys.stdin.read()` waiting for a close that never comes is a real risk with no way to test it here in advance. `marcos.vault-capture`'s own `save()` already passes a multi-line note body as a single argv element successfully today (Linux `ARG_MAX` is measured in megabytes), so this plan keeps that verified-working shape instead of the stdin one the design sketched.
- **Real vault notes were read before writing any template below** — every frontmatter field order, blank-line count, and heading language (including the English "Notes & Highlights" / "Review" that Book Search writes for books, next to the Spanish everywhere else) is copied from an actual note in `~/Vault/20-Media/`, not invented. Two things the design doc got wrong against the real files, corrected here: movie notes carry **no** `> [!info] Ficha` callout and **no** `🔗 Relacionado` section (checked against `Backrooms.md` and `El día de la revelación.md`), and the heading is `💭 Reseña`, not `Opinión`.

---

### Task 1: `Capture.js` — the category table and note builders

**Files:**
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.vault-capture/Capture.js`
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.vault-capture/test/load.mjs` (copy of the one in `marcos.metrics`)
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.vault-capture/test/capture.test.mjs`

**Interfaces:**
- Consumes: nothing.
- Produces, as a `.pragma library` with top-level `function`s (so `loadQmlJs` can find them):
  - `categories() -> array` of `{ key, label, icon, folder, fields }`, `fields` an array of `{ key, label, kind: "text"|"number"|"choice", value?, options?, hint? }`.
  - `categoryFor(key) -> category` — falls back to the first category for an unknown key.
  - `defaultValues(category) -> object` — one entry per field in `category.fields`; `""` for `text`/`number`, the field's own `value` for `choice`.
  - `toFilename(text) -> string` — unchanged behavior from the current `BarWidget.qml` (strip `/\:*?"<>|`, collapse whitespace, cut at 80 chars on a word boundary, `"Sin titulo"` when empty).
  - `buildNote(categoryKey, title, values, notes, created) -> string` — the finished markdown, `created` a pre-formatted `"YYYY-MM-DD"` string.

- [ ] **Step 1: Copy the test harness**

```bash
cd ~/dotfiles/.config/omarchy/plugins/marcos.vault-capture
mkdir -p test
cp ../marcos.metrics/test/load.mjs test/load.mjs
```

- [ ] **Step 2: Write the failing tests**

```javascript
// test/capture.test.mjs
import { test } from "node:test"
import assert from "node:assert/strict"
import { loadQmlJs } from "./load.mjs"

const C = loadQmlJs(new URL("../Capture.js", import.meta.url).pathname)

test("there are seven categories in a stable order", () => {
  const keys = C.categories().map(c => c.key)
  assert.deepEqual(keys, ["idea", "project", "manual", "travel", "book", "movie", "game"])
})

test("every category folder is under the vault root, no leading slash", () => {
  for (const c of C.categories()) {
    assert.equal(c.folder.startsWith("/"), false, c.key)
  }
})

test("categoryFor falls back to the first category for an unknown key", () => {
  assert.equal(C.categoryFor("nope").key, "idea")
  assert.equal(C.categoryFor("game").key, "game")
})

test("defaultValues seeds choice fields with their listed value, text fields empty", () => {
  assert.deepEqual(C.defaultValues(C.categoryFor("idea")), {})
  assert.deepEqual(C.defaultValues(C.categoryFor("project")), { priority: "medium" })
  assert.deepEqual(C.defaultValues(C.categoryFor("travel")),
    { country: "", region: "", kind: "city", status: "idea" })
  assert.deepEqual(C.defaultValues(C.categoryFor("book")),
    { author: "", series: "", genre: "", status: "to-read" })
  assert.deepEqual(C.defaultValues(C.categoryFor("movie")),
    { mediaType: "movie", director: "", year: "", genre: "", status: "to-watch" })
  assert.deepEqual(C.defaultValues(C.categoryFor("game")),
    { saga: "", genre: "", year: "", steamId: "", status: "to-play" })
})

test("toFilename strips illegal characters and collapses whitespace", () => {
  assert.equal(C.toFilename('Dune: Part 2? / "Awakening"'), "Dune Part 2 Awakening")
  assert.equal(C.toFilename("   "), "Sin titulo")
  assert.equal(C.toFilename(""), "Sin titulo")
})

test("toFilename cuts at 80 characters on a word boundary", () => {
  const long = "palabra ".repeat(20).trim()
  const result = C.toFilename(long)
  assert.ok(result.length <= 80)
  assert.equal(result.endsWith(" "), false)
})

test("an idea note is the frontmatter plus a bare heading", () => {
  const note = C.buildNote("idea", "Hacerme una revision", {}, "", "2026-09-14")
  assert.equal(note, [
    "---",
    "type: idea",
    "tags:",
    "  - inbox",
    "created: 2026-09-14",
    "---",
    "",
    "# Hacerme una revision",
  ].join("\n") + "\n")
})

test("an idea note appends the free-text notes below the heading", () => {
  const note = C.buildNote("idea", "Revisión médica", {}, "Pedir cita en el centro de salud", "2026-09-14")
  assert.ok(note.endsWith("# Revisión médica\n\nPedir cita en el centro de salud\n"))
})

test("a project note follows the vault's own template headings", () => {
  const note = C.buildNote("project", "Torre de libros", { priority: "high" }, "", "2026-09-14")
  assert.equal(note, [
    "---",
    "type: project",
    "status: idea",
    "priority: high",
    "created: 2026-09-14",
    "tags:",
    "  - project",
    "---",
    "# Torre de libros",
    "",
    "## 💡 Idea / Objetivo",
    "",
    "",
    "## 🧩 Por qué / Motivación",
    "",
    "",
    "## 📋 Próximos pasos",
    "- [ ] ",
    "",
    "## 🔗 Recursos",
    "",
    "",
    "## 📓 Registro",
    "- 2026-09-14 — creado",
  ].join("\n") + "\n")
})

test("a manual-project note carries the extra manual tag", () => {
  const note = C.buildNote("manual", "Pegboard", { priority: "medium" }, "", "2026-09-14")
  assert.ok(note.includes("tags:\n  - project\n  - manual\n"))
})

test("a project note's idea field carries the typed notes", () => {
  const note = C.buildNote("project", "Torre de libros", { priority: "low" }, "Usar CNC para los cortes", "2026-09-14")
  assert.ok(note.includes("## 💡 Idea / Objetivo\nUsar CNC para los cortes\n\n## 🧩"))
})

test("a travel note with every field filled", () => {
  const values = { country: "Georgia", region: "Cáucaso", kind: "nature", status: "planned" }
  const note = C.buildNote("travel", "Trekking en el Cáucaso", values, "Ir en septiembre, mejor clima", "2026-09-14")
  assert.equal(note, [
    "---",
    "type: travel",
    'title: "Trekking en el Cáucaso"',
    'country: "Georgia"',
    'region: "Cáucaso"',
    "kind: nature",
    "status: planned",
    "created: 2026-09-14",
    "tags:",
    "  - travel",
    "---",
    "",
    "# Trekking en el Cáucaso",
    "",
    "## 📝 Notas",
    "Ir en septiembre, mejor clima",
    "",
    "## 🔗 Relacionado",
  ].join("\n") + "\n")
})

test("a travel note with empty text fields writes quoted-empty strings", () => {
  const values = { country: "", region: "", kind: "city", status: "idea" }
  const note = C.buildNote("travel", "Sitio sin definir", values, "", "2026-09-14")
  assert.ok(note.includes('country: ""\nregion: ""\n'))
})

test("a book note matches Book Search's own shape, Género and Saga both present", () => {
  const values = { author: "Brandon Sanderson", series: "Nacidos de la Bruma", genre: "Fantasía", status: "read" }
  const note = C.buildNote("book", "Aleación de ley 2", values, "", "2026-09-14")
  assert.equal(note, [
    "---",
    "type: book",
    'title: "Aleación de ley 2"',
    'author: "Brandon Sanderson"',
    'series: "Nacidos de la Bruma"',
    'cover: ""',
    "status: read",
    "rating: ",
    'category: "Fantasía"',
    "published: ",
    "started: ",
    "finished: ",
    "tags:",
    "  - book",
    "---",
    "",
    "## 📝 Notes & Highlights",
    "",
    "",
    "## 💭 Review",
    "",
    "## 🔗 Relacionado",
    "- Género: [[Fantasía]]",
    "- Saga: [[Nacidos de la Bruma]]",
  ].join("\n") + "\n")
})

test("a book note with no genre and no series omits both Relacionado bullets", () => {
  const values = { author: "", series: "", genre: "", status: "to-read" }
  const note = C.buildNote("book", "Un libro cualquiera", values, "", "2026-09-14")
  assert.ok(note.endsWith("## 🔗 Relacionado\n"))
})

test("a movie note has no Ficha callout and no Relacionado section", () => {
  const values = { mediaType: "movie", director: "Denis Villeneuve", year: "2027", genre: "Ciencia ficción", status: "to-watch" }
  const note = C.buildNote("movie", "Dune Part Three", values, "Estreno confirmado", "2026-09-14")
  assert.equal(note, [
    "---",
    "type: movie",
    'title: "Dune Part Three"',
    "year: 2027",
    'director: "Denis Villeneuve"',
    'genre: "Ciencia ficción"',
    "status: to-watch",
    "rating: ",
    "runtime: ",
    "released: ",
    "poster: ",
    "watched: ",
    "tags:",
    "  - movie",
    "---",
    "# Dune Part Three",
    "",
    "## 📝 Notas",
    "Estreno confirmado",
    "",
    "## 💭 Reseña",
  ].join("\n") + "\n")
})

test("a show writes type: show but keeps the movie tag", () => {
  const values = { mediaType: "show", director: "", year: "", genre: "", status: "to-watch" }
  const note = C.buildNote("movie", "Una serie", values, "", "2026-09-14")
  assert.ok(note.startsWith("---\ntype: show\n"))
  assert.ok(note.includes("tags:\n  - movie\n"))
})

test("a game note builds the Steam cover URL from the Steam id", () => {
  const values = { saga: "", genre: "Metroidvania", year: "2025", steamId: "1030300", status: "to-play" }
  const note = C.buildNote("game", "Hollow Knight: Silksong", values, "", "2026-09-14")
  assert.ok(note.includes('cover: "https://cdn.cloudflare.steamstatic.com/steam/apps/1030300/library_600x900_2x.jpg"'))
  assert.ok(note.includes('genre: ["Metroidvania"]'))
  assert.ok(note.includes('category: "Metroidvania"'))
  assert.ok(note.includes("> [!info] Ficha\n> **Género:** Metroidvania · **Año:** 2025\n"))
})

test("a game note with a saga adds it to the Ficha line and the Relacionado bullet", () => {
  const values = { saga: "Dark Souls", genre: "Soulslike", year: "2011", steamId: "", status: "played" }
  const note = C.buildNote("game", "Dark Souls Remastered", values, "", "2026-09-14")
  assert.ok(note.includes("**Saga:** [[Dark Souls]]"))
  assert.ok(note.includes("- Saga: [[Dark Souls]]"))
  assert.ok(note.includes('cover: ""'))
})

test("a game note with no genre, year or saga has no second Ficha line", () => {
  const values = { saga: "", genre: "", year: "", steamId: "", status: "to-play" }
  const note = C.buildNote("game", "Juego sin datos", values, "", "2026-09-14")
  assert.ok(note.includes("> [!info] Ficha\n\n## 📝 Notas"))
})

test("saga is written bare when absent, like the vault's own game notes", () => {
  const values = { saga: "", genre: "Roguelike", year: "2024", steamId: "", status: "played" }
  const note = C.buildNote("game", "Balatro 2", values, "", "2026-09-14")
  assert.ok(note.includes("\nsaga: \n"))
})
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd ~/dotfiles/.config/omarchy/plugins/marcos.vault-capture && deno test --allow-read test/capture.test.mjs`
Expected: FAIL — `Capture.js` does not exist yet, `loadQmlJs` throws ENOENT.

- [ ] **Step 4: Write the implementation**

```javascript
// Capture.js
.pragma library

// One entry per category the bar's quick-capture panel can write. The panel
// walks this table blindly — it renders a text/number/choice control per
// field and knows no category by name, so a new one is an entry here, not
// new QML. Folder is relative to the vault root.
var CATEGORIES = [
  {
    key: "idea",
    label: "Idea",
    icon: "󰛩",
    folder: "00-Inbox",
    fields: []
  },
  {
    key: "project",
    label: "Proyecto",
    icon: "󰌢",
    folder: "10-Projects",
    fields: [
      { key: "priority", label: "Prioridad", kind: "choice", value: "medium",
        options: [
          { value: "low", label: "Baja" },
          { value: "medium", label: "Media" },
          { value: "high", label: "Alta" }
        ] }
    ]
  },
  {
    key: "manual",
    label: "Manual",
    icon: "󱌣",
    folder: "11-Manual-Projects",
    fields: [
      { key: "priority", label: "Prioridad", kind: "choice", value: "medium",
        options: [
          { value: "low", label: "Baja" },
          { value: "medium", label: "Media" },
          { value: "high", label: "Alta" }
        ] }
    ]
  },
  {
    key: "travel",
    label: "Viaje",
    icon: "󰀝",
    folder: "16-Travel",
    fields: [
      { key: "country", label: "País", kind: "text" },
      { key: "region", label: "Región", kind: "text" },
      { key: "kind", label: "Tipo", kind: "choice", value: "city",
        options: [
          { value: "city", label: "Ciudad" },
          { value: "nature", label: "Naturaleza" },
          { value: "route", label: "Ruta" },
          { value: "beach", label: "Playa" }
        ] },
      { key: "status", label: "Estado", kind: "choice", value: "idea",
        options: [
          { value: "idea", label: "Idea" },
          { value: "planned", label: "Planeado" },
          { value: "done", label: "Hecho" }
        ] }
    ]
  },
  {
    key: "book",
    label: "Libro",
    icon: "📖",
    folder: "20-Media/Books",
    fields: [
      { key: "author", label: "Autor", kind: "text" },
      { key: "series", label: "Saga", kind: "text" },
      { key: "genre", label: "Género", kind: "text" },
      { key: "status", label: "Estado", kind: "choice", value: "to-read",
        options: [
          { value: "to-read", label: "Por leer" },
          { value: "reading", label: "Leyendo" },
          { value: "read", label: "Leído" }
        ] }
    ]
  },
  {
    key: "movie",
    label: "Peli/Serie",
    icon: "🎬",
    folder: "20-Media/Movies",
    fields: [
      { key: "mediaType", label: "Tipo", kind: "choice", value: "movie",
        options: [
          { value: "movie", label: "Película" },
          { value: "show", label: "Serie" }
        ] },
      { key: "director", label: "Director", kind: "text" },
      { key: "year", label: "Año", kind: "number" },
      { key: "genre", label: "Género", kind: "text" },
      { key: "status", label: "Estado", kind: "choice", value: "to-watch",
        options: [
          { value: "to-watch", label: "Por ver" },
          { value: "watching", label: "Viendo" },
          { value: "watched", label: "Vista" }
        ] }
    ]
  },
  {
    key: "game",
    label: "Juego",
    icon: "🎮",
    folder: "20-Media/Games",
    fields: [
      { key: "saga", label: "Saga", kind: "text" },
      { key: "genre", label: "Género", kind: "text" },
      { key: "year", label: "Año", kind: "number" },
      { key: "steamId", label: "Steam ID", kind: "text", hint: "para la portada" },
      { key: "status", label: "Estado", kind: "choice", value: "to-play",
        options: [
          { value: "to-play", label: "Por jugar" },
          { value: "playing", label: "Jugando" },
          { value: "played", label: "Jugado" }
        ] }
    ]
  }
]

function categories() {
  return CATEGORIES
}

function categoryFor(key) {
  for (var i = 0; i < CATEGORIES.length; i++) {
    if (CATEGORIES[i].key === key) return CATEGORIES[i]
  }
  return CATEGORIES[0]
}

// Defaults for a category's own fields: a choice field starts at its listed
// value, text/number fields start empty. Title and notes are common to every
// category and are not part of this table.
function defaultValues(category) {
  var out = {}
  for (var i = 0; i < category.fields.length; i++) {
    var field = category.fields[i]
    out[field.key] = field.kind === "choice" ? field.value : ""
  }
  return out
}

// Obsidian titles are filenames, so the text has to survive as one: strip the
// characters a filename cannot hold and collapse whitespace.
function toFilename(text) {
  var clean = String(text || "")
    .replace(/[\/\\:*?"<>|]/g, " ")
    .replace(/\s+/g, " ")
    .replace(/^\s+|\s+$/g, "")
  if (clean.length > 80) clean = clean.slice(0, 80).replace(/\s+\S*$/, "")
  return clean === "" ? "Sin titulo" : clean
}

function esc(text) {
  return String(text || "").replace(/"/g, '\\"')
}

// Quoted frontmatter string: "" when empty, matching how the vault's own
// book/movie notes write an unset text field.
function quoted(text) {
  return text ? '"' + esc(text) + '"' : '""'
}

// Bare (unquoted) frontmatter value: blank when empty. Used for the fields
// whose real notes in the vault carry no quotes at all (game's saga, any
// year).
function bare(text) {
  return text ? String(text) : ""
}

function steamCoverUrl(steamId) {
  return steamId
    ? "https://cdn.cloudflare.steamstatic.com/steam/apps/" + steamId + "/library_600x900_2x.jpg"
    : ""
}

function buildIdeaNote(title, values, notes, created) {
  var lines = [
    "---",
    "type: idea",
    "tags:",
    "  - inbox",
    "created: " + created,
    "---",
    "",
    "# " + title
  ]
  if (notes) {
    lines.push("")
    lines.push(notes)
  }
  return lines.join("\n") + "\n"
}

// Shared by project and manual: same template (~/Vault/90-Templates/Project.md),
// manual only adds its own tag on top.
function buildProjectNote(title, values, notes, created, extraTags) {
  var lines = [
    "---",
    "type: project",
    "status: idea",
    "priority: " + values.priority,
    "created: " + created,
    "tags:",
    "  - project"
  ]
  for (var i = 0; i < extraTags.length; i++) lines.push("  - " + extraTags[i])
  lines.push("---")
  lines.push("# " + title)
  lines.push("")
  lines.push("## 💡 Idea / Objetivo")
  if (notes) {
    lines.push(notes)
    lines.push("")
  } else {
    lines.push("")
    lines.push("")
  }
  lines.push("## 🧩 Por qué / Motivación")
  lines.push("")
  lines.push("")
  lines.push("## 📋 Próximos pasos")
  lines.push("- [ ] ")
  lines.push("")
  lines.push("## 🔗 Recursos")
  lines.push("")
  lines.push("")
  lines.push("## 📓 Registro")
  lines.push("- " + created + " — creado")
  return lines.join("\n") + "\n"
}

// No schema existed for this folder before this feature; see the addition to
// ~/Vault/CLAUDE.md made in the same cycle as this file.
function buildTravelNote(title, values, notes, created) {
  var lines = [
    "---",
    "type: travel",
    'title: "' + esc(title) + '"',
    "country: " + quoted(values.country),
    "region: " + quoted(values.region),
    "kind: " + values.kind,
    "status: " + values.status,
    "created: " + created,
    "tags:",
    "  - travel",
    "---",
    "",
    "# " + title,
    "",
    "## 📝 Notas"
  ]
  if (notes) {
    lines.push(notes)
    lines.push("")
  } else {
    lines.push("")
    lines.push("")
  }
  lines.push("## 🔗 Relacionado")
  return lines.join("\n") + "\n"
}

function buildBookNote(title, values, notes, created) {
  var lines = [
    "---",
    "type: book",
    'title: "' + esc(title) + '"',
    "author: " + quoted(values.author),
    "series: " + quoted(values.series),
    'cover: ""',
    "status: " + values.status,
    "rating: ",
    "category: " + quoted(values.genre),
    "published: ",
    "started: ",
    "finished: ",
    "tags:",
    "  - book",
    "---",
    "",
    "## 📝 Notes & Highlights"
  ]
  if (notes) {
    lines.push(notes)
    lines.push("")
  } else {
    lines.push("")
    lines.push("")
  }
  lines.push("## 💭 Review")
  lines.push("")
  lines.push("## 🔗 Relacionado")
  if (values.genre) lines.push("- Género: [[" + values.genre + "]]")
  if (values.series) lines.push("- Saga: [[" + values.series + "]]")
  return lines.join("\n") + "\n"
}

// No Ficha callout and no Relacionado section: unlike games, real movie
// notes in the vault carry neither (checked against Backrooms.md).
function buildMovieNote(title, values, notes, created) {
  var lines = [
    "---",
    "type: " + values.mediaType,
    'title: "' + esc(title) + '"',
    "year: " + bare(values.year),
    "director: " + quoted(values.director),
    "genre: " + quoted(values.genre),
    "status: " + values.status,
    "rating: ",
    "runtime: ",
    "released: ",
    "poster: ",
    "watched: ",
    "tags:",
    "  - movie",
    "---",
    "# " + title,
    "",
    "## 📝 Notas"
  ]
  if (notes) {
    lines.push(notes)
    lines.push("")
  } else {
    lines.push("")
    lines.push("")
  }
  lines.push("## 💭 Reseña")
  return lines.join("\n") + "\n"
}

function buildGameNote(title, values, notes, created) {
  var lines = [
    "---",
    "type: game",
    'title: "' + esc(title) + '"',
    "saga: " + bare(values.saga),
    'developer: ""',
    'publisher: ""',
    "genre: " + (values.genre ? '["' + esc(values.genre) + '"]' : "[]"),
    "category: " + quoted(values.genre),
    "year: " + bare(values.year),
    "status: " + values.status,
    "rating: ",
    "hours: ",
    "cover: " + quoted(steamCoverUrl(values.steamId)),
    "finished: ",
    "tags:",
    "  - game",
    "---",
    ""
  ]
  var fichaParts = []
  if (values.genre) fichaParts.push("**Género:** " + values.genre)
  if (values.year) fichaParts.push("**Año:** " + values.year)
  if (values.saga) fichaParts.push("**Saga:** [[" + values.saga + "]]")
  lines.push("> [!info] Ficha")
  if (fichaParts.length > 0) lines.push("> " + fichaParts.join(" · "))
  lines.push("")
  lines.push("## 📝 Notas")
  if (notes) {
    lines.push(notes)
    lines.push("")
  } else {
    lines.push("")
    lines.push("")
  }
  lines.push("## 💭 Opinión")
  lines.push("")
  lines.push("## 🔗 Relacionado")
  if (values.genre) lines.push("- Género: [[" + values.genre + "]]")
  if (values.saga) lines.push("- Saga: [[" + values.saga + "]]")
  return lines.join("\n") + "\n"
}

function buildNote(categoryKey, title, values, notes, created) {
  switch (categoryKey) {
    case "idea": return buildIdeaNote(title, values, notes, created)
    case "project": return buildProjectNote(title, values, notes, created, [])
    case "manual": return buildProjectNote(title, values, notes, created, ["manual"])
    case "travel": return buildTravelNote(title, values, notes, created)
    case "book": return buildBookNote(title, values, notes, created)
    case "movie": return buildMovieNote(title, values, notes, created)
    case "game": return buildGameNote(title, values, notes, created)
  }
  return buildIdeaNote(title, values, notes, created)
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd ~/dotfiles/.config/omarchy/plugins/marcos.vault-capture && deno test --allow-read test/capture.test.mjs`
Expected: PASS, 21 tests.

- [ ] **Step 6: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .config/omarchy/plugins/marcos.vault-capture/Capture.js .config/omarchy/plugins/marcos.vault-capture/test
git commit -m "feat(capture): category table and note builders"
```

---

### Task 2: `omarchy-capture` — the writer

**Files:**
- Create: `~/dotfiles/.local/bin/omarchy-capture`
- Create: `~/dotfiles/tests/test_omarchy_capture.py`

**Interfaces:**
- Consumes: nothing external.
- Produces: a CLI, `omarchy-capture <folder> <title> <body>`, that creates `<folder>` if missing, writes `<title>.md` (or `<title> 2.md`, `<title> 3.md`, ... on collision) with `<body>` as its content, and prints `{"ok": bool, "path": str, "reason": str}` on stdout. Always exits 0.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_omarchy_capture.py
import json
import subprocess
from pathlib import Path

SCRIPT = Path.home() / "dotfiles/.local/bin/omarchy-capture"


def run(folder, title, body):
    result = subprocess.run(
        [str(SCRIPT), str(folder), title, body], capture_output=True, text=True
    )
    return result, json.loads(result.stdout)


def test_writes_a_new_file(tmp_path):
    folder = tmp_path / "20-Media" / "Games"
    result, data = run(folder, "Hollow Knight", "---\ntype: game\n---\n")
    assert result.returncode == 0
    assert data["ok"] is True
    written = Path(data["path"])
    assert written == folder / "Hollow Knight.md"
    assert written.read_text() == "---\ntype: game\n---\n"


def test_creates_missing_parent_folders(tmp_path):
    folder = tmp_path / "16-Travel"
    assert not folder.exists()
    _, data = run(folder, "Georgia", "# Georgia\n")
    assert data["ok"] is True
    assert folder.is_dir()


def test_resolves_name_collisions(tmp_path):
    (tmp_path / "Dune.md").write_text("first")
    _, first = run(tmp_path, "Dune", "second")
    assert first["path"] == str(tmp_path / "Dune 2.md")
    (tmp_path / "Dune 2.md").write_text("already there too")
    _, second = run(tmp_path, "Dune", "third")
    assert second["path"] == str(tmp_path / "Dune 3.md")


def test_never_writes_outside_the_target_folder(tmp_path):
    folder = tmp_path / "00-Inbox"
    _, data = run(folder, "escape/../../attempt", "x")
    assert data["ok"] is True
    written = Path(data["path"])
    assert written.parent == folder


def test_missing_arguments_reports_and_exits_zero():
    result = subprocess.run([str(SCRIPT)], capture_output=True, text=True)
    data = json.loads(result.stdout)
    assert result.returncode == 0
    assert data["ok"] is False
    assert "usage" in data["reason"]


def test_write_failure_is_reported_not_raised(tmp_path):
    # A file standing where a parent directory should be makes mkdir fail.
    blocker = tmp_path / "blocker"
    blocker.write_text("not a directory")
    result, data = run(blocker / "sub", "Title", "body")
    assert result.returncode == 0
    assert data["ok"] is False
    assert data["reason"] != ""


def test_unicode_and_quotes_in_title_survive(tmp_path):
    _, data = run(tmp_path, 'Año "difícil" en España', "body")
    assert data["ok"] is True
    assert Path(data["path"]).read_text() == "body"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/dotfiles && uv run --with pytest pytest tests/test_omarchy_capture.py -q`
Expected: FAIL — `omarchy-capture` does not exist yet.

- [ ] **Step 3: Write the implementation**

```python
#!/usr/bin/env python3
"""Write a captured note into the vault, resolving name collisions."""

import json
import sys
from pathlib import Path


def safe_name(name):
    # Defense in depth: the caller (Capture.js's toFilename) already strips
    # filesystem-illegal characters, but a stray "/" here must never be
    # allowed to escape the target folder.
    cleaned = str(name or "").replace("/", "-").replace("\\", "-").strip()
    return cleaned or "Sin titulo"


def unique_path(folder, title):
    candidate = folder / (title + ".md")
    n = 2
    while candidate.exists():
        candidate = folder / (title + " " + str(n) + ".md")
        n += 1
    return candidate


def emit(ok, path, reason):
    json.dump({"ok": ok, "path": path, "reason": reason}, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


def main():
    if len(sys.argv) != 4:
        return emit(False, "", "usage: omarchy-capture <folder> <title> <body>")

    folder, title, body = sys.argv[1], sys.argv[2], sys.argv[3]
    if not folder or not title:
        return emit(False, "", "faltan folder o title")

    try:
        directory = Path(folder)
        directory.mkdir(parents=True, exist_ok=True)
        path = unique_path(directory, safe_name(title))
        path.write_text(body, encoding="utf-8")
    except OSError as error:
        return emit(False, "", str(error))

    return emit(True, str(path), "")


if __name__ == "__main__":
    sys.exit(main())
```

```bash
chmod +x ~/dotfiles/.local/bin/omarchy-capture
ln -sfn ~/dotfiles/.local/bin/omarchy-capture ~/.local/bin/omarchy-capture
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/dotfiles && uv run --with pytest pytest tests/test_omarchy_capture.py -q`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .local/bin/omarchy-capture tests/test_omarchy_capture.py
git commit -m "feat(capture): omarchy-capture writes the note, replacing the inline sh -c"
```

---

### Task 3: `MultilineField.qml` — the notes input

**Files:**
- Create: `~/dotfiles/.config/omarchy/plugins/marcos.vault-capture/MultilineField.qml`

**Interfaces:**
- Consumes: `qs.Commons` (`Color`, `Style`, `Border`), `qs.Ui` (`BorderSurface`).
- Produces: a `TextArea` subclass with the same border/focus/hover treatment as `qs.Ui.TextField`, so the notes box matches every other input in the panel. No new signals — callers read `.text` directly, same as any `TextArea`.

There is no dedicated multi-line input in `qs.Ui` (only `TextField`, single-line). Checked against the installed Qt 6 `QtQuick.Templates` (`TextArea` has `hovered`, `hoverEnabled`, `placeholderText`, `placeholderTextColor`, `background` — the same surface `TextField.qml` already styles), so this mirrors `qs.Ui/TextField.qml` line for line, swapping the base type.

- [ ] **Step 1: Write the component**

```qml
// MultilineField.qml
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Multi-line sibling of qs.Ui.TextField, styled the same way. TextField
// itself can't do this — it's single-line — so the notes box needed its own
// component rather than reusing one.
TextArea {
  id: root

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color selectionTint: Style.selectionFillFor(foreground, accent)
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.inputPaddingY
  property bool hasCursor: false

  readonly property bool _focused: activeFocus
  readonly property bool _hot: hovered || hasCursor
  readonly property var _borderSpec: Border.controlSpec(_focused ? "focus" : (_hot ? "hover-cursor" : "normal"), root.foreground, root.accent)

  wrapMode: TextEdit.Wrap
  hoverEnabled: true
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  color: foreground
  selectionColor: selectionTint
  selectedTextColor: foreground
  placeholderTextColor: Qt.darker(foreground, 1.6)

  leftPadding: horizontalPadding + Border.left(_borderSpec)
  rightPadding: horizontalPadding + Border.right(_borderSpec)
  topPadding: verticalPadding + Border.top(_borderSpec)
  bottomPadding: verticalPadding + Border.bottom(_borderSpec)

  background: BorderSurface {
    color: Style.controlFill(root._focused, root._hot, root.foreground, root.accent)
    borderSpec: root._borderSpec
    radius: Style.cornerRadius
  }
}
```

- [ ] **Step 2: No automated test for this file**

Headless QML does not run on this machine (`qml`/`qmltestrunner` exit silently — the same limitation `docs/dashboard/plan.md` hit). This component is verified visually in Task 4's manual pass, alongside the panel that uses it.

- [ ] **Step 3: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .config/omarchy/plugins/marcos.vault-capture/MultilineField.qml
git commit -m "feat(capture): multiline text input, styled like qs.Ui.TextField"
```

---

### Task 4: Wire the form into `Panel.qml` and `BarWidget.qml`

**Files:**
- Modify: `~/dotfiles/.config/omarchy/plugins/marcos.vault-capture/Panel.qml`
- Modify: `~/dotfiles/.config/omarchy/plugins/marcos.vault-capture/BarWidget.qml`

**Interfaces:**
- Consumes: `Capture.js` (Task 1), `omarchy-capture` (Task 2), `MultilineField.qml` (Task 3).
- Produces: nothing outside this plugin.

**Step 1: Rewrite `BarWidget.qml`**

Remove `categories`, `categoryFor`, `today`, `toFilename`, `buildNote`, `save`, `noteSaved` — everything Task 1's `Capture.js` now owns or that the new `save()` no longer needs. Replace with:

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Capture.js" as Capture

// Quick capture into the Obsidian vault. Notes are plain markdown files in
// folders, so this writes them directly — no Obsidian plugin, API or running
// instance needed. Nothing is polled: the only process runs when a note is
// actually saved.
BarWidget {
  id: root
  moduleName: "marcos.vault-capture"

  readonly property string vaultPath: Quickshell.env("HOME") + "/Vault"
  readonly property string vaultName: "Vault"

  signal saveFinished(bool ok, string path, string reason)

  function today() {
    var now = new Date()
    var month = ("0" + (now.getMonth() + 1)).slice(-2)
    var day = ("0" + now.getDate()).slice(-2)
    return now.getFullYear() + "-" + month + "-" + day
  }

  function save(categoryKey, title, values, notes) {
    var category = Capture.categoryFor(categoryKey)
    var cleanTitle = Capture.toFilename(title)
    var body = Capture.buildNote(categoryKey, cleanTitle, values, notes, today())
    // Body travels as an argv element, not stdin: Quickshell's Process has no
    // confirmed way to signal EOF on a stdin pipe, and this is exactly how
    // this widget's own save() already passed a multi-line body successfully.
    saveProc.command = ["omarchy-capture", vaultPath + "/" + category.folder, cleanTitle, body]
    saveTimeout.restart()
    saveProc.running = true
  }

  function openInObsidian(relativePath) {
    Quickshell.execDetached([
      "xdg-open",
      "obsidian://open?vault=" + encodeURIComponent(vaultName) + "&file=" + encodeURIComponent(relativePath)
    ])
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Process {
    id: saveProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        saveTimeout.stop()
        try {
          var data = JSON.parse(String(text || "{}"))
          root.saveFinished(data.ok === true, data.path || "", data.reason || "")
        } catch (error) {
          root.saveFinished(false, "", "respuesta ilegible de omarchy-capture")
        }
      }
    }
  }

  // A process that fails to start (omarchy-capture missing from PATH) never
  // reaches onStreamFinished — Quickshell's Process has no confirmed public
  // signal for that failure, only exited(), which Qt does not emit when a
  // process never started. A plain timeout is what actually catches it.
  Timer {
    id: saveTimeout
    interval: 4000
    onTriggered: root.saveFinished(false, "", "omarchy-capture no respondió — ¿está en el PATH?")
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    foreground: "#fab387"  // bar-colors: cluster colour, re-applied by omarchy-bar-colors
    text: "󱘓"
    slotSize: Style.bar.statusSlot
    tooltipText: "Captura rápida al vault"
    onPressed: root.togglePanel()
  }
}
```

**Step 2: Rewrite `Panel.qml`**

```qml
import QtQuick
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Ui
import "Capture.js" as Capture

// Seven categories, one declarative table (Capture.js) driving all of them:
// this file knows no category by name, only the three field kinds
// (text/number/choice) it renders for whichever one is selected.
Panel {
  id: root
  moduleName: "marcos.vault-capture"
  ipcTarget: "marcos.vault-capture"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property string selectedKey: "idea"
  readonly property var currentCategory: Capture.categoryFor(selectedKey)
  readonly property string folderPath: hostWidget ? hostWidget.vaultPath + "/" + currentCategory.folder : ""

  property string statusText: ""
  property bool statusError: false

  // Reads every currently-rendered field control fresh, rather than
  // mirroring their values into a parallel object — the Repeater below
  // already destroys and recreates the right controls per category, so the
  // live UI state is the only source of truth this needs.
  function collectFieldValues() {
    var values = {}
    var fields = root.currentCategory.fields
    for (var i = 0; i < fields.length; i++) {
      var field = fields[i]
      var delegate = fieldsRepeater.itemAt(i)
      var loaded = delegate ? delegate.fieldLoader.item : null
      if (!loaded) {
        values[field.key] = field.kind === "choice" ? field.value : ""
        continue
      }
      values[field.key] = field.kind === "choice" ? loaded.value : loaded.text
    }
    return values
  }

  function commit() {
    var title = titleField.text
    if (title.replace(/\s+/g, "") === "") return
    if (!root.hostWidget) return
    root.hostWidget.save(root.selectedKey, title, root.collectFieldValues(), notesField.text)
  }

  onOpenedChanged: {
    if (opened) {
      root.statusText = ""
      Qt.callLater(function() { titleField.forceActiveFocus() })
    }
  }

  onSelectedKeyChanged: {
    notesField.text = ""
    root.statusText = ""
  }

  Connections {
    target: root.hostWidget
    function onSaveFinished(ok, path, reason) {
      if (ok) {
        var name = path.split("/").pop()
        root.statusText = "Guardado: " + name
        root.statusError = false
        titleField.text = ""
        notesField.text = ""
      } else {
        root.statusText = reason || "No se pudo guardar"
        root.statusError = true
      }
    }
  }

  // Shared Enter-saves / Escape-closes handling for every single-line field.
  Component {
    id: textFieldComponent
    TextField {
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.commit(); event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.close(); event.accepted = true
        }
      }
    }
  }

  Component {
    id: numberFieldComponent
    TextField {
      validator: IntValidator { bottom: 0; top: 9999 }
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.commit(); event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.close(); event.accepted = true
        }
      }
    }
  }

  Component {
    id: choiceFieldComponent
    ButtonGroup {
      property var fieldOptions: []
      options: fieldOptions
      onChanged: function(v) { value = v }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: titleField
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Every field owns its own Enter/Escape handling; this catcher stays
      // out of the way, same as before this form grew past one field.
      blocked: true
      onCloseRequested: root.close()

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        Text {
          text: "Captura rápida"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: Capture.categories()

            Button {
              required property var modelData
              text: modelData.label
              iconText: modelData.icon
              selected: root.selectedKey === modelData.key
              bordered: true
              fontSize: Style.font.caption
              onClicked: root.selectedKey = modelData.key
            }
          }
        }

        PanelSeparator { width: parent.width }

        TextField {
          id: titleField
          width: parent.width
          placeholderText: "Título"
          font.family: Style.font.family

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.commit(); event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
              root.close(); event.accepted = true
            }
          }
        }

        Repeater {
          id: fieldsRepeater
          model: root.currentCategory.fields

          Column {
            id: fieldRow
            required property var modelData
            property alias fieldLoader: loader
            width: parent.width
            spacing: Style.space(4)

            Text {
              text: fieldRow.modelData.label + (fieldRow.modelData.hint ? " · " + fieldRow.modelData.hint : "")
              color: Color.popups.text
              opacity: 0.65
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Loader {
              id: loader
              width: parent.width
              sourceComponent: fieldRow.modelData.kind === "choice" ? choiceFieldComponent
                : (fieldRow.modelData.kind === "number" ? numberFieldComponent : textFieldComponent)
              onLoaded: {
                if (fieldRow.modelData.kind === "choice") {
                  item.fieldOptions = fieldRow.modelData.options
                  item.value = fieldRow.modelData.value
                } else {
                  item.text = ""
                  item.width = loader.width
                }
              }
            }
          }
        }

        Text {
          text: "Notas"
          color: Color.popups.text
          opacity: 0.65
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        MultilineField {
          id: notesField
          width: parent.width
          height: Style.space(70)
          placeholderText: "Enlaces, por qué te interesa…"

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.close(); event.accepted = true
            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                && (event.modifiers & Qt.ControlModifier)) {
              root.commit(); event.accepted = true
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: "Guardar"
            bordered: true
            fontSize: Style.font.caption
            onClicked: root.commit()
          }

          Text {
            text: "En " + root.currentCategory.folder + " · ⏎ guarda · Ctrl+⏎ en Notas · Esc sale"
            color: Color.popups.text
            opacity: 0.5
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Text {
          visible: root.statusText !== ""
          text: root.statusText
          color: root.statusError ? "#f38ba8" : "#a6e3a1"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        PanelSeparator { width: parent.width }

        FolderListModel {
          id: recentNotes
          folder: root.folderPath === "" ? "" : "file://" + root.folderPath
          nameFilters: ["*.md"]
          showDirs: false
          showDotAndDotDot: false
          sortField: FolderListModel.Time
        }

        Column {
          width: parent.width
          spacing: Style.space(2)

          Repeater {
            // Only the newest handful: this is orientation, not a file browser.
            model: Math.min(recentNotes.count, 5)

            Button {
              required property int index
              width: column.width
              leftAlign: true
              text: String(recentNotes.get(index, "fileBaseName") || "")
              fontSize: Style.font.caption
              onClicked: {
                if (!root.hostWidget) return
                root.hostWidget.openInObsidian(root.currentCategory.folder + "/" + recentNotes.get(index, "fileName"))
                root.close()
              }
            }
          }
        }

        Text {
          visible: recentNotes.count === 0
          text: "Sin notas todavía"
          color: Color.popups.text
          opacity: 0.45
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
```

- [ ] **Step 3: Apply the sync and restart the shell**

```bash
OMARCHY_PATH=/usr/share/omarchy omarchy-style >/dev/null  # re-applies bar colours after any restart
OMARCHY_PATH=/usr/share/omarchy omarchy restart shell
sleep 8
```

- [ ] **Step 4: Verify the panel opens and shows all seven categories**

```bash
OMARCHY_PATH=/usr/share/omarchy omarchy-shell shell summon marcos.vault-capture '{}'
sleep 1
grim -o DP-3 /tmp/capture.png
```
Read `/tmp/capture.png`. Expected: "Captura rápida" title, seven chips wrapped across two rows, a Título field, and — with Idea selected by default — no extra fields, just the Notas box and the recents strip.

- [ ] **Step 5: Verify a category with fields renders its chips and text fields**

```bash
ydotool mousemove -a -x <coords-of-the-Juego-chip>; sleep 0.3; ydotool click 0xC0
sleep 0.5
grim -o DP-3 /tmp/capture-game.png
```
Read `/tmp/capture-game.png`. Expected: Saga/Género/Año/Steam ID text fields and a Por jugar / Jugando / Jugado chip row, Por jugar selected by default (the chip visually marked `selected`).

- [ ] **Step 6: Capture one real note per category and verify each lands correctly**

For each category: click its chip, type a title (and for game/movie/travel a couple of the extra fields), press Enter, confirm the green "Guardado: …" status appears. Then, from a terminal:

```bash
cat "/home/marcos/Vault/00-Inbox/<title>.md"
cat "/home/marcos/Vault/20-Media/Games/<title>.md"
# ...one per category
```

Expected: every note matches its `buildNote` golden shape from Task 1 with the real title substituted, and in particular:
- the game note's `status` reads `to-play` (not "Por jugar") — this is the check that chips are storing English while showing Spanish.
- the travel note is the first file ever written to `~/Vault/16-Travel/`.

- [ ] **Step 7: Verify a save failure keeps the typed text**

```bash
sudo chmod 000 ~/Vault/16-Travel
```
Capture a travel note. Expected: the status line turns red/error-colored and the title/notes fields are NOT cleared. Then:
```bash
sudo chmod 755 ~/Vault/16-Travel
```

- [ ] **Step 8: Commit** (ask the user first)

```bash
cd ~/dotfiles
git add .config/omarchy/plugins/marcos.vault-capture/Panel.qml .config/omarchy/plugins/marcos.vault-capture/BarWidget.qml
git commit -m "feat(capture): seven-category form with chips, replacing the single text field"
```

---

### Task 5: Document the travel schema

**Files:**
- Modify: `~/Vault/CLAUDE.md`

This file is outside the dotfiles git repository (the vault has no git of its own) — a plain edit, no commit.

**Interfaces:** none; documentation only.

- [ ] **Step 1: Add the Travel schema**

In the "Frontmatter schemas" section, immediately after the Project schema block, add:

```markdown
**Travel** (`16-Travel/`)
```yaml
type: travel
title:
country:          # optional
region:           # optional, area/zone within the country
kind: city         # city | nature | route | beach
status: idea       # idea | planned | done
created:
tags: [travel]
```
```

- [ ] **Step 2: Add the row to the folder-structure table and dashboards line**

Add a row to the folder table: `| `16-Travel/` | One note per place. No dashboard yet — created by this feature; add one when there are enough notes to be worth a panel. |`

- [ ] **Step 3: Verify the file is still valid markdown**

```bash
grep -n "^\`\`\`" ~/Vault/CLAUDE.md | wc -l
```
Expected: an even number (every opened code fence is closed).

---

## Done when

- `deno test` passes in `marcos.vault-capture` (21 new tests) alongside the existing 19 in `marcos.metrics` and 11 in `marcos.dashboard`.
- `pytest` passes in `~/dotfiles/tests` (23: 11 agenda, 3 tokens, 7 capture — plus any added before this).
- The bar's vault-capture icon opens a panel with seven category chips; selecting one swaps the field set below it.
- A note captured in each of the seven categories lands in its real vault folder with the frontmatter its dashboard queries on, verified by reading the file back.
- A save failure leaves the typed title and notes in place instead of clearing them.
- `journalctl --user` clean of new errors after the restart in Task 4.
