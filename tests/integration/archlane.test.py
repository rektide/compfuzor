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
    SRC: {src!r}
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
    - import_tasks: {vars_env!r}
    - import_tasks: {fs_env!r}
      when: >
        not ENV_BYPASS|default(False)|bool and
        (
          has_env.stdout|default(0)|int != 0 or
          has_env_export.stdout|default(0)|int != 0 or
          has_env_usermode.stdout|default(0)|int != 0 or
          (ENV is defined and (ENV is mapping or (ENV is boolean and ENV))) or
          (ENV_PRIO is defined and (ENV_PRIO is mapping or (ENV_PRIO is boolean and ENV_PRIO))) or
          ENV_LIST|normalize(to='list')|length > 0 or
          ENV_PRIO_LIST|normalize(to='list')|length > 0
        )
    - import_tasks: {bins!r}
    - import_tasks: {bins_link!r}
"""


def render(name: str, overrides: dict) -> Path:
    payload = SCRATCH / name
    payload.mkdir(parents=True, exist_ok=True)
    # The playbook filename follows compfuzor's <type>.<instance>.pb
    # convention: common.yaml's lazy TYPE/INSTANCE derive from it via the
    # ansible_cmdline filter, which the vars_env/fs_env tasks template.
    playbook = SCRATCH / f"archlane.{name}.pb"
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
            src=str(payload / "src"),
            gen_apt=str(ROOT / "tasks" / "compfuzor" / "gen_apt.tasks"),
            gen_arch=str(ROOT / "tasks" / "compfuzor" / "gen_arch.tasks"),
            gen_bins=str(ROOT / "tasks" / "compfuzor" / "gen_bins.tasks"),
            vars_env=str(ROOT / "tasks" / "compfuzor" / "vars_env.tasks"),
            fs_env=str(ROOT / "tasks" / "compfuzor" / "fs_env.tasks"),
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
    assert "pacman-conf --repo-list" in arch_lane
    print("ok: apt and arch lanes coexist in the packages lane, apt first")


def test_archlane_inactive_without_declaration() -> None:
    payload = render("quiet", {})
    assert not (payload / "bin" / "install-arch.sh").exists()
    assert not (payload / "bin" / "status-arch.sh").exists()
    print("ok: archlane stays inactive without ARCH_* declarations")


def test_usermode_lanes_skip_by_default_and_force_runs() -> None:
    """USERMODE renders skip the package lanes loudly; force (or root) runs them.

    The runtime guard reads USERMODE from the deployment's env.export (emitted
    by files/_env), so the render here includes the env emission tasks. Stubs
    for pacman/pacman-conf/sudo keep the run hermetic: the skip must fire
    before any package-manager call, and the force path must reach the (stubbed)
    sudo pacman invocation.
    """
    payload = render("usermode", {"ARCH_PKGS": ["niri"], "PKGS": ["cmake"], "USERMODE": True})

    env_export = payload / "env.export"
    export_text = env_export.read_text(encoding="utf-8")
    assert 'USERMODE="True"' in export_text, export_text

    apt_lane = payload / "bin" / "install-apt.sh"
    arch_lane = payload / "bin" / "install-arch.sh"
    for lane, gate, force in (
        (apt_lane, "command -v apt-get", "COMPFUZOR_APTLANE_FORCE"),
        (arch_lane, "command -v pacman", "COMPFUZOR_ARCHLANE_FORCE"),
    ):
        body = lane.read_text(encoding="utf-8")
        assert "USERMODE" in body and force in body, body
        # the guard precedes the package-manager self-gates
        assert body.index("USERMODE") < body.index(gate), body

    stubs = payload.parent / "usermode-stubs"
    stubs.mkdir(parents=True, exist_ok=True)
    call_log = stubs / "calls.log"
    call_log.unlink(missing_ok=True)

    def lane_env(home: Path) -> dict[str, str]:
        # Drop any inherited deployment identity (DIR/ENV_BYPASS/...): the
        # bins defer to an inherited $DIR and would source a foreign
        # deployment's env.export instead of this fixture's.
        environment = {
            key: value
            for key, value in os.environ.items()
            if key not in ("DIR", "NAME", "TYPE", "INSTANCE", "USERMODE", "ENV_BYPASS")
            and not key.startswith("COMPFUZOR_")
        }
        environment["HOME"] = str(home)
        environment["PATH"] = os.pathsep.join((str(stubs), "/usr/bin", "/bin"))
        return environment

    sudo_log_line = f"echo sudo $* >> {str(call_log)!r}\n"
    for name, body in (
        ("sudo", f'#!/bin/sh\n{sudo_log_line}exec "$@"\n'),
        ("pacman", f'#!/bin/sh\necho pacman $* >> {str(call_log)!r}\nexit 0\n'),
        ("pacman-conf", "#!/bin/sh\necho core\nexit 0\n"),
    ):
        stub = stubs / name
        stub.write_text(body, encoding="utf-8")
        stub.chmod(0o755)

    skipped = subprocess.run(
        [str(arch_lane)], cwd=payload, env=lane_env(payload.parent), text=True, capture_output=True
    )
    assert skipped.returncode == 0, (skipped.stdout, skipped.stderr)
    assert "skipping USERMODE packages lane" in skipped.stderr, skipped.stderr
    assert "COMPFUZOR_ARCHLANE_FORCE=1" in skipped.stderr, skipped.stderr
    assert "sudo" in skipped.stderr, skipped.stderr
    assert not call_log.exists()

    apt_skipped = subprocess.run(
        [str(apt_lane)], cwd=payload, env=lane_env(payload.parent), text=True, capture_output=True
    )
    assert apt_skipped.returncode == 0, (apt_skipped.stdout, apt_skipped.stderr)
    assert "skipping USERMODE packages lane" in apt_skipped.stderr, apt_skipped.stderr
    assert "COMPFUZOR_APTLANE_FORCE=1" in apt_skipped.stderr, apt_skipped.stderr
    assert not call_log.exists()

    forced = subprocess.run(
        [str(arch_lane)],
        cwd=payload,
        env=lane_env(payload.parent) | {"COMPFUZOR_ARCHLANE_FORCE": "1"},
        text=True,
        capture_output=True,
    )
    assert forced.returncode == 0, (forced.stdout, forced.stderr)
    calls = call_log.read_text(encoding="utf-8") if call_log.exists() else ""
    assert "pacman -S --needed --noconfirm niri" in calls, calls

    # Without USERMODE the lane runs unchanged (no skip, straight to the
    # package-manager gates and the convergence call).
    plain = render("plain-run", {"ARCH_PKGS": ["niri"]})
    plain_export = (plain / "env.export").read_text(encoding="utf-8")
    assert "USERMODE" not in plain_export, plain_export
    plain_run = subprocess.run(
        [str(plain / "bin" / "install-arch.sh")],
        cwd=plain,
        env=lane_env(plain.parent),
        text=True,
        capture_output=True,
    )
    assert plain_run.returncode == 0, (plain_run.stdout, plain_run.stderr)
    assert "skipping USERMODE" not in plain_run.stderr
    calls = call_log.read_text(encoding="utf-8")
    assert "pacman -S --needed --noconfirm niri" in calls, calls

    # status-apt.sh keeps reporting absent declared packages loudly.
    status_apt = payload / "bin" / "status-apt.sh"
    status_text = status_apt.read_text(encoding="utf-8")
    assert "missing package" in status_text
    assert 'echo "missing package: ${_p}"' in status_text
    print("ok: USERMODE lanes skip loudly; force env runs; plain lanes unchanged")


if __name__ == "__main__":
    test_archlane_renders_bins_and_joins_packages_lane()
    test_archlane_and_aptlane_coexist_in_packages_lane()
    test_archlane_inactive_without_declaration()
    test_usermode_lanes_skip_by_default_and_force_runs()
