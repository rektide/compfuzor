#!/usr/bin/env python3
"""Render the real Niri/Umbriel consumer-host playbooks and prove adoption/migration.

Run directly:

    ./tests/integration/keybindings_consumer_hosts.test.py

Renders niri.etc.pb and umbriel.etc.pb through the actual playbook files into
isolated deployment dirs (etc-type shape: DIR==ETC), then runs the generated
user installers against isolated HOMEs. No live compositor configuration is
touched. The old previously-managed umbriel.user.pb template bytes are
embedded as historical literals and cross-checked against the playbook's
pinned migration hashes.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib

import yaml
from keybindings.fixtures import registry_policy, isolate_xdg

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent/keybindings-consumer-hosts"

OLD_CONFIG_TOML = """# Umbriel user configuration
# Managed by compfuzor: edit umbriel.user.pb / files/umbriel/config.toml,
# not this rendered copy.
#
# Umbriel picks the first config it finds and never auto-layers, so this file
# explicitly includes the system default installed by umbriel.src.pb
# (/usr/local/share/umbriel/config.toml) and layers on top of it:
#   - tables merge key-by-key ([keybinds] merges chord-by-chord)
#   - arrays of tables (window_rule, workspace, ...) accumulate
#   - anything set below wins over the default
# The vicinae fragment is optional so the config stays valid without it.
# keybinds-local.toml (umbriel.user.pb) loads after it and wins conflicts.
# animation.toml (umbriel.user.pb) layers focus-navigation motion tuning on
# top of the default animation tables; it conflicts with nothing.
# Managed includes live beside this file (see keybinds-vicinae.toml).
# Do not add a [keybinds] table here: in the root config it would REPLACE
# the entire built-in default set. Chord overrides belong in included
# fragments (see keybinds-vicinae.toml and keybinds-local.toml).

[include]
files = ["/usr/local/share/umbriel/config.toml"]
optional = { files = ["keybinds-vicinae.toml", "keybinds-local.toml", "animation.toml"] }
"""

OLD_KEYBINDS_LOCAL_TOML = """# Personal keybind overrides for the Umbriel compositor.
# Managed by compfuzor (umbriel.user.pb); included optionally from
# ~/.config/umbriel/config.toml AFTER the vicinae fragment, so these win
# same-chord conflicts. Merges chord-by-chord over the system default --
# adding chords here never disturbs binds defined elsewhere in the chain.
[keybinds]
# "?"-means-help: reopen the keybind cheatsheet overlay (the keybind listing
# shown at startup via general.show_cheatsheet). Stored as the level-0
# 'slash' keysym; the matcher also accepts the shifted 'question' symbol
# (src/server/server_keybinds.cpp matchKeybind, rawKeysym path), so this
# fires on Shift+Slash as typed.
"Mod+Shift+Slash" = "cheatsheet-toggle"

# Vicinae clipboard history (paste picker); ?toggle=true closes it when
# already showing, matching the launcher/window-switcher binds.
"Mod+Grave" = "spawn:vicinae deeplink 'vicinae://launch/clipboard/history?toggle=true'"
# Vim-style move chords. The default set binds only the arrow variants
# (Mod+Shift+Left/Down/Up/Right), so H/J/K/L moves were lost when the
# hand-copied keybind set became the include chain. J/K use the hybrid
# actions: move the window within its column, and carry it to the adjacent
# workspace when it hits the edge -- in-workspace behavior stays intact.
"Mod+Shift+H" = "column-move-left"
"Mod+Shift+L" = "column-move-right"
"Mod+Shift+J" = "window-move-or-workspace-down"
"Mod+Shift+K" = "window-move-or-workspace-up"
# Relative workspace navigation, niri-style Page keys (chords borrowed from
# the example config's optional recipes; unbound in the default).
"Mod+Page_Down" = "workspace-next"
"Mod+Page_Up" = "workspace-previous"
"Mod+Shift+Page_Down" = "window-move-to-workspace-next"
"Mod+Shift+Page_Up" = "window-move-to-workspace-previous"
"""


def run(command, env, check=True):
    result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True)
    if check and result.returncode:
        raise AssertionError(f"failed {command}\n{result.stdout}\n{result.stderr}")
    return result


def render_playbook(playbook: str, name: str, extra: dict | None = None, etc_typed: bool = True) -> Path:
    """Render an actual playbook file into an isolated deployment dir.

    etc_typed deployments mirror the real shape DIR==ETC (material directly
    under the deployment root with the structural DIR/etc exposure link);
    source deployments use DIR with DIR/etc as a real subdirectory.
    """
    # Every render starts fresh: stale retired launchers intentionally aren't
    # pruned by Compfuzor, so a previous proof tree cannot prove their absence.
    SCRATCH.mkdir(parents=True, exist_ok=True)
    deployment = Path(tempfile.mkdtemp(prefix=name + "-", dir=SCRATCH))
    payload = deployment / "payload"
    deployment.mkdir(parents=True, exist_ok=True)
    scenario = {
        "DIR": str(payload),
        "PREFIX_DIR": str(deployment),
        "ETC": str(payload if etc_typed else payload / "etc"),
        "BINS_DIR": str(payload / "bin"),
        "REPO_BYPASS": True,
        "PKGS_BYPASS": True,
        "APT_BYPASS": True,
        "ARCH_BYPASS": True,
        "BINS_RUN_BYPASS": True,
        "GLOBAL_BINS_BYPASS": True,
        "LINKS_BYPASS": True,
        "MODULES_BYPASS": True,
        "SYSTEMD_THUNK_BYPASS": True,
        "GET_URLS": [],
        "KEYBINDING_REGISTRY_POLICY": registry_policy(),
    }
    if playbook == "vicinae.src.pb":
        # Rendering producer declarations must not create /usr/share/vicinae,
        # archive workspaces or source-to-/opt exposure links on the workstation.
        scenario.update({"DIRS": [], "DIRSET": ["etc"], "FS_SRCS_BYPASS": True,
                         "SRC": str(payload), "OPT": str(payload / "opt"),
                         "REPO_DIR": str(payload / "repo"), "GIT_DIR": str(payload / "repo")})
        for kind in ["VAR", "LOG", "CACHE", "SHARE", "PID", "SRV", "SPOOL"]:
            scenario[kind] = str(payload / kind.lower())
        for relative in ["bin/config/processors", "bin/internal/config", "bin/zim"]:
            (payload / relative).mkdir(parents=True, exist_ok=True)
    if extra:
        scenario.update(extra)
    scenario_file = deployment / "scenario.json"
    scenario_file.write_text(json.dumps(scenario), encoding="utf-8")
    env = isolate_xdg(dict(os.environ), deployment / "home")
    result = subprocess.run(
        ["ansible-playbook", "-i", "localhost,", "-c", "local", str(ROOT / playbook), "-e", f"@{scenario_file}"],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise AssertionError(f"{playbook} render failed:\n{result.stdout}\n{result.stderr}")
    return payload


def consumer_env(home: Path) -> dict:
    assert home.resolve().is_relative_to(ROOT / ".test-agent"), "consumer tests require isolated HOME"
    commands = home / "test-commands"
    commands.mkdir(parents=True, exist_ok=True)
    # HOME alone does not isolate the session bus: never touch the real user manager.
    systemctl = commands / "systemctl"
    systemctl.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$SERVICE_TEST_TRACE"\nexit 0\n')
    systemctl.chmod(0o755)
    for forbidden in ["sudo", "steamos-readonly", "steamosctl"]:
        command = commands / forbidden
        command.write_text('#!/bin/sh\nprintf "unexpected privileged/session command: %s\\n" "$0" >&2\nexit 97\n')
        command.chmod(0o755)
    node = subprocess.run(["node", "-p", "process.execPath"], check=True, text=True, capture_output=True).stdout.strip()
    env = {
        **os.environ,
        "HOME": str(home),
        "TMPDIR": str(SCRATCH),
        "SERVICE_TEST_TRACE": str(home / "service-test-trace"),
        "PATH": os.pathsep.join([str(commands), str(Path(node).parent), "/usr/local/bin", "/usr/bin", "/bin", str(Path.home() / ".local/share/pnpm")]),
    }
    for variable in ["DIR", "COMPFUZOR_NIRI_PROFILE", "COMPFUZOR_UMBRIEL_PROFILE", "COMPFUZOR_CONFIG_BYPASS", "COMPFUZOR_KEYBINDINGS_BYPASS", "COMPFUZOR_ACTION_SESSION", "COMPFUZOR_ACTION_OPERATION", "COMPFUZOR_ACTION_OPERATION_MODE"]:
        env.pop(variable, None)
    isolate_xdg(env, home)
    return env


def assert_shell_syntax(bin_dir: Path) -> None:
    scripts = sorted(str(path) for path in bin_dir.glob("*.sh") if path.is_file() and not path.is_symlink())
    result = subprocess.run(["bash", "-n", *scripts], text=True, capture_output=True)
    if result.returncode:
        raise AssertionError(f"generated shell syntax failed:\n{result.stderr}")


def test_niri_consumer_host() -> None:
    payload = render_playbook("niri.etc.pb", "niri-host")
    profile = json.loads((payload / "keybinding-niri.json").read_text())
    assert profile["target"] == "niri"
    assert profile["contexts"]["user"] == {"scope": "user", "root": {"path": "${XDG_CONFIG_HOME}"}, "subpath": "niri"}
    assert profile["baseline"] == []  # No fabricated baseline.
    assert "templateFile" not in profile and profile["userSources"] == []
    assert not (payload / "keybinding-producer.json").exists()  # Implicit consumer-only host.
    installer = (payload / "bin/install-keybindings-niri.sh").read_text()
    assert f"--descriptor {payload}/keybindings/consumers/user/niri.json" in installer and " host " in installer
    aggregate = (payload / "bin/install-user.sh").read_text()
    assert aggregate.index("--remove vicinae") < aggregate.index("actions children")
    assert aggregate.count("actions children") == 1
    assert (payload / "bin/install.mjs").is_symlink() and (payload / "bin/assemble.mjs").is_symlink()
    assert (payload / "bin/keybindings.mjs").is_symlink()
    assert_shell_syntax(payload / "bin")

    with tempfile.TemporaryDirectory(prefix="niri-", dir=SCRATCH) as tmp:
        home = Path(tmp) / "home"
        config_dir = home / ".config/niri"
        config_dir.mkdir(parents=True)
        (config_dir / "handy").mkdir()
        (config_dir / "config.d").mkdir()
        (config_dir / "handy/handy.kdl").write_text('binds { Mod+H hotkey-overlay-title="handy" { spawn "echo" "handy"; }; }\n')
        (config_dir / "config.d/display-alt.kdl").write_text('output "DP-1" { scale 2; }\n')
        (config_dir / "config.kdl").write_text(
            'output "DP-1" {\n    scale 1\n}\n\nbinds {\n    Mod+Q { quit; }\n}\n\n'
            "// handy start\ninclude \"./handy/handy.kdl\"\n// handy end\n"
            '// vicinae start\ninclude "./vicinae/keybinding-clipboard.kdl"\ninclude "./vicinae/keybinding-launch.kdl"\n// vicinae end\n\n'
            'include "./config.d/display-alt.kdl"\n'
        )
        env = consumer_env(home)
        run([str(payload / "bin/install.mjs")], env)
        assert (home / "registries/user/consumers.d/niri.json").resolve() == (payload / "keybindings/consumers/user/niri.json").resolve()
        root = (config_dir / "config.kdl").read_text()
        assert root.count("// compfuzor-keybindings-begin") == 1 and root.count("// compfuzor-keybindings-end") == 1
        assert root.index("// handy start") < root.index('include "./handy/handy.kdl"') < root.index("// handy end")
        assert "vicinae/keybinding-clipboard.kdl" not in root and "vicinae start" not in root  # Retired exactly once.
        assert 'include "./config.d/display-alt.kdl"' in root  # Unknown text untouched.
        assert root.index('include "./config.d/display-alt.kdl"') < root.index("// compfuzor-keybindings-begin")  # Markers appended at EOF.
        if shutil.which("niri"):
            assert subprocess.run(["niri", "validate", "-c", str(config_dir / "config.kdl")], env=env, capture_output=True).returncode == 0
        stable = root
        run([str(payload / "bin/install.mjs")], env)  # Idempotent adoption.
        assert (config_dir / "config.kdl").read_text() == stable

        # Missing root: minimal skeleton with the managed area only.
        fresh = Path(tmp) / "fresh" / ".config/niri"
        fresh.mkdir(parents=True)
        env2 = consumer_env(Path(tmp) / "fresh")
        run([str(payload / "bin/install.mjs")], env2)
        created = (fresh / "config.kdl").read_text()
        assert created == "// compfuzor-keybindings-begin\n// compfuzor-keybindings-end\n"
    print("ok: niri consumer host renders, adopts conservatively and is idempotent")


def test_umbriel_consumer_host() -> None:
    payload = render_playbook("umbriel.etc.pb", "umbriel-host")
    playbook = yaml.safe_load((ROOT / "umbriel.etc.pb").read_text())
    migrations = playbook[0]["vars"]["UMBRIEL_MIGRATIONS"]
    # The embedded historical literals are the exact bytes the playbook pins.
    assert hashlib.sha256(OLD_CONFIG_TOML.encode()).hexdigest() == migrations["config.toml"]
    assert hashlib.sha256(OLD_KEYBINDS_LOCAL_TOML.encode()).hexdigest() == migrations["keybinds-local.toml"]

    profile = json.loads((payload / "keybinding-umbriel.json").read_text())
    assert profile["target"] == "umbriel"
    assert profile["templateFile"] == {"path": str(payload / "config.toml")}
    assert profile["baseline"] == [{"path": "/usr/local/share/umbriel/config.toml"}]
    assert [source["path"]["path"].rsplit("/", 1)[-1] for source in profile["userSources"]] == ["vicinae-clipboard.yaml"]
    assert profile["userSources"][0]["whenPresent"] is True  # Patch stays dormant without the producer.
    assert not (payload / "keybinding-producer.json").exists()

    with (payload / "config.toml").open("rb") as handle:
        template = tomllib.load(handle)
    assert template["include"]["files"] == ["/usr/local/share/umbriel/config.toml"]  # Array-internal markers are comments.
    assert template["include"]["optional"]["files"] == ["keybinds-local.toml", "animation.toml"]
    # tomllib coverage above proves keybinds-vicinae.toml is no longer referenced anywhere in the chain.
    assert "keybinds" not in template  # The root never carries a [keybinds] table.
    local_text = (payload / "keybinds-local.toml").read_text()
    assert '"Mod+Grave"' not in local_text.split("[keybinds]")[1]  # Duplicate command-valued entry removed.
    with (payload / "keybinds-local.toml").open("rb") as handle:
        assert tomllib.load(handle)["keybinds"]["Mod+Shift+Slash"] == "cheatsheet-toggle"
    aggregate = (payload / "bin/install-user.sh").read_text()
    assert aggregate.index("umbriel_seed") < aggregate.index("actions children")
    assert aggregate.count("actions children") == 1
    assert_shell_syntax(payload / "bin")

    with tempfile.TemporaryDirectory(prefix="umbriel-", dir=SCRATCH) as tmp:
        # Migration: live files still byte-match the previously managed templates.
        home = Path(tmp) / "home"
        live = home / ".config/umbriel"
        live.mkdir(parents=True)
        (live / "config.toml").write_text(OLD_CONFIG_TOML)
        (live / "keybinds-local.toml").write_text(OLD_KEYBINDS_LOCAL_TOML)
        env = consumer_env(home)
        migrated = run([str(payload / "bin/install.mjs")], env)
        assert migrated.stdout.count("migrated") == 2
        assert (live / "config.toml").read_text() == (payload / "config.toml").read_text()
        assert (live / "keybinds-local.toml").read_text() == (payload / "keybinds-local.toml").read_text()
        assert '"Mod+Grave"' not in (live / "keybinds-local.toml").read_text().split("[keybinds]")[1]
        assert "# compfuzor-keybindings-begin" in (live / "config.toml").read_text()

        # A stale vicinae fragment stays on disk, merely unreferenced.
        (live / "keybinds-vicinae.toml").write_text('[keybinds]\n"Mod+Space" = "spawn:vicinae toggle"\n')
        rerun = run([str(payload / "bin/install.mjs")], env)
        with (live / "config.toml").open("rb") as handle:
            live_template = tomllib.load(handle)
        assert "keybinds-vicinae.toml" not in live_template["include"]["optional"]["files"]  # Unreferenced, not pruned.
        assert (live / "keybinds-vicinae.toml").exists()

        # User edits always win: content matching neither template is never
        # replaced, and an unadopted custom root then fails the host assembly
        # loudly instead of rewriting the user's text.
        edited = Path(tmp) / "edited" / ".config/umbriel"
        edited.mkdir(parents=True)
        (edited / "config.toml").write_text('# my own root\n[include]\nfiles = ["/usr/local/share/umbriel/config.toml"]\n')
        (edited / "animation.toml").write_text("# my tuning\n[animation]\nenabled = false\n")
        env2 = consumer_env(Path(tmp) / "edited")
        noted = run([str(payload / "bin/install.mjs")], env2, check=False)
        assert noted.returncode != 0  # Operator action required, not silent rewrite.
        assert "user edits" in noted.stderr
        assert (edited / "config.toml").read_text().startswith("# my own root")
        assert (edited / "animation.toml").read_text().startswith("# my tuning")
        assert (edited / "keybinds-local.toml").read_text() == (payload / "keybinds-local.toml").read_text()  # Missing entries still seed.
    print("ok: umbriel consumer host seeds, migrates byte-matches only and preserves user edits")


if __name__ == "__main__":
    SCRATCH.mkdir(parents=True, exist_ok=True)
    if not (SCRATCH / "README.md").exists():
        (SCRATCH / "README.md").write_text(
            "# Keybindings consumer-host scratch\nIsolated renders of niri.etc.pb/umbriel.etc.pb and installer runs against temp HOMEs; no live configs.\n"
        )
    test_niri_consumer_host()
    test_umbriel_consumer_host()
