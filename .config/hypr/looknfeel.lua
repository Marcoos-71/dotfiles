-- Change the default Omarchy look'n'feel.

hl.config({
  general = {
    resize_on_border = true,
    allow_tearing = true,
  },
})

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--
--     -- Change to niri-like side-scrolling layout.
--     layout = "scrolling",
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })

-- Redondeo de esquinas. La barra hereda este valor para sus tooltips, popups
-- y el pill de hover (Style.cornerRadius lo lee de aqui), asi que subirlo
-- suaviza tambien el shell, no solo las ventanas.
hl.config({
  decoration = {
    rounding = 8,
  },
})

-- Desenfoque: apagado para ventanas a proposito. Omarchy les pone
-- opacity 0.985, asi que blur global costaria una pasada por ventana sin
-- ganancia visible. Solo las superficies propias lo piden por namespace.
hl.config({
  decoration = {
    blur = {
      enabled = true,
      size = 8,
      passes = 2,
      new_optimizations = true,
      ignore_opacity = true,
    },
  },
})

o.window(".*", { no_blur = true })

-- `hyprctl keyword` no vale en 0.56 con el parser Lua ("keyword can't work
-- with non-legacy parsers"), asi que la regla se escribe como hl.layer_rule,
-- igual que las de omarchy-shell.lua.
hl.layer_rule({ match = { namespace = "marcos-dashboard" }, blur = true })
