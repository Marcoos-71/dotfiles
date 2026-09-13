import json
import os
import stat
import subprocess
import sys
from pathlib import Path

SCRIPT = Path.home() / "dotfiles/.local/bin/omarchy-agenda"


def bin_dir(tmp_path, name="bin"):
    """A PATH directory holding the interpreter and nothing else.

    These tests replace PATH wholesale to hide khal, but the script's shebang
    resolves python3 through PATH too, so an empty directory makes it exit 127
    with no output instead of reporting a missing khal.
    """
    directory = tmp_path / name
    directory.mkdir(exist_ok=True)
    link = directory / "python3"
    if not link.exists():
        link.symlink_to(sys.executable)
    return directory


def fake_khal(tmp_path, stdout="", returncode=0):
    directory = bin_dir(tmp_path)
    khal = directory / "khal"
    # Written in Python rather than as a shell heredoc: PATH is stripped here,
    # so the stub cannot call out to cat, and a repr-quoted literal survives
    # quotes and accents in fixtures.
    khal.write_text(
        "#!/usr/bin/env python3\n"
        "import sys\n"
        f"sys.stdout.write({stdout!r})\n"
        f"sys.exit({returncode})\n"
    )
    khal.chmod(khal.stat().st_mode | stat.S_IEXEC)
    return directory


def run(path_dir):
    env = dict(os.environ, PATH=str(path_dir))
    result = subprocess.run([str(SCRIPT)], capture_output=True, text=True, env=env)
    return result, json.loads(result.stdout)


def test_parses_timed_events(tmp_path):
    out = "09:30|10:30|Reunión equipo|Sala 2\n13:00|14:00|Comida|"
    result, data = run(fake_khal(tmp_path, out))
    assert result.returncode == 0
    assert data["ok"] is True
    assert data["events"][0] == {
        "start": "09:30", "end": "10:30",
        "title": "Reunión equipo", "location": "Sala 2", "allDay": False,
    }
    assert data["events"][1]["location"] == ""


def test_all_day_event_has_no_start(tmp_path):
    result, data = run(fake_khal(tmp_path, "||Cumpleaños de Ana|"))
    assert data["events"][0]["allDay"] is True
    assert data["events"][0]["start"] == ""
    assert data["events"][0]["title"] == "Cumpleaños de Ana"


def test_no_events_is_success_with_empty_list(tmp_path):
    result, data = run(fake_khal(tmp_path, ""))
    assert data["ok"] is True
    assert data["events"] == []


def test_titles_containing_a_pipe_survive(tmp_path):
    result, data = run(fake_khal(tmp_path, "09:00|10:00|Repaso | tesis|"))
    assert data["events"][0]["title"] == "Repaso | tesis"


def test_missing_khal_reports_a_reason_and_still_exits_zero(tmp_path):
    result, data = run(bin_dir(tmp_path, "empty"))
    assert result.returncode == 0
    assert data["ok"] is False
    assert "khal" in data["reason"]
    assert data["events"] == []


def test_reports_when_the_calendar_last_synced(tmp_path):
    result, data = run(fake_khal(tmp_path, ""))
    calendars = Path.home() / ".calendars"
    if calendars.exists():
        assert data["syncedAt"] == int(calendars.stat().st_mtime)
    else:
        assert data["syncedAt"] is None


def test_khal_failure_reports_a_reason(tmp_path):
    result, data = run(fake_khal(tmp_path, "error", returncode=1))
    assert result.returncode == 0
    assert data["ok"] is False
    assert data["events"] == []
