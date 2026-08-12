#!/usr/bin/env python3
"""Verify old _D consumers use flat filename-keyed concat configs."""

from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]


def variables(playbook: str) -> dict:
    return yaml.safe_load((ROOT / playbook).read_text(encoding="utf-8"))[0]["vars"]


def test_legacy_d_removal() -> None:
    expected = {
        "dovecot.pb": ("conf.d/11-master-lmtp.conf", "concat"),
        "locales.pb": ("locale.gen", "concat"),
        "screen.user.pb": (".screenrc", "concat"),
        "clickpad.user.pb": (".xinitrc", "concat"),
    }
    for playbook, (output, processor) in expected.items():
        declared = variables(playbook)
        assert "DROPINS" not in declared
        assert declared["CONFIGS"][output]["processor"] == processor

    assert any(
        item.get("name") == "conf.d/11-master-lmtp.conf.d/20-11-master-lmtp.conf"
        for item in variables("dovecot.pb")["ETC_FILES"] if isinstance(item, dict)
    )
    assert all(not (ROOT / path).exists() for path in (
        "tasks/compfuzor/fs_d.tasks",
        "tasks/compfuzor/fs_base_d.tasks",
    ))


if __name__ == "__main__":
    test_legacy_d_removal()
    print("ok: legacy _D removal")
