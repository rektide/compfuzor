#!/usr/bin/env python3
"""Deb822 generation and unprivileged publication into sandbox paths."""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "apt-deb822"


def render(name, overrides, expect_failure=False):
    root = SCRATCH / name
    for directory in (root / "etc", root / "sources", root / "preferences", root / "keyrings"):
        directory.mkdir(parents=True, exist_ok=True)
    SCRATCH.mkdir(parents=True, exist_ok=True)
    (SCRATCH / "README.md").write_text("# apt-deb822 tests\n\nSandboxed render and publication probes.\n")
    for child in ("vars", "files"):
        link = SCRATCH / child
        if not link.exists():
            link.symlink_to(ROOT / child, target_is_directory=True)
    playbook = SCRATCH / "probe.pb"
    playbook.write_text(
        """---
- hosts: all
  gather_facts: false
  vars_files:
    - {common}
  vars:
    TYPE: apt-probe
    NAME: apt-probe-main
    ETC: {etc}
    ETC_FILES: []
    APT_SOURCES_DIR: {sources}
    APT_PREFERENCES_DIR: {preferences}
    APT_KEYRINGS_DIR: {keyrings}
    APT_BECOME: false
    APT_UPDATE_BYPASS: true
  tasks:
    - import_tasks: {vars_apt}
    - import_tasks: {gen}
      when: APT is defined or APTS is defined
    - copy:
        dest: "{{{{ ETC }}}}/{{{{ item.name }}}}"
        content: "{{{{ item.content }}}}"
        mode: "0644"
      loop: "{{{{ ETC_FILES | selectattr('content', 'defined') | list }}}}"
    - import_tasks: {deliver}
      when: APT is defined or APTS is defined
""".format(
            common=ROOT / "vars/common.yaml", etc=root / "etc", sources=root / "sources",
            preferences=root / "preferences", keyrings=root / "keyrings",
            vars_apt=ROOT / "tasks/compfuzor/vars_apt.tasks",
            gen=ROOT / "tasks/compfuzor/gen_apt_sources.tasks",
            deliver=ROOT / "tasks/compfuzor/apt_deb822.tasks",
        )
    )
    (SCRATCH / "vars.json").write_text(json.dumps({"TYPE": "apt-probe", "NAME": "apt-probe-main", **overrides}))
    result = subprocess.run(
        ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook), "-e", f"@{SCRATCH / 'vars.json'}"],
        cwd=ROOT, env={**os.environ, "HOME": str(SCRATCH)}, text=True, capture_output=True,
    )
    if expect_failure:
        assert result.returncode, result.stdout + result.stderr
    else:
        assert result.returncode == 0, result.stdout + result.stderr
    return root, result.stdout + result.stderr


def test_sources_override_legacy():
    root, log = render("source-only", {
        "APT": {"URIs": "https://example.org/repo", "Suites": "stable", "By-Hash": "yes"},
        "APT_REPO": "https://legacy.example.org/repo",
        "APT_LIST_URL": "https://legacy.example.org/apt.list",
        "APT_PIN": "release n=legacy", "APT_PIN_PRIORITY": 200,
        "APT_PREFS": {"Pin": "release n=stable", "Pin-Priority": 600},
    })
    source = root / "sources/apt-probe.sources"
    assert source.is_symlink()
    assert "By-Hash: yes" in source.read_text()
    assert "legacy.example.org" not in source.read_text()
    assert not (root / "sources/apt-probe.list").exists()
    assert (root / "preferences/apt-probe.pref").read_text() == "Package: *\nPin: release n=stable\nPin-Priority: 600\n"
    assert "ignoring legacy" in log
    assert "APT_REPO" in log and "APT_PIN" in log


def test_invalid_empty_apt_does_not_fall_back():
    _, log = render("empty", {"APT": {}, "APT_REPO": "https://legacy.example.org"}, True)
    assert "requires URIs" in log


if __name__ == "__main__":
    test_sources_override_legacy()
    test_invalid_empty_apt_does_not_fall_back()
    print("ok: deb822 source render and precedence")
