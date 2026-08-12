#!/usr/bin/env python3
"""Verify legacy _D consumers use explicit concat config declarations."""

from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]


def variables(playbook: str) -> dict:
    return yaml.safe_load((ROOT / playbook).read_text(encoding="utf-8"))[0]["vars"]


def check_concat(
    playbook: str,
    dropin_id: str,
    config_id: str,
    root: str,
    source: str,
    output: str,
) -> None:
    declared = variables(playbook)
    dropin = declared["DROPINS"][dropin_id]
    assembly = next(iter(declared["CONFIGS"][config_id]["assemblies"].values()))

    assert dropin["root"] == root
    assert dropin["path"] == source
    assert dropin["include"] == "*"
    assert assembly["output"] == output
    assert assembly["processor"] == "concat"
    assert assembly["inputs"] == [{"dropins": dropin_id}]


def test_legacy_d_removal() -> None:
    check_concat(
        "dovecot.pb",
        "dovecot-master-lmtp",
        "dovecot",
        "{{ETC}}",
        "conf.d/11-master-lmtp.conf.d",
        "conf.d/11-master-lmtp.conf",
    )
    check_concat("locales.pb", "locales", "locales", "/etc", "locale.gen.d", "locale.gen")
    check_concat(
        "screen.user.pb",
        "screen",
        "screen",
        "{{HOMEDIR}}",
        ".screenrc.d",
        ".screenrc",
    )
    check_concat(
        "clickpad.user.pb",
        "clickpad",
        "clickpad",
        "{{home.stdout}}",
        ".xinitrc.d",
        ".xinitrc",
    )

    assert variables("dovecot.pb")["DROPINS"]["dovecot-master-lmtp"]["files"] == [
        {"name": "20-11-master-lmtp.conf", "src": "conf.d/11-master-lmtp.conf"}
    ]
    assert variables("clickpad.user.pb")["DROPINS"]["clickpad"]["files"] == [
        {"name": "foo", "src": "clickpad.xinitrc"}
    ]

    removed = (
        "tasks/compfuzor/fs_d.tasks",
        "tasks/compfuzor/fs_base_d.tasks",
    )
    assert all(not (ROOT / path).exists() for path in removed)

    plumbing = "\n".join(
        (ROOT / path).read_text(encoding="utf-8")
        for path in (
            "tasks/compfuzor.includes",
            "tasks/compfuzor/_multi.tasks",
            "tasks/compfuzor/fs_hierarchy.tasks",
            "tasks/compfuzor/vars_fs.tasks",
            "prometheus.pb",
        )
    )
    for legacy in ("fs_d.tasks", "fs_base_d.tasks", "_D_BYPASS", "ETC_D:", "assemble:"):
        assert legacy not in plumbing


if __name__ == "__main__":
    test_legacy_d_removal()
    print("ok: legacy _D removal")
