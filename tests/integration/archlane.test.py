#!/usr/bin/env python3
"""Prove the archlane renders install/status bins and joins install.sh's packages lane.

Run directly (like the other integration probes):

    ./tests/integration/archlane.test.py

Renders a scratch playbook that imports gen_apt/gen_arch/gen_bins/bins tasks
against a temp payload, then asserts the lane artifacts. Everything stays
inside .test-agent/archlane.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "archlane"

SCRATCH_PLAYBOOK = """---
- hosts: all
  gather_facts: false
  vars_files: [{vars_common!r}]
  vars:
    TYPE: archlane-probe
    NAME: archlane-probe-main
    INSTANCE: main
    DIR: {payload!r}
    ETC: {etc!r}
    BINS_DIR: {bins_dir!r}
    BINS: []
    ETC_FILES: []
    ETC_DIRS: []
    DIRS: []
    ENV: {{}}
    ENV_LIST: []
    STATUSES: []
    GET_URLS: []
    PKGS: []
    ARCH_PKGS: []
  tasks:
    - import_tasks: {gen_apt!r}
      when: PKGS is defined or PKGSET is defined or PKGSETS is defined
    - import_tasks: {gen_arch!r}
      when: ARCH_PKGS is defined or ARCH_PKGSET is defined or ARCH_PKGSETS is defined
    - import_tasks: {gen_bins!r}
    - file:
        path: "{{{{ item }}}}"
        state: directory
      loop: "{{{{ [ETC, BINS_DIR] + (ETC_DIRS | map('defaultDir', ETC) | list) }}}}"
    - import_tasks: {bins!r}
    - import_tasks: {bins_link!r}
"""


def render(name: str, overrides: dict) -> Path:
    payload = SCRATCH / name
    payload.mkdir(parents=True, exist_ok=True)
    playbook = SCRATCH / f"archlane-{name}.pb"
    playbook.parent.mkdir(parents=True, exist_ok=True)
    for link_name in ("files", "vars"):
        link = playbook.parent / link_name
        if not link.exists():
            link.symlink_to(ROOT / link_name, target_is_directory=True)
    playbook.write_text(
        SCRATCH_PLAYBOOK.format(
            vars_common=str(ROOT / "vars" / "common.yaml"),
            payload=str(payload),
            etc=str(payload / "etc"),
            bins_dir=str(payload / "bin"),
            gen_apt=str(ROOT / "tasks" / "compfuzor" / "gen_apt.tasks"),
            gen_arch=str(ROOT / "tasks" / "compfuzor" / "gen_arch.tasks"),
            gen_bins=str(ROOT / "tasks" / "compfuzor" / "gen_bins.tasks"),
            bins=str(ROOT / "tasks" / "compfuzor" / "bins.tasks"),
            bins_link=str(ROOT / "tasks" / "compfuzor" / "bins_link.tasks"),
        ),
        encoding="utf-8",
    )
    scenario = playbook.with_suffix(".json")
    scenario.write_text(json.dumps(overrides), encoding="utf-8")
    env = dict(os.environ, HOME=str(payload.parent))
    result = subprocess.run(
        ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook), "-e", f"@{scenario}"],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise AssertionError(f"render failed:\n{result.stdout}\n{result.stderr}")
    return payload


def test_archlane_renders_bins_and_joins_packages_lane() -> None:
    payload = render("render", {"ARCH_PKGS": ["niri", "xwayland-satellite"]})

    install_arch = payload / "bin" / "install-arch.sh"
    if not install_arch.is_file():
        raise AssertionError("install-arch.sh not materialized")
    body = install_arch.read_text(encoding="utf-8")
    assert "pacman -S --needed --noconfirm" in body
    assert "niri" in body and "xwayland-satellite" in body
    # lane self-gates so dual-list playbooks stay safe on apt hosts
    assert "command -v pacman" in body

    status_arch = payload / "bin" / "status-arch.sh"
    if not status_arch.is_file():
        raise AssertionError("status-arch.sh not materialized")
    assert "pacman -Q" in status_arch.read_text(encoding="utf-8")

    install = payload / "bin" / "install.sh"
    if not install.is_file():
        raise AssertionError("install.sh compositor not materialized")
    compositor = install.read_text(encoding="utf-8")
    if "install-arch.sh" not in compositor:
        raise AssertionError("arch lane missing from install.sh run_all")
    print("ok: archlane renders install/status bins and joins install.sh")


def test_archlane_and_aptlane_coexist_in_packages_lane() -> None:
    payload = render("dual", {"ARCH_PKGS": ["niri"], "PKGS": ["cmake"]})

    compositor = (payload / "bin" / "install.sh").read_text(encoding="utf-8")
    assert "install-apt.sh" in compositor
    assert "install-arch.sh" in compositor
    assert compositor.index("install-apt.sh") < compositor.index("install-arch.sh")
    assert (payload / "bin" / "install-apt.sh").is_file()
    assert (payload / "bin" / "install-arch.sh").is_file()
    apt_lane = (payload / "bin" / "install-apt.sh").read_text(encoding="utf-8")
    assert "command -v apt-get" in apt_lane
    arch_lane = (payload / "bin" / "install-arch.sh").read_text(encoding="utf-8")
    assert "command -v pacman" in arch_lane
    print("ok: apt and arch lanes coexist in the packages lane, apt first")


def test_archlane_inactive_without_declaration() -> None:
    payload = render("quiet", {})
    assert not (payload / "bin" / "install-arch.sh").exists()
    assert not (payload / "bin" / "status-arch.sh").exists()
    print("ok: archlane stays inactive without ARCH_* declarations")


if __name__ == "__main__":
    test_archlane_renders_bins_and_joins_packages_lane()
    test_archlane_and_aptlane_coexist_in_packages_lane()
    test_archlane_inactive_without_declaration()
