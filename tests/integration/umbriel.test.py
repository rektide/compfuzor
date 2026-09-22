#!/usr/bin/env python3
"""Render regular/SteamOS Umbriel deployments and verify their contracts.

Run directly:

    ./tests/integration/umbriel.test.py

All outputs stay under .test-agent/umbriel-test; package, repository, global
link, and automatic-bin effects are bypassed.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "umbriel-test"


def render(name: str, playbook: str) -> Path:
    deployment = SCRATCH / name
    payload = deployment / "payload"
    payload.mkdir(parents=True, exist_ok=True)
    scenario = deployment / "scenario.json"
    scenario.write_text(
        json.dumps(
            {
                "DIR": str(payload),
                "ETC": str(payload / "etc"),
                "BINS_DIR": str(payload / "bin"),
                "REPO_BYPASS": True,
                "PKGS_BYPASS": True,
                "APT_BYPASS": True,
                "BINS_RUN_BYPASS": True,
                "GLOBAL_BINS_BYPASS": True,
                "LINKS_BYPASS": True,
                "GET_URLS": [],
            }
        ),
        encoding="utf-8",
    )
    env = dict(os.environ, HOME=str(deployment / "home"))
    result = subprocess.run(
        [
            "ansible-playbook",
            "-i",
            "localhost,",
            "-c",
            "local",
            str(ROOT / playbook),
            "-e",
            f"@{scenario}",
        ],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise AssertionError(f"{playbook} render failed:\n{result.stdout}\n{result.stderr}")
    return payload


def assert_shell_syntax(bin_dir: Path) -> None:
    scripts = sorted(str(path) for path in bin_dir.glob("*.sh"))
    result = subprocess.run(["bash", "-n", *scripts], text=True, capture_output=True)
    if result.returncode:
        raise AssertionError(f"generated shell syntax failed:\n{result.stderr}")


def test_regular_source_deployment() -> None:
    payload = render("regular", "umbriel.src.pb")
    bins = payload / "bin"
    expected = {
        "build.sh",
        "install.sh",
        "install-apt.sh",
        "install-arch.sh",
        "install-umbriel.sh",
        "run-nested.sh",
        "validate.sh",
    }
    assert expected <= {path.name for path in bins.iterdir()}
    installer = (bins / "install.sh").read_text(encoding="utf-8")
    assert installer.index("install-apt.sh") < installer.index("install-arch.sh")
    assert installer.index("install-arch.sh") < installer.index("install-umbriel.sh")
    build = (bins / "build.sh").read_text(encoding="utf-8")
    assert "--prefix=\"$_prefix\"" in build and "_prefix=/usr/local" in build
    assert '_build="${DIR}/build-release"' in build
    assert '$PWD/build-release' not in build
    assert "-Dtests=disabled" in build
    assert "git status --porcelain" in build
    install_leaf = (bins / "install-umbriel.sh").read_text(encoding="utf-8")
    assert "chmod 0644" in install_leaf
    assert "umbriel-session.target" in install_leaf
    assert_shell_syntax(bins)
    print("ok: regular Umbriel source deployment renders package → build/install")


def test_steamos_deployment_is_reinstallable() -> None:
    payload = render("steamos", "steamos-umbriel.opt.pb")
    bins = payload / "bin"
    installer = (bins / "install.sh").read_text(encoding="utf-8")
    assert "sudo steamos-readonly disable" in installer
    arch_run = installer.index('"$DIR/bin/install-arch.sh"')
    umbriel_run = installer.index('"$DIR/bin/install-umbriel.sh"')
    assert installer.index("steamos-readonly disable") < arch_run < umbriel_run
    build = (bins / "build.sh").read_text(encoding="utf-8")
    assert "_prefix=/usr" in build
    assert 'rm -rf "$_build"' in build
    session = (bins / "session.sh").read_text(encoding="utf-8")
    assert "set-default-desktop-session umbriel.desktop" in session
    assert_shell_syntax(bins)
    print("ok: SteamOS Umbriel renders readonly/package/clean-build/session recovery")


def test_steamos_session_toolkit_composes_umbriel() -> None:
    payload = render("session", "steamos-umbriel.srv.pb")
    bins = payload / "bin"
    expected = {
        "to-desktop.sh",
        "default-desktop.sh",
        "to-plasma.sh",
        "default-plasma.sh",
        "to-game.sh",
        "sessions.sh",
        "to-umbriel.sh",
        "default-umbriel.sh",
    }
    assert expected == {path.name for path in bins.iterdir()}
    umbriel_switch = (bins / "to-umbriel.sh").read_text(encoding="utf-8")
    assert "umbriel.desktop" in umbriel_switch
    assert '"${DIR}/bin/to-desktop.sh"' in umbriel_switch
    assert_shell_syntax(bins)
    print("ok: shared SteamOS toolkit composes Umbriel-specific operators")


if __name__ == "__main__":
    test_regular_source_deployment()
    test_steamos_deployment_is_reinstallable()
    test_steamos_session_toolkit_composes_umbriel()
