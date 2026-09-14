import json
import subprocess
from pathlib import Path

SCRIPT = Path.home() / "dotfiles/.local/bin/omarchy-capture"


def run(folder, title, body):
    result = subprocess.run(
        [str(SCRIPT), str(folder), title, body], capture_output=True, text=True
    )
    return result, json.loads(result.stdout)


def test_writes_a_new_file(tmp_path):
    folder = tmp_path / "20-Media" / "Games"
    result, data = run(folder, "Hollow Knight", "---\ntype: game\n---\n")
    assert result.returncode == 0
    assert data["ok"] is True
    written = Path(data["path"])
    assert written == folder / "Hollow Knight.md"
    assert written.read_text() == "---\ntype: game\n---\n"


def test_creates_missing_parent_folders(tmp_path):
    folder = tmp_path / "16-Travel"
    assert not folder.exists()
    _, data = run(folder, "Georgia", "# Georgia\n")
    assert data["ok"] is True
    assert folder.is_dir()


def test_resolves_name_collisions(tmp_path):
    (tmp_path / "Dune.md").write_text("first")
    _, first = run(tmp_path, "Dune", "second")
    assert first["path"] == str(tmp_path / "Dune 2.md")
    (tmp_path / "Dune 2.md").write_text("already there too")
    _, second = run(tmp_path, "Dune", "third")
    assert second["path"] == str(tmp_path / "Dune 3.md")


def test_never_writes_outside_the_target_folder(tmp_path):
    folder = tmp_path / "00-Inbox"
    _, data = run(folder, "escape/../../attempt", "x")
    assert data["ok"] is True
    written = Path(data["path"])
    assert written.parent == folder


def test_missing_arguments_reports_and_exits_zero():
    result = subprocess.run([str(SCRIPT)], capture_output=True, text=True)
    data = json.loads(result.stdout)
    assert result.returncode == 0
    assert data["ok"] is False
    assert "usage" in data["reason"]


def test_write_failure_is_reported_not_raised(tmp_path):
    # A file standing where a parent directory should be makes mkdir fail.
    blocker = tmp_path / "blocker"
    blocker.write_text("not a directory")
    result, data = run(blocker / "sub", "Title", "body")
    assert result.returncode == 0
    assert data["ok"] is False
    assert data["reason"] != ""


def test_unicode_and_quotes_in_title_survive(tmp_path):
    _, data = run(tmp_path, 'Año "difícil" en España', "body")
    assert data["ok"] is True
    assert Path(data["path"]).read_text() == "body"
