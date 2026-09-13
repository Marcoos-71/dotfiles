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
