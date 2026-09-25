-- Activity logger for ~/Projects/wrapped (see docs/design.md there).
-- Appends one TSV line per window event: ts, event, class, title, extra.
-- Kill switch: touch ~/.local/state/wrapped/logger-off and reload Hyprland.

local HOME = os.getenv("HOME")
local RAW_DIR = HOME .. "/.local/share/wrapped/raw/hypr"
local STATE_DIR = HOME .. "/.local/state/wrapped"
local MAX_ERRORS = 20
local KEY_FLUSH_EVERY = 500
local TITLE_MAX = 200
local REDACT_CLASSES = { "bitwarden", "1password", "keepassxc" }
local REDACT_TITLES = { "Private Browsing", "Navegación privada", "Incognito", "Incógnito" }

local W = _G.__wrapped or {}
_G.__wrapped = W
for _, sub in ipairs(W.subs or {}) do
  pcall(function() sub:remove() end)
end
if W.file then
  pcall(function() W.file:close() end)
end
W.subs, W.file, W.month = {}, nil, nil
W.errors, W.calls, W.cpu = 0, 0, 0
W.keys, W.focus_class = 0, ""

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end

if exists(STATE_DIR .. "/logger-off") then
  return
end

local function clean(s)
  if s == nil then return "" end
  s = tostring(s):gsub("[\t\r\n]", " ")
  if #s > TITLE_MAX then s = s:sub(1, TITLE_MAX) end
  return s
end

local function redacted_title(class, title)
  local lc = class:lower()
  for _, c in ipairs(REDACT_CLASSES) do
    if lc:find(c, 1, true) then return "" end
  end
  for _, t in ipairs(REDACT_TITLES) do
    if title:find(t, 1, true) then return "[private]" end
  end
  return title
end

local function handle()
  local month = os.date("!%Y-%m")
  if W.file and W.month == month then return W.file end
  if W.file then W.file:close() end
  local path = RAW_DIR .. "/events-" .. month .. ".tsv"
  local f = io.open(path, "a")
  if not f then
    os.execute("mkdir -p '" .. RAW_DIR .. "'")
    f = assert(io.open(path, "a"))
  end
  f:setvbuf("full", 8192)
  W.file, W.month = f, month
  return f
end

local function write(event, class, title, extra)
  handle():write(os.time(), "\t", event, "\t", class or "", "\t", title or "", "\t", extra or "", "\n")
end

local function flush_keys()
  if W.keys > 0 then
    write("keys", W.focus_class, "", tostring(W.keys))
    W.keys = 0
  end
end

local function window_fields(w)
  if w == nil then return "", "" end
  local class = clean(w.class)
  return class, redacted_title(class, clean(w.title))
end

local function disable(reason)
  for _, sub in ipairs(W.subs) do
    pcall(function() sub:remove() end)
  end
  W.subs = {}
  pcall(function()
    os.execute("mkdir -p '" .. STATE_DIR .. "'")
    local f = io.open(STATE_DIR .. "/logger-broken", "w")
    f:write(os.date("!%Y-%m-%dT%H:%M:%SZ"), "\t", clean(reason), "\n")
    f:close()
  end)
end

local function guard(fn)
  return function(...)
    local t0 = os.clock()
    local ok, err = pcall(fn, ...)
    W.calls = W.calls + 1
    W.cpu = W.cpu + (os.clock() - t0)
    if not ok then
      W.errors = W.errors + 1
      W.last_error = err
      if W.errors >= MAX_ERRORS then disable(err) end
    end
  end
end

local handlers = {
  ["window.open"] = function(w)
    local class, title = window_fields(w)
    write("open", class, title, tostring(w.address))
  end,
  ["window.close"] = function(w)
    local class = window_fields(w)
    write("close", class, "", tostring(w.address))
  end,
  ["window.active"] = function(w)
    flush_keys()
    local class, title = window_fields(w)
    W.focus_class = class
    write("focus", class, title, w and tostring(w.address) or "")
    W.file:flush()
  end,
  ["window.fullscreen"] = function(w)
    local class = window_fields(w)
    write("fullscreen", class, "", tostring(w.fullscreen))
  end,
  ["workspace.active"] = function(ws)
    write("workspace", "", "", ws and clean(ws.name) or "")
  end,
  ["input.keyboard.key"] = function(_, _, state)
    if state ~= 1 then return end
    W.keys = W.keys + 1
    if W.keys >= KEY_FLUSH_EVERY then flush_keys() end
  end,
  ["hyprland.shutdown"] = function()
    flush_keys()
    write("shutdown")
    W.file:flush()
  end,
}

local ok, err = pcall(function()
  write("start", "", "", "")
  W.file:flush()
  for event, fn in pairs(handlers) do
    table.insert(W.subs, hl.on(event, guard(fn)))
  end
end)
if not ok then disable(err) end
