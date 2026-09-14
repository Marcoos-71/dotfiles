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
