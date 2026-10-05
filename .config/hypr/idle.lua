-- Fullscreen games and videos count as activity: no screensaver or lock while they are fullscreen.
-- A controller doesn't reach Hyprland, so without this a long gamepad session locks the screen.
o.window("^steam_app_.*", { idle_inhibit = "fullscreen" })   -- Steam games (Proton included)
o.window(".*\\.exe$", { idle_inhibit = "fullscreen" })       -- Wine/umu games
o.window("^(Minecraft.*|com\\.factorio\\.Factorio|Celeste)$", { idle_inhibit = "fullscreen" })  -- native games
o.window("^firefox$", { idle_inhibit = "fullscreen" })       -- fullscreen video
