import importlib.machinery
import importlib.util
from pathlib import Path

SCRIPT = Path.home() / "dotfiles/.local/bin/omarchy-style"
TOML = Path.home() / "dotfiles/.config/omarchy/style-tokens.toml"


def load():
    """Import omarchy-style as a module despite having no .py extension."""
    spec = importlib.util.spec_from_loader(
        "omarchy_style",
        importlib.machinery.SourceFileLoader("omarchy_style", str(SCRIPT)),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_parse_flattens_sections_to_camel_case():
    m = load()
    values = m.parse_tokens(TOML.read_text())
    assert values["motionNormal"] == 260
    assert values["motionScaleFrom"] == 0.965
    assert values["scrimAlpha"] == 0.30
    assert values["elevOverlayBlur"] == 38


def test_render_produces_a_pragma_library_with_every_value():
    m = load()
    js = m.render_tokens_js({"motionNormal": 260, "scrimAlpha": 0.3})
    assert js.startswith(".pragma library")
    assert "var motionNormal = 260" in js
    assert "var scrimAlpha = 0.3" in js
    assert "do not edit" in js.lower()


def test_old_name_still_runs():
    old = Path.home() / "dotfiles/.local/bin/omarchy-bar-colors"
    assert old.is_symlink()
    assert old.resolve().name == "omarchy-style"
