# Style tokens

The source of truth is `~/.config/omarchy/style-tokens.toml`; every `Tokens.js` is generated and will be overwritten.

`omarchy-style` reads that file, flattens it into camelCase names and writes one
`Tokens.js` per plugin in `TOKEN_PLUGINS` (`marcos.dashboard`, `marcos.netspeed`,
`marcos.sysmon`). QML imports its own copy — no service, no cross-plugin imports:

```qml
import "Tokens.js" as Tokens
// ...
duration: Tokens.motionNormal
```

## Motion

| Token | Value | Unit | What it is for |
|---|---|---|---|
| `motionNormal` | 260 | ms | Opening a surface. A 150ms fade is imperceptible on a full-screen card; a 420ms spring wears thin by the third time in a day. |
| `motionFast` | 150 | ms | Transitions inside a surface that is already open, and every exit: leaving is always quicker than arriving. |
| `motionInstant` | 90 | ms | Semantic state changes we own, like netspeed turning blue on traffic. |
| `motionRise` | 8 | px | How far a surface travels while it appears. |
| `motionScaleFrom` | 0.965 | 0..1 | Scale a surface starts from before settling at 1. |

## Depth

| Token | Value | Unit | What it is for |
|---|---|---|---|
| `scrimAlpha` | 0.30 | 0..1 | Opacity of the dim behind an overlay. Low because Hyprland blurs the layer underneath. |
| `ruleAlpha` | 0.16 | 0..1 | Separator lines against the card background: visible as structure, never as a border. |

## Elevation

Shadow of a surface, by how far it floats above the desktop.

| Token | Value | Unit | What it is for |
|---|---|---|---|
| `elevPopupY` | 6 | px | Vertical offset of a popup's shadow. |
| `elevPopupBlur` | 18 | px | Blur radius of a popup's shadow. |
| `elevPopupAlpha` | 0.35 | 0..1 | Opacity of a popup's shadow. |
| `elevOverlayY` | 14 | px | Vertical offset of a full overlay's shadow. |
| `elevOverlayBlur` | 38 | px | Blur radius of a full overlay's shadow. |
| `elevOverlayAlpha` | 0.50 | 0..1 | Opacity of a full overlay's shadow. |

## Changing a value

```bash
$EDITOR ~/.config/omarchy/style-tokens.toml   # the file is a symlink into ~/dotfiles
OMARCHY_PATH=/usr/share/omarchy omarchy-style # regenerates every Tokens.js
```

## Seeing what changed

```bash
git -C ~/dotfiles diff .config/omarchy/style-tokens.toml .config/omarchy/plugins/*/Tokens.js
```
