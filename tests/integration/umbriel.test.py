#!/usr/bin/env python3
"""Render regular/SteamOS/user Umbriel deployments and verify their contracts.

Run directly:

    ./tests/integration/umbriel.test.py

All outputs stay under .test-agent/umbriel-test; package, repository, global
link, and automatic-bin effects are bypassed.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "umbriel-test"


def render(name: str, playbook: str, etc_typed: bool = False) -> Path:
    deployment = SCRATCH / name
    shutil.rmtree(deployment, ignore_errors=True)
    payload = deployment / "payload"
    payload.mkdir(parents=True, exist_ok=True)
    scenario = deployment / "scenario.json"
    scenario.write_text(
        json.dumps(
            {
                "DIR": str(payload),
                # etc-typed deployments materialize ETC at DIR itself (the
                # real /etc/opt/NAME shape with the structural DIR/etc link);
                # other types keep DIR/etc as a real subdirectory.
                "ETC": str(payload if etc_typed else payload / "etc"),
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


import tomllib


def read_toml(path: Path) -> dict:
    with path.open("rb") as handle:
        return tomllib.load(handle)


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
    assert "--prefix=/usr/local" in build
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
    assert "--prefix=/usr" in build
    assert 'rm -rf "$_build"' in build
    session = (bins / "session.sh").read_text(encoding="utf-8")
    assert "set-default-desktop-session umbriel.desktop" in session
    assert_shell_syntax(bins)
    print("ok: SteamOS Umbriel renders readonly/package/clean-build/session recovery")


def test_steamos_umbriel_session_tools() -> None:
    payload = render("session", "steamos-umbriel.srv.pb")
    bins = payload / "bin"
    expected = {
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
    assert_shell_syntax(bins)
    print("ok: self-contained SteamOS Umbriel session operators render")


def test_user_config_include_chain_and_animation() -> None:
    # umbriel.user.pb was absorbed by umbriel.etc.pb: the root template and
    # personal fragments are deployment material under an etc-typed DIR
    # (scenario pins ETC==DIR to mirror the real /etc/opt/umbriel shape).
    payload = render("user", "umbriel.etc.pb", etc_typed=True)
    etc = payload

    # The root config stays a pure include chain: system default baseline,
    # then the keybinding insertion area (comments inside the files array),
    # then optional fragments. No [keybinds] table here -- in the root it
    # would REPLACE the entire built-in default keybind set. The hardcoded
    # keybinds-vicinae.toml include is gone: producers own that binding now.
    config = read_toml(etc / "config.toml")
    assert config["include"]["files"] == ["/usr/local/share/umbriel/config.toml"]
    optional = config["include"]["optional"]["files"]
    assert optional == ["keybinds-local.toml", "animation.toml"]
    assert "# compfuzor-keybindings-begin" in (etc / "config.toml").read_text()
    assert "keybinds" not in config

    # Fragments stage beside the root config. The duplicate command-valued
    # Mod+Grave entry is gone: the consumer profile patch owns that chord.
    keybinds = read_toml(etc / "keybinds-local.toml")
    assert "Mod+Shift+Slash" in keybinds["keybinds"]
    assert "Mod+Grave" not in keybinds["keybinds"]

    # Animation fragment: focus-navigation reveal rides the windows_move
    # timeline (no separate nav event exists), dialed to a 650 ms symmetric
    # bezier. Tables merge key-by-key, so sibling event tables keep defaults.
    animation = read_toml(etc / "animation.toml")
    assert animation["animation"]["enabled"] is True
    move = animation["animation"]["windows_move"]
    assert move["enabled"] is True
    assert move["duration_ms"] == 650
    assert move["curve"] == "0.42,0,0.58,1"

    # Consumer profile: templateFile pins the staged root template; the
    # consumer-owned vicinae-clipboard chord patch rides as a dormant
    # (whenPresent) user source until the producer registers.
    profile = json.loads((etc / "keybinding-umbriel.json").read_text())
    assert profile["target"] == "umbriel"
    assert profile["templateFile"] == {"path": str(etc / "config.toml")}
    assert [source["path"]["path"] for source in profile["userSources"]] == [
        str(etc / "keybinding/vicinae-clipboard.yaml")
    ]
    assert profile["userSources"][0]["whenPresent"] is True

    # Validate the full chain (system default + fragments) with the
    # installed compositor when present.
    umbriel = shutil.which("umbriel")
    if umbriel:
        result = subprocess.run(
            [umbriel, "validate", "-c", str(etc / "config.toml")],
            text=True,
            capture_output=True,
        )
        assert result.returncode == 0, f"umbriel validate failed:\n{result.stdout}\n{result.stderr}"
    print("ok: etc deployment stages area-marked chain template, Mod+Grave-free local chords, animation values, consumer profile")


if __name__ == "__main__":
    test_regular_source_deployment()
    test_steamos_deployment_is_reinstallable()
    test_steamos_umbriel_session_tools()
    test_user_config_include_chain_and_animation()
