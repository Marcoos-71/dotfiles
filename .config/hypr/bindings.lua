-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- Restauradas tras la migración a Omarchy 4: estos defaults nuevos pisaban
-- teclas que ya usaba para otra cosa en Omarchy 3.
hl.unbind("SUPER + SHIFT + M")
o.bind("SUPER + SHIFT + M", "Music", { focus = "nuclear", launch = "nuclear" }) -- default nuevo: Spotify

hl.unbind("SUPER + SHIFT + S")
o.bind("SUPER + SHIFT + S", "Steam", { focus = "steam", launch = "steam" }) -- default nuevo: Google Maps

hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "Claude", { webapp = "https://claude.ai" }) -- default nuevo: ChatGPT

hl.unbind("SUPER + SHIFT + C")
o.bind("SUPER + SHIFT + C", "Calendar", { webapp = "https://calendar.google.com/" }) -- default nuevo: Hey Calendar

hl.unbind("SUPER + SHIFT + E")
o.bind("SUPER + SHIFT + E", "Email", { webapp = "https://mail.google.com/" }) -- default nuevo: Hey Email

hl.unbind("SUPER + SHIFT + SLASH")
o.bind("SUPER + SHIFT + SLASH", "Passwords", { launch = "bitwarden" }) -- default nuevo: 1Password

-- Nuevas (no existían en los defaults de Omarchy 4)
o.bind("SUPER + SHIFT + V", "VS Code", { focus = "code", launch = "code" })
o.bind("SUPER + SHIFT + L", "Git", { tui = "lazygit" })
o.bind("SUPER + SHIFT + I", "Odysseus", { webapp = "http://localhost:7000" })

-- Navegación de workspaces con Home/Prior/Next
o.bind("Home", "Workspace anterior", hl.dsp.focus({ workspace = "e-1" }))
o.bind("Prior", "Workspace siguiente", hl.dsp.focus({ workspace = "e+1" }))
o.bind("Next", "Mover ventana al workspace siguiente", hl.dsp.window.move({ workspace = "e+1" }))

-- SUPER CTRL W (antes "Toggle Waybar") queda pendiente del rediseño de la
-- barra con Quickshell. Por ahora esa tecla sigue siendo el default nuevo
-- (Network) — no la toco hasta diseñar la barra.
