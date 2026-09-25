.pragma library

var TIERS = ["", "bronce", "plata", "oro", "diamante"]
// Catppuccin Mocha: peach, subtext1, yellow, sky.
var TIER_COLORS = ["", "#fab387", "#bac2de", "#f9e2af", "#89dceb"]
var MONTHS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]

function fmtMinutes(minutes) {
  if (typeof minutes !== "number" || !isFinite(minutes) || minutes < 0) return "--"
  var total = Math.round(minutes)
  var h = Math.floor(total / 60)
  var m = total % 60
  if (h === 0) return m + " min"
  if (m === 0) return h + " h"
  return h + " h " + m + " min"
}

function fmtCount(value) {
  if (typeof value !== "number" || !isFinite(value)) return "--"
  var sign = value < 0 ? "-" : ""
  var digits = String(Math.round(Math.abs(value)))
  return sign + digits.replace(/\B(?=(\d{3})+(?!\d))/g, ".")
}

function tierName(tier) {
  return TIERS[tier] || ""
}

function tierColor(tier) {
  return TIER_COLORS[tier] || ""
}

function fmtDay(iso) {
  var match = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || ""))
  if (!match) return ""
  var month = Number(match[2])
  if (month < 1 || month > 12) return ""
  return Number(match[3]) + " " + MONTHS[month - 1]
}

// Null means "hide the block": missing command, empty output or a shape we do
// not recognise all read the same to the widget.
function parseToday(text) {
  var data
  try { data = JSON.parse(String(text || "")) } catch (error) { return null }
  if (!data || typeof data.active_minutes !== "number") return null
  var apps = Array.isArray(data.top_apps) ? data.top_apps : []
  return {
    activeMinutes: data.active_minutes,
    keys: typeof data.keys === "number" ? data.keys : null,
    apps: apps.filter(function(app) { return app && typeof app.minutes === "number" })
              .slice(0, 3)
              .map(function(app) {
                return { name: String(app.name || "?"), minutes: app.minutes, icon: String(app.icon || "") }
              })
  }
}

function parseDashboard(text) {
  var data
  try { data = JSON.parse(String(text || "")) } catch (error) { return null }
  if (!data || typeof data !== "object") return null
  var health = data.health || {}
  var messages = Array.isArray(health.messages) ? health.messages : []
  return {
    stat: data.stat_of_the_day || null,
    achievement: data.latest_achievement || null,
    healthOk: health.ok !== false,
    healthMessage: messages.length > 0 ? String(messages[0]) : ""
  }
}

function share(part, total) {
  if (typeof part !== "number" || typeof total !== "number" || total <= 0) return 0
  return Math.max(0, Math.min(1, part / total))
}
