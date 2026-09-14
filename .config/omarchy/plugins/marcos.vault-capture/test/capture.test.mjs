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
