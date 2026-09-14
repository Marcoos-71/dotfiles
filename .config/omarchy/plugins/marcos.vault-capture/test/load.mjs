import { readFileSync } from "node:fs"

export function loadQmlJs(path) {
  const src = readFileSync(path, "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "")
  const names = [...src.matchAll(/^function\s+([A-Za-z_$][\w$]*)/gm)].map(m => m[1])
  return new Function(`${src}\nreturn { ${names.join(", ")} }`)()
}
